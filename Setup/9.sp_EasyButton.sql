use DBA;
go 

if object_id('dbo.sp_EasyButton') is null
  exec ('create procedure dbo.sp_EasyButton as return 0;');
go

alter procedure dbo.sp_EasyButton
  @Configure bit = 0
  ,@FileGrowth bit = 0
  ,@FileGrowthSysDbs bit = 0
  ,@FileGrowthDataMB smallint = 256
  ,@FileGrowthLogMB smallint = 128
  ,@Alerts bit = 0
  ,@OperatorName nvarchar(100) = null
  ,@OperatorEmail nvarchar(320) = null
as
  /*
  Instructions
  */
  if @Configure = 0
     and @FileGrowth = 0
     and @FileGrowthSysDbs = 0
     and @FileGrowthDataMB = 256
     and @FileGrowthLogMB = 128
     and @Alerts = 0
     and @OperatorName is null
     and @OperatorEmail is null
    begin
      print '
/*
sp_EasyButton

For when you just need an Easy Button. One-button server 
configuration to implement commonly-accepted best practices.

Credit: Pim Brouwers

Source: https://github.com/pimbrouwers/sp_EasyButton

License: https://github.com/pimbrouwers/sp_EasyButton/blob/master/LICENSE

Parameters:
  @Configure bit - run all sp_configure operations
  @FileGrowth bit - adjust filegrowth
  @FileGrowthSysDbs bit - include system databases (master, model, msdb)
  @FileGrowthDataMB smallint - MB value for data filegrowth (256 recommended)
  @FileGrowthLogMB smallint - MB value for log filegrowth (128 recommended)
  @Alerts bit - enable alerts
  @OperatorName nvarchar(100) - operator name for alert dispatch
  @OperatorEmail nvarchar(320) - operator eamil for alert dispatch
*/';
      return;
    end;

  /*
  Version Detection
  */
  declare @VersionNumber decimal(3, 1);
  declare @ProductVersion varchar(25) = cast(serverproperty('ProductVersion') as varchar(25));

  set @VersionNumber = cast(substring(@ProductVersion, 1, charindex('.', @ProductVersion) + 1) as decimal(5, 2));

  /*
  Configuration
  */
  if @Configure = 1
    begin
      print ('-------------------');
      print ('-- CONFIGURATION --');
      print ('-------------------');

      -- ARITHABORT
      -- https://docs.microsoft.com/en-us/sql/t-sql/statements/set-arithabort-transact-sql      
      exec sys.sp_configure
        N'user options'
        ,N'64';

      -- Show Advanced Options
      -- https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/show-advanced-options-server-configuration-option      
      exec sys.sp_configure
        'show advanced options'
        ,1;

      -- Backup Compression
      -- 2008R2+ (v10.5)
      -- This way no matter who takes the backup, it will be compressed
      -- https://www.brentozar.com/archive/2013/09/five-sql-server-settings-to-change/      
      if @VersionNumber > 10
        exec sys.sp_configure
          'backup compression default'
          ,'1';

      -- Lightweight pooling
      -- https://docs.microsoft.com/en-us/sql/relational-databases/policy-based-management/disable-lightweight-pooling      
      exec sys.sp_configure
        'lightweight pooling'
        ,'0';

      -- Priority Boost
      -- http://dataeducation.com/the-sql-hall-of-shame/ 
      exec sys.sp_configure
        'priority boost'
        ,'0';

      -- Remote DAC
      -- https://www.brentozar.com/archive/2013/09/five-sql-server-settings-to-change/
      exec sys.sp_configure
        'remote admin connections'
        ,'1';

      -- Cost Threshold for parallelism
      -- If you see a lot of CXPACKET waits on your system together with High CPU usage, 
      -- consider reviewing this parameter further together with the MAXDOP.
      -- https://www.brentozar.com/archive/2013/09/five-sql-server-settings-to-change/      
      exec sys.sp_configure
        'cost threshold for parallelism'
        ,'50';

      -- Maximum degrees of parallelism
      -- Represents the number of CPU that a single query can use. A value of 0 means 
      -- you are letting SQL Server decide how many, of which it will use all available
      -- (up to 64). Youï¿½ll end up using all your CPUs for each and every query, if by 
      -- chance, you didn't change the Cost Threshold for Parallelism (from the default of 5). 
      -- https://support.microsoft.com/en-ca/help/2806535/recommendations-and-guidelines-for-the-max-degree-of-parallelism-confi
      declare
        @NumaNodes int
        ,@LogicalProcessors int
        ,@MaxDop int = 8;

      select
        @NumaNodes = count(*)
      from
        sys.dm_os_memory_nodes
      where
        memory_node_id <> 64;

      select
        @LogicalProcessors = cpu_count
      from
        sys.dm_os_sys_info;

      if @NumaNodes = 1
         or @LogicalProcessors < 8
        begin
          set @MaxDop = @LogicalProcessors;
        end;

      exec sys.sp_configure
        'max degree of parallelism'
        ,@MaxDop;

      -- Max Server Memory (MB)
      -- The default value is ALL of your server's memory. Yes. All. As a baseline
      -- leave 25% for the OS (optimistic). But if the total memory available to this 
      -- instance is > 32GB than 12.5% should be sufficient for the OS to operate.
      -- https://www.brentozar.com/blitz/max-memory/
      declare
        @SystemMemory int
        ,@MaxServerMemory int;

      select
        @SystemMemory = total_physical_memory_kb / 1024
      from
        sys.dm_os_sys_memory;

      set @MaxServerMemory = floor(@SystemMemory * .75);

      if @SystemMemory >= 32768
        begin
          set @MaxServerMemory = floor(@SystemMemory * .875);
        end;

      exec sys.sp_configure
        'max server memory (MB)'
        ,@MaxServerMemory;

      reconfigure;
    end;

  /*
  Filegrowth
  */
  if @FileGrowth = 1
    begin
      print ('');
      print ('------------------------------------------');
      print ('-- FILEGROWTH (data: ' + cast(@FileGrowthDataMB as varchar(25)) + 'MB, log: ' + cast(@FileGrowthLogMB as varchar(25)) + 'MB)') + ' --';
      print ('------------------------------------------');

      if @FileGrowthDataMB is null
         or @FileGrowthDataMB <= 0
         or @FileGrowthLogMB is null
         or @FileGrowthLogMB <= 0
        print ('!!! To configure filegrowth, you must provide @FileGrowthDataMB and @FileGrowthLogMB and these values must be greater than 0 !!!');
      else
        begin
          declare @Sql nvarchar(max);

          ;with files as (
            select
              f.*
              ,db_name(f.database_id) as dbname
              ,p.name as ownername
            from
              sys.master_files f with (nolock)
            join
              sys.databases d with (nolock)
              on d.database_id = f.database_id
            join
              sys.server_principals p with (nolock)
              on p.sid = d.owner_sid
          )
          ,dbs as (
            select
              f.dbname
              ,cast(f.name as varchar(128)) as filename
              ,cast(l.logfilename as varchar(128)) as logfilename
              ,f.ownername
            from
              files f
            cross apply (
              select
                l.name as logfilename
              from
                files l
              where
                l.type = 1
                and l.database_id = f.database_id
            ) l
            where
              f.type = 0
              and db_name(f.database_id) <> 'tempdb'
          )
          select
            @Sql = stuff((
                           select
                             'alter database ' + quotename(dbs.dbname) + ' modify file (name = ' + quotename(dbs.filename) + ', filegrowth = ' + cast(@FileGrowthDataMB as varchar(25)) + '); ' + 'alter database ' + quotename(dbs.dbname) + ' modify file (name = ' + quotename(dbs.logfilename) + ', filegrowth = ' + cast(@FileGrowthLogMB as varchar(25)) + '); ' + 'print (''' + quotename(dbs.dbname) + ''');'
                           from
                             dbs
                           where
                             @FileGrowthSysDbs = 1
                             or dbs.ownername <> 'sa'
                           for xml path('')
                         ), 1, 0, ''
                   );

          exec (@Sql);
        end;
    end;

  /*
  Alerts
  */
  if @Alerts = 1
    begin
      print ('');
      print ('------------');
      print ('-- ALERTS --');
      print ('------------');

      if @OperatorName is null
         or @OperatorName = ''
         or @OperatorEmail is null
         or @OperatorEmail = ''
        print ('!!! To configure alerts, you must provide @OperatorName and @OperatorEmail !!!');
      else
        begin
          -- Operator
          -- Create if not exists
          if not exists (select null from msdb.dbo.sysoperators where name = @OperatorName)
            begin
              exec msdb.dbo.sp_add_operator
                @name = @OperatorName
                ,@enabled = 1
                ,@weekday_pager_start_time = 90000
                ,@weekday_pager_end_time = 180000
                ,@saturday_pager_start_time = 90000
                ,@saturday_pager_end_time = 180000
                ,@sunday_pager_start_time = 90000
                ,@sunday_pager_end_time = 180000
                ,@pager_days = 0
                ,@email_address = @OperatorEmail;
            end;

          declare @severity int = 16;
          declare @alertName varchar(50) = 'Severity 0' + cast(@severity as varchar(25));

          -- Severity 16
          -- Indicates general errors that can be corrected by the user.
          print ('Severity 16 - User errors');

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 17
          -- Indicates that the statement caused SQL Server to run out of resources (such as 
          -- memory, locks, or disk space for the database) or to exceed some limit set by 
          -- the system administrator.
          print ('Severity 17 - Out of resources');

          set @severity = 17;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 18 
          -- Indicates a problem in the Database Engine software, but the statement completes 
          -- execution, and the connection to the instance of the Database Engine is maintained. 
          print ('Severity 18 - Non-fatal internal error');

          set @severity = 18;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 19
          -- Indicates that a nonconfigurable Database Engine limit has been exceeded and the current 
          -- batch process has been terminated. Error messages with a severity level of 19 or higher 
          -- stop the execution of the current batch.
          print ('Severity 19 - Security context');

          set @severity = 19;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 20 
          -- Indicates that a statement has encountered a problem. Because the problem has affected 
          -- only the current task, it is unlikely that the database itself has been damaged.
          print ('Severity 20 - Connection problem with current statement');

          set @severity = 20;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 21 
          -- ndicates that a problem has been encountered that affects all tasks in the current 
          -- database, but it is unlikely that the database itself has been damaged.
          print ('Severity 21 - Error affecting all processes');

          set @severity = 21;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 22 
          -- Indicates that the table or index specified in the message has been damaged by a 
          -- software or hardware problem.
          print ('Severity 22 - Corrupt or damaged table/index');

          set @severity = 22;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 23 
          -- Indicates that the integrity of the entire database is in question because of 
          -- a hardware or software problem.
          print ('Severity 23 - Database integrity');

          set @severity = 23;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 24 
          -- Indicates a media failure. The system administrator may have to restore the 
          -- database. You may also have to call your hardware vendor.
          print ('Severity 24 - Hardware');

          set @severity = 24;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Severity 25 
          -- Unexpected error
          print ('Severity 25 - Unexpected error');

          set @severity = 25;
          set @alertName = 'Severity 0' + cast(@severity as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = 0
                ,@severity = @severity
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Error number 823 
          -- Operating system error.
          print ('Error Number 823 - Operating System');

          declare @errorNumber int = 823;

          set @alertName = 'Error Number ' + cast(@errorNumber as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = @errorNumber
                ,@severity = 0
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Error number 824 
          -- Logical consistency io error.
          print ('Error Number 824 - Logical consistent io error');

          set @errorNumber = 824;
          set @alertName = 'Error Number ' + cast(@errorNumber as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = @errorNumber
                ,@severity = 0
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;

          -- Error number 825 
          -- Read file error.
          print ('Error Number 825 - Read file error');

          set @errorNumber = 825;
          set @alertName = 'Error Number ' + cast(@errorNumber as varchar(25));

          if not exists (select null from msdb.dbo.sysalerts where name = @alertName)
            begin
              exec msdb.dbo.sp_add_alert
                @name = @alertName
                ,@message_id = @errorNumber
                ,@severity = 0
                ,@enabled = 1
                ,@delay_between_responses = 60
                ,@include_event_description_in = 1;

              exec msdb.dbo.sp_add_notification
                @alert_name = @alertName
                ,@operator_name = @OperatorName
                ,@notification_method = 7;
            end;
        end;
    end;
go
