/*
  sp_AnalyzeServerCritical
*/
use DBA;
go

if object_id('dbo.sp_AnalyzeServerCritical') is null
  exec ('create procedure dbo.sp_AnalyzeServerCritical as return 0;');
go

alter procedure dbo.sp_AnalyzeServerCritical
as
  set nocount on;

  exec dbo.sp_Blitz
    @IgnorePrioritiesAbove = 100
    ,@CheckUserDatabaseObjects = 0;
go