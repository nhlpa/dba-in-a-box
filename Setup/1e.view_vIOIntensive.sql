/*
Most CPU intensive queries
*/
use DBA;
go

create view dbo.vIOIntensive
as
	with queryStats as (
	  select
	    qs.plan_handle
	    ,sum(qs.execution_count) as ExecutionCount
	    ,sum(qs.total_logical_reads) as LogicalReads
	    ,cast(sum(qs.total_logical_reads) / (sum(qs.execution_count) + 0.0) as decimal(25, 2)) as AvgLogicalReads
	    ,max(qs.total_logical_reads) as MaxLogicalReads
	    ,min(qs.total_logical_reads) as MinLogicalReads
	    ,cast(sum(qs.total_worker_time) / (sum(qs.execution_count) + 0.0) as decimal(25, 2)) as AvgCpuTime
	    ,cast(sum(qs.total_elapsed_time) / (sum(qs.execution_count) + 0.0) as decimal(25, 2)) as AvgDuration
	    ,cast(sum(qs.total_physical_reads) / (sum(qs.execution_count) + 0.0) as decimal(25, 2)) as AvgPhysicalReads    
	    ,cast(sum(qs.total_logical_writes) / (sum(qs.execution_count) + 0.0) as decimal(25, 2)) as AvgLogicalWrites
	    ,max(qs.last_execution_time) as LastExecution
	  from
	    sys.dm_exec_query_stats qs
	  group by
	    qs.plan_handle
	)
	select top 25
	  db_name(st.dbid) as Db
	  ,st.objectid
	  ,object_schema_name(st.objectid, st.dbid) + '.' + object_name(st.objectid, st.dbid) as OperationName
	  ,qs.ExecutionCount
	  ,qs.LogicalReads
	  ,qs.AvgLogicalReads
	  ,qs.MaxLogicalReads
	  ,qs.MinLogicalReads
	  ,qs.AvgCpuTime
	  ,qs.AvgDuration
	  ,qs.AvgPhysicalReads
	  ,qs.AvgLogicalWrites
	  ,qs.LastExecution
	  ,st.text as StatementText
	  ,qp.query_plan as ExecutionPlan
	from
	  queryStats qs
	cross apply sys.dm_exec_sql_text(qs.plan_handle) st
	cross apply sys.dm_exec_query_plan(qs.plan_handle) qp
	where  
	  db_name(st.dbid) is not null
	  and db_name(st.dbid) not in ('master', 'model', 'msdb')
	order by  
	  qs.LogicalReads desc;
 go