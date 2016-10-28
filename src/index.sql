
-- 未被使用的索引
SELECT  OBJECT_NAME(i.[object_id]) AS [Table Name] ,
        i.name
FROM    sys.indexes AS i
        INNER JOIN sys.objects AS o ON i.[object_id] = o.[object_id]
WHERE   i.index_id NOT IN ( SELECT  ddius.index_id
                            FROM    sys.dm_db_index_usage_stats AS ddius
                            WHERE   ddius.[object_id] = i.[object_id]
                                    AND i.index_id = ddius.index_id
                                    AND database_id = DB_ID() )
        AND o.[type] = 'U'
ORDER BY OBJECT_NAME(i.[object_id]) ASC;

--需要维护但是未被用过的索引
SELECT  '[' + DB_NAME() + '].[' + su.[name] + '].[' + o.[name] + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] AS [user_reads] ,
        ddius.[user_updates] AS [user_writes] ,
        SUM(SP.rows) AS [total_rows]
FROM    sys.dm_db_index_usage_stats ddius
        INNER JOIN sys.indexes i ON ddius.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddius.[index_id]
        INNER JOIN sys.partitions SP ON ddius.[object_id] = SP.[object_id]
                                        AND SP.[index_id] = ddius.[index_id]
        INNER JOIN sys.objects o ON ddius.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
WHERE   ddius.[database_id] = DB_ID() -- current database only
        AND OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.[index_id] > 0
GROUP BY su.[name] ,
        o.[name] ,
        i.[name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] ,
        ddius.[user_updates]
HAVING  ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] = 0
ORDER BY ddius.[user_updates] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]

-- 可能不高效的非聚集索引 (writes > reads)
SELECT  OBJECT_NAME(ddius.[object_id]) AS [Table Name] ,
        i.name AS [Index Name] ,
        i.index_id ,
        user_updates AS [Total Writes] ,
        user_seeks + user_scans + user_lookups AS [Total Reads] ,
        user_updates - ( user_seeks + user_scans + user_lookups ) AS [Difference]
FROM    sys.dm_db_index_usage_stats AS ddius WITH ( NOLOCK )
        INNER JOIN sys.indexes AS i WITH ( NOLOCK ) ON ddius.[object_id] = i.[object_id]
                                                       AND i.index_id = ddius.index_id
WHERE   OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.database_id = DB_ID()
        AND user_updates > ( user_seeks + user_scans + user_lookups )
        AND i.index_id > 1
ORDER BY [Difference] DESC ,
        [Total Writes] DESC ,
        [Total Reads] ASC;

--没有用于用户查询的索引
SELECT  '[' + DB_NAME() + '].[' + su.[name] + '].[' + o.[name] + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] AS [user_reads] ,
        ddius.[user_updates] AS [user_writes] ,
        ddios.[leaf_insert_count] ,
        ddios.[leaf_delete_count] ,
        ddios.[leaf_update_count] ,
        ddios.[nonleaf_insert_count] ,
        ddios.[nonleaf_delete_count] ,
        ddios.[nonleaf_update_count]
FROM    sys.dm_db_index_usage_stats ddius
        INNER JOIN sys.indexes i ON ddius.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddius.[index_id]
        INNER JOIN sys.partitions SP ON ddius.[object_id] = SP.[object_id]
                                        AND SP.[index_id] = ddius.[index_id]
        INNER JOIN sys.objects o ON ddius.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
        INNER JOIN sys.[dm_db_index_operational_stats](DB_ID(), NULL, NULL,
                                                       NULL) AS ddios ON ddius.[index_id] = ddios.[index_id]
                                                              AND ddius.[object_id] = ddios.[object_id]
                                                              AND SP.[partition_number] = ddios.[partition_number]
                                                              AND ddius.[database_id] = ddios.[database_id]
WHERE   OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.[index_id] > 0
        AND ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] = 0
ORDER BY ddius.[user_updates] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]

--查找丢失索引
SELECT  user_seeks * avg_total_user_cost * ( avg_user_impact * 0.01 ) AS [index_advantage] ,
        dbmigs.last_user_seek ,
        dbmid.[statement] AS [Database.Schema.Table] ,
        dbmid.equality_columns ,
        dbmid.inequality_columns ,
        dbmid.included_columns ,
        dbmigs.unique_compiles ,
        dbmigs.user_seeks ,
        dbmigs.avg_total_user_cost ,
        dbmigs.avg_user_impact
FROM    sys.dm_db_missing_index_group_stats AS dbmigs WITH ( NOLOCK )
        INNER JOIN sys.dm_db_missing_index_groups AS dbmig WITH ( NOLOCK ) ON dbmigs.group_handle = dbmig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details AS dbmid WITH ( NOLOCK ) ON dbmig.index_handle = dbmid.index_handle
WHERE   dbmid.[database_id] = DB_ID()
ORDER BY index_advantage DESC;

--索引上的碎片超过15%并且索引体积较大（超过500页）的索引。
SELECT  '[' + DB_NAME() + '].[' + OBJECT_SCHEMA_NAME(ddips.[object_id],
                                                     DB_ID()) + '].['
        + OBJECT_NAME(ddips.[object_id], DB_ID()) + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddips.[index_type_desc] ,
        ddips.[partition_number] ,
        ddips.[alloc_unit_type_desc] ,
        ddips.[index_depth] ,
        ddips.[index_level] ,
        CAST(ddips.[avg_fragmentation_in_percent] AS SMALLINT) AS [avg_frag_%] ,
        CAST(ddips.[avg_fragment_size_in_pages] AS SMALLINT) AS [avg_frag_size_in_pages] ,
        ddips.[fragment_count] ,
        ddips.[page_count]
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'limited') ddips
        INNER JOIN sys.[indexes] i ON ddips.[object_id] = i.[object_id]
                                      AND ddips.[index_id] = i.[index_id]
WHERE   ddips.[avg_fragmentation_in_percent] > 15
        AND ddips.[page_count] > 500
ORDER BY ddips.[avg_fragmentation_in_percent] ,
        OBJECT_NAME(ddips.[object_id], DB_ID()) ,
        i.[name]

--缺失索引
SELECT migs.group_handle, mid.* 
FROM sys.dm_db_missing_index_group_stats AS migs 
INNER JOIN sys.dm_db_missing_index_groups AS mig 
ON (migs.group_handle = mig.index_group_handle) 
INNER JOIN sys.dm_db_missing_index_details AS mid 
ON (mig.index_handle = mid.index_handle) 
WHERE migs.group_handle = 2

--无用索引
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED 
SELECT 
DB_NAME() AS DatbaseName 
, SCHEMA_NAME(O.Schema_ID) AS SchemaName 
, OBJECT_NAME(I.object_id) AS TableName 
, I.name AS IndexName 
INTO #TempNeverUsedIndexes 
FROM sys.indexes I INNER JOIN sys.objects O ON I.object_id = O.object_id 
WHERE 1=2 
EXEC sp_MSForEachDB 'USE [?]; INSERT INTO #TempNeverUsedIndexes 
SELECT 
DB_NAME() AS DatbaseName 
, SCHEMA_NAME(O.Schema_ID) AS SchemaName 
, OBJECT_NAME(I.object_id) AS TableName 
, I.NAME AS IndexName 
FROM sys.indexes I INNER JOIN sys.objects O ON I.object_id = O.object_id 
LEFT OUTER JOIN sys.dm_db_index_usage_stats S ON S.object_id = I.object_id 
AND I.index_id = S.index_id 
AND DATABASE_ID = DB_ID() 
WHERE OBJECTPROPERTY(O.object_id,''IsMsShipped'') = 0 
AND I.name IS NOT NULL 
AND S.object_id IS NULL' 
SELECT * FROM #TempNeverUsedIndexes 
ORDER BY DatbaseName, SchemaName, TableName, IndexName 
DROP TABLE #TempNeverUsedIndexes

--经常被大量更新，但是却基本不适用的索引项-
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED 
SELECT 
DB_NAME() AS DatabaseName 
, SCHEMA_NAME(o.Schema_ID) AS SchemaName 
, OBJECT_NAME(s.[object_id]) AS TableName 
, i.name AS IndexName 
, s.user_updates 
, s.system_seeks + s.system_scans + s.system_lookups 
AS [System usage] 
INTO #TempUnusedIndexes 
FROM sys.dm_db_index_usage_stats s 
INNER JOIN sys.indexes i ON s.[object_id] = i.[object_id] 
AND s.index_id = i.index_id 
INNER JOIN sys.objects o ON i.object_id = O.object_id 
WHERE 1=2 
EXEC sp_MSForEachDB 'USE [?]; INSERT INTO #TempUnusedIndexes 
SELECT TOP 20 
DB_NAME() AS DatabaseName 
, SCHEMA_NAME(o.Schema_ID) AS SchemaName 
, OBJECT_NAME(s.[object_id]) AS TableName 
, i.name AS IndexName 
, s.user_updates 
, s.system_seeks + s.system_scans + s.system_lookups 
AS [System usage] 
FROM sys.dm_db_index_usage_stats s 
INNER JOIN sys.indexes i ON s.[object_id] = i.[object_id] 
AND s.index_id = i.index_id 
INNER JOIN sys.objects o ON i.object_id = O.object_id 
WHERE s.database_id = DB_ID() 
AND OBJECTPROPERTY(s.[object_id], ''IsMsShipped'') = 0 
AND s.user_seeks = 0 
AND s.user_scans = 0 
AND s.user_lookups = 0 
AND i.name IS NOT NULL 
ORDER BY s.user_updates DESC' 
SELECT TOP 20 * FROM #TempUnusedIndexes ORDER BY [user_updates] DESC 
DROP TABLE #TempUnusedIndexes

