--查询当前数据库的配置信息
Select configuration_id ConfigurationId,
name Name,
description Description,
Cast(value as int) value,
Cast(minimum as int) Minimum,
Cast(maximum as int) Maximum,
Cast(value_in_use as int) ValueInUse,
is_dynamic IsDynamic,
is_advanced IsAdvanced
From sys.configurations
Order By is_advanced, name

--检查SQL SERVER 当前已创建的线程数
select count(*) from sys.dm_os_workers

--查询当前连接到数据库的用户信息
Select s.login_name LoginName,
s.host_name HostName,
s.transaction_isolation_level TransactionIsolationLevel,
Max(c.connect_time) LastConnectTime,
Count(*) ConnectionCount,
Sum(Cast(c.num_reads as BigInt)) TotalReads,
Sum(Cast(c.num_writes as BigInt)) TotalWrites
From sys.dm_exec_connections c
Join sys.dm_exec_sessions s
On c.most_recent_session_id = s.session_id
Group By s.login_name, s.host_name, s.transaction_isolation_level

--查询CPU和内存利用率
Select DateAdd(s, (timestamp - (osi.cpu_ticks / Convert(Float, (osi.cpu_ticks / osi.ms_ticks)))) / 1000, GETDATE()) AS EventTime,
Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') as SystemIdle,
Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') as ProcessUtilization,
Record.value('(./Record/SchedulerMonitorEvent/SystemHealth/MemoryUtilization)[1]', 'int') as MemoryUtilization
From (Select timestamp,
convert(xml, record) As Record
From sys.dm_os_ring_buffers
Where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
And record Like '%<SystemHealth>%') x
Cross Join sys.dm_os_sys_info osi
Order By timestamp

--查看每个数据库缓存大小
SELECT  COUNT(*) * 8 / 1024 AS 'Cached Size (MB)' ,
        CASE database_id
          WHEN 32767 THEN 'ResourceDb'
          ELSE DB_NAME(database_id)
        END AS 'Database'
FROM    sys.dm_os_buffer_descriptors
GROUP BY DB_NAME(database_id) ,
        database_id
ORDER BY 'Cached Size (MB)' DESC


--SQL SERVER  统计IO活动信息
SET STATISTICS IO ON
select top 10* from Table
SET STATISTICS IO OFF

--SQL SERVER 清除缓存SQL语句
CHECKPOINT;
GO
DBCC  FREEPROCCACHE      ---清空执行计划缓存
DBCC DROPCLEANBUFFERS;   --清空数据缓存
GO

--查看当前进程的信息
DBCC INPUTBUFFER(51)

--查看当前数据是否启用了快照隔离
DBCC USEROPTIONS;

--查看摸个数据库数据表中的数据页类型
--In_Row_Data: 分别为存储行内数据的
	--LOB_Data: 存储Lob对象,Lob对象用于存储存在数据库的二进制文件
	          --当这个类型的列出现时,原有的列会存储一个24字节的指针，而将具体的二进制数据存在LOB页中
	--Row_Overflow_data:存储溢出数据的,使用Varchar,nvarchar等数据类型时，当行的大小不超过8060字节时，全部存在行内In-row data
					--当varchar中存储的数据过多使得整行超过8060字节时，会将额外的部分存于Row-overflow data页中，
					--如果update这列使得行大小减少到小于8060字节，则这行又会全部回到in-row data页
					--text,ntext和image类型来说，每一列只要不为null,即使占用很小的数据，也需要额外分配一个LOB页
DBCC IND ( Lawyer, [dbo.tb_Contract], -1)

