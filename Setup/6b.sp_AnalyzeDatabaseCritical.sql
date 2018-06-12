/*
  sp_AnalyzeDatabaseCritical
*/
use DBA;
go

if object_id('dbo.sp_AnalyzeDatabaseCritical') is null
  exec ('create procedure dbo.sp_AnalyzeDatabaseCritical as return 0;');
go

alter procedure dbo.sp_AnalyzeDatabaseCritical
as
  set nocount on;

  exec dbo.sp_Blitz
    @IgnorePrioritiesAbove = 100
    ,@CheckServerInfo = 0
    ,@CheckUserDatabaseObjects = 1;
go
