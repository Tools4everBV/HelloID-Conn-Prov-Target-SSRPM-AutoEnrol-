#Initialize default properties
$p = $person | ConvertFrom-Json
$c = $configuration | ConvertFrom-Json
$aref = $accountreference | ConvertFrom-Json

$updateUserOnCorrelate = $c.updateUserOnCorrelate

$connectionString = "Data Source=$($c.server);Initial Catalog=$($c.database);persist security info=True;Integrated Security=SSPI;";    

$success = $true # Set to true at start, because only when an error occurs it is set to false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

function get-SSRPMuser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][Object]$account
        , [Parameter(Mandatory)][string]$ConnectionString
    )
    try {
        $query = "SELECT * FROM [enrolled users] WHERE samaccountname = '$($account.samaccountname)'"

        # Initialize connection and query information
        # Connect to the SQL server
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $ConnectionString
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        
        #Query to get all person information adjust to liking#
        $SqlCmd.CommandText = $query
        $SqlAdapter.SelectCommand = $SqlCmd 
        $DataSet = New-Object System.Data.DataSet
        $SqlAdapter.Fill($DataSet) | out-null
        $sqlData = $DataSet.Tables[0]
        
        return $sqlData | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
    }
    catch {
        Throw "Failed to get SSRPM user - Error: $($_)"   
    }
}

function New-SSRPMuser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$connectionString,
        [Parameter(Mandatory = $true)][int]$ProfileID,
        [Parameter(Mandatory = $true)][Object]$account
    )    
    try {
        if ([string]::IsNullOrEmpty($account.sAMAccountName) -OR
            [string]::IsNullOrEmpty($account.CanonicalName) -OR       
            [string]::IsNullOrEmpty($account.ObjectSID)) {
            Throw "one of the mandatory field is empty or missing"
        }

        $XML_Answers = $null   

        foreach ($answer in $account.answers) {
            if (-NOT([string]::IsNullOrEmpty($answer.QuestionID) -OR [string]::IsNullOrEmpty($answer.text))) {
                $XML_Answers += "<a id=""$($answer.QuestionID)"">$($answer.text)</a>"
            }
        }

        $XML_Answers = "<answers>" + $XML_Answers + "</answers>"

        #SQL connection
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $ConnectionString;
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand

        #sql command
        $SqlCmd.CommandText = "$($c.database).dbo.enrolluser"
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure

        #sql parameters
        [void]$SqlCmd.Parameters.AddWithValue("@ProfileID", $ProfileID) 
        [void]$SqlCmd.Parameters.AddWithValue("@AD_CanonicalName", $account.CanonicalName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_sAMAccountName", $account.SamAccountName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_EmailAddress", $account.mail)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_ObjectSID", $account.ObjectSID)
        [void]$SqlCmd.Parameters.AddWithValue("@XML_Answers", $XML_Answers)

        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $SqlAdapter.SelectCommand = $SqlCmd
        $DataSet = New-Object System.Data.DataSet
        #execute
        $SqlAdapter.Fill($DataSet)
    
        $SqlConnection.Close()
        
    }
    catch {
        Throw "Failed to create new SSRPM user - Error: $($_)"    
    }
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
            Throw "one of the mandatory field is empty or missing"
        }

        $XML_Answers = $null   

        foreach ($answer in $account.answers) {
            if (-NOT([string]::IsNullOrEmpty($answer.QuestionID) -OR [string]::IsNullOrEmpty($answer.text))) {
                $XML_Answers += "<a id=""$($answer.QuestionID)"">$($answer.text)</a>"
            }
        }

        $XML_Answers = "<answers>" + $XML_Answers + "</answers>"

        #SQL connection
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $ConnectionString;
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand

        #sql command
        $SqlCmd.CommandText = "updateUser"
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure

        #sql parameters
        [void]$SqlCmd.Parameters.AddWithValue("@SSRPM_ID", $account.SSRPMID)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_CanonicalName", $account.CanonicalName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_sAMAccountName", $account.SamAccountName)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_EmailAddress", $account.mail)
        [void]$SqlCmd.Parameters.AddWithValue("@AD_ObjectSID", $account.ObjectSID)
        [void]$SqlCmd.Parameters.AddWithValue("@XML_Answers", $XML_Answers)
        
        
        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $SqlAdapter.SelectCommand = $SqlCmd
        $DataSet = New-Object System.Data.DataSet
        #execute
        $SqlAdapter.Fill($DataSet)
    
        $SqlConnection.Close()
        
    }
    catch {
        Throw "Failed to update new SSRPM user - Error: $($_)"    
    }
}

function format-date {
    [CmdletBinding()]
    Param
    (
        [string]$date,
        [string]$InputFormat,
        [string]$OutputFormat
    )
    try {
        if (-NOT([string]::IsNullOrEmpty($date))) {    
            $dateString = get-date([datetime]::ParseExact($date, $InputFormat, $null)) -Format($OutputFormat)
        }
        else {
            $dateString = $null
        }

        return $dateString
    }
    catch {
        throw("An error was thrown while formatting date: $($_.Exception.Message): $($_.ScriptStackTrace)")
    }
    
}

try {

    $account = [PSCustomObject]@{
        SSRPMID        = $aref
        
        # #on dependent system:
        # sAMAccountName = $p.accounts._2a468112bb3e42ed87f6f53c936d6640.SamAccountName
        # mail           = $p.accounts._2a468112bb3e42ed87f6f53c936d6640.mail
        # CanonicalName  = $null
        # ObjectSID      = $null

        #based on AD search:
        CanonicalName  = $null
        sAMAccountName = $null
        mail           = $null
        ObjectSID      = $null
     

        answers        = @(@{
                QuestionID = 16 #geboortedatum
                text       = format-date -date $p.details.BirthDate  -InputFormat 'yyyy-MM-ddThh:mm:ssZ' -OutputFormat "dd-MM-yyyy"
            },
            @{
                QuestionID = 17 #postcode
                text       = $p.contact.personal.address.PostalCode -Replace '[^a-zA-Z0-9]', ""
            },
            @{
                QuestionID = 18
                text       = $p.externalID
            }
        )
    }

    try {
        $adUser = Get-AdUser -ldapfilter "(employeeid=$($p.externalID))" -Properties CanonicalName, samaccountname, mail
    }
    catch {
        $adUser = null
    }
    
    $account.CanonicalName = $adUser.CanonicalName
    $account.ObjectSID = $aduser.sid.value
    $account.samaccountname = $aduser.samaccountname
    $account.mail = $aduser.mail
    
    write-verbose "try correlating user"
    $SSRPMuser = get-SSRPMuser -account $account -connectionString $connectionString
    if (($SSRPMuser | measure-object).count -eq 1) {
        write-verbose "User with samaccountname $($account.samaccountname) found in SSRPM DB"    

        if ($updateUserOnCorrelate) {
            $action = "correlate-update"
        }
        else {
            $action = "correlate"
        }
    }
    elseif (($SSRPMuser | measure-object).count -gt 1) {
        throw "User with samaccountname $($account.samaccountname) found multiple times"
    }
    else {
        $action = "create"
    }

    switch ($action) {
        "correlate" {  
            write-verbose "correlate only"
            $account.SSRPMID = $SSRPMuser.id
        
        }
        "correlate-update" {
            write-verbose "correlate and update user"
            
            $account.SSRPMID = $SSRPMuser.id
            if (-Not($dryRun -eq $True)) {
                $result = Update-SSRPMuser -connectionString $connectionString -account $account       
            }
            else {
                write-verbose "will update during enforcement: $($account | convertto-json)"
            }           
        
        }
        "create" {
            write-verbose "creating user"

            
            if (-Not($dryRun -eq $True)) {
                $result = New-SSRPMuser -connectionString $connectionString -account $account -ProfileID 3                
            }
            else {
                write-verbose  "will create during enforcement: $($account | convertto-json)"
            }
            $SSRPMuser = get-SSRPMuser -account $account  -connectionString $connectionString 
            $account.SSRPMID = $SSRPMuser.id
        }
        Default {
            throw "no action defined"
        }
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = "$action user successfully for $($p.displayname) with aref: $($account.SSRPMID)"
            IsError = $false
        })
}
catch {
    $success = $false
    $auditLogs.Add([PSCustomObject]@{
            Message = "$action user failed - $($_)"
            IsError = $true
        })
}

#build up result
$result = [PSCustomObject]@{ 
    Success          = $success
    AccountReference = $account.SSRPMID
    auditLogs        = $auditLogs
    Account          = $account
    # Optionally return data for use in other systems
    ExportData       = @{
        ID             = $account.SSRPMID
        samaccountname = $account.samaccountname
    }
};

#send result back
Write-Output $result | ConvertTo-Json -Depth 10