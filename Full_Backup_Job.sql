USE [msdb]
GO
BEGIN TRANSACTION
/************* Provide  the Powershell Script location in this Block ********************************** 

Eg: 
DECLARE @script_location sysname ='C:\LogshippingScripts\Logshipping_Full_Backup.ps1'

*/

DECLARE @script_location sysname ='C:\LogshippingScripts\Logshipping_Full_Backup.ps1' --- Replace the file location

/********************************* End of Input Details *****************************************/
DECLARE @job_name sysname = 'Logshipping_FullBackup_Primary'
DECLARE @owner_login_name sysname ='sa'
DECLARE @step_name sysname ='Full_Backup_Primary'
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
DECLARE @command NVARCHAR(max)=N'$ErrorActionPreference ="Stop"
try
{
powershell.exe "'+@script_location+'"
}
Catch{
Throw
}'

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job 
		@job_name=@job_name,
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Restore_Secondary]    Script Date: 4/5/2022 5:35:10 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep 
		@job_id=@jobId, 
		@step_name=@step_name, 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=@command, 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


