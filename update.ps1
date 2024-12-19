#################################################
# HelloID-Conn-Prov-Target-SSRPM-AutoEnroll-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions

function get-SSRPMuserById {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$Id
        , [Parameter(Mandatory)][string]$ConnectionString
    )
    try {
        Write-Information "Select user from [enrolled users] with id $Id"
        $query = "SELECT * FROM [enrolled users] WHERE id = '$($Id)'"

        # Initialize connection and query information
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new($query, $SqlConnection)
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new($SqlCmd)
        $DataSet = [System.Data.DataSet]::new()
        $SqlAdapter.Fill($DataSet) | out-null
        $sqlData = $DataSet.Tables[0]

        Write-Information "Found $($sqlData.Rows.Count) user(s) in SSRPM database"
        $Rowlist = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $sqlData.rows) {
            $Rowlist.Add(($row | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors))
        }
        return , $Rowlist

    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
function get-SSRPMAnswers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$UserId
        , [Parameter(Mandatory)][string]$ConnectionString
    )
    try {
        Write-Information "Select user from [enrolled users] with id $Id"
        #$query = "SELECT * FROM [User Answers] WHERE [Account id] = '$($UserId)'"
        $query = "SELECT questionID,text=Answer FROM [User Answers]ua inner join [Questions]q on q.Question=ua.Question WHERE [Account id] = '$($UserId)'"

        # Initialize connection and query information
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new($query, $SqlConnection)
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new($SqlCmd)
        $DataSet = [System.Data.DataSet]::new()
        $SqlAdapter.Fill($DataSet) | out-null
        $sqlData = $DataSet.Tables[0]

        $Rowlist = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $sqlData.rows) {
            $Rowlist.Add(($row | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors))
        }

        return , $Rowlist
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
function Compare-Answers {
    [CmdletBinding()]
    param(

        [PSCustomObject]
        $OldAnswers,

        [PSCustomObject]
        $NewAnswers
    )
    if($null -eq $OldAnswers)
    {
        return $true
    }
    $oldAnswersGrouped = $OldAnswers | Group-Object -property "QuestionId" -AsHashTable
    $ReturnValue = $false
    foreach ($question in $NewAnswers) {
        $oldQuestion = $oldAnswersGrouped[$Question.QuestionID]
        if (($null -eq $oldQuestion) -or ($question.text -ne $oldQuestion.text)) {
            $ReturnValue = $true
            break
        }
    }
    write-output $Returnvalue
}
function Update-SSRPMuser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$connectionString,
        [Parameter(Mandatory = $true)][Object]$account
    )
    try {
        if ([string]::IsNullOrEmpty($account.sAMAccountName) -OR
            [string]::IsNullOrEmpty($account.CanonicalName) -OR
            [string]::IsNullOrEmpty($account.ObjectSID)) {
            Throw "one of the mandatory fields is empty or missing"
        }

        $XML_Answers = $null
        $AnswerList = $Account.answers
        foreach ($answer in $AnswerList) {
            if (-NOT([string]::IsNullOrEmpty($answer.QuestionID) -OR [string]::IsNullOrEmpty($answer.text))) {
                $XML_Answers += "<a id=""$($answer.QuestionID)"">$($answer.text)</a>"
            }
        }

        $XML_Answers = "<answers>" + $XML_Answers + "</answers>"

        #SQL connection
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new()

        #sql command
        $SqlCmd.CommandText = "updateUser"
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure

        #sql parameters
        [void]$SqlCmd.Parameters.AddWithValue("@SSRPM_ID", $account.Id)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_CanonicalName", $account.CanonicalName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_sAMAccountName", $account.SamAccountName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_EmailAddress", $account.mail)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_ObjectSID", $account.ObjectSID)
        [void]$SqlCmd.Parameters.AddWithValue("@Private_EmailAddress", $account.PrivateMail)
        [void]$SqlCmd.Parameters.AddWithValue("@Private_Mobile", $account.PrivateMobile)
        [void]$SqlCmd.Parameters.AddWithValue("@XML_Answers", $XML_Answers)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_CommonName", $account.commonName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_DisplayName", $account.displayName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_SurName", $account.surname)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_GivenName", $account.givenName)

        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new($SqlCmd)
        $DataSet = [System.Data.DataSet]::new()
        #execute
        $SqlAdapter.Fill($DataSet)
        $SqlConnection.Close()
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
function ConvertTo-AccountObject {
    param(

        [PSCustomObject]
        $SourceUserObject,

        [System.Collections.Generic.List[object]]
        $AnswersqueryResult
    )

    $AccountObject = [PSCustomObject]@{
        CanonicalName  = $SourceUserObject.'Account Name'
        SAMAccountName = $SourceUserObject.sAMAccountName
        Mail           = $SourceUserObject.InternalEmailAddress
        ObjectSid      = $SourceUserObject.'Account SID'
        PrivateMail    = $SourceUserObject.'Email Address'
        PrivateMobile  = $SourceUserObject.'Mobile Phone Number'
        Answers        = $AnswersqueryResult | ConvertTo-Json | ConvertFrom-Json
    }

    Write-Output $AccountObject

}

#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a SSRPM-AutoEnroll account exists'
    $SSRPMUser = get-SSRPMuserById -Id $actionContext.References.Account -ConnectionString $actionContext.Configuration.ConnectionString

    # Always compare the account against the current account in target system
    if ($null -ne $SSRPMUser) {

        $SSRPMAnswers = get-SSRPMAnswers -UserId $actionContext.References.Account -ConnectionString $actionContext.Configuration.ConnectionString
        $correlatedAccount = ConvertTo-AccountObject -SourceUserObject  $SSRPMUser[0] -Answers $SSRPMAnswers

        $outputContext.PreviousData = $correlatedAccount

        if ($null -ne $actionContext.Data.ProfileId) {
            $actionContext.Data.PSObject.Properties.Remove("profileId")
        }

        $actionContext.Data.Answers = $actionContext.Data.Answers | ConvertFrom-Json

        $sidObjectBytes = [system.convert]::FromBase64String($actionContext.Data.Objectsid)
        $securityIdentifier = [system.security.Principal.SecurityIdentifier]::new($sidObjectBytes,0)
        $SidString = $securityIdentifier.ToString()
        $actionContext.Data.Objectsid = $SidString


        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        $answersChanged = Compare-Answers -OldAnswers $correlatedAccount.Answers -NewAnswers $actionContext.Data.Answers

        if ($propertiesChanged -or $answersChanged) {
            $action = 'UpdateAccount'
        }
        else {
            $action = 'NoChanges'
        }
    }
    else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {

            if ($answersChanged) {
                Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', '), Answers"
            }
            else {
                Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating SSRPM-AutoEnroll account with accountReference: [$($actionContext.References.Account)]"
                $actionContext.Data | Add-Member -MemberType NoteProperty -Name "id" -Value $($actionContext.References.Account)
                $result = Update-SSRPMuser -connectionString $actionContext.Configuration.ConnectionString -account $actionContext.Data

            }
            else {
                Write-Information "[DryRun] Update SSRPM-AutoEnroll account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true

            if ($answersChanged) {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ','), Answers]"
                        IsError = $false
                    })
            }
            else {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                        IsError = $false
                    })
            }
            break
        }

        'NoChanges' {
            Write-Information "No changes to SSRPM-AutoEnroll account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "SSRPM-AutoEnroll account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "SSRPM-AutoEnroll account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem

    $auditMessage = "Could not update SSRPM-AutoEnroll account. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}