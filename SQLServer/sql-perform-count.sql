--查询CPU最高的10条SQL
SELECT TOP 10 TEXT AS 'SQL Statement'
    ,last_execution_time AS 'Last Execution Time'
    ,(total_logical_reads + total_physical_reads + total_logical_writes) / execution_count AS [Average IO]
    ,(total_worker_time / execution_count) / 1000000.0 AS [Average CPU Time (sec)]
    ,(total_elapsed_time / execution_count) / 1000000.0 AS [Average Elapsed Time (sec)]
    ,execution_count AS "Execution Count",qs.total_physical_reads,qs.total_logical_writes
    ,qp.query_plan AS "Query Plan"
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.plan_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY total_elapsed_time / execution_count DESC


--找出执行频繁的语句的SQL语句
with aa as (
SELECT  
--执行次数 
QS.execution_count, 
--查询语句 
SUBSTRING(ST.text,(QS.statement_start_offset/2)+1, 
((CASE QS.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) 
ELSE QS.statement_end_offset END - QS.statement_start_offset)/2) + 1 
) AS statement_text, 
--执行文本 
ST.text, 
--执行计划 
qs.last_elapsed_time,
qs.min_elapsed_time,
qs.max_elapsed_time,
QS.total_worker_time, 
QS.last_worker_time, 
QS.max_worker_time, 
QS.min_worker_time 
FROM 
sys.dm_exec_query_stats QS 
--关键字 
CROSS APPLY 
sys.dm_exec_sql_text(QS.sql_handle) ST 
WHERE 
QS.last_execution_time > '2016-02-14 00:00:00' and  execution_count > 500

-- AND ST.text LIKE '%%' 
--ORDER BY 
--QS.execution_count DESC

)
select text,max(execution_count) execution_count --,last_elapsed_time,min_elapsed_time,max_elapsed_time 
from aa
where [text] not  like '%sp_MSupd_%' and  [text] not like '%sp_MSins_%' and  [text] not like '%sp_MSdel_%' 
group by text
order by 2  desc


-- 查找逻辑读取最高的查询(存储过程)
SELECT TOP ( 25 )
        P.name AS [SP Name] ,
        Deps.total_logical_reads AS [TotalLogicalReads] ,
        deps.total_logical_reads / deps.execution_count AS [AvgLogicalReads] ,
        deps.execution_count ,
        ISNULL(deps.execution_count / DATEDIFF(Second, deps.cached_time,
                                               GETDATE()), 0) AS [Calls/Second] ,
        deps.total_elapsed_time ,
        deps.total_elapsed_time / deps.execution_count AS [avg_elapsed_time] ,
        deps.cached_time
FROM    sys.procedures AS p
        INNER JOIN sys.dm_exec_procedure_stats AS deps ON p.[Object_id] = deps.[Object_id]
WHERE   deps.Database_id = DB_ID()
ORDER BY deps.total_logical_reads DESC;

-- 查看某个SQL的执行计划
SET STATISTICS PROFILE ON 
SELECT * FROM Demo
SET STATISTICS PROFILE OFF

-- 查询某个SQL的执行时间
SET STATISTICS Time ON 
SELECT * FROM Demo
SET STATISTICS TIME OFF

-- 查询某个SQL的IO信息
SET STATISTICS IO ON 
SELECT * FROM Demo
SET STATISTICS IO OFF
