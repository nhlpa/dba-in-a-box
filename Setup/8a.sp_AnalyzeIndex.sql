/*
sp_AnalyzeIndexes

Executes sp_BlitzIndex for all databases, or specific database.
*/
use DBA;
go
 
if object_id('dbo.sp_AnalyzeIndexes') is null
  exec ('create procedure dbo.sp_AnalyzeIndexes as return 0;');
go

alter procedure dbo.sp_AnalyzeIndexes
  @DatabaseName nvarchar(128) = null
as
  set nocount on;

  declare @__DatabaseName nvarchar(128) = @DatabaseName

  exec dbo.sp_BlitzIndex
    @DatabaseName = @__DatabaseName,
    @GetAllDatabases = 1;
go