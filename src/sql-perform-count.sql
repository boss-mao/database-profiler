
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