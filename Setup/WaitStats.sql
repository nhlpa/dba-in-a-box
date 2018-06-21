if object_id('dbo.WaitStats', 'U') is not null
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

