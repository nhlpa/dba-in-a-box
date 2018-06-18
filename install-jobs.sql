/*
Creates the tables for storage of:
- sp_whoisactive snapshots
- wait stats
- index rebuilds
*/
use DBA;
go

if object_id('dbo.CommandLog') is not null
  drop table dbo.CommandLog;

create table dbo.CommandLog
(
  ID int identity(1, 1) not null
  ,DatabaseName sysname null
  ,SchemaName sysname null
  ,ObjectName sysname null
  ,ObjectType char(2) null
  ,IndexName sysname null
  ,IndexType tinyint null
  ,StatisticsName sysname null
  ,PartitionNumber int null
  ,ExtendedInfo xml null
  ,Command nvarchar(max) not null
  ,CommandType nvarchar(60) not null
  ,StartTime datetime not null
  ,EndTime datetime null
  ,ErrorNumber int null
  ,ErrorMessage nvarchar(max) null
  ,constraint PK_CommandLog primary key(ID asc)
);
go

if object_id('dbo.WaitStats') is not null
  drop table dbo.WaitStats;

create table dbo.WaitStats
(
  Id int identity(1, 1) not null
  ,CollectionTime smalldatetime
  ,WaitType nvarchar(100)
  ,WaitTimeSeconds decimal(16, 2)
  ,CpuDelaySeconds decimal(16, 2)
  ,SignalWaitSeconds decimal(16, 2)
  ,WaitingTasks int
  ,WaitPercent decimal(5, 2)
  ,AvgWaitTimeSeconds decimal(16, 2)
  ,AvgCpuDelaySeconds decimal(16, 2)
  ,AverageSignalWaitSeconds decimal(16, 2)
  ,constraint pk_waitstats primary key(Id asc)
);
go

if object_id('dbo.WhoIsActive') is not null
  drop table dbo.WhoIsActive;

create table dbo.WhoIsActive
(
  [dd hh:mm:ss.mss] varchar(8000) null
  ,session_id smallint not null
  ,sql_text xml null
  ,sql_command xml null
  ,login_name nvarchar(128) not null
  ,wait_info nvarchar(4000) null
  ,tran_log_writes nvarchar(4000) null
  ,CPU varchar(30) null
  ,tempdb_allocations varchar(30) null
  ,tempdb_current varchar(30) null
  ,blocking_session_id smallint null
  ,reads varchar(30) null
  ,writes varchar(30) null
  ,physical_reads varchar(30) null
  ,query_plan xml null
  ,used_memory varchar(30) null
  ,status varchar(30) not null
  ,tran_start_time datetime null
  ,open_tran_count varchar(30) null
  ,percent_complete varchar(30) null
  ,host_name nvarchar(128) null
  ,database_name nvarchar(128) null
  ,program_name nvarchar(128) null
  ,start_time datetime not null
  ,login_time datetime null
  ,request_id int null
  ,collection_time datetime not null
);
go

create clustered index cx_whoisactive_collectiontime
  on dbo.WhoIsActive(collection_time asc);
go
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
declare @jobName varchar(50) = 'DBA_CHECKDB';
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
declare @jobName varchar(50) = 'DBA_INDEX-STATS-LOGS';
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
declare @jobName varchar(50) = 'DBA_WHOISACTIVE';
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
/*
sp_CollectWaitStats (run daily)
*/
use DBA;
go

if object_id('dbo.sp_CollectWaitStats') is null
  exec('create procedure dbo.sp_CollectWaitStats as return 0;');
go

alter procedure dbo.sp_CollectWaitStats
as
  set nocount on;

  declare @retention int = 7;

  -- capture
  with waits as (
    select
      wait_type
      ,wait_time_ms / 1000.0 as wait_time_s
      ,(wait_time_ms - signal_wait_time_ms) / 1000.0 as cpu_delay_s
      ,signal_wait_time_ms / 1000.0 as signal_wait_time_s
      ,waiting_tasks_count as waiting_tasks
      ,100.0 * wait_time_ms / sum(wait_time_ms) over () as wait_percent
      ,row_number() over (order by wait_time_ms desc) as r
    from
      sys.dm_os_wait_stats
    where
      wait_type not in (N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE', N'CXCONSUMER', N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE', N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX', N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_XE_GETTARGETSTATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_RECOVERY', N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT')
      and waiting_tasks_count > 0
  )
  insert into dbo.WaitStats
  select
    cast(getdate() as smalldatetime)
    ,max(w1.wait_type)
    ,cast(max(w1.wait_time_s) as decimal(16, 2))
    ,cast(max(w1.cpu_delay_s) as decimal(16, 2))
    ,cast(max(w1.signal_wait_time_s) as decimal(16, 2))
    ,max(w1.waiting_tasks)
    ,cast(max(w1.wait_percent) as decimal(5, 2))
    ,cast((max(w1.wait_time_s) / max(w1.waiting_tasks)) as decimal(16, 4))
    ,cast((max(w1.cpu_delay_s) / max(w1.waiting_tasks)) as decimal(16, 4))
    ,cast((max(w1.signal_wait_time_s) / max(w1.waiting_tasks)) as decimal(16, 4))
  from
    waits w1
  inner join
    waits w2
    on w2.r <= w1.r
  group by
    w1.r
  having
    sum(w2.wait_percent) - max(w1.wait_percent) < 95; -- percentage threshold

  -- cleanup
  delete from dbo.WaitStats where CollectionTime < dateadd(day, -(@retention), getdate());
go

/*
WAITSTAITS JOB
*/
use msdb;
go

declare @categoryName varchar(50) = '[MONITOR]';
declare @jobId uniqueidentifier;
declare @jobName varchar(50) = 'DBA_WAITSTATS';
declare @jobDescription varchar(255) = 'Collect rollups from sys.dm_os_wait_stats';
declare @scheduleName varchar(50) = '[WAITSTATS - Daily]';

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
  ,@step_name = 'Run dbo.sp_CollectWaitStats'
  ,@command = N'exec dbo.sp_CollectWaitStats'
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
