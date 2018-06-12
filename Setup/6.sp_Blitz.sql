/*
  https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/sp_Blitz.sql
*/

use DBA;
go

if OBJECT_ID('dbo.sp_Blitz') is null
  EXEC ('CREATE PROCEDURE dbo.sp_Blitz AS RETURN 0;');
go

alter procedure [dbo].[sp_Blitz]
  @Help tinyint = 0 ,
  @CheckUserDatabaseObjects tinyint = 1 ,
  @CheckProcedureCache tinyint = 0 ,
  @OutputType varchar(20) = 'TABLE' ,
  @OutputProcedureCache tinyint = 0 ,
  @CheckProcedureCacheFilter varchar(10) = null ,
  @CheckServerInfo tinyint = 0 ,
  @SkipChecksServer nvarchar(256) = null ,
  @SkipChecksDatabase nvarchar(256) = null ,
  @SkipChecksSchema nvarchar(256) = null ,
  @SkipChecksTable nvarchar(256) = null ,
  @IgnorePrioritiesBelow int = null ,
  @IgnorePrioritiesAbove int = null ,
  @OutputServerName nvarchar(256) = null ,
  @OutputDatabaseName nvarchar(256) = null ,
  @OutputSchemaName nvarchar(256) = null ,
  @OutputTableName nvarchar(256) = null ,
  @OutputXMLasNVARCHAR tinyint = 0 ,
  @EmailRecipients varchar(MAX) = null ,
  @EmailProfile sysname = null ,
  @SummaryMode tinyint = 0 ,
  @BringThePain tinyint = 0 ,
  @Debug tinyint  = 0,
  @VersionDate datetime = null OUTPUT
with
  RECOMPILE
as
    set NOCOUNT on;
	set transaction ISOLATION LEVEL read UNCOMMITTED;
	declare @Version varchar(30);
	set @Version = '6.6';
	set @VersionDate = '20180601';
	set @OutputType = UPPER(@OutputType);

	if @Help = 1 print '
	/*
	sp_Blitz from http://FirstResponderKit.org
	
	This script checks the health of your SQL Server and gives you a prioritized
	to-do list of the most urgent things you should consider fixing.

	To learn more, visit http://FirstResponderKit.org where you can download new
	versions for free, watch training videos on how it works, get more info on
	the findings, contribute your own code, and more.

	Known limitations of this version:
	 - Only Microsoft-supported versions of SQL Server. Sorry, 2005 and 2000.
	 - If a database name has a question mark in it, some tests will fail. Gotta
	   love that unsupported sp_MSforeachdb.
	 - If you have offline databases, sp_Blitz fails the first time you run it,
	   but does work the second time. (Hoo, boy, this will be fun to debug.)
      - @OutputServerName will output QueryPlans as NVARCHAR(MAX) since Microsoft
	    has refused to support XML columns in Linked Server queries. The bug is now
		16 years old! *~ \o/ ~*

	Unknown limitations of this version:
	 - None.  (If we knew them, they would be known. Duh.)

     Changes - for the full list of improvements and fixes in this version, see:
     https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/

	Parameter explanations:

	@CheckUserDatabaseObjects	1=review user databases for triggers, heaps, etc. Takes more time for more databases and objects.
	@CheckServerInfo			1=show server info like CPUs, memory, virtualization
	@CheckProcedureCache		1=top 20-50 resource-intensive cache plans and analyze them for common performance issues.
	@OutputProcedureCache		1=output the top 20-50 resource-intensive plans even if they did not trigger an alarm
	@CheckProcedureCacheFilter	''CPU'' | ''Reads'' | ''Duration'' | ''ExecCount''
	@OutputType					''TABLE''=table | ''COUNT''=row with number found | ''MARKDOWN''=bulleted list | ''SCHEMA''=version and field list | ''NONE'' = none
	@IgnorePrioritiesBelow		50=ignore priorities below 50
	@IgnorePrioritiesAbove		50=ignore priorities above 50
	For the rest of the parameters, see https://www.BrentOzar.com/blitz/documentation for details.

    MIT License
	
	Copyright for portions of sp_Blitz are held by Microsoft as part of project
	tigertoolbox and are provided under the MIT license:
	https://github.com/Microsoft/tigertoolbox
	
	All other copyright for sp_Blitz are held by Brent Ozar Unlimited, 2017.

	Copyright (c) 2017 Brent Ozar Unlimited

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

	*/';
	else if @OutputType = 'SCHEMA'
	begin
  select FieldList = '[Priority] TINYINT, [FindingsGroup] VARCHAR(50), [Finding] VARCHAR(200), [DatabaseName] NVARCHAR(128), [URL] VARCHAR(200), [Details] NVARCHAR(4000), [QueryPlan] NVARCHAR(MAX), [QueryPlanFiltered] NVARCHAR(MAX), [CheckID] INT';

end;
	else /* IF @OutputType = 'SCHEMA' */
	begin

  declare @StringToExecute nvarchar(4000)
			,@curr_tracefilename nvarchar(500)
			,@base_tracefilename nvarchar(500)
			,@indx int
			,@query_result_separator char(1)
			,@EmailSubject nvarchar(255)
			,@EmailBody nvarchar(MAX)
			,@EmailAttachmentFilename nvarchar(255)
			,@ProductVersion nvarchar(128)
			,@ProductVersionMajor decimal(10,2)
			,@ProductVersionMinor decimal(10,2)
			,@CurrentName nvarchar(128)
			,@CurrentDefaultValue nvarchar(200)
			,@CurrentCheckID int
			,@CurrentPriority int
			,@CurrentFinding varchar(200)
			,@CurrentURL varchar(200)
			,@CurrentDetails nvarchar(4000)
			,@MsSinceWaitsCleared decimal(38,0)
			,@CpuMsSinceWaitsCleared decimal(38,0)
			,@ResultText nvarchar(MAX)
			,@crlf nvarchar(2)
			,@Processors int
			,@NUMANodes int
			,@MinServerMemory bigint
			,@MaxServerMemory bigint
			,@ColumnStoreIndexesInUse bit
			,@TraceFileIssue bit
			-- Flag for Windows OS to help with Linux support
			,@IsWindowsOperatingSystem bit
			,@DaysUptime numeric(23,2);

  set @crlf = NCHAR(13) + NCHAR(10);
  set @ResultText = 'sp_Blitz Results: ' + @crlf;

  /* Last startup */
  select @DaysUptime = CAST(DATEDIFF(HOUR, create_date, GETDATE()) / 24. as numeric(23, 2))
  from sys.databases
  where  database_id = 2;

  if @DaysUptime = 0
		    set @DaysUptime = .01;

  /*
		--TOURSTOP01--
		See https://www.BrentOzar.com/go/blitztour for a guided tour.

		We start by creating #BlitzResults. It's a temp table that will store all of
		the results from our checks. Throughout the rest of this stored procedure,
		we're running a series of checks looking for dangerous things inside the SQL
		Server. When we find a problem, we insert rows into #BlitzResults. At the
		end, we return these results to the end user.

		#BlitzResults has a CheckID field, but there's no Check table. As we do
		checks, we insert data into this table, and we manually put in the CheckID.
		For a list of checks, visit http://FirstResponderKit.org.
		*/
  if OBJECT_ID('tempdb..#BlitzResults') is not null
			drop table #BlitzResults;
  create table #BlitzResults
  (
    ID int identity(1, 1) ,
    CheckID int ,
    DatabaseName nvarchar(128) ,
    Priority tinyint ,
    FindingsGroup varchar(50) ,
    Finding varchar(200) ,
    URL varchar(200) ,
    Details nvarchar(4000) ,
    QueryPlan [xml] null ,
    QueryPlanFiltered [nvarchar](MAX) null
  );

  if OBJECT_ID('tempdb..#TemporaryDatabaseResults') is not null
			drop table #TemporaryDatabaseResults;
  create table #TemporaryDatabaseResults
  (
    DatabaseName nvarchar(128) ,
    Finding nvarchar(128)
  );

  /*
		You can build your own table with a list of checks to skip. For example, you
		might have some databases that you don't care about, or some checks you don't
		want to run. Then, when you run sp_Blitz, you can specify these parameters:
		@SkipChecksDatabase = 'DBAtools',
		@SkipChecksSchema = 'dbo',
		@SkipChecksTable = 'BlitzChecksToSkip'
		Pass in the database, schema, and table that contains the list of checks you
		want to skip. This part of the code checks those parameters, gets the list,
		and then saves those in a temp table. As we run each check, we'll see if we
		need to skip it.

		Really anal-retentive users will note that the @SkipChecksServer parameter is
		not used. YET. We added that parameter in so that we could avoid changing the
		stored proc's surface area (interface) later.
		*/
  /* --TOURSTOP07-- */
  if OBJECT_ID('tempdb..#SkipChecks') is not null
			drop table #SkipChecks;
  create table #SkipChecks
  (
    DatabaseName nvarchar(128) ,
    CheckID int ,
    ServerName nvarchar(128)
  );
  create clustered index IX_CheckID_DatabaseName on #SkipChecks(CheckID, DatabaseName);

  if @SkipChecksTable is not null
    and @SkipChecksSchema is not null
    and @SkipChecksDatabase is not null
			begin

    if @Debug in (1, 2) raiserror('Inserting SkipChecks', 0, 1) with NOWAIT;

    set @StringToExecute = 'INSERT INTO #SkipChecks(DatabaseName, CheckID, ServerName )
				SELECT DISTINCT DatabaseName, CheckID, ServerName
				FROM ' + QUOTENAME(@SkipChecksDatabase) + '.' + QUOTENAME(@SkipChecksSchema) + '.' + QUOTENAME(@SkipChecksTable)
					+ ' WHERE ServerName IS NULL OR ServerName = SERVERPROPERTY(''ServerName'') OPTION (RECOMPILE);';
    EXEC(@StringToExecute);
  end;

  if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 106 )
    and (select convert(int,value_in_use)
    from sys.configurations
    where name = 'default trace enabled' ) = 1
			begin
    -- Flag for Windows OS to help with Linux support
    if exists ( select 1
    from sys.all_objects
    where   name = 'dm_os_host_info' )
					begin
      select @IsWindowsOperatingSystem = case when host_platform = 'Windows' then 1 else 0 end
      from sys.dm_os_host_info
    ;
    end;
					else
					begin
      select @IsWindowsOperatingSystem = 1
    ;
    end;

    select @curr_tracefilename = [path]
    from sys.traces
    where is_default = 1
    ;
    set @curr_tracefilename = reverse(@curr_tracefilename);

    -- Set the trace file path separator based on underlying OS
    if (@IsWindowsOperatingSystem = 1)
					begin
      select @indx = patindex('%\%', @curr_tracefilename)
      ;
      set @curr_tracefilename = reverse(@curr_tracefilename)
      ;
      set @base_tracefilename = left( @curr_tracefilename,len(@curr_tracefilename) - @indx) + '\log.trc'
    ;
    end;
					else
					begin
      select @indx = patindex('%/%', @curr_tracefilename)
      ;
      set @curr_tracefilename = reverse(@curr_tracefilename)
      ;
      set @base_tracefilename = left( @curr_tracefilename,len(@curr_tracefilename) - @indx) + '/log.trc'
    ;
    end;

  end;

  /* If the server has any databases on Antiques Roadshow, skip the checks that would break due to CTEs. */
  if @CheckUserDatabaseObjects = 1 and exists(select *
    from sys.databases
    where compatibility_level < 90)
		begin
    set @CheckUserDatabaseObjects = 0;
    print 'Databases with compatibility level < 90 found, so setting @CheckUserDatabaseObjects = 0.';
    print 'The database-level checks rely on CTEs, which are not supported in SQL 2000 compat level databases.';
    print 'Get with the cool kids and switch to a current compatibility level, Grandpa. To find the problems, run:';
    print 'SELECT * FROM sys.databases WHERE compatibility_level < 90;';
    insert  into #BlitzResults
      ( CheckID ,
      Priority ,
      FindingsGroup ,
      Finding ,
      URL ,
      Details
      )
    select 204 as CheckID ,
      0 as Priority ,
      'Informational' as FindingsGroup ,
      '@CheckUserDatabaseObjects Disabled' as Finding ,
      'https://www.BrentOzar.com/blitz/' as URL ,
      'Since you have databases with compatibility_level < 90, we can''t run @CheckUserDatabaseObjects = 1. To find them: SELECT * FROM sys.databases WHERE compatibility_level < 90' as Details;
  end;

  /* --TOURSTOP08-- */
  /* If the server is Amazon RDS, skip checks that it doesn't allow */
  if left(CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as varchar(8000)), 8) = 'EC2AMAZ-'
    and left(CAST(SERVERPROPERTY('MachineName') as varchar(8000)), 8) = 'EC2AMAZ-'
    and left(CAST(SERVERPROPERTY('ServerName') as varchar(8000)), 8) = 'EC2AMAZ-'
			begin
    insert into #SkipChecks
      (CheckID)
    values
      (6);
    insert into #SkipChecks
      (CheckID)
    values
      (29);
    insert into #SkipChecks
      (CheckID)
    values
      (30);
    insert into #SkipChecks
      (CheckID)
    values
      (31);
    insert into #SkipChecks
      (CheckID)
    values
      (40);
    /* TempDB only has one data file */
    insert into #SkipChecks
      (CheckID)
    values
      (57);
    insert into #SkipChecks
      (CheckID)
    values
      (59);
    insert into #SkipChecks
      (CheckID)
    values
      (61);
    insert into #SkipChecks
      (CheckID)
    values
      (62);
    insert into #SkipChecks
      (CheckID)
    values
      (68);
    insert into #SkipChecks
      (CheckID)
    values
      (69);
    insert into #SkipChecks
      (CheckID)
    values
      (73);
    insert into #SkipChecks
      (CheckID)
    values
      (79);
    insert into #SkipChecks
      (CheckID)
    values
      (92);
    insert into #SkipChecks
      (CheckID)
    values
      (94);
    insert into #SkipChecks
      (CheckID)
    values
      (96);
    insert into #SkipChecks
      (CheckID)
    values
      (98);
    insert into #SkipChecks
      (CheckID)
    values
      (100);
    /* Remote DAC disabled */
    insert into #SkipChecks
      (CheckID)
    values
      (123);
    insert into #SkipChecks
      (CheckID)
    values
      (177);
    insert into #SkipChecks
      (CheckID)
    values
      (180);
    /* 180/181 are maintenance plans */
    insert into #SkipChecks
      (CheckID)
    values
      (181);
  end;
  /* Amazon RDS skipped checks */

  /* If the server is ExpressEdition, skip checks that it doesn't allow */
  if CAST(SERVERPROPERTY('Edition') as nvarchar(1000)) like N'%Express%'
			begin
    insert into #SkipChecks
      (CheckID)
    values
      (30);
    /* Alerts not configured */
    insert into #SkipChecks
      (CheckID)
    values
      (31);
    /* Operators not configured */
    insert into #SkipChecks
      (CheckID)
    values
      (61);
    /* Agent alerts 19-25 */
    insert into #SkipChecks
      (CheckID)
    values
      (73);
    /* Failsafe operator */
    insert into #SkipChecks
      (CheckID)
    values
      (96);
  /* Agent alerts for corruption */
  end;
  /* Express Edition skipped checks */

  /* If the server is an Azure Managed Instance, skip checks that it doesn't allow */
  if SERVERPROPERTY('EngineEdition') = 8
			begin
    insert into #SkipChecks
      (CheckID)
    values
      (1);
    /* Full backups - because of the MI GUID name bug mentioned here: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/issues/1481 */
    insert into #SkipChecks
      (CheckID)
    values
      (2);
    /* Log backups - because of the MI GUID name bug mentioned here: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/issues/1481 */
    insert into #SkipChecks
      (CheckID)
    values
      (100);
    /* Remote DAC disabled - but it's working anyway, details here: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/issues/1481 */
    insert into #SkipChecks
      (CheckID)
    values
      (199);
  /* Default trace, details here: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/issues/1481 */
  end;
  /* Azure Managed Instance skipped checks */

  /*
		That's the end of the SkipChecks stuff.
		The next several tables are used by various checks later.
		*/
  if OBJECT_ID('tempdb..#ConfigurationDefaults') is not null
			drop table #ConfigurationDefaults;
  create table #ConfigurationDefaults
  (
    name nvarchar(128) ,
    DefaultValue bigint,
    CheckID int
  );

  if OBJECT_ID ('tempdb..#Recompile') is not null
            drop table #Recompile;
  create table #Recompile
  (
    DBName varchar(200),
    ProcName varchar(300),
    RecompileFlag varchar(1),
    SPSchema varchar(50)
  );

  if OBJECT_ID('tempdb..#DatabaseDefaults') is not null
			drop table #DatabaseDefaults;
  create table #DatabaseDefaults
  (
    name nvarchar(128) ,
    DefaultValue nvarchar(200),
    CheckID int,
    Priority int,
    Finding varchar(200),
    URL varchar(200),
    Details nvarchar(4000)
  );

  if OBJECT_ID('tempdb..#DatabaseScopedConfigurationDefaults') is not null
			drop table #DatabaseScopedConfigurationDefaults;
  create table #DatabaseScopedConfigurationDefaults
  (
    ID int identity(1,1),
    configuration_id int,
    [name] nvarchar(60),
    default_value sql_variant,
    default_value_for_secondary sql_variant,
    CheckID int,
  );

  if OBJECT_ID('tempdb..#DBCCs') is not null
			drop table #DBCCs;
  create table #DBCCs
  (
    ID int identity(1, 1)
      primary key ,
    ParentObject varchar(255) ,
    Object varchar(255) ,
    Field varchar(255) ,
    Value varchar(255) ,
    DbName nvarchar(128) null
  );

  if OBJECT_ID('tempdb..#LogInfo2012') is not null
			drop table #LogInfo2012;
  create table #LogInfo2012
  (
    recoveryunitid int ,
    FileID smallint ,
    FileSize bigint ,
    StartOffset bigint ,
    FSeqNo bigint ,
    [Status] tinyint ,
    Parity tinyint ,
    CreateLSN numeric(38)
  );

  if OBJECT_ID('tempdb..#LogInfo') is not null
			drop table #LogInfo;
  create table #LogInfo
  (
    FileID smallint ,
    FileSize bigint ,
    StartOffset bigint ,
    FSeqNo bigint ,
    [Status] tinyint ,
    Parity tinyint ,
    CreateLSN numeric(38)
  );

  if OBJECT_ID('tempdb..#partdb') is not null
			drop table #partdb;
  create table #partdb
  (
    dbname nvarchar(128) ,
    objectname nvarchar(200) ,
    type_desc nvarchar(128)
  );

  if OBJECT_ID('tempdb..#TraceStatus') is not null
			drop table #TraceStatus;
  create table #TraceStatus
  (
    TraceFlag varchar(10) ,
    status bit ,
    Global bit ,
    Session bit
  );

  if OBJECT_ID('tempdb..#driveInfo') is not null
			drop table #driveInfo;
  create table #driveInfo
  (
    drive nvarchar ,
    SIZE decimal(18, 2)
  );

  if OBJECT_ID('tempdb..#dm_exec_query_stats') is not null
			drop table #dm_exec_query_stats;
  create table #dm_exec_query_stats
  (
    [id] [int] not null
      identity(1, 1) ,
    [sql_handle] [varbinary](64) not null ,
    [statement_start_offset] [int] not null ,
    [statement_end_offset] [int] not null ,
    [plan_generation_num] [bigint] not null ,
    [plan_handle] [varbinary](64) not null ,
    [creation_time] [datetime] not null ,
    [last_execution_time] [datetime] not null ,
    [execution_count] [bigint] not null ,
    [total_worker_time] [bigint] not null ,
    [last_worker_time] [bigint] not null ,
    [min_worker_time] [bigint] not null ,
    [max_worker_time] [bigint] not null ,
    [total_physical_reads] [bigint] not null ,
    [last_physical_reads] [bigint] not null ,
    [min_physical_reads] [bigint] not null ,
    [max_physical_reads] [bigint] not null ,
    [total_logical_writes] [bigint] not null ,
    [last_logical_writes] [bigint] not null ,
    [min_logical_writes] [bigint] not null ,
    [max_logical_writes] [bigint] not null ,
    [total_logical_reads] [bigint] not null ,
    [last_logical_reads] [bigint] not null ,
    [min_logical_reads] [bigint] not null ,
    [max_logical_reads] [bigint] not null ,
    [total_clr_time] [bigint] not null ,
    [last_clr_time] [bigint] not null ,
    [min_clr_time] [bigint] not null ,
    [max_clr_time] [bigint] not null ,
    [total_elapsed_time] [bigint] not null ,
    [last_elapsed_time] [bigint] not null ,
    [min_elapsed_time] [bigint] not null ,
    [max_elapsed_time] [bigint] not null ,
    [query_hash] [binary](8) null ,
    [query_plan_hash] [binary](8) null ,
    [query_plan] [xml] null ,
    [query_plan_filtered] [nvarchar](MAX) null ,
    [text] [nvarchar](MAX) collate SQL_Latin1_General_CP1_CI_AS
      null ,
    [text_filtered] [nvarchar](MAX) collate SQL_Latin1_General_CP1_CI_AS
      null
  );

  if OBJECT_ID('tempdb..#ErrorLog') is not null
			drop table #ErrorLog;
  create table #ErrorLog
  (
    LogDate datetime ,
    ProcessInfo nvarchar(20) ,
    [Text] nvarchar(1000)
  );

  if OBJECT_ID('tempdb..#fnTraceGettable') is not null
			drop table #fnTraceGettable;
  create table #fnTraceGettable
  (
    TextData nvarchar(4000) ,
    DatabaseName nvarchar(256) ,
    EventClass int ,
    Severity int ,
    StartTime datetime ,
    EndTime datetime ,
    Duration bigint ,
    NTUserName nvarchar(256) ,
    NTDomainName nvarchar(256) ,
    HostName nvarchar(256) ,
    ApplicationName nvarchar(256) ,
    LoginName nvarchar(256) ,
    DBUserName nvarchar(256)
  );

  if OBJECT_ID('tempdb..#Instances') is not null
			drop table #Instances;
  create table #Instances
  (
    Instance_Number nvarchar(MAX) ,
    Instance_Name nvarchar(MAX) ,
    Data_Field nvarchar(MAX)
  );

  if OBJECT_ID('tempdb..#IgnorableWaits') is not null
			drop table #IgnorableWaits;
  create table #IgnorableWaits
  (
    wait_type nvarchar(60)
  );
  insert into #IgnorableWaits
  values
    ('BROKER_EVENTHANDLER');
  insert into #IgnorableWaits
  values
    ('BROKER_RECEIVE_WAITFOR');
  insert into #IgnorableWaits
  values
    ('BROKER_TASK_STOP');
  insert into #IgnorableWaits
  values
    ('BROKER_TO_FLUSH');
  insert into #IgnorableWaits
  values
    ('BROKER_TRANSMITTER');
  insert into #IgnorableWaits
  values
    ('CHECKPOINT_QUEUE');
  insert into #IgnorableWaits
  values
    ('CLR_AUTO_EVENT');
  insert into #IgnorableWaits
  values
    ('CLR_MANUAL_EVENT');
  insert into #IgnorableWaits
  values
    ('CLR_SEMAPHORE');
  insert into #IgnorableWaits
  values
    ('DBMIRROR_DBM_EVENT');
  insert into #IgnorableWaits
  values
    ('DBMIRROR_DBM_MUTEX');
  insert into #IgnorableWaits
  values
    ('DBMIRROR_EVENTS_QUEUE');
  insert into #IgnorableWaits
  values
    ('DBMIRROR_WORKER_QUEUE');
  insert into #IgnorableWaits
  values
    ('DBMIRRORING_CMD');
  insert into #IgnorableWaits
  values
    ('DIRTY_PAGE_POLL');
  insert into #IgnorableWaits
  values
    ('DISPATCHER_QUEUE_SEMAPHORE');
  insert into #IgnorableWaits
  values
    ('FT_IFTS_SCHEDULER_IDLE_WAIT');
  insert into #IgnorableWaits
  values
    ('FT_IFTSHC_MUTEX');
  insert into #IgnorableWaits
  values
    ('HADR_CLUSAPI_CALL');
  insert into #IgnorableWaits
  values
    ('HADR_FILESTREAM_IOMGR_IOCOMPLETION');
  insert into #IgnorableWaits
  values
    ('HADR_LOGCAPTURE_WAIT');
  insert into #IgnorableWaits
  values
    ('HADR_NOTIFICATION_DEQUEUE');
  insert into #IgnorableWaits
  values
    ('HADR_TIMER_TASK');
  insert into #IgnorableWaits
  values
    ('HADR_WORK_QUEUE');
  insert into #IgnorableWaits
  values
    ('LAZYWRITER_SLEEP');
  insert into #IgnorableWaits
  values
    ('LOGMGR_QUEUE');
  insert into #IgnorableWaits
  values
    ('ONDEMAND_TASK_QUEUE');
  insert into #IgnorableWaits
  values
    ('PARALLEL_REDO_DRAIN_WORKER');
  insert into #IgnorableWaits
  values
    ('PARALLEL_REDO_LOG_CACHE');
  insert into #IgnorableWaits
  values
    ('PARALLEL_REDO_TRAN_LIST');
  insert into #IgnorableWaits
  values
    ('PARALLEL_REDO_WORKER_SYNC');
  insert into #IgnorableWaits
  values
    ('PARALLEL_REDO_WORKER_WAIT_WORK');
  insert into #IgnorableWaits
  values
    ('PREEMPTIVE_HADR_LEASE_MECHANISM');
  insert into #IgnorableWaits
  values
    ('PREEMPTIVE_SP_SERVER_DIAGNOSTICS');
  insert into #IgnorableWaits
  values
    ('QDS_ASYNC_QUEUE');
  insert into #IgnorableWaits
  values
    ('QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP');
  insert into #IgnorableWaits
  values
    ('QDS_PERSIST_TASK_MAIN_LOOP_SLEEP');
  insert into #IgnorableWaits
  values
    ('QDS_SHUTDOWN_QUEUE');
  insert into #IgnorableWaits
  values
    ('REDO_THREAD_PENDING_WORK');
  insert into #IgnorableWaits
  values
    ('REQUEST_FOR_DEADLOCK_SEARCH');
  insert into #IgnorableWaits
  values
    ('SLEEP_SYSTEMTASK');
  insert into #IgnorableWaits
  values
    ('SLEEP_TASK');
  insert into #IgnorableWaits
  values
    ('SP_SERVER_DIAGNOSTICS_SLEEP');
  insert into #IgnorableWaits
  values
    ('SQLTRACE_BUFFER_FLUSH');
  insert into #IgnorableWaits
  values
    ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP');
  insert into #IgnorableWaits
  values
    ('UCS_SESSION_REGISTRATION');
  insert into #IgnorableWaits
  values
    ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG');
  insert into #IgnorableWaits
  values
    ('WAITFOR');
  insert into #IgnorableWaits
  values
    ('XE_DISPATCHER_WAIT');
  insert into #IgnorableWaits
  values
    ('XE_LIVE_TARGET_TVF');
  insert into #IgnorableWaits
  values
    ('XE_TIMER_EVENT');

  if @Debug in (1, 2) raiserror('Setting @MsSinceWaitsCleared', 0, 1) with NOWAIT;

  select @MsSinceWaitsCleared = DATEDIFF(MINUTE, create_date, current_timestamp) * 60000.0
  from sys.databases
  where   name = 'tempdb';

  /* Have they cleared wait stats? Using a 10% fudge factor */
  if @MsSinceWaitsCleared * .9 > (select MAX(wait_time_ms)
  from sys.dm_os_wait_stats
  where wait_type in ('SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'REQUEST_FOR_DEADLOCK_SEARCH', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'LAZYWRITER_SLEEP', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'DIRTY_PAGE_POLL', 'LOGMGR_QUEUE'))
			begin

    if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 185) with NOWAIT;

    set @MsSinceWaitsCleared = (select MAX(wait_time_ms)
    from sys.dm_os_wait_stats
    where wait_type in ('SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'REQUEST_FOR_DEADLOCK_SEARCH', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'LAZYWRITER_SLEEP', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'DIRTY_PAGE_POLL', 'LOGMGR_QUEUE'));
    if @MsSinceWaitsCleared = 0 set @MsSinceWaitsCleared = 1;
    insert  into #BlitzResults
      ( CheckID ,
      Priority ,
      FindingsGroup ,
      Finding ,
      URL ,
      Details
      )
    values( 185,
        240,
        'Wait Stats',
        'Wait Stats Have Been Cleared',
        'https://BrentOzar.com/go/waits',
        'Someone ran DBCC SQLPERF to clear sys.dm_os_wait_stats at approximately: ' 
									+ convert(nvarchar(100), 
										DATEADD(MINUTE, (-1. * (@MsSinceWaitsCleared) / 1000. / 60.), GETDATE()), 120));
  end;

  /* @CpuMsSinceWaitsCleared is used for waits stats calculations */

  if @Debug in (1, 2) raiserror('Setting @CpuMsSinceWaitsCleared', 0, 1) with NOWAIT;

  select @CpuMsSinceWaitsCleared = @MsSinceWaitsCleared * scheduler_count
  from sys.dm_os_sys_info;

  /* If we're outputting CSV or Markdown, don't bother checking the plan cache because we cannot export plans. */
  if @OutputType = 'CSV' or @OutputType = 'MARKDOWN'
			set @CheckProcedureCache = 0;

  /* If we're posting a question on Stack, include background info on the server */
  if @OutputType = 'MARKDOWN'
			set @CheckServerInfo = 1;

  /* Only run CheckUserDatabaseObjects if there are less than 50 databases. */
  if @BringThePain = 0 and 50 <= (select COUNT(*)
    from sys.databases) and @CheckUserDatabaseObjects = 1
			begin
    set @CheckUserDatabaseObjects = 0;
    print 'Running sp_Blitz @CheckUserDatabaseObjects = 1 on a server with 50+ databases may cause temporary insanity for the server and/or user.';
    print 'If you''re sure you want to do this, run again with the parameter @BringThePain = 1.';
    insert  into #BlitzResults
      ( CheckID ,
      Priority ,
      FindingsGroup ,
      Finding ,
      URL ,
      Details
      )
    select 201 as CheckID ,
      0 as Priority ,
      'Informational' as FindingsGroup ,
      '@CheckUserDatabaseObjects Disabled' as Finding ,
      'https://www.BrentOzar.com/blitz/' as URL ,
      'If you want to check 50+ databases, you have to also use @BringThePain = 1.' as Details;
  end;

  /* Sanitize our inputs */
  select
    @OutputServerName = QUOTENAME(@OutputServerName),
    @OutputDatabaseName = QUOTENAME(@OutputDatabaseName),
    @OutputSchemaName = QUOTENAME(@OutputSchemaName),
    @OutputTableName = QUOTENAME(@OutputTableName);

  /* Get the major and minor build numbers */

  if @Debug in (1, 2) raiserror('Getting version information.', 0, 1) with NOWAIT;

  set @ProductVersion = CAST(SERVERPROPERTY('ProductVersion') as nvarchar(128));
  select @ProductVersionMajor = SUBSTRING(@ProductVersion, 1,CHARINDEX('.', @ProductVersion) + 1 ),
    @ProductVersionMinor = PARSENAME(convert(varchar(32), @ProductVersion), 2);

  /*
		Whew! we're finally done with the setup, and we can start doing checks.
		First, let's make sure we're actually supposed to do checks on this server.
		The user could have passed in a SkipChecks table that specified to skip ALL
		checks on this server, so let's check for that:
		*/
  if ( ( SERVERPROPERTY('ServerName') not in ( select ServerName
    from #SkipChecks
    where  DatabaseName is null
      and CheckID is null ) )
    or ( @SkipChecksTable is null )
		   )
			begin

    /*
				Our very first check! We'll put more comments in this one just to
				explain exactly how it works. First, we check to see if we're
				supposed to skip CheckID 1 (that's the check we're working on.)
				*/
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 1 )
					begin

      /*
						Below, we check master.sys.databases looking for databases
						that haven't had a backup in the last week. If we find any,
						we insert them into #BlitzResults, the temp table that
						tracks our server's problems. Note that if the check does
						NOT find any problems, we don't save that. We're only
						saving the problems, not the successful checks.
						*/

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 1) with NOWAIT;

      if SERVERPROPERTY('EngineName') <> 8 /* Azure Managed Instances need a special query */
                            begin
        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 1 as CheckID ,
          d.[name] as DatabaseName ,
          1 as Priority ,
          'Backup' as FindingsGroup ,
          'Backups Not Performed Recently' as Finding ,
          'https://BrentOzar.com/go/nobak' as URL ,
          'Last backed up: '
										    + coalesce(CAST(MAX(b.backup_finish_date) as VARCHAR(25)),'never') as Details
        from master.sys.databases d
          left outer join msdb.dbo.backupset b on d.name collate SQL_Latin1_General_CP1_CI_AS = b.database_name collate SQL_Latin1_General_CP1_CI_AS
            and b.type = 'D'
            and b.server_name = SERVERPROPERTY('ServerName')
        /*Backupset ran on current server  */
        where   d.database_id <> 2 /* Bonus points if you know what that means */
          and d.state not in(1, 6, 10) /* Not currently offline or restoring, like log shipping databases */
          and d.is_in_standby = 0 /* Not a log shipping target database */
          and d.source_database_id is null /* Excludes database snapshots */
          and d.name not in ( select distinct
            DatabaseName
          from #SkipChecks
          where CheckID is null or CheckID = 1)
        /*
										    The above NOT IN filters out the databases we're not supposed to check.
										    */
        group by d.name
        having  MAX(b.backup_finish_date) <= DATEADD(dd,
																      -7, GETDATE())
          or MAX(b.backup_finish_date) is null;
      end;

                        else /* SERVERPROPERTY('EngineName') must be 8, Azure Managed Instances */
                            begin
        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 1 as CheckID ,
          d.[name] as DatabaseName ,
          1 as Priority ,
          'Backup' as FindingsGroup ,
          'Backups Not Performed Recently' as Finding ,
          'https://BrentOzar.com/go/nobak' as URL ,
          'Last backed up: '
										    + coalesce(CAST(MAX(b.backup_finish_date) as VARCHAR(25)),'never') as Details
        from master.sys.databases d
          left outer join msdb.dbo.backupset b on d.name collate SQL_Latin1_General_CP1_CI_AS = b.database_name collate SQL_Latin1_General_CP1_CI_AS
            and b.type = 'D'
        where   d.database_id <> 2 /* Bonus points if you know what that means */
          and d.state not in(1, 6, 10) /* Not currently offline or restoring, like log shipping databases */
          and d.is_in_standby = 0 /* Not a log shipping target database */
          and d.source_database_id is null /* Excludes database snapshots */
          and d.name not in ( select distinct
            DatabaseName
          from #SkipChecks
          where CheckID is null or CheckID = 1)
        /*
										    The above NOT IN filters out the databases we're not supposed to check.
										    */
        group by d.name
        having  MAX(b.backup_finish_date) <= DATEADD(dd,
																      -7, GETDATE())
          or MAX(b.backup_finish_date) is null;
      end;



    /*
						And there you have it. The rest of this stored procedure works the same
						way: it asks:
						- Should I skip this check?
						- If not, do I find problems?
						- Insert the results into #BlitzResults
						*/

    end;

    /*
				And that's the end of CheckID #1.

				CheckID #2 is a little simpler because it only involves one query, and it's
				more typical for queries that people contribute. But keep reading, because
				the next check gets more complex again.
				*/

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 2 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 2) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        2 as CheckID ,
        d.name as DatabaseName ,
        1 as Priority ,
        'Backup' as FindingsGroup ,
        'Full Recovery Model w/o Log Backups' as Finding ,
        'https://BrentOzar.com/go/biglogs' as URL ,
        ( 'The ' + CAST(CAST((select ((SUM([mf].[size]) * 8.) / 1024.)
        from sys.[master_files] as [mf]
        where [mf].[database_id] = d.[database_id] and [mf].[type_desc] = 'LOG') as decimal(18,2)) as varchar(30)) + 'MB log file has not been backed up in the last week.' ) as Details
      from master.sys.databases d
      where   d.recovery_model in ( 1, 2 )
        and d.database_id not in ( 2, 3 )
        and d.source_database_id is null
        and d.state not in(1, 6, 10) /* Not currently offline or restoring, like log shipping databases */
        and d.is_in_standby = 0 /* Not a log shipping target database */
        and d.source_database_id is null /* Excludes database snapshots */
        and d.name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 2)
        and not exists ( select *
        from msdb.dbo.backupset b
        where  d.name collate SQL_Latin1_General_CP1_CI_AS = b.database_name collate SQL_Latin1_General_CP1_CI_AS
          and b.type = 'L'
          and b.backup_finish_date >= DATEADD(dd,
																  -7, GETDATE()) );
    end;

    /*
				Next up, we've got CheckID 8. (These don't have to go in order.) This one
				won't work on SQL Server 2005 because it relies on a new DMV that didn't
				exist prior to SQL Server 2008. This means we have to check the SQL Server
				version first, then build a dynamic string with the query we want to run:
				*/

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 8 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 8) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
							(CheckID, Priority,
							FindingsGroup,
							Finding, URL,
							Details)
					  SELECT 8 AS CheckID,
					  230 AS Priority,
					  ''Security'' AS FindingsGroup,
					  ''Server Audits Running'' AS Finding,
					  ''https://BrentOzar.com/go/audits'' AS URL,
					  (''SQL Server built-in audit functionality is being used by server audit: '' + [name]) AS Details FROM sys.dm_server_audit_status  OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    /*
				But what if you need to run a query in every individual database?
				Hop down to the @CheckUserDatabaseObjects section.

				And that's the basic idea! You can read through the rest of the
				checks if you like - some more exciting stuff happens closer to the
				end of the stored proc, where we start doing things like checking
				the plan cache, but those aren't as cleanly commented.

				If you'd like to contribute your own check, use one of the check
				formats shown above and email it to Help@BrentOzar.com. You don't
				have to pick a CheckID or a link - we'll take care of that when we
				test and publish the code. Thanks!
				*/

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 93 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 93) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select
        93 as CheckID ,
        1 as Priority ,
        'Backup' as FindingsGroup ,
        'Backing Up to Same Drive Where Databases Reside' as Finding ,
        'https://BrentOzar.com/go/backup' as URL ,
        CAST(COUNT(1) as varchar(50)) + ' backups done on drive '
										+ UPPER(left(bmf.physical_device_name, 3))
										+ ' in the last two weeks, where database files also live. This represents a serious risk if that array fails.' Details
      from msdb.dbo.backupmediafamily as bmf
        inner join msdb.dbo.backupset as bs on bmf.media_set_id = bs.media_set_id
          and bs.backup_start_date >= ( DATEADD(dd,
																  -14, GETDATE()) )
        /* Filter out databases that were recently restored: */
        left outer join msdb.dbo.restorehistory rh on bs.database_name = rh.destination_database_name and rh.restore_date > DATEADD(dd, -14, GETDATE())
      where   UPPER(left(bmf.physical_device_name, 3)) <> 'HTT' and
        UPPER(left(bmf.physical_device_name collate SQL_Latin1_General_CP1_CI_AS, 3)) in (
										select distinct
          UPPER(left(mf.physical_name collate SQL_Latin1_General_CP1_CI_AS, 3))
        from sys.master_files as mf )
        and rh.destination_database_name is null
      group by UPPER(left(bmf.physical_device_name, 3));
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 119 )
      and exists ( select *
      from sys.all_objects o
      where  o.name = 'dm_database_encryption_keys' )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 119) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, DatabaseName, URL, Details)
								SELECT 119 AS CheckID,
								1 AS Priority,
								''Backup'' AS FindingsGroup,
								''TDE Certificate Not Backed Up Recently'' AS Finding,
								db_name(dek.database_id) AS DatabaseName,
								''https://BrentOzar.com/go/tde'' AS URL,
								''The certificate '' + c.name + '' is used to encrypt database '' + db_name(dek.database_id) + ''. Last backup date: '' + COALESCE(CAST(c.pvt_key_last_backup_date AS VARCHAR(100)), ''Never'') AS Details
								FROM sys.certificates c INNER JOIN sys.dm_database_encryption_keys dek ON c.thumbprint = dek.encryptor_thumbprint
								WHERE pvt_key_last_backup_date IS NULL OR pvt_key_last_backup_date <= DATEADD(dd, -30, GETDATE())  OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 202 )
      and exists ( select *
      from sys.all_columns c
      where  c.name = 'pvt_key_last_backup_date' )
      and exists ( select *
      from msdb.INFORMATION_SCHEMA.COLUMNS c
      where  c.TABLE_NAME = 'backupset' and c.COLUMN_NAME = 'encryptor_thumbprint' )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 202) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
								SELECT DISTINCT 202 AS CheckID,
								1 AS Priority,
								''Backup'' AS FindingsGroup,
								''Encryption Certificate Not Backed Up Recently'' AS Finding,
								''https://BrentOzar.com/go/tde'' AS URL,
								''The certificate '' + c.name + '' is used to encrypt database backups. Last backup date: '' + COALESCE(CAST(c.pvt_key_last_backup_date AS VARCHAR(100)), ''Never'') AS Details
								FROM sys.certificates c
                                INNER JOIN msdb.dbo.backupset bs ON c.thumbprint = bs.encryptor_thumbprint
                                WHERE pvt_key_last_backup_date IS NULL OR pvt_key_last_backup_date <= DATEADD(dd, -30, GETDATE()) OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 3 )
					begin
      if DATEADD(dd, -60, GETDATE()) > (select top 1
        backup_start_date
      from msdb.dbo.backupset
      order by backup_start_date)

						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 3) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select top 1
          3 as CheckID ,
          'msdb' ,
          200 as Priority ,
          'Backup' as FindingsGroup ,
          'MSDB Backup History Not Purged' as Finding ,
          'https://BrentOzar.com/go/history' as URL ,
          ( 'Database backup history retained back to '
										  + CAST(bs.backup_start_date as varchar(20)) ) as Details
        from msdb.dbo.backupset bs
        order by backup_start_date asc;
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 186 )
					begin
      if DATEADD(dd, -2, GETDATE()) < (select top 1
        backup_start_date
      from msdb.dbo.backupset
      order by backup_start_date)

						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 186) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select top 1
          186 as CheckID ,
          'msdb' ,
          200 as Priority ,
          'Backup' as FindingsGroup ,
          'MSDB Backup History Purged Too Frequently' as Finding ,
          'https://BrentOzar.com/go/history' as URL ,
          ( 'Database backup history only retained back to '
											  + CAST(bs.backup_start_date as varchar(20)) ) as Details
        from msdb.dbo.backupset bs
        order by backup_start_date asc;
      end;
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 178 )
      and exists (select *
      from msdb.dbo.backupset bs
      where bs.type = 'D'
        and bs.backup_size >= 50000000000 /* At least 50GB */
        and DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) <= 60 /* Backup took less than 60 seconds */
        and bs.backup_finish_date >= DATEADD(DAY, -14, GETDATE()) /* In the last 2 weeks */)
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 178) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 178 as CheckID ,
        200 as Priority ,
        'Performance' as FindingsGroup ,
        'Snapshot Backups Occurring' as Finding ,
        'https://BrentOzar.com/go/snaps' as URL ,
        ( CAST(COUNT(*) as varchar(20)) + ' snapshot-looking backups have occurred in the last two weeks, indicating that IO may be freezing up.') as Details
      from msdb.dbo.backupset bs
      where bs.type = 'D'
        and bs.backup_size >= 50000000000 /* At least 50GB */
        and DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) <= 60 /* Backup took less than 60 seconds */
        and bs.backup_finish_date >= DATEADD(DAY, -14, GETDATE());
    /* In the last 2 weeks */
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 4 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 4) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 4 as CheckID ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Sysadmins' as Finding ,
        'https://BrentOzar.com/go/sa' as URL ,
        ( 'Login [' + l.name
										  + '] is a sysadmin - meaning they can do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' ) as Details
      from master.sys.syslogins l
      where   l.sysadmin = 1
        and l.name <> SUSER_SNAME(0x01)
        and l.denylogin = 0
        and l.name not like 'NT SERVICE\%'
        and l.name <> 'l_certSignSmDetach';
    /* Added in SQL 2016 */
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 5 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 5) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 5 as CheckID ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Security Admins' as Finding ,
        'https://BrentOzar.com/go/sa' as URL ,
        ( 'Login [' + l.name
										  + '] is a security admin - meaning they can give themselves permission to do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' ) as Details
      from master.sys.syslogins l
      where   l.securityadmin = 1
        and l.name <> SUSER_SNAME(0x01)
        and l.denylogin = 0;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 104 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 104) with NOWAIT;

      insert  into #BlitzResults
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details]
        )
      select 104 as [CheckID] ,
        230 as [Priority] ,
        'Security' as [FindingsGroup] ,
        'Login Can Control Server' as [Finding] ,
        'https://BrentOzar.com/go/sa' as [URL] ,
        'Login [' + pri.[name]
										+ '] has the CONTROL SERVER permission - meaning they can do absolutely anything in SQL Server, including dropping databases or hiding their tracks.' as [Details]
      from sys.server_principals as pri
      where   pri.[principal_id] in (
										select p.[grantee_principal_id]
        from sys.server_permissions as p
        where   p.[state] in ( 'G', 'W' )
          and p.[class] = 100
          and p.[type] = 'CL' )
        and pri.[name] not like '##%##';
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 6 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 6) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 6 as CheckID ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Jobs Owned By Users' as Finding ,
        'https://BrentOzar.com/go/owners' as URL ,
        ( 'Job [' + j.name + '] is owned by ['
										  + SUSER_SNAME(j.owner_sid)
										  + '] - meaning if their login is disabled or not available due to Active Directory problems, the job will stop working.' ) as Details
      from msdb.dbo.sysjobs j
      where   j.enabled = 1
        and SUSER_SNAME(j.owner_sid) <> SUSER_SNAME(0x01);
    end;

    /* --TOURSTOP06-- */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 7 )
					begin
      /* --TOURSTOP02-- */

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 7) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 7 as CheckID ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Stored Procedure Runs at Startup' as Finding ,
        'https://BrentOzar.com/go/startup' as URL ,
        ( 'Stored procedure [master].['
										  + r.SPECIFIC_SCHEMA + '].['
										  + r.SPECIFIC_NAME
										  + '] runs automatically when SQL Server starts up.  Make sure you know exactly what this stored procedure is doing, because it could pose a security risk.' ) as Details
      from master.INFORMATION_SCHEMA.ROUTINES r
      where   OBJECTPROPERTY(OBJECT_ID(ROUTINE_NAME),
													   'ExecIsStartup') = 1;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 10 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 10) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
							(CheckID,
							Priority,
							FindingsGroup,
							Finding,
							URL,
							Details)
					  SELECT 10 AS CheckID,
					  100 AS Priority,
					  ''Performance'' AS FindingsGroup,
					  ''Resource Governor Enabled'' AS Finding,
					  ''https://BrentOzar.com/go/rg'' AS URL,
					  (''Resource Governor is enabled.  Queries may be throttled.  Make sure you understand how the Classifier Function is configured.'') AS Details FROM sys.resource_governor_configuration WHERE is_enabled = 1 OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 11 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 11) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
							(CheckID,
							Priority,
							FindingsGroup,
							Finding,
							URL,
							Details)
					  SELECT 11 AS CheckID,
					  100 AS Priority,
					  ''Performance'' AS FindingsGroup,
					  ''Server Triggers Enabled'' AS Finding,
					  ''https://BrentOzar.com/go/logontriggers/'' AS URL,
					  (''Server Trigger ['' + [name] ++ ''] is enabled.  Make sure you understand what that trigger is doing - the less work it does, the better.'') AS Details FROM sys.server_triggers WHERE is_disabled = 0 AND is_ms_shipped = 0  OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 12 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 12) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 12 as CheckID ,
        [name] as DatabaseName ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        'Auto-Close Enabled' as Finding ,
        'https://BrentOzar.com/go/autoclose' as URL ,
        ( 'Database [' + [name]
										  + '] has auto-close enabled.  This setting can dramatically decrease performance.' ) as Details
      from sys.databases
      where   is_auto_close_on = 1
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 12);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 13 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 13) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 13 as CheckID ,
        [name] as DatabaseName ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        'Auto-Shrink Enabled' as Finding ,
        'https://BrentOzar.com/go/autoshrink' as URL ,
        ( 'Database [' + [name]
										  + '] has auto-shrink enabled.  This setting can dramatically decrease performance.' ) as Details
      from sys.databases
      where   is_auto_shrink_on = 1
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 13);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 14 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 14) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
							(CheckID,
							DatabaseName,
							Priority,
							FindingsGroup,
							Finding,
							URL,
							Details)
					  SELECT 14 AS CheckID,
					  [name] as DatabaseName,
					  50 AS Priority,
					  ''Reliability'' AS FindingsGroup,
					  ''Page Verification Not Optimal'' AS Finding,
					  ''https://BrentOzar.com/go/torn'' AS URL,
					  (''Database ['' + [name] + ''] has '' + [page_verify_option_desc] + '' for page verification.  SQL Server may have a harder time recognizing and recovering from storage corruption.  Consider using CHECKSUM instead.'') COLLATE database_default AS Details
					  FROM sys.databases
					  WHERE page_verify_option < 2
					  AND name <> ''tempdb''
					  and name not in (select distinct DatabaseName from #SkipChecks WHERE CheckID IS NULL OR CheckID = 14) OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 15 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 15) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 15 as CheckID ,
        [name] as DatabaseName ,
        110 as Priority ,
        'Performance' as FindingsGroup ,
        'Auto-Create Stats Disabled' as Finding ,
        'https://BrentOzar.com/go/acs' as URL ,
        ( 'Database [' + [name]
										  + '] has auto-create-stats disabled.  SQL Server uses statistics to build better execution plans, and without the ability to automatically create more, performance may suffer.' ) as Details
      from sys.databases
      where   is_auto_create_stats_on = 0
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 15);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 16 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 16) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 16 as CheckID ,
        [name] as DatabaseName ,
        110 as Priority ,
        'Performance' as FindingsGroup ,
        'Auto-Update Stats Disabled' as Finding ,
        'https://BrentOzar.com/go/aus' as URL ,
        ( 'Database [' + [name]
										  + '] has auto-update-stats disabled.  SQL Server uses statistics to build better execution plans, and without the ability to automatically update them, performance may suffer.' ) as Details
      from sys.databases
      where   is_auto_update_stats_on = 0
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 16);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 17 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 17) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 17 as CheckID ,
        [name] as DatabaseName ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Stats Updated Asynchronously' as Finding ,
        'https://BrentOzar.com/go/asyncstats' as URL ,
        ( 'Database [' + [name]
										  + '] has auto-update-stats-async enabled.  When SQL Server gets a query for a table with out-of-date statistics, it will run the query with the stats it has - while updating stats to make later queries better. The initial run of the query may suffer, though.' ) as Details
      from sys.databases
      where   is_auto_update_stats_async_on = 1
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 17);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 18 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 18) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 18 as CheckID ,
        [name] as DatabaseName ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Forced Parameterization On' as Finding ,
        'https://BrentOzar.com/go/forced' as URL ,
        ( 'Database [' + [name]
										  + '] has forced parameterization enabled.  SQL Server will aggressively reuse query execution plans even if the applications do not parameterize their queries.  This can be a performance booster with some programming languages, or it may use universally bad execution plans when better alternatives are available for certain parameters.' ) as Details
      from sys.databases
      where   is_parameterization_forced = 1
        and name not in ( select DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 18);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 20 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 20) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 20 as CheckID ,
        [name] as DatabaseName ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Date Correlation On' as Finding ,
        'https://BrentOzar.com/go/corr' as URL ,
        ( 'Database [' + [name]
										  + '] has date correlation enabled.  This is not a default setting, and it has some performance overhead.  It tells SQL Server that date fields in two tables are related, and SQL Server maintains statistics showing that relation.' ) as Details
      from sys.databases
      where   is_date_correlation_on = 1
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 20);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 21 )
					begin
      /* --TOURSTOP04-- */
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 21) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
							(CheckID,
							DatabaseName,
							Priority,
							FindingsGroup,
							Finding,
							URL,
							Details)
					  SELECT 21 AS CheckID,
					  [name] as DatabaseName,
					  200 AS Priority,
					  ''Informational'' AS FindingsGroup,
					  ''Database Encrypted'' AS Finding,
					  ''https://BrentOzar.com/go/tde'' AS URL,
					  (''Database ['' + [name] + ''] has Transparent Data Encryption enabled.  Make absolutely sure you have backed up the certificate and private key, or else you will not be able to restore this database.'') AS Details
					  FROM sys.databases
					  WHERE is_encrypted = 1
					  and name not in (select distinct DatabaseName from #SkipChecks WHERE CheckID IS NULL OR CheckID = 21) OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    /*
				Believe it or not, SQL Server doesn't track the default values
				for sp_configure options! We'll make our own list here.
				*/

    if @Debug in (1, 2) raiserror('Generating default configuration values', 0, 1) with NOWAIT;

    insert  into #ConfigurationDefaults
    values
      ( 'access check cache bucket count', 0, 1001 );
    insert  into #ConfigurationDefaults
    values
      ( 'access check cache quota', 0, 1002 );
    insert  into #ConfigurationDefaults
    values
      ( 'Ad Hoc Distributed Queries', 0, 1003 );
    insert  into #ConfigurationDefaults
    values
      ( 'affinity I/O mask', 0, 1004 );
    insert  into #ConfigurationDefaults
    values
      ( 'affinity mask', 0, 1005 );
    insert  into #ConfigurationDefaults
    values
      ( 'affinity64 mask', 0, 1066 );
    insert  into #ConfigurationDefaults
    values
      ( 'affinity64 I/O mask', 0, 1067 );
    insert  into #ConfigurationDefaults
    values
      ( 'Agent XPs', 0, 1071 );
    insert  into #ConfigurationDefaults
    values
      ( 'allow updates', 0, 1007 );
    insert  into #ConfigurationDefaults
    values
      ( 'awe enabled', 0, 1008 );
    insert  into #ConfigurationDefaults
    values
      ( 'backup checksum default', 0, 1070 );
    insert  into #ConfigurationDefaults
    values
      ( 'backup compression default', 0, 1073 );
    insert  into #ConfigurationDefaults
    values
      ( 'blocked process threshold', 0, 1009 );
    insert  into #ConfigurationDefaults
    values
      ( 'blocked process threshold (s)', 0, 1009 );
    insert  into #ConfigurationDefaults
    values
      ( 'c2 audit mode', 0, 1010 );
    insert  into #ConfigurationDefaults
    values
      ( 'clr enabled', 0, 1011 );
    insert  into #ConfigurationDefaults
    values
      ( 'common criteria compliance enabled', 0, 1074 );
    insert  into #ConfigurationDefaults
    values
      ( 'contained database authentication', 0, 1068 );
    insert  into #ConfigurationDefaults
    values
      ( 'cost threshold for parallelism', 5, 1012 );
    insert  into #ConfigurationDefaults
    values
      ( 'cross db ownership chaining', 0, 1013 );
    insert  into #ConfigurationDefaults
    values
      ( 'cursor threshold', -1, 1014 );
    insert  into #ConfigurationDefaults
    values
      ( 'Database Mail XPs', 0, 1072 );
    insert  into #ConfigurationDefaults
    values
      ( 'default full-text language', 1033, 1016 );
    insert  into #ConfigurationDefaults
    values
      ( 'default language', 0, 1017 );
    insert  into #ConfigurationDefaults
    values
      ( 'default trace enabled', 1, 1018 );
    insert  into #ConfigurationDefaults
    values
      ( 'disallow results from triggers', 0, 1019 );
    insert  into #ConfigurationDefaults
    values
      ( 'EKM provider enabled', 0, 1075 );
    insert  into #ConfigurationDefaults
    values
      ( 'filestream access level', 0, 1076 );
    insert  into #ConfigurationDefaults
    values
      ( 'fill factor (%)', 0, 1020 );
    insert  into #ConfigurationDefaults
    values
      ( 'ft crawl bandwidth (max)', 100, 1021 );
    insert  into #ConfigurationDefaults
    values
      ( 'ft crawl bandwidth (min)', 0, 1022 );
    insert  into #ConfigurationDefaults
    values
      ( 'ft notify bandwidth (max)', 100, 1023 );
    insert  into #ConfigurationDefaults
    values
      ( 'ft notify bandwidth (min)', 0, 1024 );
    insert  into #ConfigurationDefaults
    values
      ( 'index create memory (KB)', 0, 1025 );
    insert  into #ConfigurationDefaults
    values
      ( 'in-doubt xact resolution', 0, 1026 );
    insert  into #ConfigurationDefaults
    values
      ( 'lightweight pooling', 0, 1027 );
    insert  into #ConfigurationDefaults
    values
      ( 'locks', 0, 1028 );
    insert  into #ConfigurationDefaults
    values
      ( 'max degree of parallelism', 0, 1029 );
    insert  into #ConfigurationDefaults
    values
      ( 'max full-text crawl range', 4, 1030 );
    insert  into #ConfigurationDefaults
    values
      ( 'max server memory (MB)', 2147483647, 1031 );
    insert  into #ConfigurationDefaults
    values
      ( 'max text repl size (B)', 65536, 1032 );
    insert  into #ConfigurationDefaults
    values
      ( 'max worker threads', 0, 1033 );
    insert  into #ConfigurationDefaults
    values
      ( 'media retention', 0, 1034 );
    insert  into #ConfigurationDefaults
    values
      ( 'min memory per query (KB)', 1024, 1035 );
    /* Accepting both 0 and 16 below because both have been seen in the wild as defaults. */
    if exists ( select *
    from sys.configurations
    where   name = 'min server memory (MB)'
      and value_in_use in ( 0, 16 ) )
					insert  into #ConfigurationDefaults
    select 'min server memory (MB)' ,
      CAST(value_in_use as bigint), 1036
    from sys.configurations
    where   name = 'min server memory (MB)';
				else
					insert  into #ConfigurationDefaults
    values
      ( 'min server memory (MB)', 0, 1036 );
    insert  into #ConfigurationDefaults
    values
      ( 'nested triggers', 1, 1037 );
    insert  into #ConfigurationDefaults
    values
      ( 'network packet size (B)', 4096, 1038 );
    insert  into #ConfigurationDefaults
    values
      ( 'Ole Automation Procedures', 0, 1039 );
    insert  into #ConfigurationDefaults
    values
      ( 'open objects', 0, 1040 );
    insert  into #ConfigurationDefaults
    values
      ( 'optimize for ad hoc workloads', 0, 1041 );
    insert  into #ConfigurationDefaults
    values
      ( 'PH timeout (s)', 60, 1042 );
    insert  into #ConfigurationDefaults
    values
      ( 'precompute rank', 0, 1043 );
    insert  into #ConfigurationDefaults
    values
      ( 'priority boost', 0, 1044 );
    insert  into #ConfigurationDefaults
    values
      ( 'query governor cost limit', 0, 1045 );
    insert  into #ConfigurationDefaults
    values
      ( 'query wait (s)', -1, 1046 );
    insert  into #ConfigurationDefaults
    values
      ( 'recovery interval (min)', 0, 1047 );
    insert  into #ConfigurationDefaults
    values
      ( 'remote access', 1, 1048 );
    insert  into #ConfigurationDefaults
    values
      ( 'remote admin connections', 0, 1049 );
    /* SQL Server 2012 changes a configuration default */
    if @@VERSION like '%Microsoft SQL Server 2005%'
      or @@VERSION like '%Microsoft SQL Server 2008%'
					begin
      insert  into #ConfigurationDefaults
      values
        ( 'remote login timeout (s)', 20, 1069 );
    end;
				else
					begin
      insert  into #ConfigurationDefaults
      values
        ( 'remote login timeout (s)', 10, 1069 );
    end;
    insert  into #ConfigurationDefaults
    values
      ( 'remote proc trans', 0, 1050 );
    insert  into #ConfigurationDefaults
    values
      ( 'remote query timeout (s)', 600, 1051 );
    insert  into #ConfigurationDefaults
    values
      ( 'Replication XPs', 0, 1052 );
    insert  into #ConfigurationDefaults
    values
      ( 'RPC parameter data validation', 0, 1053 );
    insert  into #ConfigurationDefaults
    values
      ( 'scan for startup procs', 0, 1054 );
    insert  into #ConfigurationDefaults
    values
      ( 'server trigger recursion', 1, 1055 );
    insert  into #ConfigurationDefaults
    values
      ( 'set working set size', 0, 1056 );
    insert  into #ConfigurationDefaults
    values
      ( 'show advanced options', 0, 1057 );
    insert  into #ConfigurationDefaults
    values
      ( 'SMO and DMO XPs', 1, 1058 );
    insert  into #ConfigurationDefaults
    values
      ( 'SQL Mail XPs', 0, 1059 );
    insert  into #ConfigurationDefaults
    values
      ( 'transform noise words', 0, 1060 );
    insert  into #ConfigurationDefaults
    values
      ( 'two digit year cutoff', 2049, 1061 );
    insert  into #ConfigurationDefaults
    values
      ( 'user connections', 0, 1062 );
    insert  into #ConfigurationDefaults
    values
      ( 'user options', 0, 1063 );
    insert  into #ConfigurationDefaults
    values
      ( 'Web Assistant Procedures', 0, 1064 );
    insert  into #ConfigurationDefaults
    values
      ( 'xp_cmdshell', 0, 1065 );

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 22 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 22) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select cd.CheckID ,
        200 as Priority ,
        'Non-Default Server Config' as FindingsGroup ,
        cr.name as Finding ,
        'https://BrentOzar.com/go/conf' as URL ,
        ( 'This sp_configure option has been changed.  Its default value is '
										  + coalesce(CAST(cd.[DefaultValue] as VARCHAR(100)),
													 '(unknown)')
										  + ' and it has been set to '
										  + CAST(cr.value_in_use as varchar(100))
										  + '.' ) as Details
      from sys.configurations cr
        inner join #ConfigurationDefaults cd on cd.name = cr.name
        left outer join #ConfigurationDefaults cdUsed on cdUsed.name = cr.name
          and cdUsed.DefaultValue = cr.value_in_use
      where   cdUsed.name is null;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 190 )
					begin

      if @Debug in (1, 2) raiserror('Setting @MinServerMemory and @MaxServerMemory', 0, 1) with NOWAIT;

      select @MinServerMemory = CAST(value_in_use as bigint)
      from sys.configurations
      where name = 'min server memory (MB)';
      select @MaxServerMemory = CAST(value_in_use as bigint)
      from sys.configurations
      where name = 'max server memory (MB)';

      if (@MinServerMemory = @MaxServerMemory)
						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 190) with NOWAIT;

        insert into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        values
          ( 190,
            200,
            'Performance',
            'Non-Dynamic Memory',
            'https://BrentOzar.com/go/memory',
            'Minimum Server Memory setting is the same as the Maximum (both set to ' + CAST(@MinServerMemory as nvarchar(50)) + '). This will not allow dynamic memory. Please revise memory settings'
									);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 188 )
					begin

      /* Let's set variables so that our query is still SARGable */

      if @Debug in (1, 2) raiserror('Setting @Processors.', 0, 1) with NOWAIT;

      set @Processors = (select cpu_count
      from sys.dm_os_sys_info);

      if @Debug in (1, 2) raiserror('Setting @NUMANodes', 0, 1) with NOWAIT;

      set @NUMANodes = (select COUNT(1)
      from sys.dm_os_performance_counters pc
      where pc.object_name like '%Buffer Node%'
        and counter_name = 'Page life expectancy');
      /* If Cost Threshold for Parallelism is default then flag as a potential issue */
      /* If MAXDOP is default and processors > 8 or NUMA nodes > 1 then flag as potential issue */

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 188) with NOWAIT;

      insert into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 188 as CheckID ,
        200 as Priority ,
        'Performance' as FindingsGroup ,
        cr.name as Finding ,
        'https://BrentOzar.com/go/cxpacket' as URL ,
        ( 'Set to ' + CAST(cr.value_in_use as nvarchar(50)) + ', its default value. Changing this sp_configure setting may reduce CXPACKET waits.')
      from sys.configurations cr
        inner join #ConfigurationDefaults cd on cd.name = cr.name
          and cr.value_in_use = cd.DefaultValue
      where   cr.name = 'cost threshold for parallelism'
        or (cr.name = 'max degree of parallelism' and (@NUMANodes > 1 or @Processors > 8));
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 24 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 24) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        24 as CheckID ,
        DB_NAME(database_id) as DatabaseName ,
        170 as Priority ,
        'File Configuration' as FindingsGroup ,
        'System Database on C Drive' as Finding ,
        'https://BrentOzar.com/go/cdrive' as URL ,
        ( 'The ' + DB_NAME(database_id)
										  + ' database has a file on the C drive.  Putting system databases on the C drive runs the risk of crashing the server when it runs out of space.' ) as Details
      from sys.master_files
      where   UPPER(left(physical_name, 1)) = 'C'
        and DB_NAME(database_id) in ( 'master',
																  'model', 'msdb' );
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 25 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 25) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select top 1
        25 as CheckID ,
        'tempdb' ,
        20 as Priority ,
        'File Configuration' as FindingsGroup ,
        'TempDB on C Drive' as Finding ,
        'https://BrentOzar.com/go/cdrive' as URL ,
        case when growth > 0
											 then ( 'The tempdb database has files on the C drive.  TempDB frequently grows unpredictably, putting your server at risk of running out of C drive space and crashing hard.  C is also often much slower than other drives, so performance may be suffering.' )
											 else ( 'The tempdb database has files on the C drive.  TempDB is not set to Autogrow, hopefully it is big enough.  C is also often much slower than other drives, so performance may be suffering.' )
										end as Details
      from sys.master_files
      where   UPPER(left(physical_name, 1)) = 'C'
        and DB_NAME(database_id) = 'tempdb';
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 26 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 26) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        26 as CheckID ,
        DB_NAME(database_id) as DatabaseName ,
        20 as Priority ,
        'Reliability' as FindingsGroup ,
        'User Databases on C Drive' as Finding ,
        'https://BrentOzar.com/go/cdrive' as URL ,
        ( 'The ' + DB_NAME(database_id)
										  + ' database has a file on the C drive.  Putting databases on the C drive runs the risk of crashing the server when it runs out of space.' ) as Details
      from sys.master_files
      where   UPPER(left(physical_name, 1)) = 'C'
        and DB_NAME(database_id) not in ( 'master',
																  'model', 'msdb',
																  'tempdb' )
        and DB_NAME(database_id) not in (
										select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 26 );
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 27 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 27) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 27 as CheckID ,
        'master' as DatabaseName ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Tables in the Master Database' as Finding ,
        'https://BrentOzar.com/go/mastuser' as URL ,
        ( 'The ' + name
										  + ' table in the master database was created by end users on '
										  + CAST(create_date as varchar(20))
										  + '. Tables in the master database may not be restored in the event of a disaster.' ) as Details
      from master.sys.tables
      where   is_ms_shipped = 0;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 28 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 28) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 28 as CheckID ,
        'msdb' as DatabaseName ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Tables in the MSDB Database' as Finding ,
        'https://BrentOzar.com/go/msdbuser' as URL ,
        ( 'The ' + name
										  + ' table in the msdb database was created by end users on '
										  + CAST(create_date as varchar(20))
										  + '. Tables in the msdb database may not be restored in the event of a disaster.' ) as Details
      from msdb.sys.tables
      where   is_ms_shipped = 0 and name not like '%DTA_%';
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 29 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 29) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 29 as CheckID ,
        'msdb' as DatabaseName ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Tables in the Model Database' as Finding ,
        'https://BrentOzar.com/go/model' as URL ,
        ( 'The ' + name
										  + ' table in the model database was created by end users on '
										  + CAST(create_date as varchar(20))
										  + '. Tables in the model database are automatically copied into all new databases.' ) as Details
      from model.sys.tables
      where   is_ms_shipped = 0;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 30 )
					begin
      if ( select COUNT(*)
      from msdb.dbo.sysalerts
      where  severity between 19 and 25
						   ) < 7

						   begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 30) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 30 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'Not All Alerts Configured' as Finding ,
          'https://BrentOzar.com/go/alert' as URL ,
          ( 'Not all SQL Server Agent alerts have been configured.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) as Details;
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 59 )
					begin
      if exists ( select *
      from msdb.dbo.sysalerts
      where   enabled = 1
        and coalesce(has_notification, 0) = 0
        and (job_id is null or job_id = 0x))

							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 59) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 59 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'Alerts Configured without Follow Up' as Finding ,
          'https://BrentOzar.com/go/alert' as URL ,
          ( 'SQL Server Agent alerts have been configured but they either do not notify anyone or else they do not take any action.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) as Details;

      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 96 )
					begin
      if not exists ( select *
      from msdb.dbo.sysalerts
      where   message_id in ( 823, 824, 825 ) )
							
							begin;

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 96) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 96 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'No Alerts for Corruption' as Finding ,
          'https://BrentOzar.com/go/alert' as URL ,
          ( 'SQL Server Agent alerts do not exist for errors 823, 824, and 825.  These three errors can give you notification about early hardware failure. Enabling them can prevent you a lot of heartbreak.' ) as Details;

      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 61 )
					begin
      if not exists ( select *
      from msdb.dbo.sysalerts
      where   severity between 19 and 25 )
							
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 61) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 61 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'No Alerts for Sev 19-25' as Finding ,
          'https://BrentOzar.com/go/alert' as URL ,
          ( 'SQL Server Agent alerts do not exist for severity levels 19 through 25.  These are some very severe SQL Server errors. Knowing that these are happening may let you recover from errors faster.' ) as Details;

      end;

    end;

    --check for disabled alerts
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 98 )
					begin
      if exists ( select name
      from msdb.dbo.sysalerts
      where   enabled = 0 )
							
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 98) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 98 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'Alerts Disabled' as Finding ,
          'https://www.BrentOzar.com/go/alerts/' as URL ,
          ( 'The following Alert is disabled, please review and enable if desired: '
											  + name ) as Details
        from msdb.dbo.sysalerts
        where   enabled = 0;

      end;

    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 31 )
					begin
      if not exists ( select *
      from msdb.dbo.sysoperators
      where   enabled = 1 )
							
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 31) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 31 as CheckID ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'No Operators Configured/Enabled' as Finding ,
          'https://BrentOzar.com/go/op' as URL ,
          ( 'No SQL Server Agent operators (emails) have been configured.  This is a free, easy way to get notified of corruption, job failures, or major outages even before monitoring systems pick it up.' ) as Details;

      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 34 )
					begin
      if exists ( select *
      from sys.all_objects
      where   name = 'dm_db_mirroring_auto_page_repair' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 34) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT DISTINCT
		  34 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''https://BrentOzar.com/go/repair'' AS URL ,
		  ( ''Database mirroring has automatically repaired at least one corrupt page in the last 30 days. For more information, query the DMV sys.dm_db_mirroring_auto_page_repair.'' ) AS Details
		  FROM (SELECT rp2.database_id, rp2.modification_time
			FROM sys.dm_db_mirroring_auto_page_repair rp2
			WHERE rp2.[database_id] not in (
			SELECT db2.[database_id]
			FROM sys.databases as db2
			WHERE db2.[state] = 1
			) ) as rp
		  INNER JOIN master.sys.databases db ON rp.database_id = db.database_id
		  WHERE   rp.modification_time >= DATEADD(dd, -30, GETDATE())  OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 89 )
					begin
      if exists ( select *
      from sys.all_objects
      where   name = 'dm_hadr_auto_page_repair' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 89) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT DISTINCT
		  89 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''https://BrentOzar.com/go/repair'' AS URL ,
		  ( ''Availability Groups has automatically repaired at least one corrupt page in the last 30 days. For more information, query the DMV sys.dm_hadr_auto_page_repair.'' ) AS Details
		  FROM    sys.dm_hadr_auto_page_repair rp
		  INNER JOIN master.sys.databases db ON rp.database_id = db.database_id
		  WHERE   rp.modification_time >= DATEADD(dd, -30, GETDATE()) OPTION (RECOMPILE) ;';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 90 )
					begin
      if exists ( select *
      from msdb.sys.all_objects
      where   name = 'suspect_pages' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 90) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT DISTINCT
		  90 AS CheckID ,
		  db.name ,
		  1 AS Priority ,
		  ''Corruption'' AS FindingsGroup ,
		  ''Database Corruption Detected'' AS Finding ,
		  ''https://BrentOzar.com/go/repair'' AS URL ,
		  ( ''SQL Server has detected at least one corrupt page in the last 30 days. For more information, query the system table msdb.dbo.suspect_pages.'' ) AS Details
		  FROM    msdb.dbo.suspect_pages sp
		  INNER JOIN master.sys.databases db ON sp.database_id = db.database_id
		  WHERE   sp.last_update_date >= DATEADD(dd, -30, GETDATE())  OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 36 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 36) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        36 as CheckID ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Slow Storage Reads on Drive '
										+ UPPER(left(mf.physical_name, 1)) as Finding ,
        'https://BrentOzar.com/go/slow' as URL ,
        'Reads are averaging longer than 200ms for at least one database on this drive.  For specific database file speeds, run the query from the information link.' as Details
      from sys.dm_io_virtual_file_stats(null, null)
										as fs
        inner join sys.master_files as mf on fs.database_id = mf.database_id
          and fs.[file_id] = mf.[file_id]
      where   ( io_stall_read_ms / ( 1.0 + num_of_reads ) ) > 200
        and num_of_reads > 100000;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 37 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 37) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        37 as CheckID ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Slow Storage Writes on Drive '
										+ UPPER(left(mf.physical_name, 1)) as Finding ,
        'https://BrentOzar.com/go/slow' as URL ,
        'Writes are averaging longer than 100ms for at least one database on this drive.  For specific database file speeds, run the query from the information link.' as Details
      from sys.dm_io_virtual_file_stats(null, null)
										as fs
        inner join sys.master_files as mf on fs.database_id = mf.database_id
          and fs.[file_id] = mf.[file_id]
      where   ( io_stall_write_ms / ( 1.0
																+ num_of_writes ) ) > 100
        and num_of_writes > 100000;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 40 )
					begin
      if ( select COUNT(*)
      from tempdb.sys.database_files
      where  type_desc = 'ROWS'
						   ) = 1
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 40) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        values
          ( 40 ,
            'tempdb' ,
            170 ,
            'File Configuration' ,
            'TempDB Only Has 1 Data File' ,
            'https://BrentOzar.com/go/tempdb' ,
            'TempDB is only configured with one data file.  More data files are usually required to alleviate SGAM contention.'
										);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 183 )

				begin

      if ( select COUNT (distinct [size])
      from tempdb.sys.database_files
      where  type_desc = 'ROWS'
      having MAX((size * 8) / (1024. * 1024)) - MIN((size * 8) / (1024. * 1024)) > 1.
							) <> 1
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 183) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        values
          ( 183 ,
            'tempdb' ,
            170 ,
            'File Configuration' ,
            'TempDB Unevenly Sized Data Files' ,
            'https://BrentOzar.com/go/tempdb' ,
            'TempDB data files are not configured with the same size.  Unevenly sized tempdb data files will result in unevenly sized workloads.'
										);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 44 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 44) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 44 as CheckID ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Queries Forcing Order Hints' as Finding ,
        'https://BrentOzar.com/go/hints' as URL ,
        CAST(occurrence as varchar(10))
										+ ' instances of order hinting have been recorded since restart.  This means queries are bossing the SQL Server optimizer around, and if they don''t know what they''re doing, this can cause more harm than good.  This can also explain why DBA tuning efforts aren''t working.' as Details
      from sys.dm_exec_query_optimizer_info
      where   counter = 'order hint'
        and occurrence > 1000;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 45 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 45) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 45 as CheckID ,
        150 as Priority ,
        'Performance' as FindingsGroup ,
        'Queries Forcing Join Hints' as Finding ,
        'https://BrentOzar.com/go/hints' as URL ,
        CAST(occurrence as varchar(10))
										+ ' instances of join hinting have been recorded since restart.  This means queries are bossing the SQL Server optimizer around, and if they don''t know what they''re doing, this can cause more harm than good.  This can also explain why DBA tuning efforts aren''t working.' as Details
      from sys.dm_exec_query_optimizer_info
      where   counter = 'join hint'
        and occurrence > 1000;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 49 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 49) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        49 as CheckID ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Linked Server Configured' as Finding ,
        'https://BrentOzar.com/go/link' as URL ,
        +case when l.remote_name = 'sa'
											  then s.data_source
												   + ' is configured as a linked server. Check its security configuration as it is connecting with sa, because any user who queries it will get admin-level permissions.'
											  else s.data_source
												   + ' is configured as a linked server. Check its security configuration to make sure it isn''t connecting with SA or some other bone-headed administrative login, because any user who queries it might get admin-level permissions.'
										 end as Details
      from sys.servers s
        inner join sys.linked_logins l on s.server_id = l.server_id
      where   s.is_linked = 1;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 50 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 50) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
		  SELECT  50 AS CheckID ,
		  100 AS Priority ,
		  ''Performance'' AS FindingsGroup ,
		  ''Max Memory Set Too High'' AS Finding ,
		  ''https://BrentOzar.com/go/max'' AS URL ,
		  ''SQL Server max memory is set to ''
			+ CAST(c.value_in_use AS VARCHAR(20))
			+ '' megabytes, but the server only has ''
			+ CAST(( CAST(m.total_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20))
			+ '' megabytes.  SQL Server may drain the system dry of memory, and under certain conditions, this can cause Windows to swap to disk.'' AS Details
		  FROM    sys.dm_os_sys_memory m
		  INNER JOIN sys.configurations c ON c.name = ''max server memory (MB)''
		  WHERE   CAST(m.total_physical_memory_kb AS BIGINT) < ( CAST(c.value_in_use AS BIGINT) * 1024 ) OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 51 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 51) with NOWAIT

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
		  SELECT  51 AS CheckID ,
		  1 AS Priority ,
		  ''Performance'' AS FindingsGroup ,
		  ''Memory Dangerously Low'' AS Finding ,
		  ''https://BrentOzar.com/go/max'' AS URL ,
		  ''The server has '' + CAST(( CAST(m.total_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20)) + '' megabytes of physical memory, but only '' + CAST(( CAST(m.available_physical_memory_kb AS BIGINT) / 1024 ) AS VARCHAR(20))
			+ '' megabytes are available.  As the server runs out of memory, there is danger of swapping to disk, which will kill performance.'' AS Details
		  FROM    sys.dm_os_sys_memory m
		  WHERE   CAST(m.available_physical_memory_kb AS BIGINT) < 262144 OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 159 )
					begin
      if @@VERSION not like '%Microsoft SQL Server 2000%'
        and @@VERSION not like '%Microsoft SQL Server 2005%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 159) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
		  SELECT DISTINCT 159 AS CheckID ,
		  1 AS Priority ,
		  ''Performance'' AS FindingsGroup ,
		  ''Memory Dangerously Low in NUMA Nodes'' AS Finding ,
		  ''https://BrentOzar.com/go/max'' AS URL ,
		  ''At least one NUMA node is reporting THREAD_RESOURCES_LOW in sys.dm_os_nodes and can no longer create threads.'' AS Details
		  FROM    sys.dm_os_nodes m
		  WHERE   node_state_desc LIKE ''%THREAD_RESOURCES_LOW%'' OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 53 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 53) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select top 1
        53 as CheckID ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Cluster Node' as Finding ,
        'https://BrentOzar.com/go/node' as URL ,
        'This is a node in a cluster.' as Details
      from sys.dm_os_cluster_nodes;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 55 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 55) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 55 as CheckID ,
        [name] as DatabaseName ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Database Owner <> SA' as Finding ,
        'https://BrentOzar.com/go/owndb' as URL ,
        ( 'Database name: ' + [name] + '   '
										  + 'Owner name: ' + SUSER_SNAME(owner_sid) ) as Details
      from sys.databases
      where   SUSER_SNAME(owner_sid) <> SUSER_SNAME(0x01)
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 55);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 213 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 213) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 213 as CheckID ,
        [name] as DatabaseName ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'Database Owner is Unknown' as Finding ,
        '' as URL ,
        ( 'Database name: ' + [name] + '   '
										  + 'Owner name: ' + ISNULL(SUSER_SNAME(owner_sid),'~~ UNKNOWN ~~') ) as Details
      from sys.databases
      where   SUSER_SNAME(owner_sid) is null
        and name not in ( select distinct DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 213);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 57 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 57) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 57 as CheckID ,
        230 as Priority ,
        'Security' as FindingsGroup ,
        'SQL Agent Job Runs at Startup' as Finding ,
        'https://BrentOzar.com/go/startup' as URL ,
        ( 'Job [' + j.name
										  + '] runs automatically when SQL Server Agent starts up.  Make sure you know exactly what this job is doing, because it could pose a security risk.' ) as Details
      from msdb.dbo.sysschedules sched
        join msdb.dbo.sysjobschedules jsched on sched.schedule_id = jsched.schedule_id
        join msdb.dbo.sysjobs j on jsched.job_id = j.job_id
      where   sched.freq_type = 64
        and sched.enabled = 1;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 97 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 97) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 97 as CheckID ,
        100 as Priority ,
        'Performance' as FindingsGroup ,
        'Unusual SQL Server Edition' as Finding ,
        'https://BrentOzar.com/go/workgroup' as URL ,
        ( 'This server is using '
										  + CAST(SERVERPROPERTY('edition') as varchar(100))
										  + ', which is capped at low amounts of CPU and memory.' ) as Details
      where   CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Standard%'
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Enterprise%'
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Data Center%'
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Developer%'
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Business Intelligence%';
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 154 )
      and SERVERPROPERTY('EngineEdition') <> 8
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 154) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 154 as CheckID ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        '32-bit SQL Server Installed' as Finding ,
        'https://BrentOzar.com/go/32bit' as URL ,
        ( 'This server uses the 32-bit x86 binaries for SQL Server instead of the 64-bit x64 binaries. The amount of memory available for query workspace and execution plans is heavily limited.' ) as Details
      where   CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%64%';
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 62 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 62) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 62 as CheckID ,
        [name] as DatabaseName ,
        200 as Priority ,
        'Performance' as FindingsGroup ,
        'Old Compatibility Level' as Finding ,
        'https://BrentOzar.com/go/compatlevel' as URL ,
        ( 'Database ' + [name]
										  + ' is compatibility level '
										  + CAST(compatibility_level as varchar(20))
										  + ', which may cause unwanted results when trying to run queries that have newer T-SQL features.' ) as Details
      from sys.databases
      where   name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 62)
        and compatibility_level <= 90;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 94 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 94) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 94 as CheckID ,
        200 as [Priority] ,
        'Monitoring' as FindingsGroup ,
        'Agent Jobs Without Failure Emails' as Finding ,
        'https://BrentOzar.com/go/alerts' as URL ,
        'The job ' + [name]
										+ ' has not been set up to notify an operator if it fails.' as Details
      from msdb.[dbo].[sysjobs] j
        inner join ( select distinct
          [job_id]
        from [msdb].[dbo].[sysjobschedules]
        where  next_run_date > 0
												   ) s on j.job_id = s.job_id
      where   j.enabled = 1
        and j.notify_email_operator_id = 0
        and j.notify_netsend_operator_id = 0
        and j.notify_page_operator_id = 0
        and j.category_id <> 100;
    /* Exclude SSRS category */
    end;

    if exists ( select 1
      from sys.configurations
      where   name = 'remote admin connections'
        and value_in_use = 0 )
      and not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 100 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 100) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 100 as CheckID ,
        50 as Priority ,
        'Reliability' as FindingGroup ,
        'Remote DAC Disabled' as Finding ,
        'https://BrentOzar.com/go/dac' as URL ,
        'Remote access to the Dedicated Admin Connection (DAC) is not enabled. The DAC can make remote troubleshooting much easier when SQL Server is unresponsive.';
    end;

    if exists ( select *
      from sys.dm_os_schedulers
      where   is_online = 0 )
      and not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 101 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 101) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 101 as CheckID ,
        50 as Priority ,
        'Performance' as FindingGroup ,
        'CPU Schedulers Offline' as Finding ,
        'https://BrentOzar.com/go/schedulers' as URL ,
        'Some CPU cores are not accessible to SQL Server due to affinity masking or licensing problems.';
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 110 )
      and exists (select *
      from master.sys.all_objects
      where name = 'dm_os_memory_nodes')
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 110) with NOWAIT;

      set @StringToExecute = 'IF EXISTS (SELECT  *
												FROM sys.dm_os_nodes n
												INNER JOIN sys.dm_os_memory_nodes m ON n.memory_node_id = m.memory_node_id
												WHERE n.node_state_desc = ''OFFLINE'')
												INSERT  INTO #BlitzResults
														( CheckID ,
														  Priority ,
														  FindingsGroup ,
														  Finding ,
														  URL ,
														  Details
														)
														SELECT  110 AS CheckID ,
																50 AS Priority ,
																''Performance'' AS FindingGroup ,
																''Memory Nodes Offline'' AS Finding ,
																''https://BrentOzar.com/go/schedulers'' AS URL ,
																''Due to affinity masking or licensing problems, some of the memory may not be available.'' OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if exists ( select *
      from sys.databases
      where   state > 1 )
      and not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 102 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 102) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 102 as CheckID ,
        [name] ,
        20 as Priority ,
        'Reliability' as FindingGroup ,
        'Unusual Database State: ' + [state_desc] as Finding ,
        'https://BrentOzar.com/go/repair' as URL ,
        'This database may not be online.'
      from sys.databases
      where   state > 1;
    end;

    if exists ( select *
      from master.sys.extended_procedures )
      and not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 105 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 105) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 105 as CheckID ,
        'master' ,
        200 as Priority ,
        'Reliability' as FindingGroup ,
        'Extended Stored Procedures in Master' as Finding ,
        'https://BrentOzar.com/go/clr' as URL ,
        'The [' + name
										+ '] extended stored procedure is in the master database. CLR may be in use, and the master database now needs to be part of your backup/recovery planning.'
      from master.sys.extended_procedures;
    end;

    if not exists ( select 1
    from #SkipChecks
    where  DatabaseName is null and CheckID = 107 )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 107) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 107 as CheckID ,
        50 as Priority ,
        'Performance' as FindingGroup ,
        'Poison Wait Detected: ' + wait_type  as Finding ,
        'https://BrentOzar.com/go/poison/#' + wait_type as URL ,
        convert(varchar(10), (SUM([wait_time_ms]) / 1000) / 86400) + ':' + convert(varchar(20), DATEADD(s, (SUM([wait_time_ms]) / 1000), 0), 108) + ' of this wait have been recorded. This wait often indicates killer performance problems.'
      from sys.[dm_os_wait_stats]
      where wait_type in('IO_QUEUE_LIMIT', 'IO_RETRY', 'LOG_RATE_GOVERNOR', 'PREEMPTIVE_DEBUG', 'RESMGR_THROTTLED', 'RESOURCE_SEMAPHORE', 'RESOURCE_SEMAPHORE_QUERY_COMPILE','SE_REPL_CATCHUP_THROTTLE','SE_REPL_COMMIT_ACK','SE_REPL_COMMIT_TURN','SE_REPL_ROLLBACK_ACK','SE_REPL_SLOW_SECONDARY_THROTTLE','THREADPOOL')
      group by wait_type
      having SUM([wait_time_ms]) > (select 5000 * datediff(HH,create_date,current_timestamp) as hours_since_startup
        from sys.databases
        where name='tempdb')
        and SUM([wait_time_ms]) > 60000;
    end;

    if not exists ( select 1
    from #SkipChecks
    where  DatabaseName is null and CheckID = 121 )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 121) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 121 as CheckID ,
        50 as Priority ,
        'Performance' as FindingGroup ,
        'Poison Wait Detected: Serializable Locking'  as Finding ,
        'https://BrentOzar.com/go/serializable' as URL ,
        convert(varchar(10), (SUM([wait_time_ms]) / 1000) / 86400) + ':' + convert(varchar(20), DATEADD(s, (SUM([wait_time_ms]) / 1000), 0), 108) + ' of LCK_M_R% waits have been recorded. This wait often indicates killer performance problems.'
      from sys.[dm_os_wait_stats]
      where wait_type in ('LCK_M_RS_S', 'LCK_M_RS_U', 'LCK_M_RIn_NL','LCK_M_RIn_S', 'LCK_M_RIn_U','LCK_M_RIn_X', 'LCK_M_RX_S', 'LCK_M_RX_U','LCK_M_RX_X')
      having SUM([wait_time_ms]) > (select 5000 * datediff(HH,create_date,current_timestamp) as hours_since_startup
        from sys.databases
        where name='tempdb')
        and SUM([wait_time_ms]) > 60000;
    end;


    if not exists ( select 1
    from #SkipChecks
    where  DatabaseName is null and CheckID = 111 )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 111) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        DatabaseName ,
        URL ,
        Details
        )
      select 111 as CheckID ,
        50 as Priority ,
        'Reliability' as FindingGroup ,
        'Possibly Broken Log Shipping'  as Finding ,
        d.[name] ,
        'https://BrentOzar.com/go/shipping' as URL ,
        d.[name] + ' is in a restoring state, but has not had a backup applied in the last two days. This is a possible indication of a broken transaction log shipping setup.'
      from [master].sys.databases d
        inner join [master].sys.database_mirroring dm on d.database_id = dm.database_id
          and dm.mirroring_role is null
      where ( d.[state] = 1
        or (d.[state] = 0 and d.[is_in_standby] = 1) )
        and not exists(select *
        from msdb.dbo.restorehistory rh
          inner join msdb.dbo.backupset bs on rh.backup_set_id = bs.backup_set_id
        where d.[name] collate SQL_Latin1_General_CP1_CI_AS = rh.destination_database_name collate SQL_Latin1_General_CP1_CI_AS
          and rh.restore_date >= DATEADD(dd, -2, GETDATE()));

    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 112 )
      and exists (select *
      from master.sys.all_objects
      where name = 'change_tracking_databases')
							begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 112) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults
									(CheckID,
									Priority,
									FindingsGroup,
									Finding,
									URL,
									Details)
							  SELECT 112 AS CheckID,
							  100 AS Priority,
							  ''Performance'' AS FindingsGroup,
							  ''Change Tracking Enabled'' AS Finding,
							  ''https://BrentOzar.com/go/tracking'' AS URL,
							  ( d.[name] + '' has change tracking enabled. This is not a default setting, and it has some performance overhead. It keeps track of changes to rows in tables that have change tracking turned on.'' ) AS Details FROM sys.change_tracking_databases AS ctd INNER JOIN sys.databases AS d ON ctd.database_id = d.database_id OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 116 )
      and exists (select *
      from msdb.sys.all_columns
      where name = 'compressed_backup_size')
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 116) with NOWAIT

      set @StringToExecute = 'INSERT  INTO #BlitzResults
									( CheckID ,
									  Priority ,
									  FindingsGroup ,
									  Finding ,
									  URL ,
									  Details
									)
									SELECT  116 AS CheckID ,
											200 AS Priority ,
											''Informational'' AS FindingGroup ,
											''Backup Compression Default Off''  AS Finding ,
											''https://BrentOzar.com/go/backup'' AS URL ,
											''Uncompressed full backups have happened recently, and backup compression is not turned on at the server level. Backup compression is included with SQL Server 2008R2 & newer, even in Standard Edition. We recommend turning backup compression on by default so that ad-hoc backups will get compressed.''
											FROM sys.configurations
											WHERE configuration_id = 1579 AND CAST(value_in_use AS INT) = 0
                                            AND EXISTS (SELECT * FROM msdb.dbo.backupset WHERE backup_size = compressed_backup_size AND type = ''D'' AND backup_finish_date >= DATEADD(DD, -14, GETDATE())) OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 117 )
      and exists (select *
      from master.sys.all_objects
      where name = 'dm_exec_query_resource_semaphores')
							begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 117) with NOWAIT;

      set @StringToExecute = 'IF 0 < (SELECT SUM([forced_grant_count]) FROM sys.dm_exec_query_resource_semaphores WHERE [forced_grant_count] IS NOT NULL)
								INSERT INTO #BlitzResults
									(CheckID,
									Priority,
									FindingsGroup,
									Finding,
									URL,
									Details)
							  SELECT 117 AS CheckID,
							  100 AS Priority,
							  ''Performance'' AS FindingsGroup,
							  ''Memory Pressure Affecting Queries'' AS Finding,
							  ''https://BrentOzar.com/go/grants'' AS URL,
							  CAST(SUM(forced_grant_count) AS NVARCHAR(100)) + '' forced grants reported in the DMV sys.dm_exec_query_resource_semaphores, indicating memory pressure has affected query runtimes.''
							  FROM sys.dm_exec_query_resource_semaphores WHERE [forced_grant_count] IS NOT NULL OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 124 )
							begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 124) with NOWAIT;

      insert into #BlitzResults
        (CheckID,
        Priority,
        FindingsGroup,
        Finding,
        URL,
        Details)
      select 124,
        150,
        'Performance',
        'Deadlocks Happening Daily',
        'https://BrentOzar.com/go/deadlocks',
        CAST(CAST(p.cntr_value / @DaysUptime as bigint) as nvarchar(100)) + ' average deadlocks per day. To find them, run sp_BlitzLock.' as Details
      from sys.dm_os_performance_counters p
        inner join sys.databases d on d.name = 'tempdb'
      where RTRIM(p.counter_name) = 'Number of Deadlocks/sec'
        and RTRIM(p.instance_name) = '_Total'
        and p.cntr_value > 0
        and (1.0 * p.cntr_value / nullif(datediff(DD,create_date,current_timestamp),0)) > 10;
    end;

    if DATEADD(mi, -15, GETDATE()) < (select top 1
        creation_time
      from sys.dm_exec_query_stats
      order by creation_time)
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 125 )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 125) with NOWAIT;

      insert into #BlitzResults
        (CheckID,
        Priority,
        FindingsGroup,
        Finding,
        URL,
        Details)
      select top 1
        125, 10, 'Performance', 'Plan Cache Erased Recently', 'https://BrentOzar.com/askbrent/plan-cache-erased-recently/',
        'The oldest query in the plan cache was created at ' + CAST(creation_time as nvarchar(50)) + '. Someone ran DBCC FREEPROCCACHE, restarted SQL Server, or it is under horrific memory pressure.'
      from sys.dm_exec_query_stats with (NOLOCK)
      order by creation_time;
    end;

    if exists (select *
      from sys.configurations
      where name = 'priority boost' and (value = 1 or value_in_use = 1))
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 126 )
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 126) with NOWAIT;

      insert into #BlitzResults
        (CheckID,
        Priority,
        FindingsGroup,
        Finding,
        URL,
        Details)
      values(126, 5, 'Reliability', 'Priority Boost Enabled', 'https://BrentOzar.com/go/priorityboost/',
          'Priority Boost sounds awesome, but it can actually cause your SQL Server to crash.');
    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 128 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
							begin

      if (@ProductVersionMajor = 14 and @ProductVersionMinor < 1000) or
        (@ProductVersionMajor = 13 and @ProductVersionMinor < 4001) or
        (@ProductVersionMajor = 12 and @ProductVersionMinor < 5000) or
        (@ProductVersionMajor = 11 and @ProductVersionMinor < 6020) or
        (@ProductVersionMajor = 10.5 and @ProductVersionMinor < 6000) or
        (@ProductVersionMajor = 10 and @ProductVersionMinor < 6000) or
        (@ProductVersionMajor = 9 /*AND @ProductVersionMinor <= 5000*/)
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 128) with NOWAIT;

        insert into #BlitzResults
          (CheckID, Priority, FindingsGroup, Finding, URL, Details)
        values(128, 20, 'Reliability', 'Unsupported Build of SQL Server', 'https://BrentOzar.com/go/unsupported',
            'Version ' + CAST(@ProductVersionMajor as varchar(100)) + '.' +
										case when @ProductVersionMajor > 9 then
										CAST(@ProductVersionMinor as varchar(100)) + ' is no longer supported by Microsoft. You need to apply a service pack.'
										else ' is no longer support by Microsoft. You should be making plans to upgrade to a modern version of SQL Server.' end);
      end;

    end;

    /* Reliability - Dangerous Build of SQL Server (Corruption) */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 129 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
							begin
      if (@ProductVersionMajor = 11 and @ProductVersionMinor >= 3000 and @ProductVersionMinor <= 3436) or
        (@ProductVersionMajor = 11 and @ProductVersionMinor = 5058) or
        (@ProductVersionMajor = 12 and @ProductVersionMinor >= 2000 and @ProductVersionMinor <= 2342)
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 129) with NOWAIT;

        insert into #BlitzResults
          (CheckID, Priority, FindingsGroup, Finding, URL, Details)
        values(129, 20, 'Reliability', 'Dangerous Build of SQL Server (Corruption)', 'http://sqlperformance.com/2014/06/sql-indexes/hotfix-sql-2012-rebuilds',
            'There are dangerous known bugs with version ' + CAST(@ProductVersionMajor as varchar(100)) + '.' + CAST(@ProductVersionMinor as varchar(100)) + '. Check the URL for details and apply the right service pack or hotfix.');
      end;

    end;

    /* Reliability - Dangerous Build of SQL Server (Security) */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 157 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
							begin
      if (@ProductVersionMajor = 10 and @ProductVersionMinor >= 5500 and @ProductVersionMinor <= 5512) or
        (@ProductVersionMajor = 10 and @ProductVersionMinor >= 5750 and @ProductVersionMinor <= 5867) or
        (@ProductVersionMajor = 10.5 and @ProductVersionMinor >= 4000 and @ProductVersionMinor <= 4017) or
        (@ProductVersionMajor = 10.5 and @ProductVersionMinor >= 4251 and @ProductVersionMinor <= 4319) or
        (@ProductVersionMajor = 11 and @ProductVersionMinor >= 3000 and @ProductVersionMinor <= 3129) or
        (@ProductVersionMajor = 11 and @ProductVersionMinor >= 3300 and @ProductVersionMinor <= 3447) or
        (@ProductVersionMajor = 12 and @ProductVersionMinor >= 2000 and @ProductVersionMinor <= 2253) or
        (@ProductVersionMajor = 12 and @ProductVersionMinor >= 2300 and @ProductVersionMinor <= 2370)
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 157) with NOWAIT;

        insert into #BlitzResults
          (CheckID, Priority, FindingsGroup, Finding, URL, Details)
        values(157, 20, 'Reliability', 'Dangerous Build of SQL Server (Security)', 'https://technet.microsoft.com/en-us/library/security/MS14-044',
            'There are dangerous known bugs with version ' + CAST(@ProductVersionMajor as varchar(100)) + '.' + CAST(@ProductVersionMinor as varchar(100)) + '. Check the URL for details and apply the right service pack or hotfix.');
      end;

    end;

    /* Check if SQL 2016 Standard Edition but not SP1 */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 189 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
							begin
      if (@ProductVersionMajor = 13 and @ProductVersionMinor < 4001 and @@VERSION like '%Standard Edition%')
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 189) with NOWAIT;

        insert into #BlitzResults
          (CheckID, Priority, FindingsGroup, Finding, URL, Details)
        values(189, 100, 'Features', 'Missing Features', 'https://blogs.msdn.microsoft.com/sqlreleaseservices/sql-server-2016-service-pack-1-sp1-released/',
            'SQL 2016 Standard Edition is being used but not Service Pack 1. Check the URL for a list of Enterprise Features that are included in Standard Edition as of SP1.');
      end;

    end;

    /* Check if SQL 2017 but not CU3 */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 216 )
      and SERVERPROPERTY('EngineEdition') <> 8 /* Azure Managed Instances */
							begin
      if (@ProductVersionMajor = 14 and @ProductVersionMinor < 3015)
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 216) with NOWAIT;

        insert into #BlitzResults
          (CheckID, Priority, FindingsGroup, Finding, URL, Details)
        values(216, 100, 'Features', 'Missing Features', 'https://support.microsoft.com/en-us/help/4041814',
            'SQL 2017 is being used but not Cumulative Update 3. We''d recommend patching to take advantage of increased analytics when running BlitzCache.');
      end;

    end;

    /* Performance - High Memory Use for In-Memory OLTP (Hekaton) */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 145 )
      and exists ( select *
      from sys.all_objects o
      where  o.name = 'dm_db_xtp_table_memory_stats' )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 145) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        SELECT 145 AS CheckID,
			                        10 AS Priority,
			                        ''Performance'' AS FindingsGroup,
			                        ''High Memory Use for In-Memory OLTP (Hekaton)'' AS Finding,
			                        ''https://BrentOzar.com/go/hekaton'' AS URL,
			                        CAST(CAST((SUM(mem.pages_kb / 1024.0) / CAST(value_in_use AS INT) * 100) AS INT) AS NVARCHAR(100)) + ''% of your '' + CAST(CAST((CAST(value_in_use AS DECIMAL(38,1)) / 1024) AS MONEY) AS NVARCHAR(100)) + ''GB of your max server memory is being used for in-memory OLTP tables (Hekaton). Microsoft recommends having 2X your Hekaton table space available in memory just for Hekaton, with a max of 250GB of in-memory data regardless of your server memory capacity.'' AS Details
			                        FROM sys.configurations c INNER JOIN sys.dm_os_memory_clerks mem ON mem.type = ''MEMORYCLERK_XTP''
                                    WHERE c.name = ''max server memory (MB)''
                                    GROUP BY c.value_in_use
                                    HAVING CAST(value_in_use AS DECIMAL(38,2)) * .25 < SUM(mem.pages_kb / 1024.0)
                                      OR SUM(mem.pages_kb / 1024.0) > 250000 OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* Performance - In-Memory OLTP (Hekaton) In Use */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 146 )
      and exists ( select *
      from sys.all_objects o
      where  o.name = 'dm_db_xtp_table_memory_stats' )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 146) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        SELECT 146 AS CheckID,
			                        200 AS Priority,
			                        ''Performance'' AS FindingsGroup,
			                        ''In-Memory OLTP (Hekaton) In Use'' AS Finding,
			                        ''https://BrentOzar.com/go/hekaton'' AS URL,
			                        CAST(CAST((SUM(mem.pages_kb / 1024.0) / CAST(value_in_use AS INT) * 100) AS INT) AS NVARCHAR(100)) + ''% of your '' + CAST(CAST((CAST(value_in_use AS DECIMAL(38,1)) / 1024) AS MONEY) AS NVARCHAR(100)) + ''GB of your max server memory is being used for in-memory OLTP tables (Hekaton).'' AS Details
			                        FROM sys.configurations c INNER JOIN sys.dm_os_memory_clerks mem ON mem.type = ''MEMORYCLERK_XTP''
                                    WHERE c.name = ''max server memory (MB)''
                                    GROUP BY c.value_in_use
                                    HAVING SUM(mem.pages_kb / 1024.0) > 10 OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* In-Memory OLTP (Hekaton) - Transaction Errors */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 147 )
      and exists ( select *
      from sys.all_objects o
      where  o.name = 'dm_xtp_transaction_stats' )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 147) with NOWAIT

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        SELECT 147 AS CheckID,
			                        100 AS Priority,
			                        ''In-Memory OLTP (Hekaton)'' AS FindingsGroup,
			                        ''Transaction Errors'' AS Finding,
			                        ''https://BrentOzar.com/go/hekaton'' AS URL,
			                        ''Since restart: '' + CAST(validation_failures AS NVARCHAR(100)) + '' validation failures, '' + CAST(dependencies_failed AS NVARCHAR(100)) + '' dependency failures, '' + CAST(write_conflicts AS NVARCHAR(100)) + '' write conflicts, '' + CAST(unique_constraint_violations AS NVARCHAR(100)) + '' unique constraint violations.'' AS Details
			                        FROM sys.dm_xtp_transaction_stats
                                    WHERE validation_failures <> 0
                                            OR dependencies_failed <> 0
                                            OR write_conflicts <> 0
                                            OR unique_constraint_violations <> 0 OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* Reliability - Database Files on Network File Shares */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 148 )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 148) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct 148 as CheckID ,
        d.[name] as DatabaseName ,
        170 as Priority ,
        'Reliability' as FindingsGroup ,
        'Database Files on Network File Shares' as Finding ,
        'https://BrentOzar.com/go/nas' as URL ,
        ( 'Files for this database are on: ' + left(mf.physical_name, 30)) as Details
      from sys.databases d
        inner join sys.master_files mf on d.database_id = mf.database_id
      where mf.physical_name like '\\%'
        and d.name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 148);
    end;

    /* Reliability - Database Files Stored in Azure */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 149 )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 149) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct 149 as CheckID ,
        d.[name] as DatabaseName ,
        170 as Priority ,
        'Reliability' as FindingsGroup ,
        'Database Files Stored in Azure' as Finding ,
        'https://BrentOzar.com/go/azurefiles' as URL ,
        ( 'Files for this database are on: ' + left(mf.physical_name, 30)) as Details
      from sys.databases d
        inner join sys.master_files mf on d.database_id = mf.database_id
      where mf.physical_name like 'http://%'
        and d.name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 149);
    end;

    /* Reliability - Errors Logged Recently in the Default Trace */

    /* First, let's check that there aren't any issues with the trace files */
    BEGIN try
						
						insert into #fnTraceGettable
      ( TextData ,
      DatabaseName ,
      EventClass ,
      Severity ,
      StartTime ,
      EndTime ,
      Duration ,
      NTUserName ,
      NTDomainName ,
      HostName ,
      ApplicationName ,
      LoginName ,
      DBUserName
      )
    select top 20000
      convert(nvarchar(4000),t.TextData) ,
      t.DatabaseName ,
      t.EventClass ,
      t.Severity ,
      t.StartTime ,
      t.EndTime ,
      t.Duration ,
      t.NTUserName ,
      t.NTDomainName ,
      t.HostName ,
      t.ApplicationName ,
      t.LoginName ,
      t.DBUserName
    from sys.fn_trace_gettable(@base_tracefilename, default) t
    where
							(
								t.EventClass = 22
      and t.Severity >= 17
      and t.StartTime > DATEADD(dd, -30, GETDATE())
							)
      or
      (
							    t.EventClass in (92, 93)
      and t.StartTime > DATEADD(dd, -30, GETDATE())
      and t.Duration > 15000000
							)
      or
      (
								t.EventClass in (94, 95, 116)
							)

							set @TraceFileIssue = 0

						END TRY
						BEGIN catch

							set @TraceFileIssue = 1
						
						END CATCH

    if @TraceFileIssue = 1
							begin
      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 199 )								
								
								insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select
        '199' as CheckID ,
        '' as DatabaseName ,
        50 as Priority ,
        'Reliability' as FindingsGroup ,
        'There Is An Error With The Default Trace' as Finding ,
        'https://BrentOzar.com/go/defaulttrace' as URL ,
        'Somebody has been messing with your trace files. Check the files are present at ' + @base_tracefilename as Details
    end

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 150 )
      and @base_tracefilename is not null
      and @TraceFileIssue = 0
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 150) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct 150 as CheckID ,
        t.DatabaseName,
        50 as Priority ,
        'Reliability' as FindingsGroup ,
        'Errors Logged Recently in the Default Trace' as Finding ,
        'https://BrentOzar.com/go/defaulttrace' as URL ,
        CAST(t.TextData as nvarchar(4000)) as Details
      from #fnTraceGettable t
      where t.EventClass = 22
    /* Removed these as they're unnecessary, we filter this when inserting data into #fnTraceGettable */
    --AND t.Severity >= 17
    --AND t.StartTime > DATEADD(dd, -30, GETDATE());
    end;

    /* Performance - File Growths Slow */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 151 )
      and @base_tracefilename is not null
      and @TraceFileIssue = 0
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 151) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct 151 as CheckID ,
        t.DatabaseName,
        50 as Priority ,
        'Performance' as FindingsGroup ,
        'File Growths Slow' as Finding ,
        'https://BrentOzar.com/go/filegrowth' as URL ,
        CAST(COUNT(*) as nvarchar(100)) + ' growths took more than 15 seconds each. Consider setting file autogrowth to a smaller increment.' as Details
      from #fnTraceGettable t
      where t.EventClass in (92, 93)
      /* Removed these as they're unnecessary, we filter this when inserting data into #fnTraceGettable */
      --AND t.StartTime > DATEADD(dd, -30, GETDATE())
      --AND t.Duration > 15000000
      group by t.DatabaseName
      having COUNT(*) > 1;
    end;

    /* Performance - Many Plans for One Query */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 160 )
      and exists (select *
      from sys.all_columns
      where name = 'query_hash')
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 160) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        SELECT TOP 1 160 AS CheckID,
			                        100 AS Priority,
			                        ''Performance'' AS FindingsGroup,
			                        ''Many Plans for One Query'' AS Finding,
			                        ''https://BrentOzar.com/go/parameterization'' AS URL,
			                        CAST(COUNT(DISTINCT plan_handle) AS NVARCHAR(50)) + '' plans are present for a single query in the plan cache - meaning we probably have parameterization issues.'' AS Details
			                        FROM sys.dm_exec_query_stats qs
                                    CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
                                    WHERE pa.attribute = ''dbid''
                                    GROUP BY qs.query_hash, pa.value
                                    HAVING COUNT(DISTINCT plan_handle) > 50
									ORDER BY COUNT(DISTINCT plan_handle) DESC OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* Performance - High Number of Cached Plans */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 161 )
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 161) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        SELECT TOP 1 161 AS CheckID,
			                        100 AS Priority,
			                        ''Performance'' AS FindingsGroup,
			                        ''High Number of Cached Plans'' AS Finding,
			                        ''https://BrentOzar.com/go/planlimits'' AS URL,
			                        ''Your server configuration is limited to '' + CAST(ht.buckets_count * 4 AS VARCHAR(20)) + '' '' + ht.name + '', and you are currently caching '' + CAST(cc.entries_count AS VARCHAR(20)) + ''.'' AS Details
			                        FROM sys.dm_os_memory_cache_hash_tables ht
			                        INNER JOIN sys.dm_os_memory_cache_counters cc ON ht.name = cc.name AND ht.type = cc.type
			                        where ht.name IN ( ''SQL Plans'' , ''Object Plans'' , ''Bound Trees'' )
			                        AND cc.entries_count >= (3 * ht.buckets_count) OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* Performance - Too Much Free Memory */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 165 )
							begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 165) with NOWAIT;

      insert into #BlitzResults
        (CheckID,
        Priority,
        FindingsGroup,
        Finding,
        URL,
        Details)
      select 165, 50, 'Performance', 'Too Much Free Memory', 'https://BrentOzar.com/go/freememory',
        CAST((CAST(cFree.cntr_value as bigint) / 1024 / 1024 ) as nvarchar(100)) + N'GB of free memory inside SQL Server''s buffer pool, which is ' + CAST((CAST(cTotal.cntr_value as bigint) / 1024 / 1024) as nvarchar(100)) + N'GB. You would think lots of free memory would be good, but check out the URL for more information.' as Details
      from sys.dm_os_performance_counters cFree
        inner join sys.dm_os_performance_counters cTotal on cTotal.object_name like N'%Memory Manager%'
          and cTotal.counter_name = N'Total Server Memory (KB)                                                                                                        '
      where cFree.object_name like N'%Memory Manager%'
        and cFree.counter_name = N'Free Memory (KB)                                                                                                                '
        and CAST(cTotal.cntr_value as bigint) > 20480000000
        and CAST(cTotal.cntr_value as bigint) * .3 <= CAST(cFree.cntr_value as bigint)
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Standard%';

    end;

    /* Outdated sp_Blitz - sp_Blitz is Over 6 Months Old */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 155 )
      and DATEDIFF(MM, @VersionDate, GETDATE()) > 6
	                        begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 155) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 155 as CheckID ,
        0 as Priority ,
        'Outdated sp_Blitz' as FindingsGroup ,
        'sp_Blitz is Over 6 Months Old' as Finding ,
        'http://FirstResponderKit.org/' as URL ,
        'Some things get better with age, like fine wine and your T-SQL. However, sp_Blitz is not one of those things - time to go download the current one.' as Details;
    end;

    /* Populate a list of database defaults. I'm doing this kind of oddly -
						    it reads like a lot of work, but this way it compiles & runs on all
						    versions of SQL Server.
						*/

    if @Debug in (1, 2) raiserror('Generating database defaults.', 0, 1) with NOWAIT;

    insert into #DatabaseDefaults
    select 'is_supplemental_logging_enabled', 0, 131, 210, 'Supplemental Logging Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_supplemental_logging_enabled' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'snapshot_isolation_state', 0, 132, 210, 'Snapshot Isolation Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'snapshot_isolation_state' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_read_committed_snapshot_on', 0, 133, 210, 'Read Committed Snapshot Isolation Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_read_committed_snapshot_on' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_auto_create_stats_incremental_on', 0, 134, 210, 'Auto Create Stats Incremental Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_auto_create_stats_incremental_on' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_ansi_null_default_on', 0, 135, 210, 'ANSI NULL Default Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_ansi_null_default_on' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_recursive_triggers_on', 0, 136, 210, 'Recursive Triggers Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_recursive_triggers_on' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_trustworthy_on', 0, 137, 210, 'Trustworthy Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_trustworthy_on' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_parameterization_forced', 0, 138, 210, 'Forced Parameterization Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_parameterization_forced' and object_id = OBJECT_ID('sys.databases');
    /* Not alerting for this since we actually want it and we have a separate check for it:
						INSERT INTO #DatabaseDefaults
						  SELECT 'is_query_store_on', 0, 139, 210, 'Query Store Enabled', 'https://BrentOzar.com/go/dbdefaults', NULL
						  FROM sys.all_columns
						  WHERE name = 'is_query_store_on' AND object_id = OBJECT_ID('sys.databases');
						*/
    insert into #DatabaseDefaults
    select 'is_cdc_enabled', 0, 140, 210, 'Change Data Capture Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_cdc_enabled' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'containment', 0, 141, 210, 'Containment Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'containment' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'target_recovery_time_in_seconds', 0, 142, 210, 'Target Recovery Time Changed', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'target_recovery_time_in_seconds' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'delayed_durability', 0, 143, 210, 'Delayed Durability Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'delayed_durability' and object_id = OBJECT_ID('sys.databases');
    insert into #DatabaseDefaults
    select 'is_memory_optimized_elevate_to_snapshot_on', 0, 144, 210, 'Memory Optimized Enabled', 'https://BrentOzar.com/go/dbdefaults', null
    from sys.all_columns
    where name = 'is_memory_optimized_elevate_to_snapshot_on' and object_id = OBJECT_ID('sys.databases');

    declare DatabaseDefaultsLoop cursor for
						  select name, DefaultValue, CheckID, Priority, Finding, URL, Details
    from #DatabaseDefaults;

    open DatabaseDefaultsLoop;
    fetch NEXT from DatabaseDefaultsLoop into @CurrentName, @CurrentDefaultValue, @CurrentCheckID, @CurrentPriority, @CurrentFinding, @CurrentURL, @CurrentDetails;
    while @@FETCH_STATUS = 0
						begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, @CurrentCheckID) with NOWAIT;

      /* Target Recovery Time (142) can be either 0 or 60 due to a number of bugs */
      if @CurrentCheckID = 142
								set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details)
								   SELECT ' + CAST(@CurrentCheckID as nvarchar(200)) + ', d.[name], ' + CAST(@CurrentPriority as nvarchar(200)) + ', ''Non-Default Database Config'', ''' + @CurrentFinding + ''',''' + @CurrentURL + ''',''' + coalesce(@CurrentDetails, 'This database setting is not the default.') + '''
									FROM sys.databases d
									WHERE d.database_id > 4 AND (d.[' + @CurrentName + '] NOT IN (0, 60) OR d.[' + @CurrentName + '] IS NULL) OPTION (RECOMPILE);';
							else
								set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details)
								   SELECT ' + CAST(@CurrentCheckID as nvarchar(200)) + ', d.[name], ' + CAST(@CurrentPriority as nvarchar(200)) + ', ''Non-Default Database Config'', ''' + @CurrentFinding + ''',''' + @CurrentURL + ''',''' + coalesce(@CurrentDetails, 'This database setting is not the default.') + '''
									FROM sys.databases d
									WHERE d.database_id > 4 AND (d.[' + @CurrentName + '] <> ' + @CurrentDefaultValue + ' OR d.[' + @CurrentName + '] IS NULL) OPTION (RECOMPILE);';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXEC (@StringToExecute);

      fetch NEXT from DatabaseDefaultsLoop into @CurrentName, @CurrentDefaultValue, @CurrentCheckID, @CurrentPriority, @CurrentFinding, @CurrentURL, @CurrentDetails;
    end;

    close DatabaseDefaultsLoop;
    deallocate DatabaseDefaultsLoop;


    /*This checks to see if Agent is Offline*/
    if @ProductVersionMajor >= 10
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 167 )
					begin
      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_services' )
									begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 167) with NOWAIT;

        insert    into [#BlitzResults]
          ( [CheckID] ,
          [Priority] ,
          [FindingsGroup] ,
          [Finding] ,
          [URL] ,
          [Details] )

        select
          167 as [CheckID] ,
          250 as [Priority] ,
          'Server Info' as [FindingsGroup] ,
          'Agent is Currently Offline' as [Finding] ,
          '' as [URL] ,
          ( 'Oops! It looks like the ' + [servicename] + ' service is ' + [status_desc] + '. The startup type is ' + [startup_type_desc] + '.'
							   ) as [Details]
        from
          [sys].[dm_server_services]
        where [status_desc] <> 'Running'
          and [servicename] like 'SQL Server Agent%'
          and CAST(SERVERPROPERTY('Edition') as varchar(1000)) not like '%xpress%';

      end;
    end;

    /*This checks to see if the Full Text thingy is offline*/
    if @ProductVersionMajor >= 10
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 168 )
					begin
      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_services' )
					begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 168) with NOWAIT;

        insert    into [#BlitzResults]
          ( [CheckID] ,
          [Priority] ,
          [FindingsGroup] ,
          [Finding] ,
          [URL] ,
          [Details] )

        select
          168 as [CheckID] ,
          250 as [Priority] ,
          'Server Info' as [FindingsGroup] ,
          'Full-text Filter Daemon Launcher is Currently Offline' as [Finding] ,
          '' as [URL] ,
          ( 'Oops! It looks like the ' + [servicename] + ' service is ' + [status_desc] + '. The startup type is ' + [startup_type_desc] + '.'
							   ) as [Details]
        from
          [sys].[dm_server_services]
        where [status_desc] <> 'Running'
          and [servicename] like 'SQL Full-text Filter Daemon Launcher%';

      end;
    end;

    /*This checks which service account SQL Server is running as.*/
    if @ProductVersionMajor >= 10
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 169 )

					begin
      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_services' )
					begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 169) with NOWAIT;

        insert    into [#BlitzResults]
          ( [CheckID] ,
          [Priority] ,
          [FindingsGroup] ,
          [Finding] ,
          [URL] ,
          [Details] )

        select
          169 as [CheckID] ,
          250 as [Priority] ,
          'Informational' as [FindingsGroup] ,
          'SQL Server is running under an NT Service account' as [Finding] ,
          'https://BrentOzar.com/go/setup' as [URL] ,
          ( 'I''m running as ' + [service_account] + '. I wish I had an Active Directory service account instead.'
							   ) as [Details]
        from
          [sys].[dm_server_services]
        where [service_account] like 'NT Service%'
          and [servicename] like 'SQL Server%'
          and [servicename] not like 'SQL Server Agent%';

      end;
    end;

    /*This checks which service account SQL Agent is running as.*/
    if @ProductVersionMajor >= 10
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 170 )

					begin
      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_services' )
					begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 170) with NOWAIT;

        insert    into [#BlitzResults]
          ( [CheckID] ,
          [Priority] ,
          [FindingsGroup] ,
          [Finding] ,
          [URL] ,
          [Details] )

        select
          170 as [CheckID] ,
          250 as [Priority] ,
          'Informational' as [FindingsGroup] ,
          'SQL Server Agent is running under an NT Service account' as [Finding] ,
          'https://BrentOzar.com/go/setup' as [URL] ,
          ( 'I''m running as ' + [service_account] + '. I wish I had an Active Directory service account instead.'
							   ) as [Details]
        from
          [sys].[dm_server_services]
        where [service_account] like 'NT Service%'
          and [servicename] like 'SQL Server Agent%';

      end;
    end;

    /*This counts memory dumps and gives min and max date of in view*/
    if @ProductVersionMajor >= 10
      and not (@ProductVersionMajor = 10.5 and @ProductVersionMinor < 4297) /* Skip due to crash bug: https://support.microsoft.com/en-us/help/2908087 */
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 171 )
					begin
      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_memory_dumps' )
						begin
        if 5 <= (select COUNT(*)
        from [sys].[dm_server_memory_dumps]
        where [creation_time] >= DATEADD(YEAR, -1, GETDATE()))

							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 171) with NOWAIT;

          insert    into [#BlitzResults]
            ( [CheckID] ,
            [Priority] ,
            [FindingsGroup] ,
            [Finding] ,
            [URL] ,
            [Details] )

          select
            171 as [CheckID] ,
            20 as [Priority] ,
            'Reliability' as [FindingsGroup] ,
            'Memory Dumps Have Occurred' as [Finding] ,
            'https://BrentOzar.com/go/dump' as [URL] ,
            ( 'That ain''t good. I''ve had ' +
									CAST(COUNT(*) as varchar(100)) + ' memory dumps between ' +
									CAST(CAST(MIN([creation_time]) as datetime) as varchar(100)) +
									' and ' +
									CAST(CAST(MAX([creation_time]) as datetime) as varchar(100)) +
									'!'
								   ) as [Details]
          from
            [sys].[dm_server_memory_dumps]
          where [creation_time] >= DATEADD(year, -1, GETDATE());

        end;
      end;
    end;

    /*Checks to see if you're on Developer or Evaluation*/
    if	not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 173 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 173) with NOWAIT;

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select
        173 as [CheckID] ,
        200 as [Priority] ,
        'Licensing' as [FindingsGroup] ,
        'Non-Production License' as [Finding] ,
        'https://BrentOzar.com/go/licensing' as [URL] ,
        ( 'We''re not the licensing police, but if this is supposed to be a production server, and you''re running ' +
							CAST(SERVERPROPERTY('edition') as varchar(100)) +
							' the good folks at Microsoft might get upset with you. Better start counting those cores.'
							   ) as [Details]
      where CAST(SERVERPROPERTY('edition') as varchar(100)) like '%Developer%'
        or CAST(SERVERPROPERTY('edition') as varchar(100)) like '%Evaluation%';

    end;

    /*Checks to see if Buffer Pool Extensions are in use*/
    if @ProductVersionMajor >= 12
      and not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 174 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 174) with NOWAIT;

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select
        174 as [CheckID] ,
        200 as [Priority] ,
        'Performance' as [FindingsGroup] ,
        'Buffer Pool Extensions Enabled' as [Finding] ,
        'https://BrentOzar.com/go/bpe' as [URL] ,
        ( 'You have Buffer Pool Extensions enabled, and one lives here: ' +
								[path] +
								'. It''s currently ' +
								case when [current_size_in_kb] / 1024. / 1024. > 0
																	 then CAST([current_size_in_kb] / 1024. / 1024. as varchar(100))
																		  + ' GB'
																	 else CAST([current_size_in_kb] / 1024. as varchar(100))
																		  + ' MB'
								end +
								'. Did you know that BPEs only provide single threaded access 8KB (one page) at a time?'	
							   ) as [Details]
      from sys.dm_os_buffer_pool_extension_configuration
      where [state_description] <> 'BUFFER POOL EXTENSION DISABLED';

    end;

    /*Check for too many tempdb files*/
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 175 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 175) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select distinct
        175 as CheckID ,
        'TempDB' as DatabaseName ,
        170 as Priority ,
        'File Configuration' as FindingsGroup ,
        'TempDB Has >16 Data Files' as Finding ,
        'https://BrentOzar.com/go/tempdb' as URL ,
        'Woah, Nelly! TempDB has ' + CAST(COUNT_BIG(*) as varchar(30)) + '. Did you forget to terminate a loop somewhere?' as Details
      from sys.[master_files] as [mf]
      where [mf].[database_id] = 2 and [mf].[type] = 0
      having COUNT_BIG(*) > 16;
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 176 )
								begin

      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_xe_sessions' )
								
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 176) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select distinct
          176 as CheckID ,
          '' as DatabaseName ,
          200 as Priority ,
          'Monitoring' as FindingsGroup ,
          'Extended Events Hyperextension' as Finding ,
          'https://BrentOzar.com/go/xe' as URL ,
          'Hey big spender, you have ' + CAST(COUNT_BIG(*) as varchar(30)) + ' Extended Events sessions running. You sure you meant to do that?' as Details
        from sys.dm_xe_sessions
        where [name] not in
												( 'AlwaysOn_health', 
												  'system_health', 
												  'telemetry_xevents', 
												  'sp_server_diagnostics', 
												  'sp_server_diagnostics session', 
												  'hkenginexesession' )
          and name not like '%$A%'
        having COUNT_BIG(*) >= 2;
      end;
    end;

    /*Harmful startup parameter*/
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 177 )
								begin

      if exists ( select 1
      from sys.all_objects
      where   name = 'dm_server_registry' )
			
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 177) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select distinct
          177 as CheckID ,
          '' as DatabaseName ,
          5 as Priority ,
          'Monitoring' as FindingsGroup ,
          'Disabled Internal Monitoring Features' as Finding ,
          'https://msdn.microsoft.com/en-us/library/ms190737.aspx' as URL ,
          'You have -x as a startup parameter. You should head to the URL and read more about what it does to your system.' as Details
        from
          [sys].[dm_server_registry] as [dsr]
        where
													[dsr].[registry_key] like N'%MSSQLServer\Parameters'
          and [dsr].[value_data] = '-x';;
      end;
    end;


    /* Reliability - Dangerous Third Party Modules - 179 */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 179 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 179) with NOWAIT;

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select
        179 as [CheckID] ,
        5 as [Priority] ,
        'Reliability' as [FindingsGroup] ,
        'Dangerous Third Party Modules' as [Finding] ,
        'https://support.microsoft.com/en-us/kb/2033238' as [URL] ,
        ( coalesce(company, '') + ' - ' + coalesce(description, '') + ' - ' + coalesce(name, '') + ' - suspected dangerous third party module is installed.') as [Details]
      from sys.dm_os_loaded_modules
      where UPPER(name) like UPPER('%\ENTAPI.DLL') /* McAfee VirusScan Enterprise */
        or UPPER(name) like UPPER('%\HIPI.DLL') or UPPER(name) like UPPER('%\HcSQL.dll') or UPPER(name) like UPPER('%\HcApi.dll') or UPPER(name) like UPPER('%\HcThe.dll') /* McAfee Host Intrusion */
        or UPPER(name) like UPPER('%\SOPHOS_DETOURED.DLL') or UPPER(name) like UPPER('%\SOPHOS_DETOURED_x64.DLL') or UPPER(name) like UPPER('%\SWI_IFSLSP_64.dll') or UPPER(name) like UPPER('%\SOPHOS~%.dll') /* Sophos AV */
        or UPPER(name) like UPPER('%\PIOLEDB.DLL') or UPPER(name) like UPPER('%\PISDK.DLL');
    /* OSISoft PI data access */

    end;

    /*Find shrink database tasks*/

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 180 )
      and convert(varchar(128), SERVERPROPERTY ('productversion')) like '1%' /* Only run on 2008+ */
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 180) with NOWAIT;

      with
        XMLNAMESPACES ('www.microsoft.com/SqlServer/Dts' as [dts])
						,
        [maintenance_plan_steps]
        as
        (
          select [name]
								, [id] -- ID required to link maintenace plan with jobs and jobhistory (sp_Blitz Issue #776)							
								, CAST(CAST([packagedata] as varbinary(MAX)) as xml) as [maintenance_plan_xml]
          from [msdb].[dbo].[sysssispackages]
          where [packagetype] = 6
        )
      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select
        180 as [CheckID] ,
        -- sp_Blitz Issue #776
        -- Job has history and was executed in the last 30 days
        case when (cast(datediff(dd, substring(cast(sjh.run_date as nvarchar(10)), 1, 4) + '-' + substring(cast(sjh.run_date as nvarchar(10)), 5, 2) + '-' + substring(cast(sjh.run_date as nvarchar(10)), 7, 2), GETDATE()) as int) < 30) or (j.[enabled] = 1 and ssc.[enabled] = 1 )then
						    100
						else -- no job history (implicit) AND job not run in the past 30 days AND (Job disabled OR Job Schedule disabled)
					        200
						end as Priority,
        'Performance' as [FindingsGroup] ,
        'Shrink Database Step In Maintenance Plan' as [Finding] ,
        'https://BrentOzar.com/go/autoshrink' as [URL] ,
        'The maintenance plan ' + [mps].[name] + ' has a step to shrink databases in it. Shrinking databases is as outdated as maintenance plans.'
						+ case when coalesce(ssc.name,'0') != '0' then + ' (Schedule: [' + ssc.name + '])' else + '' end as [Details]
      from [maintenance_plan_steps] [mps]
							cross APPLY [maintenance_plan_xml].[nodes]('//dts:Executables/dts:Executable') [t]([c])
        join msdb.dbo.sysmaintplan_subplans as sms
        on mps.id = sms.plan_id
        join msdb.dbo.sysjobs j
        on sms.job_id = j.job_id
        left outer join msdb.dbo.sysjobsteps as step
        on j.job_id = step.job_id
        left outer join msdb.dbo.sysjobschedules as sjsc
        on j.job_id = sjsc.job_id
        left outer join msdb.dbo.sysschedules as ssc
        on sjsc.schedule_id = ssc.schedule_id
          and sjsc.job_id = j.job_id
        left outer join msdb.dbo.sysjobhistory as sjh
        on j.job_id = sjh.job_id
          and step.step_id = sjh.step_id
          and sjh.run_date in (select max(sjh2.run_date)
          from msdb.dbo.sysjobhistory as sjh2
          where sjh2.job_id = j.job_id) -- get the latest entry date
          and sjh.run_time in (select max(sjh3.run_time)
          from msdb.dbo.sysjobhistory as sjh3
          where sjh3.job_id = j.job_id and sjh3.run_date = sjh.run_date)
      -- get the latest entry time
      where [c].[value]('(@dts:ObjectName)', 'VARCHAR(128)') = 'Shrink Database Task';

    end;

    /*Find repetitive maintenance tasks*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 181 )
      and convert(varchar(128), SERVERPROPERTY ('productversion')) like '1%' /* Only run on 2008+ */
				begin
      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 181) with NOWAIT;

      with
        XMLNAMESPACES ('www.microsoft.com/SqlServer/Dts' as [dts])
						,
        [maintenance_plan_steps]
        as
        (
          select [name]
								, CAST(CAST([packagedata] as varbinary(MAX)) as xml) as [maintenance_plan_xml]
          from [msdb].[dbo].[sysssispackages]
          where [packagetype] = 6
        ),
        [maintenance_plan_table]
        as
        (
          select [mps].[name]
							, [c].[value]('(@dts:ObjectName)', 'NVARCHAR(128)') as [step_name]
          from [maintenance_plan_steps] [mps]
							cross APPLY [maintenance_plan_xml].[nodes]('//dts:Executables/dts:Executable') [t]([c])
        ),
        [mp_steps_pretty]
        as
        (
          select distinct [m1].[name] ,
            STUFF((select N', ' + [m2].[step_name]
            from [maintenance_plan_table] as [m2]
            where [m1].[name] = [m2].[name]
            for XML PATH(N'')), 1, 2, N'') as [maintenance_plan_steps]
          from [maintenance_plan_table] as [m1]
        )

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select
        181 as [CheckID] ,
        100 as [Priority] ,
        'Performance' as [FindingsGroup] ,
        'Repetitive Steps In Maintenance Plans' as [Finding] ,
        'https://ola.hallengren.com/' as [URL] ,
        'The maintenance plan ' + [m].[name] + ' is doing repetitive work on indexes and statistics. Perhaps it''s time to try something more modern?' as [Details]
      from [mp_steps_pretty] m
      where m.[maintenance_plan_steps] like '%Rebuild%Reorganize%'
        or m.[maintenance_plan_steps] like '%Rebuild%Update%';

    end;


    /* Reliability - No Failover Cluster Nodes Available - 184 */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 184 )
      and CAST(SERVERPROPERTY('ProductVersion') as nvarchar(128)) not like '10%'
      and CAST(SERVERPROPERTY('ProductVersion') as nvarchar(128)) not like '9%'
					begin
      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 184) with NOWAIT;

      set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			                        							SELECT TOP 1
							  184 AS CheckID ,
							  20 AS Priority ,
							  ''Reliability'' AS FindingsGroup ,
							  ''No Failover Cluster Nodes Available'' AS Finding ,
							  ''https://BrentOzar.com/go/node'' AS URL ,
							  ''There are no failover cluster nodes available if the active node fails'' AS Details
							FROM (
							  SELECT SUM(CASE WHEN [status] = 0 AND [is_current_owner] = 0 THEN 1 ELSE 0 END) AS [available_nodes]
							  FROM sys.dm_os_cluster_nodes
							) a
							WHERE [available_nodes] < 1 OPTION (RECOMPILE)';

      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);
    end;

    /* Reliability - TempDB File Error */
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 191 )
      and (select COUNT(*)
      from sys.master_files
      where database_id = 2) <> (select COUNT(*)
      from tempdb.sys.database_files)
				begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 191) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select
        191 as [CheckID] ,
        50 as [Priority] ,
        'Reliability' as [FindingsGroup] ,
        'TempDB File Error' as [Finding] ,
        'https://BrentOzar.com/go/tempdboops' as [URL] ,
        'Mismatch between the number of TempDB files in sys.master_files versus tempdb.sys.database_files' as [Details];
    end;

    /*Perf - Odd number of cores in a socket*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null
        and CheckID = 198 )
      and exists ( select 1
      from sys.dm_os_schedulers
      where   is_online = 1
        and scheduler_id < 255
        and parent_node_id < 64
      group by parent_node_id,
		                        is_online
      having  ( COUNT(cpu_id) + 2 ) % 2 = 1 )
		   begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 198) with NOWAIT

      insert into #BlitzResults
        (
        CheckID,
        DatabaseName,
        Priority,
        FindingsGroup,
        Finding,
        URL,
        Details
        )
      select 198 as CheckID,
        null as DatabaseName,
        10 as Priority,
        'Performance' as FindingsGroup,
        'CPU w/Odd Number of Cores' as Finding,
        'https://BrentOzar.com/go/oddity' as URL,
        'Node ' + convert(varchar(10), parent_node_id) + ' has ' + convert(varchar(10), COUNT(cpu_id))
		                + case when COUNT(cpu_id) = 1 then ' core assigned to it. This is a really bad NUMA configuration.'
		                       else ' cores assigned to it. This is a really bad NUMA configuration.'
		                  end as Details
      from sys.dm_os_schedulers
      where  is_online = 1
        and scheduler_id < 255
        and parent_node_id < 64
        and exists (
									select 1
        from ( select memory_node_id, SUM(online_scheduler_count) as schedulers
          from sys.dm_os_nodes
          where     memory_node_id < 64
          group  by memory_node_id ) as nodes
        having MIN(nodes.schedulers) <> MAX(nodes.schedulers)
									)
      group by parent_node_id,
		                is_online
      having ( COUNT(cpu_id) + 2 ) % 2 = 1;

    end;

    /*Begin: checking default trace for odd DBCC activity*/

    --Grab relevant event data
    if @TraceFileIssue = 0
		begin
      select UPPER(
					REPLACE(
						SUBSTRING(convert(nvarchar(MAX), t.TextData), 0,
								ISNULL(
									nullif(
										CHARINDEX('(', convert(NVARCHAR(MAX), t.TextData)),
										 0),
									  LEN(convert(nvarchar(MAX), t.TextData)) + 1 )) --This replaces everything up to an open paren, if one exists.
										, SUBSTRING(convert(nvarchar(MAX), t.TextData),
											ISNULL(
												nullif(
													CHARINDEX(' WITH ',convert(NVARCHAR(MAX), t.TextData))
													, 0),
												LEN(convert(nvarchar(MAX), t.TextData)) + 1),
													LEN(convert(nvarchar(MAX), t.TextData)) + 1 )
					   , '') --This replaces any optional WITH clause to a DBCC command, like tableresults.
					) as [dbcc_event_trunc_upper],
        UPPER(
				REPLACE(
					convert(nvarchar(MAX), t.TextData), SUBSTRING(convert(nvarchar(MAX), t.TextData),
											ISNULL(
												nullif(
													CHARINDEX(' WITH ',convert(NVARCHAR(MAX), t.TextData))
													, 0),
												LEN(convert(nvarchar(MAX), t.TextData)) + 1),
													LEN(convert(nvarchar(MAX), t.TextData)) + 1 ), '')) as [dbcc_event_full_upper],
        MIN(t.StartTime) over (PARTITION by convert(NVARCHAR(128), t.TextData)) as	min_start_time,
        MAX(t.StartTime) over (PARTITION by convert(NVARCHAR(128), t.TextData)) as max_start_time,
        t.NTUserName as [nt_user_name],
        t.NTDomainName as [nt_domain_name],
        t.HostName as [host_name],
        t.ApplicationName as [application_name],
        t.LoginName [login_name],
        t.DBUserName as [db_user_name]
      into #dbcc_events_from_trace
      from #fnTraceGettable as t
      where t.EventClass = 116
      option(RECOMPILE)
    end;

    /*Overall count of DBCC events excluding silly stuff*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 203 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 203) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select 203 as CheckID ,
        50 as Priority ,
        'DBCC Events' as FindingsGroup ,
        'Overall Events' as Finding ,
        '' as URL ,
        CAST(COUNT(*) as nvarchar(100)) + ' DBCC events have taken place between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
					'. This does not include CHECKDB and other usually benign DBCC events.'
					as Details
      from #dbcc_events_from_trace d
      /* This WHERE clause below looks horrible, but it's because users can run stuff like
			   DBCC     LOGINFO
			   with lots of spaces (or carriage returns, or comments) in between the DBCC and the
			   command they're trying to run. See Github issues 1062, 1074, 1075.
			*/
      where d.dbcc_event_full_upper not like '%DBCC%ADDINSTANCE%'
        and d.dbcc_event_full_upper not like '%DBCC%AUTOPILOT%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKALLOC%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKCATALOG%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKCONSTRAINTS%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKDB%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKFILEGROUP%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKIDENT%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKPRIMARYFILE%'
        and d.dbcc_event_full_upper not like '%DBCC%CHECKTABLE%'
        and d.dbcc_event_full_upper not like '%DBCC%CLEANTABLE%'
        and d.dbcc_event_full_upper not like '%DBCC%DBINFO%'
        and d.dbcc_event_full_upper not like '%DBCC%ERRORLOG%'
        and d.dbcc_event_full_upper not like '%DBCC%INCREMENTINSTANCE%'
        and d.dbcc_event_full_upper not like '%DBCC%INPUTBUFFER%'
        and d.dbcc_event_full_upper not like '%DBCC%LOGINFO%'
        and d.dbcc_event_full_upper not like '%DBCC%OPENTRAN%'
        and d.dbcc_event_full_upper not like '%DBCC%SETINSTANCE%'
        and d.dbcc_event_full_upper not like '%DBCC%SHOWFILESTATS%'
        and d.dbcc_event_full_upper not like '%DBCC%SHOW_STATISTICS%'
        and d.dbcc_event_full_upper not like '%DBCC%SQLPERF%NETSTATS%'
        and d.dbcc_event_full_upper not like '%DBCC%SQLPERF%LOGSPACE%'
        and d.dbcc_event_full_upper not like '%DBCC%TRACEON%'
        and d.dbcc_event_full_upper not like '%DBCC%TRACEOFF%'
        and d.dbcc_event_full_upper not like '%DBCC%TRACESTATUS%'
        and d.dbcc_event_full_upper not like '%DBCC%USEROPTIONS%'
        and d.application_name not like 'Critical Care(R) Collector'
        and d.application_name not like '%Red Gate Software Ltd SQL Prompt%'
        and d.application_name not like '%Spotlight Diagnostic Server%'
        and d.application_name not like '%SQL Diagnostic Manager%'
        and d.application_name not like '%Sentry%'
        and d.application_name not like '%LiteSpeed%'


      having COUNT(*) > 0;

    end;

    /*Check for someone running drop clean buffers*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 207 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 207) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select 207 as CheckID ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        'DBCC DROPCLEANBUFFERS Ran Recently' as Finding ,
        '' as URL ,
        'The user ' + coalesce(d.nt_user_name, d.login_name) + ' has run DBCC DROPCLEANBUFFERS ' + CAST(COUNT(*) as nvarchar(100)) + ' times between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
							'. If this is a production box, know that you''re clearing all data out of memory when this happens. What kind of monster would do that?'
							as Details
      from #dbcc_events_from_trace d
      where d.dbcc_event_full_upper = N'DBCC DROPCLEANBUFFERS'
      group by coalesce(d.nt_user_name, d.login_name)
      having COUNT(*) > 0;

    end;

    /*Check for someone running free proc cache*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 208 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 208) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select 208 as CheckID ,
        10 as Priority ,
        'DBCC Events' as FindingsGroup ,
        'DBCC FREEPROCCACHE Ran Recently' as Finding ,
        '' as URL ,
        'The user ' + coalesce(d.nt_user_name, d.login_name) + ' has run DBCC FREEPROCCACHE ' + CAST(COUNT(*) as nvarchar(100)) + ' times between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
							'. This has bad idea jeans written all over its butt, like most other bad idea jeans.'
							as Details
      from #dbcc_events_from_trace d
      where d.dbcc_event_full_upper = N'DBCC FREEPROCCACHE'
      group by coalesce(d.nt_user_name, d.login_name)
      having COUNT(*) > 0;

    end;

    /*Check for someone clearing wait stats*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 205 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 205) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select 205 as CheckID ,
        50 as Priority ,
        'Performance' as FindingsGroup ,
        'Wait Stats Cleared Recently' as Finding ,
        '' as URL ,
        'The user ' + coalesce(d.nt_user_name, d.login_name) + ' has run DBCC SQLPERF(''SYS.DM_OS_WAIT_STATS'',CLEAR) ' + CAST(COUNT(*) as nvarchar(100)) + ' times between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
							'. Why are you clearing wait stats? What are you hiding?'
							as Details
      from #dbcc_events_from_trace d
      where d.dbcc_event_full_upper = N'DBCC SQLPERF(''SYS.DM_OS_WAIT_STATS'',CLEAR)'
      group by coalesce(d.nt_user_name, d.login_name)
      having COUNT(*) > 0;

    end;

    /*Check for someone writing to pages. Yeah, right?*/
    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 209 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 209) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select 209 as CheckID ,
        50 as Priority ,
        'Reliability' as FindingsGroup ,
        'DBCC WRITEPAGE Used Recently' as Finding ,
        '' as URL ,
        'The user ' + coalesce(d.nt_user_name, d.login_name) + ' has run DBCC WRITEPAGE ' + CAST(COUNT(*) as nvarchar(100)) + ' times between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
								'. So, uh, are they trying to fix corruption, or cause corruption?'
								as Details
      from #dbcc_events_from_trace d
      where d.dbcc_event_trunc_upper = N'DBCC WRITEPAGE'
      group by coalesce(d.nt_user_name, d.login_name)
      having COUNT(*) > 0;

    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 210 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 210) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select 210 as CheckID ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        'DBCC SHRINK% Ran Recently' as Finding ,
        '' as URL ,
        'The user ' + coalesce(d.nt_user_name, d.login_name) + ' has run file shrinks ' + CAST(COUNT(*) as nvarchar(100)) + ' times between ' + convert(nvarchar(30), MIN(d.min_start_time)) + ' and ' + convert(nvarchar(30),  MAX(d.max_start_time)) +
								'. So, uh, are they trying cause bad performance on purpose?'
								as Details
      from #dbcc_events_from_trace d
      where d.dbcc_event_trunc_upper like N'DBCC SHRINK%'
      group by coalesce(d.nt_user_name, d.login_name)
      having COUNT(*) > 0;

    end;

    /*End: checking default trace for odd DBCC activity*/

    /*Begin check for autoshrink events*/

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 206 )
      and @TraceFileIssue = 0
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 206) with NOWAIT

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )

      select 206 as CheckID ,
        10 as Priority ,
        'Performance' as FindingsGroup ,
        'Auto-Shrink Ran Recently' as Finding ,
        '' as URL ,
        N'The database ' + QUOTENAME(t.DatabaseName) + N' has had '
											+ convert(nvarchar(10), COUNT(*))
												+ N' auto shrink events between '
													+ convert(nvarchar(30), MIN(t.StartTime)) + ' and ' + convert(nvarchar(30), MAX(t.StartTime))
														+ ' that lasted on average '
															+ convert(nvarchar(10), AVG(DATEDIFF(SECOND, t.StartTime, t.EndTime)))
																+ ' seconds.' as Details
      from #fnTraceGettable as t
      where t.EventClass in (94, 95)
      group by t.DatabaseName
      having AVG(DATEDIFF(SECOND, t.StartTime, t.EndTime)) > 5;

    end;

    if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 215 )
      and @TraceFileIssue = 0
      and exists (select *
      from sys.all_columns
      where name = 'database_id' and object_id = OBJECT_ID('sys.dm_exec_sessions'))
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 215) with NOWAIT

      set @StringToExecute = 'INSERT    INTO [#BlitzResults]
									( [CheckID] ,
									  [Priority] ,
									  [FindingsGroup] ,
									  [Finding] ,
                                      [DatabaseName] ,
									  [URL] ,
									  [Details] )

								SELECT	215 AS CheckID ,
										100 AS Priority ,
										''Performance'' AS FindingsGroup ,
										''Implicit Transactions'' AS Finding ,
										DB_NAME(s.database_id) AS DatabaseName,
										''https://www.brentozar.com/go/ImplicitTransactions/'' AS URL ,
										N''The database '' +
										DB_NAME(s.database_id)
										+ '' has ''
										+ CONVERT(NVARCHAR(20), COUNT_BIG(*))
										+ '' open implicit transactions ''
										+ '' with an oldest begin time of ''
										+ CONVERT(NVARCHAR(30), MIN(tat.transaction_begin_time)) AS details
								FROM    sys.dm_tran_active_transactions AS tat
								LEFT JOIN sys.dm_tran_session_transactions AS tst
								ON tst.transaction_id = tat.transaction_id
								LEFT JOIN sys.dm_exec_sessions AS s
								ON s.session_id = tst.session_id
								WHERE tat.name = ''implicit_transaction''
								GROUP BY DB_NAME(s.database_id), transaction_type, transaction_state;';


      if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
      if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

      EXECUTE(@StringToExecute);



    end;


    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 216 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 216) with NOWAIT;

      with
        reboot_airhorn
        as
        (
                      select create_date
            from sys.databases
            where  database_id = 2
          union all
            select CAST(DATEADD(SECOND, ( ms_ticks / 1000 ) * ( -1 ), GETDATE()) as datetime)
            from sys.dm_os_sys_info
        )
      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 216 as CheckID,
        10 as Priority,
        'Recent Restart' as FindingsGroup,
        'Server restarted in last 24 hours' as Finding,
        '' as URL,
        'Surprise! Your server was last restarted on: ' + convert(varchar(30), MAX(reboot_airhorn.create_date)) as details
      from reboot_airhorn
      having MAX(reboot_airhorn.create_date) >= DATEADD(HOUR, -24, GETDATE());


    end;



    if @CheckUserDatabaseObjects = 1
					begin

      if @Debug in (1, 2) raiserror('Starting @CheckUserDatabaseObjects section.', 0, 1) with NOWAIT

      /*
                        But what if you need to run a query in every individual database?
				        Check out CheckID 99 below. Yes, it uses sp_MSforeachdb, and no,
				        we're not happy about that. sp_MSforeachdb is known to have a lot
				        of issues, like skipping databases sometimes. However, this is the
				        only built-in option that we have. If you're writing your own code
				        for database maintenance, consider Aaron Bertrand's alternative:
				        http://www.mssqltips.com/sqlservertip/2201/making-a-more-reliable-and-flexible-spmsforeachdb/
				        We don't include that as part of sp_Blitz, of course, because
				        copying and distributing copyrighted code from others without their
				        written permission isn't a good idea.
				        */
      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 99 )
					        begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 99) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];  IF EXISTS (SELECT * FROM  sys.tables WITH (NOLOCK) WHERE name = ''sysmergepublications'' ) IF EXISTS ( SELECT * FROM sysmergepublications WITH (NOLOCK) WHERE retention = 0)   INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 99, DB_NAME(), 110, ''Performance'', ''Infinite merge replication metadata retention period'', ''https://BrentOzar.com/go/merge'', (''The ['' + DB_NAME() + ''] database has merge replication metadata retention period set to infinite - this can be the case of significant performance issues.'')';
      end;
      /*
				        Note that by using sp_MSforeachdb, we're running the query in all
				        databases. We're not checking #SkipChecks here for each database to
				        see if we should run the check in this database. That means we may
				        still run a skipped check if it involves sp_MSforeachdb. We just
				        don't output those results in the last step.
                        */

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 163 )
        and exists(select *
        from sys.all_objects
        where name = 'database_query_store_options')
							begin
        /* --TOURSTOP03-- */

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 163) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
			                            INSERT INTO #BlitzResults
			                            (CheckID,
			                            DatabaseName,
			                            Priority,
			                            FindingsGroup,
			                            Finding,
			                            URL,
			                            Details)
		                              SELECT TOP 1 163,
		                              N''?'',
		                              200,
		                              ''Performance'',
		                              ''Query Store Disabled'',
		                              ''https://BrentOzar.com/go/querystore'',
		                              (''The new SQL Server 2016 Query Store feature has not been enabled on this database.'')
		                              FROM [?].sys.database_query_store_options WHERE desired_state = 0
									  AND N''?'' NOT IN (''master'', ''model'', ''msdb'', ''tempdb'', ''DWConfiguration'', ''DWDiagnostics'', ''DWQueue'', ''ReportServer'', ''ReportServerTempDB'') OPTION (RECOMPILE)';
      end;


      if @ProductVersionMajor >= 13 and @ProductVersionMinor < 2149 --CU1 has the fix in it
        and not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 182 )
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Enterprise%'
        and CAST(SERVERPROPERTY('edition') as varchar(100)) not like '%Developer%'
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 182) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults
													(CheckID,
													DatabaseName,
													Priority,
													FindingsGroup,
													Finding,
													URL,
													Details)
													SELECT TOP 1
													182,
													''Server'',
													20,
													''Reliability'',
													''Query Store Cleanup Disabled'',
													''https://BrentOzar.com/go/cleanup'',
													(''SQL 2016 RTM has a bug involving dumps that happen every time Query Store cleanup jobs run. This is fixed in CU1 and later: https://sqlserverupdates.com/sql-server-2016-updates/'')
													FROM    sys.databases AS d
													WHERE   d.is_query_store_on = 1 OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 41 )
					        begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 41) with NOWAIT;

        exec dbo.sp_MSforeachdb 'use [?];
		                              INSERT INTO #BlitzResults
		                              (CheckID,
		                              DatabaseName,
		                              Priority,
		                              FindingsGroup,
		                              Finding,
		                              URL,
		                              Details)
		                              SELECT 41,
		                              N''?'',
		                              170,
		                              ''File Configuration'',
		                              ''Multiple Log Files on One Drive'',
		                              ''https://BrentOzar.com/go/manylogs'',
		                              (''The ['' + DB_NAME() + ''] database has multiple log files on the '' + LEFT(physical_name, 1) + '' drive. This is not a performance booster because log file access is sequential, not parallel.'')
		                              FROM [?].sys.database_files WHERE type_desc = ''LOG''
			                            AND N''?'' <> ''[tempdb]''
		                              GROUP BY LEFT(physical_name, 1)
		                              HAVING COUNT(*) > 1 OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 42 )
					        begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 42) with NOWAIT;

        exec dbo.sp_MSforeachdb 'use [?];
			                            INSERT INTO #BlitzResults
			                            (CheckID,
			                            DatabaseName,
			                            Priority,
			                            FindingsGroup,
			                            Finding,
			                            URL,
			                            Details)
			                            SELECT DISTINCT 42,
			                            N''?'',
			                            170,
			                            ''File Configuration'',
			                            ''Uneven File Growth Settings in One Filegroup'',
			                            ''https://BrentOzar.com/go/grow'',
			                            (''The ['' + DB_NAME() + ''] database has multiple data files in one filegroup, but they are not all set up to grow in identical amounts.  This can lead to uneven file activity inside the filegroup.'')
			                            FROM [?].sys.database_files
			                            WHERE type_desc = ''ROWS''
			                            GROUP BY data_space_id
			                            HAVING COUNT(DISTINCT growth) > 1 OR COUNT(DISTINCT is_percent_growth) > 1 OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 82 )
					            begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 82) with NOWAIT;

        exec sp_MSforeachdb 'use [?];
		                                INSERT INTO #BlitzResults
		                                (CheckID,
		                                DatabaseName,
		                                Priority,
		                                FindingsGroup,
		                                Finding,
		                                URL, Details)
		                                SELECT  DISTINCT 82 AS CheckID,
		                                N''?'' as DatabaseName,
		                                170 AS Priority,
		                                ''File Configuration'' AS FindingsGroup,
		                                ''File growth set to percent'',
		                                ''https://BrentOzar.com/go/percentgrowth'' AS URL,
		                                ''The ['' + DB_NAME() + ''] database file '' + f.physical_name + '' has grown to '' + CONVERT(NVARCHAR(10), CONVERT(NUMERIC(38, 2), (f.size / 128.) / 1024.)) + '' GB, and is using percent filegrowth settings. This can lead to slow performance during growths if Instant File Initialization is not enabled.''
		                                FROM    [?].sys.database_files f
		                                WHERE   is_percent_growth = 1 and size > 128000  OPTION (RECOMPILE);';
      end;

      /* addition by Henrik Staun Poulsen, Stovi Software */
      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 158 )
					            begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 158) with NOWAIT;

        exec sp_MSforeachdb 'use [?];
		                                INSERT INTO #BlitzResults
		                                (CheckID,
		                                DatabaseName,
		                                Priority,
		                                FindingsGroup,
		                                Finding,
		                                URL, Details)
		                                SELECT  DISTINCT 158 AS CheckID,
		                                N''?'' as DatabaseName,
		                                170 AS Priority,
		                                ''File Configuration'' AS FindingsGroup,
		                                ''File growth set to 1MB'',
		                                ''https://BrentOzar.com/go/percentgrowth'' AS URL,
		                                ''The ['' + DB_NAME() + ''] database file '' + f.physical_name + '' is using 1MB filegrowth settings, but it has grown to '' + CAST((f.size * 8 / 1000000) AS NVARCHAR(10)) + '' GB. Time to up the growth amount.''
		                                FROM    [?].sys.database_files f
                                        WHERE is_percent_growth = 0 and growth=128 and size > 128000  OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 33 )
					        begin
        if @@VERSION not like '%Microsoft SQL Server 2000%'
          and @@VERSION not like '%Microsoft SQL Server 2005%'
							        begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 33) with NOWAIT;

          exec dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults
					                                (CheckID,
					                                DatabaseName,
					                                Priority,
					                                FindingsGroup,
					                                Finding,
					                                URL,
					                                Details)
		                                  SELECT DISTINCT 33,
		                                  db_name(),
		                                  200,
		                                  ''Licensing'',
		                                  ''Enterprise Edition Features In Use'',
		                                  ''https://BrentOzar.com/go/ee'',
		                                  (''The ['' + DB_NAME() + ''] database is using '' + feature_name + ''.  If this database is restored onto a Standard Edition server, the restore will fail on versions prior to 2016 SP1.'')
		                                  FROM [?].sys.dm_db_persisted_sku_features OPTION (RECOMPILE);';
        end;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 19 )
					        begin
        /* Method 1: Check sys.databases parameters */

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 19) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )

        select 19 as CheckID ,
          [name] as DatabaseName ,
          200 as Priority ,
          'Informational' as FindingsGroup ,
          'Replication In Use' as Finding ,
          'https://BrentOzar.com/go/repl' as URL ,
          ( 'Database [' + [name]
										          + '] is a replication publisher, subscriber, or distributor.' ) as Details
        from sys.databases
        where   name not in ( select distinct
            DatabaseName
          from #SkipChecks
          where CheckID is null or CheckID = 19)
          and is_published = 1
          or is_subscribed = 1
          or is_merge_published = 1
          or is_distributor = 1;

        /* Method B: check subscribers for MSreplication_objects tables */
        exec dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults
										        (CheckID,
										        DatabaseName,
										        Priority,
										        FindingsGroup,
										        Finding,
										        URL,
										        Details)
							          SELECT DISTINCT 19,
							          db_name(),
							          200,
							          ''Informational'',
							          ''Replication In Use'',
							          ''https://BrentOzar.com/go/repl'',
							          (''['' + DB_NAME() + ''] has MSreplication_objects tables in it, indicating it is a replication subscriber.'')
							          FROM [?].sys.tables
							          WHERE name = ''dbo.MSreplication_objects'' AND ''?'' <> ''master'' OPTION (RECOMPILE)';

      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 32 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 32) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
			INSERT INTO #BlitzResults
			(CheckID,
			DatabaseName,
			Priority,
			FindingsGroup,
			Finding,
			URL,
			Details)
			SELECT 32,
			N''?'',
			150,
			''Performance'',
			''Triggers on Tables'',
			''https://BrentOzar.com/go/trig'',
			(''The ['' + DB_NAME() + ''] database has '' + CAST(SUM(1) AS NVARCHAR(50)) + '' triggers.'')
			FROM [?].sys.triggers t INNER JOIN [?].sys.objects o ON t.parent_id = o.object_id
			INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id WHERE t.is_ms_shipped = 0 AND DB_NAME() != ''ReportServer''
			HAVING SUM(1) > 0 OPTION (RECOMPILE)';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 38 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 38) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
			INSERT INTO #BlitzResults
			(CheckID,
			DatabaseName,
			Priority,
			FindingsGroup,
			Finding,
			URL,
			Details)
		  SELECT DISTINCT 38,
		  N''?'',
		  110,
		  ''Performance'',
		  ''Active Tables Without Clustered Indexes'',
		  ''https://BrentOzar.com/go/heaps'',
		  (''The ['' + DB_NAME() + ''] database has heaps - tables without a clustered index - that are being actively queried.'')
		  FROM [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id
		  INNER JOIN [?].sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
		  INNER JOIN sys.databases sd ON sd.name = N''?''
		  LEFT OUTER JOIN [?].sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = sd.database_id
		  WHERE i.type_desc = ''HEAP'' AND COALESCE(ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates) IS NOT NULL
		  AND sd.name <> ''tempdb'' AND sd.name <> ''DWDiagnostics'' AND o.is_ms_shipped = 0 AND o.type <> ''S'' OPTION (RECOMPILE)';
      end;

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 164 )
        and exists(select *
        from sys.all_objects
        where name = 'fn_validate_plan_guide')
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 164) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
			INSERT INTO #BlitzResults
			(CheckID,
			DatabaseName,
			Priority,
			FindingsGroup,
			Finding,
			URL,
			Details)
		  SELECT DISTINCT 164,
		  N''?'',
		  20,
		  ''Reliability'',
		  ''Plan Guides Failing'',
		  ''https://BrentOzar.com/go/misguided'',
		  (''The ['' + DB_NAME() + ''] database has plan guides that are no longer valid, so the queries involved may be failing silently.'')
		  FROM [?].sys.plan_guides g CROSS APPLY fn_validate_plan_guide(g.plan_guide_id) OPTION (RECOMPILE)';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 39 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 39) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
			INSERT INTO #BlitzResults
			(CheckID,
			DatabaseName,
			Priority,
			FindingsGroup,
			Finding,
			URL,
			Details)
		  SELECT DISTINCT 39,
		  N''?'',
		  150,
		  ''Performance'',
		  ''Inactive Tables Without Clustered Indexes'',
		  ''https://BrentOzar.com/go/heaps'',
		  (''The ['' + DB_NAME() + ''] database has heaps - tables without a clustered index - that have not been queried since the last restart.  These may be backup tables carelessly left behind.'')
		  FROM [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id
		  INNER JOIN [?].sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
		  INNER JOIN sys.databases sd ON sd.name = N''?''
		  LEFT OUTER JOIN [?].sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = sd.database_id
		  WHERE i.type_desc = ''HEAP'' AND COALESCE(ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates) IS NULL
		  AND sd.name <> ''tempdb'' AND sd.name <> ''DWDiagnostics'' AND o.is_ms_shipped = 0 AND o.type <> ''S'' OPTION (RECOMPILE)';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 46 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 46) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT 46,
		  N''?'',
		  150,
		  ''Performance'',
		  ''Leftover Fake Indexes From Wizards'',
		  ''https://BrentOzar.com/go/hypo'',
		  (''The index ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is a leftover hypothetical index from the Index Tuning Wizard or Database Tuning Advisor.  This index is not actually helping performance and should be removed.'')
		  from [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id
		  WHERE i.is_hypothetical = 1 OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 47 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 47) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT 47,
		  N''?'',
		  100,
		  ''Performance'',
		  ''Indexes Disabled'',
		  ''https://BrentOzar.com/go/ixoff'',
		  (''The index ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is disabled.  This index is not actually helping performance and should either be enabled or removed.'')
		  from [?].sys.indexes i INNER JOIN [?].sys.objects o ON i.object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id
		  WHERE i.is_disabled = 1 OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 48 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 48) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT DISTINCT 48,
		  N''?'',
		  150,
		  ''Performance'',
		  ''Foreign Keys Not Trusted'',
		  ''https://BrentOzar.com/go/trust'',
		  (''The ['' + DB_NAME() + ''] database has foreign keys that were probably disabled, data was changed, and then the key was enabled again.  Simply enabling the key is not enough for the optimizer to use this key - we have to alter the table using the WITH CHECK CHECK CONSTRAINT parameter.'')
		  from [?].sys.foreign_keys i INNER JOIN [?].sys.objects o ON i.parent_object_id = o.object_id INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id
		  WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0 AND N''?'' NOT IN (''master'', ''model'', ''msdb'', ''ReportServer'', ''ReportServerTempDB'') OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 56 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 56) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT 56,
		  N''?'',
		  150,
		  ''Performance'',
		  ''Check Constraint Not Trusted'',
		  ''https://BrentOzar.com/go/trust'',
		  (''The check constraint ['' + DB_NAME() + ''].['' + s.name + ''].['' + o.name + ''].['' + i.name + ''] is not trusted - meaning, it was disabled, data was changed, and then the constraint was enabled again.  Simply enabling the constraint is not enough for the optimizer to use this constraint - we have to alter the table using the WITH CHECK CHECK CONSTRAINT parameter.'')
		  from [?].sys.check_constraints i INNER JOIN [?].sys.objects o ON i.parent_object_id = o.object_id
		  INNER JOIN [?].sys.schemas s ON o.schema_id = s.schema_id
		  WHERE i.is_not_trusted = 1 AND i.is_not_for_replication = 0 AND i.is_disabled = 0 OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 95 )
							begin
        if @@VERSION not like '%Microsoft SQL Server 2000%'
          and @@VERSION not like '%Microsoft SQL Server 2005%'
									begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 95) with NOWAIT;

          exec dbo.sp_MSforeachdb 'USE [?];
			INSERT INTO #BlitzResults
				  (CheckID,
				  DatabaseName,
				  Priority,
				  FindingsGroup,
				  Finding,
				  URL,
				  Details)
			SELECT TOP 1 95 AS CheckID,
			N''?'' as DatabaseName,
			110 AS Priority,
			''Performance'' AS FindingsGroup,
			''Plan Guides Enabled'' AS Finding,
			''https://BrentOzar.com/go/guides'' AS URL,
			(''Database ['' + DB_NAME() + ''] has query plan guides so a query will always get a specific execution plan. If you are having trouble getting query performance to improve, it might be due to a frozen plan. Review the DMV sys.plan_guides to learn more about the plan guides in place on this server.'') AS Details
			FROM [?].sys.plan_guides WHERE is_disabled = 0 OPTION (RECOMPILE);';
        end;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 60 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 60) with NOWAIT;

        exec sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT 60 AS CheckID,
		  N''?'' as DatabaseName,
		  100 AS Priority,
		  ''Performance'' AS FindingsGroup,
		  ''Fill Factor Changed'',
		  ''https://BrentOzar.com/go/fillfactor'' AS URL,
		  ''The ['' + DB_NAME() + ''] database has '' + CAST(SUM(1) AS NVARCHAR(50)) + '' objects with fill factor = '' + CAST(fill_factor AS NVARCHAR(5)) + ''%. This can cause memory and storage performance problems, but may also prevent page splits.''
		  FROM    [?].sys.indexes
		  WHERE   fill_factor <> 0 AND fill_factor < 80 AND is_disabled = 0 AND is_hypothetical = 0
		  GROUP BY fill_factor OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 78 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 78) with NOWAIT;

        execute master.sys.sp_MSforeachdb 'USE [?];
                                    INSERT INTO #Recompile
                                    SELECT DISTINCT DBName = DB_Name(), SPName = SO.name, SM.is_recompiled, ISR.SPECIFIC_SCHEMA
                                    FROM sys.sql_modules AS SM
                                    LEFT OUTER JOIN master.sys.databases AS sDB ON SM.object_id = DB_id()
                                    LEFT OUTER JOIN dbo.sysobjects AS SO ON SM.object_id = SO.id and type = ''P''
                                    LEFT OUTER JOIN INFORMATION_SCHEMA.ROUTINES AS ISR on ISR.Routine_Name = SO.name AND ISR.SPECIFIC_CATALOG = DB_Name()
                                    WHERE SM.is_recompiled=1  OPTION (RECOMPILE); /* oh the rich irony of recompile here */
                                    ';
        insert into #BlitzResults
          (Priority,
          FindingsGroup,
          Finding,
          DatabaseName,
          URL,
          Details,
          CheckID)
        select [Priority] = '100',
          FindingsGroup = 'Performance',
          Finding = 'Stored Procedure WITH RECOMPILE',
          DatabaseName = DBName,
          URL = 'https://BrentOzar.com/go/recompile',
          Details = '[' + DBName + '].[' + SPSchema + '].[' + ProcName + '] has WITH RECOMPILE in the stored procedure code, which may cause increased CPU usage due to constant recompiles of the code.',
          CheckID = '78'
        from #Recompile as TR
        where ProcName not like 'sp_AskBrent%' and ProcName not like 'sp_Blitz%';
        drop table #Recompile;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 86 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 86) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 86, DB_NAME(), 230, ''Security'', ''Elevated Permissions on a Database'', ''https://BrentOzar.com/go/elevated'', (''In ['' + DB_NAME() + ''], user ['' + u.name + '']  has the role ['' + g.name + ''].  This user can perform tasks beyond just reading and writing data.'') FROM [?].dbo.sysmembers m inner join [?].dbo.sysusers u on m.memberuid = u.uid inner join sysusers g on m.groupuid = g.uid where u.name <> ''dbo'' and g.name in (''db_owner'' , ''db_accessadmin'' , ''db_securityadmin'' , ''db_ddladmin'') OPTION (RECOMPILE);';
      end;

      /*Check for non-aligned indexes in partioned databases*/

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 72 )
											begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 72) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
								insert into #partdb(dbname, objectname, type_desc)
								SELECT distinct db_name(DB_ID()) as DBName,o.name Object_Name,ds.type_desc
								FROM sys.objects AS o JOIN sys.indexes AS i ON o.object_id = i.object_id
								JOIN sys.data_spaces ds on ds.data_space_id = i.data_space_id
								LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s ON i.object_id = s.object_id AND i.index_id = s.index_id AND s.database_id = DB_ID()
								WHERE  o.type = ''u''
								 -- Clustered and Non-Clustered indexes
								AND i.type IN (1, 2)
								AND o.object_id in
								  (
									SELECT a.object_id from
									  (SELECT ob.object_id, ds.type_desc from sys.objects ob JOIN sys.indexes ind on ind.object_id = ob.object_id join sys.data_spaces ds on ds.data_space_id = ind.data_space_id
									  GROUP BY ob.object_id, ds.type_desc ) a group by a.object_id having COUNT (*) > 1
								  )  OPTION (RECOMPILE);';
        insert  into #BlitzResults
          ( CheckID ,
          DatabaseName ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select distinct
          72 as CheckID ,
          dbname as DatabaseName ,
          100 as Priority ,
          'Performance' as FindingsGroup ,
          'The partitioned database ' + dbname
																+ ' may have non-aligned indexes' as Finding ,
          'https://BrentOzar.com/go/aligned' as URL ,
          'Having non-aligned indexes on partitioned tables may cause inefficient query plans and CPU pressure' as Details
        from #partdb
        where   dbname is not null
          and dbname not in ( select distinct
            DatabaseName
          from #SkipChecks
          where CheckID is null or CheckID = 72);
        drop table #partdb;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 113 )
									begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 113) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
							  INSERT INTO #BlitzResults
									(CheckID,
									DatabaseName,
									Priority,
									FindingsGroup,
									Finding,
									URL,
									Details)
							  SELECT DISTINCT 113,
							  N''?'',
							  50,
							  ''Reliability'',
							  ''Full Text Indexes Not Updating'',
							  ''https://BrentOzar.com/go/fulltext'',
							  (''At least one full text index in this database has not been crawled in the last week.'')
							  from [?].sys.fulltext_indexes i WHERE change_tracking_state_desc <> ''AUTO'' AND i.is_enabled = 1 AND i.crawl_end_date < DATEADD(dd, -7, GETDATE())  OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 115 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 115) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?];
		  INSERT INTO #BlitzResults
				(CheckID,
				DatabaseName,
				Priority,
				FindingsGroup,
				Finding,
				URL,
				Details)
		  SELECT 115,
		  N''?'',
		  110,
		  ''Performance'',
		  ''Parallelism Rocket Surgery'',
		  ''https://BrentOzar.com/go/makeparallel'',
		  (''['' + DB_NAME() + ''] has a make_parallel function, indicating that an advanced developer may be manhandling SQL Server into forcing queries to go parallel.'')
		  from [?].INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = ''make_parallel'' AND ROUTINE_TYPE = ''FUNCTION'' OPTION (RECOMPILE);';
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 122 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 122) with NOWAIT;

        /* SQL Server 2012 and newer uses temporary stats for Availability Groups, and those show up as user-created */
        if exists (select *
        from sys.all_columns c
          inner join sys.all_objects o on c.object_id = o.object_id
        where c.name = 'is_temporary' and o.name = 'stats')
										
										exec dbo.sp_MSforeachdb 'USE [?];
												INSERT INTO #BlitzResults
													(CheckID,
													DatabaseName,
													Priority,
													FindingsGroup,
													Finding,
													URL,
													Details)
												SELECT TOP 1 122,
												N''?'',
												200,
												''Performance'',
												''User-Created Statistics In Place'',
												''https://BrentOzar.com/go/userstats'',
												(''['' + DB_NAME() + ''] has '' + CAST(SUM(1) AS NVARCHAR(10)) + '' user-created statistics. This indicates that someone is being a rocket scientist with the stats, and might actually be slowing things down, especially during stats updates.'')
												from [?].sys.stats WHERE user_created = 1 AND is_temporary = 0
                                                HAVING SUM(1) > 0  OPTION (RECOMPILE);';

									else
										exec dbo.sp_MSforeachdb 'USE [?];
												INSERT INTO #BlitzResults
													(CheckID,
													DatabaseName,
													Priority,
													FindingsGroup,
													Finding,
													URL,
													Details)
												SELECT 122,
												N''?'',
												200,
												''Performance'',
												''User-Created Statistics In Place'',
												''https://BrentOzar.com/go/userstats'',
												(''['' + DB_NAME() + ''] has '' + CAST(SUM(1) AS NVARCHAR(10)) + '' user-created statistics. This indicates that someone is being a rocket scientist with the stats, and might actually be slowing things down, especially during stats updates.'')
												from [?].sys.stats WHERE user_created = 1
                                                HAVING SUM(1) > 0 OPTION (RECOMPILE);';

      end;
      /* IF NOT EXISTS ( SELECT  1 */

      /*Check for high VLF count: this will omit any database snapshots*/

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 69 )
					        begin
        if @ProductVersionMajor >= 11

							        begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d] (2012 version of Log Info).', 0, 1, 69) with NOWAIT;

          exec sp_MSforeachdb N'USE [?];
		                                      INSERT INTO #LogInfo2012
		                                      EXEC sp_executesql N''DBCC LogInfo() WITH NO_INFOMSGS'';
		                                      IF    @@ROWCOUNT > 999
		                                      BEGIN
			                                    INSERT  INTO #BlitzResults
			                                    ( CheckID
			                                    ,DatabaseName
			                                    ,Priority
			                                    ,FindingsGroup
			                                    ,Finding
			                                    ,URL
			                                    ,Details)
			                                    SELECT      69
			                                    ,DB_NAME()
			                                    ,170
			                                    ,''File Configuration''
			                                    ,''High VLF Count''
			                                    ,''https://BrentOzar.com/go/vlf''
			                                    ,''The ['' + DB_NAME() + ''] database has '' +  CAST(COUNT(*) as VARCHAR(20)) + '' virtual log files (VLFs). This may be slowing down startup, restores, and even inserts/updates/deletes.''
			                                    FROM #LogInfo2012
			                                    WHERE EXISTS (SELECT name FROM master.sys.databases
					                                    WHERE source_database_id is null)  OPTION (RECOMPILE);
		                                      END
		                                    TRUNCATE TABLE #LogInfo2012;';
          drop table #LogInfo2012;
        end;
						        else
							        begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d] (pre-2012 version of Log Info).', 0, 1, 69) with NOWAIT;

          exec sp_MSforeachdb N'USE [?];
		                                      INSERT INTO #LogInfo
		                                      EXEC sp_executesql N''DBCC LogInfo() WITH NO_INFOMSGS'';
		                                      IF    @@ROWCOUNT > 999
		                                      BEGIN
			                                    INSERT  INTO #BlitzResults
			                                    ( CheckID
			                                    ,DatabaseName
			                                    ,Priority
			                                    ,FindingsGroup
			                                    ,Finding
			                                    ,URL
			                                    ,Details)
			                                    SELECT      69
			                                    ,DB_NAME()
			                                    ,170
			                                    ,''File Configuration''
			                                    ,''High VLF Count''
			                                    ,''https://BrentOzar.com/go/vlf''
			                                    ,''The ['' + DB_NAME() + ''] database has '' +  CAST(COUNT(*) as VARCHAR(20)) + '' virtual log files (VLFs). This may be slowing down startup, restores, and even inserts/updates/deletes.''
			                                    FROM #LogInfo
			                                    WHERE EXISTS (SELECT name FROM master.sys.databases
			                                    WHERE source_database_id is null) OPTION (RECOMPILE);
		                                      END
		                                      TRUNCATE TABLE #LogInfo;';
          drop table #LogInfo;
        end;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 80 )
					        begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 80) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details) SELECT DISTINCT 80, DB_NAME(), 170, ''Reliability'', ''Max File Size Set'', ''https://BrentOzar.com/go/maxsize'', (''The ['' + DB_NAME() + ''] database file '' + name + '' has a max file size set to '' + CAST(CAST(max_size AS BIGINT) * 8 / 1024 AS VARCHAR(100)) + ''MB. If it runs out of space, the database will stop working even though there may be drive space available.'') FROM sys.database_files WHERE max_size <> 268435456 AND max_size <> -1 AND type <> 2 AND name <> ''DWDiagnostics''  OPTION (RECOMPILE);';
      end;


      /* Check if columnstore indexes are in use - for Github issue #615 */
      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 74 ) /* Trace flags */
					        begin
        truncate table #TemporaryDatabaseResults;

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 74) with NOWAIT;

        exec dbo.sp_MSforeachdb 'USE [?]; IF EXISTS(SELECT * FROM sys.indexes WHERE type IN (5,6)) INSERT INTO #TemporaryDatabaseResults (DatabaseName, Finding) VALUES (DB_NAME(), ''Yup'') OPTION (RECOMPILE);';
        if exists (select *
        from #TemporaryDatabaseResults) set @ColumnStoreIndexesInUse = 1;
      end;

      /* Non-Default Database Scoped Config - Github issue #598 */
      if exists ( select *
      from sys.all_objects
      where [name] = 'database_scoped_configurations' )
					        begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d] through [%d].', 0, 1, 194, 197) with NOWAIT;

        insert into #DatabaseScopedConfigurationDefaults
          (configuration_id, [name], default_value, default_value_for_secondary, CheckID)
                                  select 1, 'MAXDOP', 0, null, 194
        union all
          select 2, 'LEGACY_CARDINALITY_ESTIMATION', 0, null, 195
        union all
          select 3, 'PARAMETER_SNIFFING', 1, null, 196
        union all
          select 4, 'QUERY_OPTIMIZER_HOTFIXES', 0, null, 197;
        exec dbo.sp_MSforeachdb 'USE [?]; INSERT INTO #BlitzResults (CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details)
									SELECT def1.CheckID, DB_NAME(), 210, ''Non-Default Database Scoped Config'', dsc.[name], ''https://BrentOzar.com/go/dbscope'', (''Set value: '' + COALESCE(CAST(dsc.value AS NVARCHAR(100)),''Empty'') + '' Default: '' + COALESCE(CAST(def1.default_value AS NVARCHAR(100)),''Empty'') + '' Set value for secondary: '' + COALESCE(CAST(dsc.value_for_secondary AS NVARCHAR(100)),''Empty'') + '' Default value for secondary: '' + COALESCE(CAST(def1.default_value_for_secondary AS NVARCHAR(100)),''Empty''))
									FROM [?].sys.database_scoped_configurations dsc
									INNER JOIN #DatabaseScopedConfigurationDefaults def1 ON dsc.configuration_id = def1.configuration_id
									LEFT OUTER JOIN #DatabaseScopedConfigurationDefaults def ON dsc.configuration_id = def.configuration_id AND (dsc.value = def.default_value OR dsc.value IS NULL) AND (dsc.value_for_secondary = def.default_value_for_secondary OR dsc.value_for_secondary IS NULL)
									LEFT OUTER JOIN #SkipChecks sk ON (sk.CheckID IS NULL OR def.CheckID = sk.CheckID) AND (sk.DatabaseName IS NULL OR sk.DatabaseName = DB_NAME())
									WHERE def.configuration_id IS NULL AND sk.CheckID IS NULL ORDER BY 1
									 OPTION (RECOMPILE);';
      end;


    end;
    /* IF @CheckUserDatabaseObjects = 1 */

    if @CheckProcedureCache = 1
					
					begin

      if @Debug in (1, 2) raiserror('Begin checking procedure cache', 0, 1) with NOWAIT;

      begin

        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 35 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 35) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details
            )
          select 35 as CheckID ,
            100 as Priority ,
            'Performance' as FindingsGroup ,
            'Single-Use Plans in Procedure Cache' as Finding ,
            'https://BrentOzar.com/go/single' as URL ,
            ( CAST(COUNT(*) as varchar(10))
												  + ' query plans are taking up memory in the procedure cache. This may be wasted memory if we cache plans for queries that never get called again. This may be a good use case for SQL Server 2008''s Optimize for Ad Hoc or for Forced Parameterization.' ) as Details
          from sys.dm_exec_cached_plans as cp
          where   cp.usecounts = 1
            and cp.objtype = 'Adhoc'
            and exists ( select
              1
            from sys.configurations
            where
																  name = 'optimize for ad hoc workloads'
              and value_in_use = 0 )
          having  COUNT(*) > 1;
        end;

        /* Set up the cache tables. Different on 2005 since it doesn't support query_hash, query_plan_hash. */
        if @@VERSION like '%Microsoft SQL Server 2005%'
							begin
          if @CheckProcedureCacheFilter = 'CPU'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			  FROM sys.dm_exec_query_stats qs
			  ORDER BY qs.total_worker_time DESC)
			  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			  FROM queries qs
			  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
			  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'Reads'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_logical_reads DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'ExecCount'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.execution_count DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'Duration'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			FROM sys.dm_exec_query_stats qs
			ORDER BY qs.total_elapsed_time DESC)
			INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
			SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time]
			FROM queries qs
			LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
			WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

        end;
        if @ProductVersionMajor >= 10
							begin
          if @CheckProcedureCacheFilter = 'CPU'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_worker_time DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'Reads'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_logical_reads DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'ExecCount'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.execution_count DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          if @CheckProcedureCacheFilter = 'Duration'
            or @CheckProcedureCacheFilter is null
									begin
            set @StringToExecute = 'WITH queries ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  AS (SELECT TOP 20 qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM sys.dm_exec_query_stats qs
		  ORDER BY qs.total_elapsed_time DESC)
		  INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		  SELECT qs.[sql_handle],qs.[statement_start_offset],qs.[statement_end_offset],qs.[plan_generation_num],qs.[plan_handle],qs.[creation_time],qs.[last_execution_time],qs.[execution_count],qs.[total_worker_time],qs.[last_worker_time],qs.[min_worker_time],qs.[max_worker_time],qs.[total_physical_reads],qs.[last_physical_reads],qs.[min_physical_reads],qs.[max_physical_reads],qs.[total_logical_writes],qs.[last_logical_writes],qs.[min_logical_writes],qs.[max_logical_writes],qs.[total_logical_reads],qs.[last_logical_reads],qs.[min_logical_reads],qs.[max_logical_reads],qs.[total_clr_time],qs.[last_clr_time],qs.[min_clr_time],qs.[max_clr_time],qs.[total_elapsed_time],qs.[last_elapsed_time],qs.[min_elapsed_time],qs.[max_elapsed_time],qs.[query_hash],qs.[query_plan_hash]
		  FROM queries qs
		  LEFT OUTER JOIN #dm_exec_query_stats qsCaught ON qs.sql_handle = qsCaught.sql_handle AND qs.plan_handle = qsCaught.plan_handle AND qs.statement_start_offset = qsCaught.statement_start_offset
		  WHERE qsCaught.sql_handle IS NULL OPTION (RECOMPILE);';
            EXECUTE(@StringToExecute);
          end;

          /* Populate the query_plan_filtered field. Only works in 2005SP2+, but we're just doing it in 2008 to be safe. */
          update  #dm_exec_query_stats
								set     query_plan_filtered = qp.query_plan
								from #dm_exec_query_stats qs
										cross APPLY sys.dm_exec_text_query_plan(qs.plan_handle,
																  qs.statement_start_offset,
																  qs.statement_end_offset)
										as qp;

        end;

        /* Populate the additional query_plan, text, and text_filtered fields */
        update  #dm_exec_query_stats
						set     query_plan = qp.query_plan ,
								[text] = st.[text] ,
								text_filtered = SUBSTRING(st.text,
														  ( qs.statement_start_offset
															/ 2 ) + 1,
														  ( ( case qs.statement_end_offset
																when -1
																then DATALENGTH(st.text)
																else qs.statement_end_offset
															  end
															  - qs.statement_start_offset )
															/ 2 ) + 1)
						from #dm_exec_query_stats qs
								cross APPLY sys.dm_exec_sql_text(qs.sql_handle) as st
								cross APPLY sys.dm_exec_query_plan(qs.plan_handle)
								as qp;

        /* Dump instances of our own script. We're not trying to tune ourselves. */
        delete  #dm_exec_query_stats
						where   text like '%sp_Blitz%'
          or text like '%#BlitzResults%';

        /* Look for implicit conversions */

        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 63 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 63) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 63 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'Implicit Conversion' as Finding ,
            'https://BrentOzar.com/go/implicit' as URL ,
            ( 'One of the top resource-intensive queries is comparing two fields that are not the same datatype.' ) as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
														 CAST(qs.query_plan as NVARCHAR(MAX))) like '%CONVERT_IMPLICIT%'
            and coalesce(qs.query_plan_filtered,
															 CAST(qs.query_plan as NVARCHAR(MAX))) like '%PhysicalOp="Index Scan"%';
        end;

        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 64 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 64) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 64 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'Implicit Conversion Affecting Cardinality' as Finding ,
            'https://BrentOzar.com/go/implicit' as URL ,
            ( 'One of the top resource-intensive queries has an implicit conversion that is affecting cardinality estimation.' ) as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
														 CAST(qs.query_plan as NVARCHAR(MAX))) like '%<PlanAffectingConvert ConvertIssue="Cardinality Estimate" Expression="CONVERT_IMPLICIT%';
        end;

        /* @cms4j, 29.11.2013: Look for RID or Key Lookups */
        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 118 )
								begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 118) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 118 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'RID or Key Lookups' as Finding ,
            'https://BrentOzar.com/go/lookup' as URL ,
            'One of the top resource-intensive queries contains RID or Key Lookups. Try to avoid them by creating covering indexes.' as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
															 CAST(qs.query_plan as NVARCHAR(MAX))) like '%Lookup="1"%';
        end;
        /* @cms4j, 29.11.2013: Look for RID or Key Lookups */

        /* Look for missing indexes */
        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 65 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 65) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 65 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'Missing Index' as Finding ,
            'https://BrentOzar.com/go/missingindex' as URL ,
            ( 'One of the top resource-intensive queries may be dramatically improved by adding an index.' ) as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
														 CAST(qs.query_plan as NVARCHAR(MAX))) like '%MissingIndexGroup%';
        end;

        /* Look for cursors */
        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 66 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 66) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 66 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'Cursor' as Finding ,
            'https://BrentOzar.com/go/cursor' as URL ,
            ( 'One of the top resource-intensive queries is using a cursor.' ) as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
														 CAST(qs.query_plan as NVARCHAR(MAX))) like '%<StmtCursor%';
        end;

        /* Look for scalar user-defined functions */

        if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 67 )
							begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 67) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details ,
            QueryPlan ,
            QueryPlanFiltered
            )
          select 67 as CheckID ,
            120 as Priority ,
            'Query Plans' as FindingsGroup ,
            'Scalar UDFs' as Finding ,
            'https://BrentOzar.com/go/functions' as URL ,
            ( 'One of the top resource-intensive queries is using a user-defined scalar function that may inhibit parallelism.' ) as Details ,
            qs.query_plan ,
            qs.query_plan_filtered
          from #dm_exec_query_stats qs
          where   coalesce(qs.query_plan_filtered,
														 CAST(qs.query_plan as NVARCHAR(MAX))) like '%<UserDefinedFunction%';
        end;

      end;
    /* IF @CheckProcedureCache = 1 */
    end;

    /*Check to see if the HA endpoint account is set at the same as the SQL Server Service Account*/
    if @ProductVersionMajor >= 10
      and not exists ( select 1
      from #SkipChecks
      where DatabaseName is null and CheckID = 187 )

		if SERVERPROPERTY('IsHadrEnabled') = 1
    		begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 187) with NOWAIT;

      insert    into [#BlitzResults]
        ( [CheckID] ,
        [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [URL] ,
        [Details] )
      select
        187 as [CheckID] ,
        230 as [Priority] ,
        'Security' as [FindingsGroup] ,
        'Endpoints Owned by Users' as [Finding] ,
        'https://BrentOzar.com/go/owners' as [URL] ,
        ( 'Endpoint ' + ep.[name] + ' is owned by ' + SUSER_NAME(ep.principal_id) + '. If the endpoint owner login is disabled or not available due to Active Directory problems, the high availability will stop working.'
                        ) as [Details]
      from sys.database_mirroring_endpoints ep
        left outer join sys.dm_server_services s on SUSER_NAME(ep.principal_id) = s.service_account
      where s.service_account is null and ep.principal_id <> 1;
    end;

    /*Check for the last good DBCC CHECKDB date */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 68 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 68) with NOWAIT;

      exec sp_MSforeachdb N'USE [?];
						INSERT #DBCCs
							(ParentObject,
							Object,
							Field,
							Value)
						EXEC (''DBCC DBInfo() With TableResults, NO_INFOMSGS'');
						UPDATE #DBCCs SET DbName = N''?'' WHERE DbName IS NULL OPTION (RECOMPILE);';

      with
        DB2
        as
        (
          select distinct
            Field ,
            Value ,
            DbName
          from #DBCCs
            inner join sys.databases d on #DBCCs.DbName = d.name
          where    Field = 'dbi_dbccLastKnownGood'
            and d.create_date < DATEADD(dd, -14, GETDATE())
        )
      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 68 as CheckID ,
        DB2.DbName as DatabaseName ,
        1 as PRIORITY ,
        'Reliability' as FindingsGroup ,
        'Last good DBCC CHECKDB over 2 weeks old' as Finding ,
        'https://BrentOzar.com/go/checkdb' as URL ,
        'Last successful CHECKDB: '
											+ case DB2.Value
												when '1900-01-01 00:00:00.000'
												then ' never.'
												else DB2.Value
											  end as Details
      from DB2
      where   DB2.DbName <> 'tempdb'
        and DB2.DbName not in ( select distinct
          DatabaseName
        from
          #SkipChecks
        where CheckID is null or CheckID = 68)
        and DB2.DbName not in ( select name
        from sys.databases
        where   is_read_only = 1)
        and convert(datetime, DB2.Value, 121) < DATEADD(DD,
																  -14,
																  current_timestamp);
    end;

    /*Verify that the servername is set */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 70 )
				begin
      if @@SERVERNAME is null
						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 70) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 70 as CheckID ,
          200 as Priority ,
          'Informational' as FindingsGroup ,
          '@@Servername Not Set' as Finding ,
          'https://BrentOzar.com/go/servername' as URL ,
          '@@Servername variable is null. You can fix it by executing: "sp_addserver ''<LocalServerName>'', local"' as Details;
      end;

      if  /* @@SERVERNAME IS set */
						(@@SERVERNAME is not null
        and
        /* not a named instance */
        CHARINDEX('\',CAST(SERVERPROPERTY('ServerName') as nvarchar(128))) = 0
        and
        /* not clustered, when computername may be different than the servername */
        SERVERPROPERTY('IsClustered') = 0
        and
        /* @@SERVERNAME is different than the computer name */
        @@SERVERNAME <> CAST(ISNULL(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),@@SERVERNAME) as nvarchar(128)) )
						 begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 70) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 70 as CheckID ,
          200 as Priority ,
          'Configuration' as FindingsGroup ,
          '@@Servername Not Correct' as Finding ,
          'https://BrentOzar.com/go/servername' as URL ,
          'The @@Servername is different than the computer name, which may trigger certificate errors.' as Details;
      end;

    end;
    /*Check to see if a failsafe operator has been configured*/
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 73 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 73) with NOWAIT;

      declare @AlertInfo table
							(
        FailSafeOperator nvarchar(255) ,
        NotificationMethod int ,
        ForwardingServer nvarchar(255) ,
        ForwardingSeverity int ,
        PagerToTemplate nvarchar(255) ,
        PagerCCTemplate nvarchar(255) ,
        PagerSubjectTemplate nvarchar(255) ,
        PagerSendSubjectOnly nvarchar(255) ,
        ForwardAlways int
							);
      insert  into @AlertInfo
      exec [master].[dbo].[sp_MSgetalertinfo] @includeaddresses = 0;
      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 73 as CheckID ,
        200 as Priority ,
        'Monitoring' as FindingsGroup ,
        'No failsafe operator configured' as Finding ,
        'https://BrentOzar.com/go/failsafe' as URL ,
        ( 'No failsafe operator is configured on this server.  This is a good idea just in-case there are issues with the [msdb] database that prevents alerting.' ) as Details
      from @AlertInfo
      where   FailSafeOperator is null;
    end;

    /*Identify globally enabled trace flags*/
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 74 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 74) with NOWAIT;

      insert  into #TraceStatus
      exec ( ' DBCC TRACESTATUS(-1) WITH NO_INFOMSGS'
									);
      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 74 as CheckID ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'TraceFlag On' as Finding ,
        case when [T].[TraceFlag] = '834' and @ColumnStoreIndexesInUse = 1 then 'https://support.microsoft.com/en-us/kb/3210239'
											 else'https://www.BrentOzar.com/go/traceflags/' end as URL ,
        'Trace flag ' +
										case when [T].[TraceFlag] = '2330' then ' 2330 enabled globally. Using this trace Flag disables missing index requests!'
											 when [T].[TraceFlag] = '1211' then ' 1211 enabled globally. Using this Trace Flag disables lock escalation when you least expect it. No Bueno!'
											 when [T].[TraceFlag] = '1224' then ' 1224 enabled globally. Using this Trace Flag disables lock escalation based on the number of locks being taken. You shouldn''t have done that, Dave.'
											 when [T].[TraceFlag] = '652'  then ' 652 enabled globally. Using this Trace Flag disables pre-fetching during index scans. If you hate slow queries, you should turn that off.'
											 when [T].[TraceFlag] = '661'  then ' 661 enabled globally. Using this Trace Flag disables ghost record removal. Who you gonna call? No one, turn that thing off.'
											 when [T].[TraceFlag] = '1806'  then ' 1806 enabled globally. Using this Trace Flag disables Instant File Initialization. I question your sanity.'
											 when [T].[TraceFlag] = '3505'  then ' 3505 enabled globally. Using this Trace Flag disables Checkpoints. Probably not the wisest idea.'
											 when [T].[TraceFlag] = '8649'  then ' 8649 enabled globally. Using this Trace Flag drops cost threshold for parallelism down to 0. I hope this is a dev server.'
										     when [T].[TraceFlag] = '834' and @ColumnStoreIndexesInUse = 1 then ' 834 is enabled globally. Using this Trace Flag with Columnstore Indexes is not a great idea.'
											 when [T].[TraceFlag] = '8017' and (CAST(SERVERPROPERTY('Edition') as nvarchar(1000)) like N'%Express%') then ' 8017 is enabled globally, which is the default for express edition.'
                                             when [T].[TraceFlag] = '8017' and (CAST(SERVERPROPERTY('Edition') as nvarchar(1000)) not like N'%Express%') then ' 8017 is enabled globally. Using this Trace Flag disables creation schedulers for all logical processors. Not good.'
											 else [T].[TraceFlag] + ' is enabled globally.' end
										as Details
      from #TraceStatus T;
    end;

    /* High CMEMTHREAD waits that could need trace flag 8048.
               This check has to be run AFTER the globally enabled trace flag check,
               since it uses the #TraceStatus table to know if flags are enabled.
            */
    if @ProductVersionMajor >= 11 and not exists ( select 1
      from #SkipChecks
      where  DatabaseName is null and CheckID = 162 )
				begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 162) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 162 as CheckID ,
        50 as Priority ,
        'Performance' as FindingGroup ,
        'Poison Wait Detected: CMEMTHREAD & NUMA'  as Finding ,
        'https://BrentOzar.com/go/poison' as URL ,
        convert(varchar(10), (MAX([wait_time_ms]) / 1000) / 86400) + ':' + convert(varchar(20), DATEADD(s, (MAX([wait_time_ms]) / 1000), 0), 108) + ' of this wait have been recorded'
                                    + case when ts.status = 1 then ' despite enabling trace flag 8048 already.'
                                        else '. In servers with over 8 cores per NUMA node, when CMEMTHREAD waits are a bottleneck, trace flag 8048 may be needed.'
                                    end
      from sys.dm_os_nodes n
        inner join sys.[dm_os_wait_stats] w on w.wait_type = 'CMEMTHREAD'
        left outer join #TraceStatus ts on ts.TraceFlag = 8048 and ts.status = 1
      where n.node_id = 0 and n.online_scheduler_count >= 8
        and exists (select *
        from sys.dm_os_nodes
        where node_id > 0 and node_state_desc not like '%DAC')
      group by w.wait_type, ts.status
      having SUM([wait_time_ms]) > (select 5000 * datediff(HH,create_date,current_timestamp) as hours_since_startup
        from sys.databases
        where name='tempdb')
        and SUM([wait_time_ms]) > 60000;
    end;


    /*Check for transaction log file larger than data file */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 75 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 75) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 75 as CheckID ,
        DB_NAME(a.database_id) ,
        50 as Priority ,
        'Reliability' as FindingsGroup ,
        'Transaction Log Larger than Data File' as Finding ,
        'https://BrentOzar.com/go/biglog' as URL ,
        'The database [' + DB_NAME(a.database_id)
										+ '] has a ' + CAST((CAST(a.size as bigint) * 8 / 1000000) as nvarchar(20)) + ' GB transaction log file, larger than the total data file sizes. This may indicate that transaction log backups are not being performed or not performed often enough.' as Details
      from sys.master_files a
      where   a.type = 1
        and DB_NAME(a.database_id) not in (
										select distinct
          DatabaseName
        from #SkipChecks
        where CheckID = 75 or CheckID is null)
        and a.size > 125000 /* Size is measured in pages here, so this gets us log files over 1GB. */
        and a.size > ( select SUM(CAST(b.size as bigint))
        from sys.master_files b
        where    a.database_id = b.database_id
          and b.type = 0
													 )
        and a.database_id in (
										select database_id
        from sys.databases
        where   source_database_id is null );
    end;

    /*Check for collation conflicts between user databases and tempdb */
    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 76 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 76) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 76 as CheckID ,
        name as DatabaseName ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Collation is ' + collation_name as Finding ,
        'https://BrentOzar.com/go/collate' as URL ,
        'Collation differences between user databases and tempdb can cause conflicts especially when comparing string values' as Details
      from sys.databases
      where   name not in ( 'master', 'model', 'msdb')
        and name not like 'ReportServer%'
        and name not in ( select distinct
          DatabaseName
        from #SkipChecks
        where CheckID is null or CheckID = 76)
        and collation_name <> ( select
          collation_name
        from
          sys.databases
        where
																  name = 'tempdb'
															  );
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 77 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 77) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        DatabaseName ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 77 as CheckID ,
        dSnap.[name] as DatabaseName ,
        50 as Priority ,
        'Reliability' as FindingsGroup ,
        'Database Snapshot Online' as Finding ,
        'https://BrentOzar.com/go/snapshot' as URL ,
        'Database [' + dSnap.[name]
										+ '] is a snapshot of ['
										+ dOriginal.[name]
										+ ']. Make sure you have enough drive space to maintain the snapshot as the original database grows.' as Details
      from sys.databases dSnap
        inner join sys.databases dOriginal on dSnap.source_database_id = dOriginal.database_id
          and dSnap.name not in (
																  select distinct DatabaseName
          from #SkipChecks
          where CheckID = 77 or CheckID is null);
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 79 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 79) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 79 as CheckID ,
        -- sp_Blitz Issue #776
        -- Job has history and was executed in the last 30 days OR Job is enabled AND Job Schedule is enabled
        case when (cast(datediff(dd, substring(cast(sjh.run_date as nvarchar(10)), 1, 4) + '-' + substring(cast(sjh.run_date as nvarchar(10)), 5, 2) + '-' + substring(cast(sjh.run_date as nvarchar(10)), 7, 2), GETDATE()) as int) < 30) or (j.[enabled] = 1 and ssc.[enabled] = 1 )then
                						    100
                						else -- no job history (implicit) AND job not run in the past 30 days AND (Job disabled OR Job Schedule disabled)
            						        200
                						end as Priority,
        'Performance' as FindingsGroup ,
        'Shrink Database Job' as Finding ,
        'https://BrentOzar.com/go/autoshrink' as URL ,
        'In the [' + j.[name] + '] job, step ['
										+ step.[step_name]
										+ '] has SHRINKDATABASE or SHRINKFILE, which may be causing database fragmentation.'
										+ case when coalesce(ssc.name,'0') != '0' then + ' (Schedule: [' + ssc.name + '])' else + '' end as Details
      from msdb.dbo.sysjobs j
        inner join msdb.dbo.sysjobsteps step on j.job_id = step.job_id
        left outer join msdb.dbo.sysjobschedules as sjsc
        on j.job_id = sjsc.job_id
        left outer join msdb.dbo.sysschedules as ssc
        on sjsc.schedule_id = ssc.schedule_id
          and sjsc.job_id = j.job_id
        left outer join msdb.dbo.sysjobhistory as sjh
        on j.job_id = sjh.job_id
          and step.step_id = sjh.step_id
          and sjh.run_date in (select max(sjh2.run_date)
          from msdb.dbo.sysjobhistory as sjh2
          where sjh2.job_id = j.job_id) -- get the latest entry date
          and sjh.run_time in (select max(sjh3.run_time)
          from msdb.dbo.sysjobhistory as sjh3
          where sjh3.job_id = j.job_id and sjh3.run_date = sjh.run_date)
      -- get the latest entry time
      where   step.command like N'%SHRINKDATABASE%'
        or step.command like N'%SHRINKFILE%';
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 81 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 81) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select 81 as CheckID ,
        200 as Priority ,
        'Non-Active Server Config' as FindingsGroup ,
        cr.name as Finding ,
        'https://www.BrentOzar.com/blitz/sp_configure/' as URL ,
        ( 'This sp_configure option isn''t running under its set value.  Its set value is '
										  + CAST(cr.[value] as varchar(100))
										  + ' and its running value is '
										  + CAST(cr.value_in_use as varchar(100))
										  + '. When someone does a RECONFIGURE or restarts the instance, this setting will start taking effect.' ) as Details
      from sys.configurations cr
      where   cr.value <> cr.value_in_use
        and not (cr.name = 'min server memory (MB)' and cr.value in (0,16) and cr.value_in_use in (0,16));
    end;

    if not exists ( select 1
    from #SkipChecks
    where   DatabaseName is null and CheckID = 123 )
					begin

      if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 123) with NOWAIT;

      insert  into #BlitzResults
        ( CheckID ,
        Priority ,
        FindingsGroup ,
        Finding ,
        URL ,
        Details
        )
      select top 1
        123 as CheckID ,
        200 as Priority ,
        'Informational' as FindingsGroup ,
        'Agent Jobs Starting Simultaneously' as Finding ,
        'https://BrentOzar.com/go/busyagent/' as URL ,
        ( 'Multiple SQL Server Agent jobs are configured to start simultaneously. For detailed schedule listings, see the query in the URL.' ) as Details
      from msdb.dbo.sysjobactivity
      where start_execution_date > DATEADD(dd, -14, GETDATE())
      group by start_execution_date
      having COUNT(*) > 1;
    end;

    if @CheckServerInfo = 1
					begin

      /*This checks Windows version. It would be better if Microsoft gave everything a separate build number, but whatever.*/
      if @ProductVersionMajor >= 10
        and not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 172 )
					begin
        -- sys.dm_os_host_info includes both Windows and Linux info
        if exists (select 1
        from sys.all_objects
        where	name = 'dm_os_host_info' )
					begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 172) with NOWAIT;

          insert    into [#BlitzResults]
            ( [CheckID] ,
            [Priority] ,
            [FindingsGroup] ,
            [Finding] ,
            [URL] ,
            [Details] )

          select
            172 as [CheckID] ,
            250 as [Priority] ,
            'Server Info' as [FindingsGroup] ,
            'Operating System Version' as [Finding] ,
            ( case when @IsWindowsOperatingSystem = 1
								then 'https://en.wikipedia.org/wiki/List_of_Microsoft_Windows_versions'
								else 'https://en.wikipedia.org/wiki/List_of_Linux_distributions'
								end
							) as [URL] ,
            ( case
								when [ohi].[host_platform] = 'Linux' then 'You''re running the ' + CAST([ohi].[host_distribution] as varchar(35)) + ' distribution of ' + CAST([ohi].[host_platform] as varchar(35)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] = '5' then 'You''re running a really old version: Windows 2000, version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] > '5' and [ohi].[host_release] < '6' then 'You''re running a really old version: ' + CAST([ohi].[host_distribution] as varchar(50)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] >= '6' and [ohi].[host_release] <= '6.1' then 'You''re running a pretty old version: Windows: ' + CAST([ohi].[host_distribution] as varchar(50)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] = '6.2' then 'You''re running a rather modern version of Windows: ' + CAST([ohi].[host_distribution] as varchar(50)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] = '6.3' then 'You''re running a pretty modern version of Windows: ' + CAST([ohi].[host_distribution] as varchar(50)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								when [ohi].[host_platform] = 'Windows' and [ohi].[host_release] > '6.3' then 'Hot dog! You''re living in the future! You''re running ' + CAST([ohi].[host_distribution] as varchar(50)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								else 'You''re running ' + CAST([ohi].[host_distribution] as varchar(35)) + ', version ' + CAST([ohi].[host_release] as varchar(5))
								end
							   ) as [Details]
          from [sys].[dm_os_host_info] [ohi];
        end;
					else
					begin
          -- Otherwise, stick with Windows-only detection

          if exists ( select 1
          from sys.all_objects
          where   name = 'dm_os_windows_info' )

							begin

            if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 172) with NOWAIT;

            insert    into [#BlitzResults]
              ( [CheckID] ,
              [Priority] ,
              [FindingsGroup] ,
              [Finding] ,
              [URL] ,
              [Details] )

            select
              172 as [CheckID] ,
              250 as [Priority] ,
              'Server Info' as [FindingsGroup] ,
              'Windows Version' as [Finding] ,
              'https://en.wikipedia.org/wiki/List_of_Microsoft_Windows_versions' as [URL] ,
              ( case
										when [owi].[windows_release] = '5' then 'You''re running a really old version: Windows 2000, version ' + CAST([owi].[windows_release] as varchar(5))
										when [owi].[windows_release] > '5' and [owi].[windows_release] < '6' then 'You''re running a really old version: Windows Server 2003/2003R2 era, version ' + CAST([owi].[windows_release] as varchar(5))
										when [owi].[windows_release] >= '6' and [owi].[windows_release] <= '6.1' then 'You''re running a pretty old version: Windows: Server 2008/2008R2 era, version ' + CAST([owi].[windows_release] as varchar(5))
										when [owi].[windows_release] = '6.2' then 'You''re running a rather modern version of Windows: Server 2012 era, version ' + CAST([owi].[windows_release] as varchar(5))
										when [owi].[windows_release] = '6.3' then 'You''re running a pretty modern version of Windows: Server 2012R2 era, version ' + CAST([owi].[windows_release] as varchar(5))
										when [owi].[windows_release] = '10.0' then 'You''re running a pretty modern version of Windows: Server 2016 era, version ' + CAST([owi].[windows_release] as varchar(5))
										else 'Hot dog! You''re living in the future! You''re running version ' + CAST([owi].[windows_release] as varchar(5))
										end
									   ) as [Details]
            from [sys].[dm_os_windows_info] [owi];

          end;
        end;
      end;

      /*
This check hits the dm_os_process_memory system view
to see if locked_page_allocations_kb is > 0,
which could indicate that locked pages in memory is enabled.
*/
      if @ProductVersionMajor >= 10 and not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 166 )
					begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 166) with NOWAIT;

        insert    into [#BlitzResults]
          ( [CheckID] ,
          [Priority] ,
          [FindingsGroup] ,
          [Finding] ,
          [URL] ,
          [Details] )
        select
          166 as [CheckID] ,
          250 as [Priority] ,
          'Server Info' as [FindingsGroup] ,
          'Locked Pages In Memory Enabled' as [Finding] ,
          'https://BrentOzar.com/go/lpim' as [URL] ,
          ( 'You currently have '
							  + case when [dopm].[locked_page_allocations_kb] / 1024. / 1024. > 0
									 then CAST([dopm].[locked_page_allocations_kb] / 1024 / 1024 as varchar(100))
										  + ' GB'
									 else CAST([dopm].[locked_page_allocations_kb] / 1024 as varchar(100))
										  + ' MB'
								end + ' of pages locked in memory.' ) as [Details]
        from
          [sys].[dm_os_process_memory] as [dopm]
        where
							[dopm].[locked_page_allocations_kb] > 0;
      end;

      /* Server Info - Locked Pages In Memory Enabled - Check 166 - SQL Server 2016 SP1 and newer */
      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 166 )
        and exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where   o.name = 'dm_os_sys_info'
          and c.name = 'sql_memory_model' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 166) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  166 AS CheckID ,
			250 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Memory Model Unconventional'' AS Finding ,
			''https://BrentOzar.com/go/lpim'' AS URL ,
			''Memory Model: '' + CAST(sql_memory_model_desc AS NVARCHAR(100))
			FROM sys.dm_os_sys_info WHERE sql_memory_model <> 1 OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;

      /*
			Starting with SQL Server 2014 SP2, Instant File Initialization
			is logged in the SQL Server Error Log.
			*/
      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 184 )
        and (@ProductVersionMajor >= 13) or (@ProductVersionMajor = 12 and @ProductVersionMinor >= 5000)
						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 184) with NOWAIT;

        insert into #ErrorLog
        exec sys.xp_readerrorlog 0, 1, N'Database Instant File Initialization: enabled';

        if @@ROWCOUNT > 0
								insert  into #BlitzResults
          ( CheckID ,
          [Priority] ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select
          193 as [CheckID] ,
          250 as [Priority] ,
          'Server Info' as [FindingsGroup] ,
          'Instant File Initialization Enabled' as [Finding] ,
          'https://BrentOzar.com/go/instant' as [URL] ,
          'The service account has the Perform Volume Maintenance Tasks permission.';
      end;

      /* Server Info - Instant File Initialization Not Enabled - Check 192 - SQL Server 2016 SP1 and newer */
      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 192 )
        and exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where   o.name = 'dm_server_services'
          and c.name = 'instant_file_initialization_enabled' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 192) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  192 AS CheckID ,
			50 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Instant File Initialization Not Enabled'' AS Finding ,
			''https://BrentOzar.com/go/instant'' AS URL ,
			''Consider enabling IFI for faster restores and data file growths.''
			FROM sys.dm_server_services WHERE instant_file_initialization_enabled <> ''Y'' AND filename LIKE ''%sqlservr.exe%'' OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 130 )
						begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 130) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 130 as CheckID ,
          250 as Priority ,
          'Server Info' as FindingsGroup ,
          'Server Name' as Finding ,
          'https://BrentOzar.com/go/servername' as URL ,
          @@SERVERNAME as Details
        where @@SERVERNAME is not null;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 83 )
							begin
        if exists ( select *
        from sys.all_objects
        where   name = 'dm_server_services' )
									begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 83) with NOWAIT;

          -- DATETIMEOFFSET and DATETIME have different minimum values, so there's
          -- a small workaround here to force 1753-01-01 if the minimum is detected
          set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
				SELECT  83 AS CheckID ,
				250 AS Priority ,
				''Server Info'' AS FindingsGroup ,
				''Services'' AS Finding ,
				'''' AS URL ,
				N''Service: '' + servicename + N'' runs under service account '' + service_account + N''. Last startup time: '' + COALESCE(CAST(CASE WHEN YEAR(last_startup_time) <= 1753 THEN CAST(''17530101'' as datetime) ELSE CAST(last_startup_time AS DATETIME) END AS VARCHAR(50)), ''not shown.'') + ''. Startup type: '' + startup_type_desc + N'', currently '' + status_desc + ''.''
				FROM sys.dm_server_services OPTION (RECOMPILE);';

          if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
          if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

          EXECUTE(@StringToExecute);
        end;
      end;

      /* Check 84 - SQL Server 2012 */
      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 84 )
							begin
        if exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where   o.name = 'dm_os_sys_info'
          and c.name = 'physical_memory_kb' )
									begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 84) with NOWAIT;

          set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  84 AS CheckID ,
			250 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Hardware'' AS Finding ,
			'''' AS URL ,
			''Logical processors: '' + CAST(cpu_count AS VARCHAR(50)) + ''. Physical memory: '' + CAST( CAST(ROUND((physical_memory_kb / 1024.0 / 1024), 1) AS INT) AS VARCHAR(50)) + ''GB.''
			FROM sys.dm_os_sys_info OPTION (RECOMPILE);';

          if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
          if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

          EXECUTE(@StringToExecute);
        end;

        /* Check 84 - SQL Server 2008 */
        if exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where   o.name = 'dm_os_sys_info'
          and c.name = 'physical_memory_in_bytes' )
									begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 84) with NOWAIT;

          set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
			SELECT  84 AS CheckID ,
			250 AS Priority ,
			''Server Info'' AS FindingsGroup ,
			''Hardware'' AS Finding ,
			'''' AS URL ,
			''Logical processors: '' + CAST(cpu_count AS VARCHAR(50)) + ''. Physical memory: '' + CAST( CAST(ROUND((physical_memory_in_bytes / 1024.0 / 1024 / 1024), 1) AS INT) AS VARCHAR(50)) + ''GB.''
			FROM sys.dm_os_sys_info OPTION (RECOMPILE);';

          if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
          if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

          EXECUTE(@StringToExecute);
        end;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 85 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 85) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 85 as CheckID ,
          250 as Priority ,
          'Server Info' as FindingsGroup ,
          'SQL Server Service' as Finding ,
          '' as URL ,
          N'Version: '
												+ CAST(SERVERPROPERTY('productversion') as nvarchar(100))
												+ N'. Patch Level: '
												+ CAST(SERVERPROPERTY('productlevel') as nvarchar(100))
								  				+ case when SERVERPROPERTY('ProductUpdateLevel') is null
												       then N''
												       else N'. Cumulative Update: '
													   + CAST(SERVERPROPERTY('ProductUpdateLevel') as nvarchar(100))
												end
												+ N'. Edition: '
												+ CAST(SERVERPROPERTY('edition') as varchar(100))
												+ N'. Availability Groups Enabled: '
												+ CAST(coalesce(SERVERPROPERTY('IsHadrEnabled'),
																0) as varchar(100))
												+ N'. Availability Groups Manager Status: '
												+ CAST(coalesce(SERVERPROPERTY('HadrManagerStatus'),
																0) as varchar(100));
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 88 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 88) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 88 as CheckID ,
          250 as Priority ,
          'Server Info' as FindingsGroup ,
          'SQL Server Last Restart' as Finding ,
          '' as URL ,
          CAST(create_date as varchar(100))
        from sys.databases
        where   database_id = 2;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 91 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 91) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 91 as CheckID ,
          250 as Priority ,
          'Server Info' as FindingsGroup ,
          'Server Last Restart' as Finding ,
          '' as URL ,
          CAST(DATEADD(SECOND, (ms_ticks/1000)*(-1), GETDATE()) as nvarchar(25))
        from sys.dm_os_sys_info;
      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 92 )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 92) with NOWAIT;

        insert  into #driveInfo
          ( drive, SIZE )
        exec master..xp_fixeddrives;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 92 as CheckID ,
          250 as Priority ,
          'Server Info' as FindingsGroup ,
          'Drive ' + i.drive + ' Space' as Finding ,
          '' as URL ,
          CAST(i.SIZE as varchar(30))
												+ 'MB free on ' + i.drive
												+ ' drive' as Details
        from #driveInfo as i;
        drop table #driveInfo;
      end;

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 103 )
        and exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where  o.name = 'dm_os_sys_info'
          and c.name = 'virtual_machine_type_desc' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 103) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
									SELECT 103 AS CheckID,
									250 AS Priority,
									''Server Info'' AS FindingsGroup,
									''Virtual Server'' AS Finding,
									''https://BrentOzar.com/go/virtual'' AS URL,
									''Type: ('' + virtual_machine_type_desc + '')'' AS Details
									FROM sys.dm_os_sys_info
									WHERE virtual_machine_type <> 0 OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 214 )
        and exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where  o.name = 'dm_os_sys_info'
          and c.name = 'container_type_desc' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 214) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
									SELECT 214 AS CheckID,
									250 AS Priority,
									''Server Info'' AS FindingsGroup,
									''Container'' AS Finding,
									''https://BrentOzar.com/go/virtual'' AS URL,
									''Type: ('' + container_type_desc + '')'' AS Details
									FROM sys.dm_os_sys_info
									WHERE container_type_desc <> ''NONE'' OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 114 )
        and exists ( select *
        from sys.all_objects o
        where  o.name = 'dm_os_memory_nodes' )
        and exists ( select *
        from sys.all_objects o
          inner join sys.all_columns c on o.object_id = c.object_id
        where  o.name = 'dm_os_nodes'
          and c.name = 'processor_group' )
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 114) with NOWAIT;

        set @StringToExecute = 'INSERT INTO #BlitzResults (CheckID, Priority, FindingsGroup, Finding, URL, Details)
										SELECT  114 AS CheckID ,
												250 AS Priority ,
												''Server Info'' AS FindingsGroup ,
												''Hardware - NUMA Config'' AS Finding ,
												'''' AS URL ,
												''Node: '' + CAST(n.node_id AS NVARCHAR(10)) + '' State: '' + node_state_desc
												+ '' Online schedulers: '' + CAST(n.online_scheduler_count AS NVARCHAR(10)) + '' Offline schedulers: '' + CAST(oac.offline_schedulers AS VARCHAR(100)) + '' Processor Group: '' + CAST(n.processor_group AS NVARCHAR(10))
												+ '' Memory node: '' + CAST(n.memory_node_id AS NVARCHAR(10)) + '' Memory VAS Reserved GB: '' + CAST(CAST((m.virtual_address_space_reserved_kb / 1024.0 / 1024) AS INT) AS NVARCHAR(100))
										FROM sys.dm_os_nodes n
										INNER JOIN sys.dm_os_memory_nodes m ON n.memory_node_id = m.memory_node_id
										OUTER APPLY (SELECT
										COUNT(*) AS [offline_schedulers]
										FROM sys.dm_os_schedulers dos
										WHERE n.node_id = dos.parent_node_id
										AND dos.status = ''VISIBLE OFFLINE''
										) oac
										WHERE n.node_state_desc NOT LIKE ''%DAC%''
										ORDER BY n.node_id OPTION (RECOMPILE);';

        if @Debug = 2 and @StringToExecute is not null print @StringToExecute;
        if @Debug = 2 and @StringToExecute is null print '@StringToExecute has gone NULL, for some reason.';

        EXECUTE(@StringToExecute);
      end;


      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 211 )
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 211) with NOWAIT;

        declare @outval varchar(36);
        /* Get power plan if set by group policy [Git Hub Issue #1620] */
        exec master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
														   @key = 'SOFTWARE\Policies\Microsoft\Power\PowerSettings',
														   @value_name = 'ActivePowerScheme',
														   @value = @outval OUTPUT;

        if @outval is null /* If power plan was not set by group policy, get local value [Git Hub Issue #1620]*/
								exec master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
								                           @key = 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes',
								                           @value_name = 'ActivePowerScheme',
								                           @value = @outval OUTPUT;

        declare @cpu_speed_mhz int,
								        @cpu_speed_ghz decimal(18,2);

        exec master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
								                           @key = 'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
								                           @value_name = '~MHz',
								                           @value = @cpu_speed_mhz OUTPUT;

        select @cpu_speed_ghz = CAST(CAST(@cpu_speed_mhz as decimal) / 1000 as decimal(18,2));

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select 211 as CheckId,
          250 as Priority,
          'Server Info' as FindingsGroup,
          'Power Plan' as Finding,
          'https://www.brentozar.com/blitz/power-mode/' as URL,
          'Your server has '
									+ CAST(@cpu_speed_ghz as varchar(4))
									+ 'GHz CPUs, and is in '
									+ case @outval
							             when 'a1841308-3541-4fab-bc81-f71556f20b4a'
							             then 'power saving mode -- are you sure this is a production SQL Server?'
							             when '381b4222-f694-41f0-9685-ff5bb260df2e'
							             then 'balanced power mode -- Uh... you want your CPUs to run at full speed, right?'
							             when '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
							             then 'high performance power mode'
										 else 'an unknown power mode.'
							        end as Details

      end;

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 212 )
								begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 212) with NOWAIT;

        insert into #Instances
          (Instance_Number, Instance_Name, Data_Field)
        exec master.sys.xp_regread @rootkey = 'HKEY_LOCAL_MACHINE',
								                           @key = 'SOFTWARE\Microsoft\Microsoft SQL Server',
								                           @value_name = 'InstalledInstances'

        if (select COUNT(*)
        from #Instances) > 1
                                begin

          declare @InstanceCount nvarchar(MAX)
          select @InstanceCount = COUNT(*)
          from #Instances

          insert into #BlitzResults
            (
            CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details
            )
          select
            212 as CheckId ,
            250 as Priority ,
            'Server Info' as FindingsGroup ,
            'Instance Stacking' as Finding ,
            'https://www.brentozar.com/go/babygotstacked/' as URL ,
            'Your Server has ' + @InstanceCount + ' Instances of SQL Server running. More than one is usually a bad idea. Read the URL for more info'
        end;
      end;

      if not exists ( select 1
        from #SkipChecks
        where   DatabaseName is null and CheckID = 106 )
        and (select convert(int,value_in_use)
        from sys.configurations
        where name = 'default trace enabled' ) = 1
        and DATALENGTH( coalesce( @base_tracefilename, '' ) ) > DATALENGTH('.TRC')
							begin

        if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 106) with NOWAIT;

        insert  into #BlitzResults
          ( CheckID ,
          Priority ,
          FindingsGroup ,
          Finding ,
          URL ,
          Details
          )
        select
          106 as CheckID
												, 250 as Priority
												, 'Server Info' as FindingsGroup
												, 'Default Trace Contents' as Finding
												, 'https://BrentOzar.com/go/trace' as URL
												, 'The default trace holds '+cast(DATEDIFF(hour,MIN(StartTime),GETDATE())as varchar(30))+' hours of data'
												+' between '+cast(Min(StartTime) as varchar(30))+' and '+cast(GETDATE()as varchar(30))
												+('. The default trace files are located in: '+left( @curr_tracefilename,len(@curr_tracefilename) - @indx)
												) as Details
        from ::fn_trace_gettable( @base_tracefilename, default )
        where EventClass between 65500 and 65600;
      end;
      /* CheckID 106 */

      if not exists ( select 1
      from #SkipChecks
      where   DatabaseName is null and CheckID = 152 )
							begin
        if exists (select *
        from sys.dm_os_wait_stats ws
          left outer join #IgnorableWaits i on ws.wait_type = i.wait_type
        where wait_time_ms > .1 * @CpuMsSinceWaitsCleared and waiting_tasks_count > 0
          and i.wait_type is null)
									begin
          /* Check for waits that have had more than 10% of the server's wait time */

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 152) with NOWAIT;

          with
            os(wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms)
            as
            (
              select ws.wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms
              from sys.dm_os_wait_stats ws
                left outer join #IgnorableWaits i on ws.wait_type = i.wait_type
              where i.wait_type is null
                and wait_time_ms > .1 * @CpuMsSinceWaitsCleared
                and waiting_tasks_count > 0
            )
          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details
            )
          select top 9
            152 as CheckID
													, 240 as Priority
													, 'Wait Stats' as FindingsGroup
													, CAST(ROW_NUMBER() over(order by os.wait_time_ms desc) as nvarchar(10)) + N' - ' + os.wait_type as Finding
													, 'https://www.sqlskills.com/help/waits/' + LOWER(os.wait_type) + '/' as URL
													, Details = CAST(CAST(SUM(os.wait_time_ms / 1000.0 / 60 / 60) over (PARTITION by os.wait_type) as numeric(18,1)) as nvarchar(20)) + N' hours of waits, ' +
													CAST(CAST((SUM(60.0 * os.wait_time_ms) over (PARTITION by os.wait_type) ) / @MsSinceWaitsCleared  as numeric(18,1)) as nvarchar(20)) + N' minutes average wait time per hour, ' +
													/* CAST(CAST(
														100.* SUM(os.wait_time_ms) OVER (PARTITION BY os.wait_type)
														/ (1. * SUM(os.wait_time_ms) OVER () )
														AS NUMERIC(18,1)) AS NVARCHAR(40)) + N'% of waits, ' + */
													CAST(CAST(
														100. * SUM(os.signal_wait_time_ms) over (PARTITION by os.wait_type)
														/ (1. * SUM(os.wait_time_ms) over ())
														as numeric(18,1)) as nvarchar(40)) + N'% signal wait, ' +
													CAST(SUM(os.waiting_tasks_count) over (PARTITION by os.wait_type) as nvarchar(40)) + N' waiting tasks, ' +
													CAST(case when  SUM(os.waiting_tasks_count) over (PARTITION by os.wait_type) > 0
													then
														CAST(
															SUM(os.wait_time_ms) over (PARTITION by os.wait_type)
																/ (1. * SUM(os.waiting_tasks_count) over (PARTITION by os.wait_type))
															as numeric(18,1))
													else 0 end as nvarchar(40)) + N' ms average wait time.'
          from os
          order by SUM(os.wait_time_ms / 1000.0 / 60 / 60) over (PARTITION by os.wait_type) desc;
        end;
        /* IF EXISTS (SELECT * FROM sys.dm_os_wait_stats WHERE wait_time_ms > 0 AND waiting_tasks_count > 0) */

        /* If no waits were found, add a note about that */
        if not exists (select *
        from #BlitzResults
        where CheckID in (107, 108, 109, 121, 152, 162))
								begin

          if @Debug in (1, 2) raiserror('Running CheckId [%d].', 0, 1, 153) with NOWAIT;

          insert  into #BlitzResults
            ( CheckID ,
            Priority ,
            FindingsGroup ,
            Finding ,
            URL ,
            Details
            )
          values
            (153, 240, 'Wait Stats', 'No Significant Waits Detected', 'https://BrentOzar.com/go/waits', 'This server might be just sitting around idle, or someone may have cleared wait stats recently.');
        end;
      end;
    /* CheckID 152 */

    end;
  /* IF @CheckServerInfo = 1 */
  end;
  /* IF ( ( SERVERPROPERTY('ServerName') NOT IN ( SELECT ServerName */

  /* Delete priorites they wanted to skip. */
  if @IgnorePrioritiesAbove is not null
					delete  #BlitzResults
					where   [Priority] > @IgnorePrioritiesAbove and CheckID <> -1;

  if @IgnorePrioritiesBelow is not null
					delete  #BlitzResults
					where   [Priority] < @IgnorePrioritiesBelow and CheckID <> -1;

  /* Delete checks they wanted to skip. */
  if @SkipChecksTable is not null
					begin
    delete  from #BlitzResults
						where   DatabaseName in ( select DatabaseName
    from #SkipChecks
    where CheckID is null
      and (ServerName is null or ServerName = SERVERPROPERTY('ServerName')));
    delete  from #BlitzResults
						where   CheckID in ( select CheckID
    from #SkipChecks
    where DatabaseName is null
      and (ServerName is null or ServerName = SERVERPROPERTY('ServerName')));
    delete r from #BlitzResults r
      inner join #SkipChecks c on r.DatabaseName = c.DatabaseName and r.CheckID = c.CheckID
        and (ServerName is null or ServerName = SERVERPROPERTY('ServerName'));
  end;

  /* Add summary mode */
  if @SummaryMode > 0
					begin
    update #BlitzResults
					  set Finding = br.Finding + ' (' + CAST(brTotals.recs as nvarchar(20)) + ')'
					  from #BlitzResults br
      inner join (select FindingsGroup, Finding, Priority, COUNT(*) as recs
      from #BlitzResults
      group by FindingsGroup, Finding, Priority) brTotals on br.FindingsGroup = brTotals.FindingsGroup and br.Finding = brTotals.Finding and br.Priority = brTotals.Priority
						where brTotals.recs > 1;

    delete br
					  from #BlitzResults br
					  where exists (select *
    from #BlitzResults brLower
    where br.FindingsGroup = brLower.FindingsGroup and br.Finding = brLower.Finding and br.Priority = brLower.Priority and br.ID > brLower.ID);

  end;

  /* Add credits for the nice folks who put so much time into building and maintaining this for free: */

  insert  into #BlitzResults
    ( CheckID ,
    Priority ,
    FindingsGroup ,
    Finding ,
    URL ,
    Details
    )
  values
    ( -1 ,
      255 ,
      'Thanks!' ,
      'From Your Community Volunteers' ,
      'http://FirstResponderKit.org' ,
      'We hope you found this tool useful.'
						);

  insert  into #BlitzResults
    ( CheckID ,
    Priority ,
    FindingsGroup ,
    Finding ,
    URL ,
    Details

    )
  values
    ( -1 ,
      0 ,
      'sp_Blitz ' + CAST(convert(datetime, @VersionDate, 102) as varchar(100)),
      'SQL Server First Responder Kit' ,
      'http://FirstResponderKit.org/' ,
      'To get help or add your own contributions, join us at http://FirstResponderKit.org.'

						);

  insert  into #BlitzResults
    ( CheckID ,
    Priority ,
    FindingsGroup ,
    Finding ,
    URL ,
    Details

    )
  select 156 ,
    254 ,
    'Rundate' ,
    GETDATE() ,
    'http://FirstResponderKit.org/' ,
    'Captain''s log: stardate something and something...';

  if @EmailRecipients is not null
					begin

    if @Debug in (1, 2) raiserror('Sending an email.', 0, 1) with NOWAIT;

    /* Database mail won't work off a local temp table. I'm not happy about this hacky workaround either. */
    if (OBJECT_ID('tempdb..##BlitzResults', 'U') is not null) drop table ##BlitzResults;
    select *
    into ##BlitzResults
    from #BlitzResults;
    set @query_result_separator = char(9);
    set @StringToExecute = 'SET NOCOUNT ON;SELECT [Priority] , [FindingsGroup] , [Finding] , [DatabaseName] , [URL] ,  [Details] , CheckID FROM ##BlitzResults ORDER BY Priority , FindingsGroup, Finding, Details; SET NOCOUNT OFF;';
    set @EmailSubject = 'sp_Blitz Results for ' + @@SERVERNAME;
    set @EmailBody = 'sp_Blitz ' + CAST(convert(datetime, @VersionDate, 102) as varchar(100)) + '. http://FirstResponderKit.org';
    if @EmailProfile is null
						exec msdb.dbo.sp_send_dbmail
							@recipients = @EmailRecipients,
							@subject = @EmailSubject,
							@body = @EmailBody,
							@query_attachment_filename = 'sp_Blitz-Results.csv',
							@attach_query_result_as_file = 1,
							@query_result_header = 1,
							@query_result_width = 32767,
							@append_query_error = 1,
							@query_result_no_padding = 1,
							@query_result_separator = @query_result_separator,
							@query = @StringToExecute;
					else
						exec msdb.dbo.sp_send_dbmail
							@profile_name = @EmailProfile,
							@recipients = @EmailRecipients,
							@subject = @EmailSubject,
							@body = @EmailBody,
							@query_attachment_filename = 'sp_Blitz-Results.csv',
							@attach_query_result_as_file = 1,
							@query_result_header = 1,
							@query_result_width = 32767,
							@append_query_error = 1,
							@query_result_no_padding = 1,
							@query_result_separator = @query_result_separator,
							@query = @StringToExecute;
    if (OBJECT_ID('tempdb..##BlitzResults', 'U') is not null) drop table ##BlitzResults;
  end;

  /* Checks if @OutputServerName is populated with a valid linked server, and that the database name specified is valid */
  declare @ValidOutputServer bit;
  declare @ValidOutputLocation bit;
  declare @LinkedServerDBCheck nvarchar(2000);
  declare @ValidLinkedServerDB int;
  declare @tmpdbchk table (cnt int);
  if @OutputServerName is not null
					begin

    if @Debug in (1, 2) raiserror('Outputting to a remote server.', 0, 1) with NOWAIT;

    if exists (select server_id
    from sys.servers
    where QUOTENAME([name]) = @OutputServerName)
							begin
      set @LinkedServerDBCheck = 'SELECT 1 WHERE EXISTS (SELECT * FROM '+@OutputServerName+'.master.sys.databases WHERE QUOTENAME([name]) = '''+@OutputDatabaseName+''')';
      insert into @tmpdbchk
      exec sys.sp_executesql @LinkedServerDBCheck;
      set @ValidLinkedServerDB = (select COUNT(*)
      from @tmpdbchk);
      if (@ValidLinkedServerDB > 0)
									begin
        set @ValidOutputServer = 1;
        set @ValidOutputLocation = 1;
      end;
								else
									raiserror('The specified database was not found on the output server', 16, 0);
    end;
						else
							begin
      raiserror('The specified output server was not found', 16, 0);
    end;
  end;
				else
					begin
    if @OutputDatabaseName is not null
      and @OutputSchemaName is not null
      and @OutputTableName is not null
      and exists ( select *
      from sys.databases
      where  QUOTENAME([name]) = @OutputDatabaseName)
							begin
      set @ValidOutputLocation = 1;
    end;
						else if @OutputDatabaseName is not null
      and @OutputSchemaName is not null
      and @OutputTableName is not null
      and not exists ( select *
      from sys.databases
      where  QUOTENAME([name]) = @OutputDatabaseName)
							begin
      raiserror('The specified output database was not found on this server', 16, 0);
    end;
						else
							begin
      set @ValidOutputLocation = 0;
    end;
  end;

  /* @OutputTableName lets us export the results to a permanent table */
  if @ValidOutputLocation = 1
					begin
    set @StringToExecute = 'USE '
							+ @OutputDatabaseName
							+ '; IF EXISTS(SELECT * FROM '
							+ @OutputDatabaseName
							+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
							+ @OutputSchemaName
							+ ''') AND NOT EXISTS (SELECT * FROM '
							+ @OutputDatabaseName
							+ '.INFORMATION_SCHEMA.TABLES WHERE QUOTENAME(TABLE_SCHEMA) = '''
							+ @OutputSchemaName + ''' AND QUOTENAME(TABLE_NAME) = '''
							+ @OutputTableName + ''') CREATE TABLE '
							+ @OutputSchemaName + '.'
							+ @OutputTableName
							+ ' (ID INT IDENTITY(1,1) NOT NULL,
								ServerName NVARCHAR(128),
								CheckDate DATETIMEOFFSET,
								Priority TINYINT ,
								FindingsGroup VARCHAR(50) ,
								Finding VARCHAR(200) ,
								DatabaseName NVARCHAR(128),
								URL VARCHAR(200) ,
								Details NVARCHAR(4000) ,
								QueryPlan [XML] NULL ,
								QueryPlanFiltered [NVARCHAR](MAX) NULL,
								CheckID INT ,
								CONSTRAINT [PK_' + CAST(NEWID() as char(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));';
    if @ValidOutputServer = 1
							begin
      set @StringToExecute = REPLACE(@StringToExecute,''''+@OutputSchemaName+'''',''''''+@OutputSchemaName+'''''');
      set @StringToExecute = REPLACE(@StringToExecute,''''+@OutputTableName+'''',''''''+@OutputTableName+'''''');
      set @StringToExecute = REPLACE(@StringToExecute,'[XML]','[NVARCHAR](MAX)');
      EXEC('EXEC('''+@StringToExecute+''') AT ' + @OutputServerName);
    end;
						else
							begin
      EXEC(@StringToExecute);
    end;
    if @ValidOutputServer = 1
							begin
      set @StringToExecute = N' IF EXISTS(SELECT * FROM '
								+ @OutputServerName + '.'
								+ @OutputDatabaseName
								+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
								+ @OutputSchemaName + ''') INSERT '
								+ @OutputServerName + '.'
								+ @OutputDatabaseName + '.'
								+ @OutputSchemaName + '.'
								+ @OutputTableName
								+ ' (ServerName, CheckDate, CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered) SELECT '''
								+ CAST(SERVERPROPERTY('ServerName') as nvarchar(128))
								+ ''', SYSDATETIMEOFFSET(), CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, CAST(QueryPlan AS NVARCHAR(MAX)), QueryPlanFiltered FROM #BlitzResults ORDER BY Priority , FindingsGroup , Finding , Details';

      EXEC(@StringToExecute);
    end;
						else
							begin
      set @StringToExecute = N' IF EXISTS(SELECT * FROM '
								+ @OutputDatabaseName
								+ '.INFORMATION_SCHEMA.SCHEMATA WHERE QUOTENAME(SCHEMA_NAME) = '''
								+ @OutputSchemaName + ''') INSERT '
								+ @OutputDatabaseName + '.'
								+ @OutputSchemaName + '.'
								+ @OutputTableName
								+ ' (ServerName, CheckDate, CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered) SELECT '''
								+ CAST(SERVERPROPERTY('ServerName') as nvarchar(128))
								+ ''', SYSDATETIMEOFFSET(), CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered FROM #BlitzResults ORDER BY Priority , FindingsGroup , Finding , Details';

      EXEC(@StringToExecute);
    end;
  end;
				else if (SUBSTRING(@OutputTableName, 2, 2) = '##')
					begin
    if @ValidOutputServer = 1
							begin
      raiserror('Due to the nature of temporary tables, outputting to a linked server requires a permanent table.', 16, 0);
    end;
						else
							begin
      set @StringToExecute = N' IF (OBJECT_ID(''tempdb..'
									+ @OutputTableName
									+ ''') IS NOT NULL) DROP TABLE ' + @OutputTableName + ';'
									+ 'CREATE TABLE '
									+ @OutputTableName
									+ ' (ID INT IDENTITY(1,1) NOT NULL,
										ServerName NVARCHAR(128),
										CheckDate DATETIMEOFFSET,
										Priority TINYINT ,
										FindingsGroup VARCHAR(50) ,
										Finding VARCHAR(200) ,
										DatabaseName NVARCHAR(128),
										URL VARCHAR(200) ,
										Details NVARCHAR(4000) ,
										QueryPlan [XML] NULL ,
										QueryPlanFiltered [NVARCHAR](MAX) NULL,
										CheckID INT ,
										CONSTRAINT [PK_' + CAST(NEWID() as char(36)) + '] PRIMARY KEY CLUSTERED (ID ASC));'
									+ ' INSERT '
									+ @OutputTableName
									+ ' (ServerName, CheckDate, CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered) SELECT '''
									+ CAST(SERVERPROPERTY('ServerName') as nvarchar(128))
									+ ''', SYSDATETIMEOFFSET(), CheckID, DatabaseName, Priority, FindingsGroup, Finding, URL, Details, QueryPlan, QueryPlanFiltered FROM #BlitzResults ORDER BY Priority , FindingsGroup , Finding , Details';

      EXEC(@StringToExecute);
    end;
  end;
				else if (SUBSTRING(@OutputTableName, 2, 1) = '#')
					begin
    raiserror('Due to the nature of Dymamic SQL, only global (i.e. double pound (##)) temp tables are supported for @OutputTableName', 16, 0);
  end;

  declare @separator as varchar(1);
  if @OutputType = 'RSV'
					set @separator = CHAR(31);
				else
					set @separator = ',';

  if @OutputType = 'COUNT'
					begin
    select COUNT(*) as Warnings
    from #BlitzResults;
  end;
				else
					if @OutputType in ( 'CSV', 'RSV' )
						begin

    select Result = CAST([Priority] as nvarchar(100))
									+ @separator + CAST(CheckID as nvarchar(100))
									+ @separator + coalesce([FindingsGroup],
															'(N/A)') + @separator
									+ coalesce([Finding], '(N/A)') + @separator
									+ coalesce(DatabaseName, '(N/A)') + @separator
									+ coalesce([URL], '(N/A)') + @separator
									+ coalesce([Details], '(N/A)')
    from #BlitzResults
    order by Priority ,
									FindingsGroup ,
									Finding ,
									DatabaseName ,
									Details;
  end;
					else if @OutputXMLasNVARCHAR = 1 and @OutputType <> 'NONE'
						begin
    select [Priority] ,
      [FindingsGroup] ,
      [Finding] ,
      [DatabaseName] ,
      [URL] ,
      [Details] ,
      CAST([QueryPlan] as nvarchar(MAX)) as QueryPlan,
      [QueryPlanFiltered] ,
      CheckID
    from #BlitzResults
    order by Priority ,
									FindingsGroup ,
									Finding ,
									DatabaseName ,
									Details;
  end;
					else if @OutputType = 'MARKDOWN'
						begin
    with
      Results
      as
      (
        select row_number() over (order by Priority, FindingsGroup, Finding, DatabaseName, Details) as rownum, *
        from #BlitzResults
        where Priority > 0 and Priority < 255 and FindingsGroup is not null and Finding is not null
          and FindingsGroup <> 'Security'
        /* Specifically excluding security checks for public exports */
      )
    select
      case
									when r.Priority <> coalesce(rPrior.Priority, 0) or r.FindingsGroup <> rPrior.FindingsGroup  then @crlf + N'**Priority ' + CAST(coalesce(r.Priority,N'') as nvarchar(5)) + N': ' + coalesce(r.FindingsGroup,N'') + N'**:' + @crlf + @crlf
									else N''
								end
								+ case when r.Finding <> coalesce(rPrior.Finding,N'') and r.Finding <> rNext.Finding then N'- ' + coalesce(r.Finding,N'') + N' ' + coalesce(r.DatabaseName, N'') + N' - ' + coalesce(r.Details,N'') + @crlf
									   when r.Finding <> coalesce(rPrior.Finding,N'') and r.Finding = rNext.Finding and r.Details = rNext.Details then N'- ' + coalesce(r.Finding,N'') + N' - ' + coalesce(r.Details,N'') + @crlf + @crlf + N'    * ' + coalesce(r.DatabaseName, N'') + @crlf
									   when r.Finding <> coalesce(rPrior.Finding,N'') and r.Finding = rNext.Finding then N'- ' + coalesce(r.Finding,N'') + @crlf + case when r.DatabaseName is null then N'' else  N'    * ' + coalesce(r.DatabaseName,N'') end + case when r.Details <> rPrior.Details then N' - ' + coalesce(r.Details,N'') + @crlf else '' end
									   else case when r.DatabaseName is null then N'' else  N'    * ' + coalesce(r.DatabaseName,N'') end + case when r.Details <> rPrior.Details then N' - ' + coalesce(r.Details,N'') + @crlf else N'' + @crlf end
								end + @crlf
    from Results r
      left outer join Results rPrior on r.rownum = rPrior.rownum + 1
      left outer join Results rNext on r.rownum = rNext.rownum - 1
    order by r.rownum
    for XML PATH(N'');
    end;
					else if @OutputType <> 'NONE'
						begin
      /* --TOURSTOP05-- */
      select [Priority] ,
        [FindingsGroup] ,
        [Finding] ,
        [DatabaseName] ,
        [URL] ,
        [Details] ,
        [QueryPlan] ,
        [QueryPlanFiltered] ,
        CheckID
      from #BlitzResults
      order by Priority ,
									FindingsGroup ,
									Finding ,
									DatabaseName ,
									Details;
    end;

    drop table #BlitzResults;

    if @OutputProcedureCache = 1
      and @CheckProcedureCache = 1
					select top 20
      total_worker_time / execution_count as AvgCPU ,
      total_worker_time as TotalCPU ,
      CAST(ROUND(100.00 * total_worker_time
									   / ( select SUM(total_worker_time)
      from sys.dm_exec_query_stats
										 ), 2) as money) as PercentCPU ,
      total_elapsed_time / execution_count as AvgDuration ,
      total_elapsed_time as TotalDuration ,
      CAST(ROUND(100.00 * total_elapsed_time
									   / ( select SUM(total_elapsed_time)
      from sys.dm_exec_query_stats
										 ), 2) as money) as PercentDuration ,
      total_logical_reads / execution_count as AvgReads ,
      total_logical_reads as TotalReads ,
      CAST(ROUND(100.00 * total_logical_reads
									   / ( select SUM(total_logical_reads)
      from sys.dm_exec_query_stats
										 ), 2) as money) as PercentReads ,
      execution_count ,
      CAST(ROUND(100.00 * execution_count
									   / ( select SUM(execution_count)
      from sys.dm_exec_query_stats
										 ), 2) as money) as PercentExecutions ,
      case when DATEDIFF(mi, creation_time,
											   qs.last_execution_time) = 0 then 0
								 else CAST(( 1.00 * execution_count / DATEDIFF(mi,
																  creation_time,
																  qs.last_execution_time) ) as money)
							end as executions_per_minute ,
      qs.creation_time as plan_creation_time ,
      qs.last_execution_time ,
      text ,
      text_filtered ,
      query_plan ,
      query_plan_filtered ,
      sql_handle ,
      query_hash ,
      plan_handle ,
      query_plan_hash
    from #dm_exec_query_stats qs
    order by case UPPER(@CheckProcedureCacheFilter)
							   when 'CPU' then total_worker_time
							   when 'READS' then total_logical_reads
							   when 'EXECCOUNT' then execution_count
							   when 'DURATION' then total_elapsed_time
							   else total_worker_time
							 end desc;

  end; /* ELSE -- IF @OutputType = 'SCHEMA' */

    set NOCOUNT off;
go

/*
--Sample execution call with the most common parameters:
EXEC [dbo].[sp_Blitz]
    @CheckUserDatabaseObjects = 1 ,
    @CheckProcedureCache = 0 ,
    @OutputType = 'TABLE' ,
    @OutputProcedureCache = 0 ,
    @CheckProcedureCacheFilter = NULL,
    @CheckServerInfo = 1
*/