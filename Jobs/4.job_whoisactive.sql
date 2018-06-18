/*
sp_CollectWhoIsActive  (run every 60s)
*/
use DBA;
go

if object_id('dbo.sp_CollectWhoIsActive') is null
  exec ('create procedure dbo.sp_CollectWhoIsActive as return 0;');
go

alter procedure dbo.sp_CollectWhoIsActive
as
  set nocount on;

  declare @databaseName varchar(128) = 'WhoIsActive';
  declare @retention int = 7;

  -- capture
  exec dbo.sp_WhoIsActive
    @get_transaction_info = 1
    ,@get_outer_command = 1
    ,@get_plans = 1
    ,@destination_table = databaseName;

  -- cleanup
  delete from WhoIsActive where collection_time < dateadd(day, -(@retention), getdate());
go

/*
WHOISACTIVE JOB
*/
use msdb;
go

declare @categoryName varchar(50) = '[MONITOR]';
declare @jobId uniqueidentifier;
declare @jobName varchar(50) = 'WHOISACTIVE';
declare @jobDescription varchar(255) = 'Collect snapshot of sp_whoIsActive';
declare @scheduleName varchar(50) = '[WHOISACTIVE - 60s]';

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
if not exists (select null
from msdb.dbo.sysschedules
where name = @scheduleName)
  exec msdb.dbo.sp_add_schedule
    @schedule_name = @scheduleName
    ,@enabled = 1
    ,@freq_type = 4
    ,@freq_interval = 1
    ,@freq_subday_type = 2
    ,@freq_subday_interval = 60
    ,@freq_relative_interval = 0
    ,@freq_recurrence_factor = 0
    ,@active_start_date = 19900101
    ,@active_end_date = 99991231
    ,@active_start_time = 0
    ,@active_end_time = 235959;

-- job
if exists (select null
from msdb.dbo.sysjobs
where name = @jobName)
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
  ,@step_name = 'Run dbo.sp_CollectWhoIsActive'
  ,@command = N'exec dbo.sp_CollectWhoIsActive'
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