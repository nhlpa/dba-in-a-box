/*
Storage of index rebuilds
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
  ,constraint pk_commandlog primary key(ID asc)
);
go