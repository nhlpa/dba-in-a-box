/*
sp_IndexStatsLogs (run daily)
*/
use DBA;
go

if object_id('dbo.sp_IndexStatsLogs') is null
  exec ('create procedure dbo.sp_IndexStatsLogs as return 0;');
go

alter procedure dbo.sp_IndexStatsLogs
as
  set nocount on;

  -- rebuild indexes for user databases
  execute dbo.IndexOptimize
    @Databases = 'USER_DATABASES'
    ,@FragmentationLow = null
    ,@FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'
    ,@FragmentationHigh = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'
    ,@FragmentationLevel1 = 5
    ,@FragmentationLevel2 = 30
    ,@LogToTable = 'Y';

  -- update column statistics for user databases
  execute dbo.IndexOptimize
    @Databases = 'USER_DATABASES'
    ,@FragmentationLow = null
    ,@FragmentationMedium = null
    ,@FragmentationHigh = null
    ,@UpdateStatistics = 'COLUMNS';

  -- cycle error log
  exec sys.sp_cycle_errorlog;

  -- cycle agent error log
  if exists (
    select
      null
    from
      sys.dm_server_services dss
    where
      dss.servicename like N'SQL Server Agent (%'
  )
    exec msdb.dbo.sp_cycle_agent_errorlog;
go

/*
INDEX-STATS-LOGS job
*/
use msdb;
go

declare @categoryName varchar(50) = '[MAINTENANCE]';
declare @jobId uniqueidentifier;
declare @jobName varchar(50) = 'INDEX-STATS-LOGS';
declare @jobDescription varchar(255) = 'Index maintenance, columns statistics and log cycling.';
declare @scheduleName varchar(50) = '[INDEX-STATS-LOGS - Weekly]';

-- category
if not exists (
  select
    name
  from
    msdb.dbo.syscategories
  where
    name = @categoryName
    and category_class = 1
)
  begin
    exec msdb.dbo.sp_add_category
      @class = N'JOB'
      ,@type = N'LOCAL'
      ,@name = @categoryName;
  end;

-- schedule
if not exists (select null from msdb.dbo.sysschedules where name = @scheduleName)
  exec msdb.dbo.sp_add_schedule
    @schedule_name = @scheduleName
    ,@enabled = 1
    ,@freq_type = 4
    ,@freq_interval = 1
    ,@freq_subday_type = 1
    ,@freq_subday_interval = 0
    ,@freq_relative_interval = 0
    ,@freq_recurrence_factor = 0
    ,@active_start_date = 19900101
    ,@active_end_date = 99991231
    ,@active_start_time = 235900
    ,@active_end_time = 235959;

-- job
if exists (select null from msdb.dbo.sysjobs where name = @jobName)
  begin
    exec msdb.dbo.sp_delete_job
      @job_name = @jobName
      ,@delete_unused_schedule = 0;
  end;

exec msdb.dbo.sp_add_job
  @job_name = @jobName
  ,@enabled = 1
  ,@owner_login_name = 'sa'
  ,@description = @jobDescription
  ,@category_name = @categoryName
  ,@notify_level_eventlog = 2
  ,@job_id = @jobId output;

exec msdb.dbo.sp_add_jobstep
  @job_id = @jobId
  ,@step_name = 'Run dbo.sp_IndexStatsLogs'
  ,@command = N'exec dbo.sp_IndexStatsLogs'
  ,@on_success_action = 1
  ,@on_fail_action = 2
  ,@database_name = N'DBA';

-- schedules
exec msdb.dbo.sp_attach_schedule
  @job_id = @jobId
  ,@schedule_name = @scheduleName;

-- server
exec msdb.dbo.sp_add_jobserver
  @job_id = @jobId
  ,@server_name = N'(local)';
