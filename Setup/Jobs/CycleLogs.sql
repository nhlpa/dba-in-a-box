declare @categoryName varchar(50) = '[MAINTENANCE]';
declare @jobId uniqueidentifier;
declare @jobName varchar(50) = 'DBA_CYCLELOGS';
declare @jobDescription varchar(255) = 'Daily cycle of log and error log files.';
declare @scheduleName varchar(50) = '[DBA_CYCLELOGS - Daily]';

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
  ,@enabled = 0
  ,@owner_login_name = 'sa'
  ,@description = @jobDescription
  ,@category_name = @categoryName
  ,@notify_level_eventlog = 2
  ,@job_id = @jobId output;

exec msdb.dbo.sp_add_jobstep
  @job_id = @jobId
  ,@step_name = 'Cycle log file.'
  ,@command = N'exec sys.sp_cycle_errorlog;'
  ,@on_success_action = 3
  ,@on_fail_action = 2;

exec msdb.dbo.sp_add_jobstep
  @job_id = @jobId
  ,@step_name = 'If exsits, cycle error log file.'
  ,@command = N'if exists (select null from sys.dm_server_services dss where dss.servicename like N''SQL Server Agent (%'') exec msdb.dbo.sp_cycle_agent_errorlog;'
  ,@on_success_action = 1
  ,@on_fail_action = 2;

-- schedules
exec msdb.dbo.sp_attach_schedule
  @job_id = @jobId
  ,@schedule_name = @scheduleName;

-- server
exec msdb.dbo.sp_add_jobserver
  @job_id = @jobId
  ,@server_name = N'(local)';

go