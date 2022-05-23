###############################
#Provide the Input text file location path (eg: "C:\Backup\Scripts\Inputparameter.txt")

$path = "C:\LogshippingScripts\Configfile.txt"

################################
function Write-LogshipLog {
    Param(
        [String]$Level,
        [string]$Message,
        [string]$logfile
    )
    $datestamp = Get-Date -format "dd-MMM-yyyy"
    $localname = $ENV:COMPUTERNAME
    $logfile = "$($backupLogFile)_" + $dateStamp + ".log" ## Provide the location where you want to logs
    $stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $line = "$stamp $localname $level $message"
    if (Test-Path -Path $logfile) {
        Add-Content $logfile -Value $Line
    } else {
        New-Item -Path $logfile -ItemType file -Force
        Add-Content $logfile -Value $Line 
    }
}

Import-Module SQLPS

$backupinputs = Get-Content -Path $path -raw | ForEach-Object { $_.Replace('\', '\\') } | ConvertFrom-Json

$primarySqlServer = $backupinputs.primarySqlServer 
$primaryServerBackupFolder = $backupinputs.primaryServerBackupFolder
$databases = $backupinputs.databases
$backupLogFile = $backupinputs.backupLogFile


foreach ($database in $databases) {
    ### Loop through each database to perform a full backup ###
    try {
        $backupDBFileName = $database + ".Bak"
        $backpLocation = $primaryServerBackupFolder + "\" + $backupDBFileName
        Write-LogshipLog -Level "INFO" -Message "Creating a full backup of $database to $BackupLocation"
        Backup-SqlDatabase -ServerInstance "$primarySqlServer" -Database $database -BackupFile $backpLocation -Initialize
        Write-LogshipLog -Level "INFO" -Message "SQL database backup completed."
    } catch [Exception] {
        $msg = "Failed to backup $$database" + $_.Exception.Message + "`r`n"
        Write-LogshipLog -Level "ERROR" -Message $msg
        throw
           
    }
}
