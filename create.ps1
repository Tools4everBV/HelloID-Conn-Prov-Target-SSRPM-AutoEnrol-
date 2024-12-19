#################################################
# HelloID-Conn-Prov-Target-SSRPM-AutoEnroll-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function get-SSRPMuserBySAMAccountName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$SAMAccountName
        , [Parameter(Mandatory)][string]$ConnectionString
    )
    try {
        Write-Information "search SSRPM database for user with username: $SAMAccountName"
        $query = "SELECT * FROM [enrolled users] WHERE samaccountname = '$($SAMAccountName)'"

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


function New-SSRPMuser {
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
        $AnswerList = $Account.answers | ConvertFrom-Json
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
        $SqlCmd.CommandText = "$($SqlConnection.Database).dbo.enrolluser"
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure

        #sql parameters
        [void]$SqlCmd.Parameters.AddWithValue("@ProfileID", $account.ProfileID)
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
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    if($null -ne $actionContext.Data.Objectsid)
    {
        $sidObjectBytes = [system.convert]::FromBase64String($actionContext.Data.Objectsid)
        $securityIdentifier = [system.security.Principal.SecurityIdentifier]::new($sidObjectBytes,0)
        $SidString = $securityIdentifier.ToString()
        $actionContext.Data.Objectsid = $SidString
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }
        # Determine if a user needs to be [created] or [correlated]

        $getResult = get-SSRPMuserBySAMAccountName -SAMAccountName $correlationValue -ConnectionString $actionContext.Configuration.ConnectionString
    }
    $NrFound = $getResult.Count

    #$NrFound = ($correlatedAccount | measure-object).count
    if ($NrFound -eq 1) {
        $action = 'CorrelateAccount'
        $CorrelatedAccount = $getResult[0]
    }
    elseif ($NrFound -gt 1) {
        $action = 'MultipleAccounts'
    }
    else {
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating SSRPM-AutoEnroll account'

                $result = New-SSRPMuser -connectionString $actionContext.Configuration.ConnectionString -account $ActionContext.Data
                $getResult = get-SSRPMuserBySAMAccountName  -SAMAccountName $correlationValue -ConnectionString $actionContext.Configuration.ConnectionString
                $createdAccount = $getResult[0]
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.Id
            }
            else {
                Write-Information '[DryRun] Create and correlate SSRPM-AutoEnroll account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating SSRPM-AutoEnroll account'

            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }

        'MultipleAccounts' {
            throw "User with samaccountname $correlationValue found multiple times"
        }

    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem

    $auditMessage = "Could not create or correlate SSRPM-AutoEnroll account. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}