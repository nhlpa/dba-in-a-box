/*
Storage of sp_whoIsActive output
*/
use DBA;
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