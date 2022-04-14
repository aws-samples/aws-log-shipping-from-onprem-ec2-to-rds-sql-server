###############################
#Provide the Input text file location path (eg: "C:\Logshippingscripts\ConfigFile.txt")

$path = "C:\LogshippingScripts\ConfigFile.txt"

################################
function Write-LogshipLog {
    Param(
        [String]$Level,
        [string]$Message,
        [string]$logfile
    )
    $datestamp = Get-Date -format "dd-MMM-yyyy"
    $localname = $ENV:COMPUTERNAME
    $logfile = "$($restoreJobLogfile)_" + $dateStamp + ".log" ## Provide the location where you want to logs
    $stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $line = "$stamp $localname $level $message"
    if (Test-Path -Path $logfile) {
        Add-Content $logfile -Value $Line
    } else {
        New-Item -Path $logfile -ItemType file -Force
        Add-Content $logfile -Value $Line 
    }
}
$restoreinputs = Get-Content -Path $path -raw | ForEach-Object { $_.Replace('\', '\\') } | ConvertFrom-Json

$primarySqlServer = $restoreinputs.primarySqlServer 
$primaryServerBackupFolder = $restoreinputs.primaryServerBackupFolder
$secondarySqlServer = $restoreinputs.secondarySqlServer
$databases = $restoreinputs.databases
$s3BucketName = $restoreinputs.s3BucketName
$s3BackupFolder = $restoreinputs.s3BackupFolder
$awsSecretName = $restoreinputs.awsSecretName 
$awsRegion = $restoreinputs.awsRegion
$restoreJobLogfile = $restoreinputs.restoreJobLogfile
$timeoutinSeconds = $restoreinputs.timeoutinSeconds
$retryIntervalseconds = $restoreinputs.verifyIntervalSeconds
$errorcount = 0


Write-LogshipLog -Level "*********INFO" -Message ":Beginning Transaction Log Restore on $($secondarySqlServer)**********"
try {
    $secret = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $awsSecretName -Region $awsRegion).SecretString
    $username = $secret.username
    $password = $secret.password
} catch {
    Write-LogshipLog "Error getting SQL credentials; Exiting"
    Exit
}
try {
    foreach ($database in $databases) {
        Write-LogshipLog "Starting Restore Opreation for database : $($Database)"
        $queryRestoreStatus =
        "IF exists (select * from sys.databases where name ='$($database)')
         BEGIN
         exec msdb.dbo.rds_task_status @db_name='$($database)'
         END
        "
        $restoreStatus = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$queryRestoreStatus” –Username  $username -Password $password
        if (!($restoreStatus)) {
            write-LogshipLog "$($Database)  doesn't exist , full restore needed;"
            write-LogshipLog "Checking if full backup file exists in S3 for the Database : $($Database)" 
            $s3fullbkupFile = get-s3object -BucketName $($s3BucketName) -Key "$($s3BackupFolder)/$($database).Bak"
            if ($s3fullbkupFile) {
                write-LogshipLog "Full backup exists in S3 for the Database : $($Database); Proceeding Restore"
                try {

                    $dbRestoreFile = "arn:aws:s3:::$($s3BucketName)/$($s3fullbkupFile.key)"

                    $dbRestoreQuery = " exec msdb.dbo.rds_restore_database 
                    @restore_db_name='$($database)', 
                    @s3_arn_to_restore_from='$($dbRestoreFile)',
                    @with_norecovery=1;"

                    Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$dbRestoreQuery” –Username $username -Password $password
                    Start-Sleep -Seconds 60
                    $queryDBRestoreStatus = "exec msdb.dbo.rds_task_status @db_name='$database'"
                    $dbRestoreStatus = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$queryDBRestoreStatus” –Username $username -Password $password
                    $dbRestoreInfo = $dbRestoreStatus | sort-object task_id -Descending | Select-Object -First 1
                    $dbRestoreStatus = $dbRestoreInfo.lifecycle
                    Write-LogshipLog " Full Restore is initiated for Database $($database) and the status is : $($dbRestoreStatus); Please check the task status in the server for further details"

                } catch [Exception] {
                    $msg = "Full Restore Failed for Database :$($database)" + $_.exception.message + "`r`n"
                    Write-LogshipLog $msg
                    $errorcount ++
                }
            } else {
                $msg = "Full Backup Doesn't Exist in S3 for Database :$($database)" + $_.exception.message + "`r`n"
                Write-LogshipLog $msg
                $errorcount ++ 
            }
            continue
        } 
        $lastRestoreinfo = $restoreStatus | sort-object task_id -Descending | Select-Object -First 1 
        $lastsuccessrestore = $restoreStatus | sort-object task_id -Descending | where-object { $_.lifecycle -eq "success" } | Select-Object -First 1 
        if (($lastRestoreinfo.lifecycle -ne "CREATED") -AND ($lastRestoreinfo.lifecycle -ne "IN_PROGRESS")) {
            Write-LogshipLog "No Ongoing Restore on $($Database), proceeding with the transaction log restores"
            $lastRestoredArn = $lastsuccessrestore.S3_object_arn
            $lastRestoredFile = $lastRestoredArn.Split('/')[-1]
            $lastRestoredFilePrimary = $primaryServerBackupFolder + $lastRestoredFile
            Write-LogshipLog "Previously Restored File is $($lastRestoredFile)"
            $queryLastLSN = "Select redo_start_lsn from sys.master_files where database_id=DB_ID('$($database)') and type_desc = 'ROWS'"
            $redostartlsn = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “ $queryLastLSN” –Username  $username -Password $password
            $lastRestoredLSN = $redostartlsn.redo_start_lsn

            $queryFilesToRestore = "
            Select 
            f.physical_device_name
            from backupset s join backupmediafamily f
            on s.media_set_id = f.media_set_id
            where s.last_lsn>('$($lastRestoredLSN)')
            and s.database_name = '$($database)'
            and s.type='L'
            order by s.last_lsn;"
            $filesToRestore = @()
            $files = @()
            $filesToRestore += Invoke-Sqlcmd –ServerInstance "$primarySqlServer" -Database "msdb" –Query “$queryFilesToRestore”
            foreach ($file in $filesToRestore) {
                $files += $file.physical_device_name
            }
           
            if (!$files) {
                Write-LogshipLog "No New files to restore for $($database) ; Proceeding to Next Database "
                continue
                $errorcount ++
            }
            :label foreach ($trnLogBackupfile in $files) {
                try {
                    $trnLogRestorefile = $trnLogBackupfile.Split('\')[-1]
                    Write-LogshipLog -Message "Next File to Restore is : $($trnLogRestorefile) "
                    $s3File = get-s3object -BucketName $($s3BucketName) -Key "$($s3BackupFolder)/$($trnLogRestorefile)"
                    if ($s3file) {
                        Write-LogshipLog -Message "$($trnLogRestorefile)  exists in S3 ; Proceeding Restore"

                        $restoreLogFile = "arn:aws:s3:::$($s3BucketName)/$($s3File.key)"

                        $logRestoreQuery = "exec msdb.dbo.rds_restore_log 
                    @restore_db_name='$($database)', 
                    @s3_arn_to_restore_from='$($restoreLogFile)',
                    @with_norecovery=1;"

                        Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$logRestoreQuery” –Username $username -Password $password
                        Start-Sleep -Seconds 30
                    } else {
                        Write-LogshipLog -Message "$($trnLogBackupfile) Does not exists in S3; Proceeding to Next Database"
                        break label
                    }
                } catch [Exception] {
                    $msg = "Restore Failed " + $_.exception.message + "`r`n"
                    Write-LogshipLog $msg
                    $errorcount ++
                }
            }
        } else {
            Write-LogshipLog "There is an ongoing restore for the DB : $($Database) , Proceeding to Next Database"
            Continue
        }
        $queryLogRestoreStatus = "exec msdb.dbo.rds_task_status @db_name='$database'"
        $logRestoreStatus = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$queryLogRestoreStatus” –Username $username -Password $password
        $logRestoreInfo = $logRestoreStatus | sort-object task_id -Descending | Select-Object -First 1       
        if ($logRestoreInfo.task_id -gt $lastRestoreinfo.task_id) {
            Write-LogshipLog "Log Restore Task Initiated"

         
            
            ## Start the timer
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while (($timer.Elapsed.TotalSeconds -lt $timeoutinSeconds) -and $logRestoreInfo.lifecycle -ne "success") {
                Start-Sleep -Seconds $retryIntervalseconds
                $queryLogRestoreStatus = "exec msdb.dbo.rds_task_status @db_name='$database'"
                $LogRestoreStatus = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$queryLogRestoreStatus” –Username $username -Password $password
                $logRestoreInfo = $LogRestoreStatus | sort-object task_id -Descending | Select-Object -First 1
                $totalSecs = [math]::Round($timer.Elapsed.TotalSeconds, 0)
                Write-LogshipLog "Waiting for restore action to complete ; Elapsed [$totalSecs] seconds..."
                if ($timer.Elapsed.TotalSeconds -gt $timeoutinSeconds) {
                    $timer.Stop()
                    Write-LogshipLog "Timeout Expired"
                }
            }
            $timer.Stop()          
            $LogRestoreStatus = Invoke-Sqlcmd –ServerInstance "$secondarySqlServer" -Database "master" –Query “$queryLogRestoreStatus” –Username $username -Password $password
            $logRestoreInfo = $LogRestoreStatus | sort-object task_id -Descending | Select-Object -First 1
            Switch ($logRestoreInfo.lifecycle) {
                "Success" {
                    Write-LogshipLog "Restore is Successful for Database : $($Database)"
                    Write-LogshipLog "Last Restored File :$($logRestoreInfo.S3_Object_arn)"
                }
                "In_Progress" {
                    Write-LogshipLog "Restore is still In-Progress for the $($Database) beyond the set timeout time ; Please check the status in the server for more details"
                    Write-LogshipLog "File Restoring :$($logRestoreInfo.S3_Object_arn)"
                }
                "Error" {
                    $errorcount++
                    Write-LogshipLog "Restore has failed for Database : $($Database)"
                    Write-LogshipLog "File tried to Restore :$($logRestoreInfo.S3_Object_arn)"
                }
                "Created" {
                    Write-LogshipLog "Restore task created for $($Database) ; But Restore didn't started beyond the set timeout time; Please check the status in the server for more details"
                    Write-LogshipLog "Task created to restore File :$($logRestoreInfo.S3_Object_arn)"
                }
            } 
        } else {
            Write-LogshipLog "Last Restore was not successful for Database $($Database); Please check the server for any error before proceeding the log lestore"
            $errorcount ++
        }
    }
} catch [Exception] {
    $msg = "Restore Failed for one or more Databases: Please check the status in the SQL instance or the logs " + $_.exception.message + "`r`n"
    Write-LogshipLog $msg
}
if ($errorcount -eq 0) {
    Write-LogshipLog -Level "**********INFO" -Message ":Completed Transaction Log Restore on $($secondarySqlServer)************"
} else {
    Write-LogshipLog "*********Restore Failed for one or more Databases: Please check the status in the SQL instance or the logs******"
    Write-LogshipLog -Level "**********INFO" -Message ":Completed Transaction Log Restore on $($secondarySqlServer)************"
    throw 
}
if ($errorcount -eq 0) {
    Write-LogshipLog -Level "**********INFO" -Message ":Completed Transaction Log Restore on $($secondarySqlServer)************"
} else {
    Write-LogshipLog "*********Restore Failed for one or more Databases: Please check the status in the SQL instance or the logs******"
    Write-LogshipLog -Level "**********INFO" -Message ":Completed Transaction Log Restore on $($secondarySqlServer)************"
    throw 
}