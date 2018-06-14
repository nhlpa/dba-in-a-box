/*
  sp_CheckDb (run weekly)
*/
use DBA;
go

if object_id('dbo.sp_CheckDb') is null
  exec ('create procedure dbo.sp_CheckDb as return 0;');
go

alter procedure dbo.sp_CheckDb
as
  set nocount on;

  -- checkdb all databases
  exec dbo.DatabaseIntegrityCheck
    @Databases = 'ALL_DATABASES'
    ,@CheckCommands = 'CHECKDB';
go

/*
  CHECKDB job
*/
use msdb;
go

declare @categoryName varchar(50) = '[MAINTENANCE]';
declare @jobId uniqueidentifier;
declare @jobName varchar(50) = 'CHECKDB';
declare @jobDescription varchar(255) = 'CHECKDB on all databases';
declare @scheduleName varchar(50) = '[CHECKDB - Weekly]';

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
    ,@freq_type = 8
    ,@freq_interval = 1
    ,@freq_subday_type = 1
    ,@freq_subday_interval = 0
    ,@freq_relative_interval = 0
    ,@freq_recurrence_factor = 1
    ,@active_start_date = 19900101
    ,@active_end_date = 99991231
    ,@active_start_time = 235900
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
  ,@step_name = 'Run dbo.sp_CheckDb'
  ,@command = N'exec dbo.sp_CheckDb'
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