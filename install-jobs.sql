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
    ,@FragmentationLevel2 = 30;

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
if not exists (select null
from msdb.dbo.sysschedules
where name = @scheduleName)
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
/*
  sp_CollectWhoIsActive  
*/
use DBA;
go

if object_id('dbo.sp_CollectWhoIsActive') is null
  exec ('create procedure dbo.sp_CollectWhoIsActive as return 0;');
go

alter procedure dbo.sp_CollectWhoIsActive
as
  set nocount on;

  declare
    @retention int = 7
    ,@destination_table varchar(500) = 'WhoIsActive'
    ,@destination_database sysname = 'DBA'
    ,@schema varchar(max)
    ,@SQL nvarchar(4000)
    ,@parameters nvarchar(500)
    ,@exists bit;

  set @destination_table = @destination_database + '.dbo.' + @destination_table;

  -- create the logging table
  if object_id(@destination_table) is null
    begin;
      exec dbo.sp_WhoIsActive
        @get_transaction_info = 1
        ,@get_outer_command = 1
        ,@get_plans = 1
        ,@return_schema = 1
        ,@schema = @schema output;

      set @schema = replace(@schema, '<table_name>', @destination_table);

      exec (@schema);
    end;

  -- create clustered index
  set @SQL = 'USE ' + quotename(@destination_database) + '; IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(@destination_table) AND name = N''cx_collection_time'') SET @exists = 0';
  set @parameters = N'@destination_table varchar(500), @exists bit OUTPUT';

  exec sys.sp_executesql
    @SQL
    ,@parameters
    ,@destination_table = @destination_table
    ,@exists = @exists output;

  if @exists = 0
    begin;
      set @SQL = 'CREATE CLUSTERED INDEX cx_collection_time ON ' + @destination_table + '(collection_time ASC)';

      exec (@SQL);
    end;

  -- collect activity
  exec dbo.sp_WhoIsActive
    @get_transaction_info = 1
    ,@get_outer_command = 1
    ,@get_plans = 1
    ,@destination_table = @destination_table;

  -- cleanup
  set @SQL = 'DELETE FROM ' + @destination_table + ' WHERE collection_time < DATEADD(day, -' + cast(@retention as varchar(10)) + ', GETDATE());';

  exec (@SQL);
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
