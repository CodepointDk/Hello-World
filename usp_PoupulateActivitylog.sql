USE [DBA_DB]
GO

IF EXISTS ( SELECT * FROM sys.objects WHERE   object_id = OBJECT_ID(N'usp_PoupulateActivitylog'))
	DROP PROCEDURE [dbo].[usp_PoupulateActivitylog]
GO

IF NOT EXISTS ( SELECT * FROM sys.objects WHERE   object_id = OBJECT_ID(N'usp_PoupulateActivitylog'))
BEGIN
	CREATE TABLE [dbo].[sp_who_over_time](
		[Login] [sysname] NULL,
		[HostName] [sysname] NULL,
		[DBName] [sysname] NULL,
		[LastBatch] [varchar](1000) NULL,
		[ProgramName] [varchar](1000) NULL
	) ON [PRIMARY]
END
GO

CREATE PROCEDURE [dbo].[usp_PoupulateActivitylog]
as
BEGIN

if OBJECT_ID('tempdb..##sp_who2') is not null
	DROP TABLE ##sp_who2

--Create temp table to hold data for user activities
CREATE TABLE ##sp_who2 (SPID INT,Status VARCHAR(255),
      Login  VARCHAR(255),HostName  VARCHAR(255), 
      BlkBy  VARCHAR(255),DBName  VARCHAR(255), 
      Command VARCHAR(255),CPUTime INT, 
      DiskIO INT,LastBatch VARCHAR(255), 
      ProgramName VARCHAR(255),SPID2 INT, 
      REQUESTID INT) 
INSERT INTO ##sp_who2 EXEC sp_who2

UPDATE 
sp_who_over_time 
SET 
sp_who_over_time.LastBatch = SW2.LastBatch
FROM
sp_who_over_time SPWOT
INNER JOIN 
##sp_who2 SW2
ON 
SPWOT.Login = SW2.Login AND SPWOT.HostName = SW2.HostName AND SPWOT.DBName = SW2.DBName AND SPWOT.ProgramName = SW2.ProgramName

INSERT INTO sp_who_over_time (Login, HostName, DBName, LastBatch, ProgramName)
SELECT  b.Login, b.HostName, b.DBName, MAX(b.LastBatch), b.ProgramName
FROM    ##sp_who2 b
WHERE   b.SPID > 50
AND (b.Login + b.HostName + b.DBName + b.ProgramName) NOT IN (SELECT (c.Login + c.HostName + c.DBName + c.ProgramName) FROM sp_who_over_time c)
GROUP BY Login, HostName, DBName, ProgramName

DROP TABLE ##sp_who2
END
GO

/* SETUP COLLECTION JOB */
USE [msdb]
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Collect Activity', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'SQL 2000 & 2005 Upgrade Project.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step 1', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC usp_PoupulateActivitylog', 
		@database_name=N'DBA_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Rec. Schedule', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20150210, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO



