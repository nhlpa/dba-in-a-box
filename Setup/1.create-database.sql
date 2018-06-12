use master;
go

if exists (select null from sys.databases where name = 'DBA')
  drop database DBA;
go

create database DBA;
go

alter database DBA
  modify file (name = DBA, filegrowth = 256mb);
go

alter database DBA
  modify file (name = DBA_log, filegrowth = 128mb);
go