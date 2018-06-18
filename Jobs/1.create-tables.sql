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