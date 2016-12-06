--查看锁住的表
select   request_session_id   spid,OBJECT_NAME(resource_associated_entity_id) tableName  
from   sys.dm_tran_locks where resource_type='OBJECT'

--哪个会话引起阻塞并且它们在运行什么 
SELECT  DTL.[request_session_id] AS [session_id] ,
        DB_NAME(DTL.[resource_database_id]) AS [Database] ,
        DTL.resource_type ,
        CASE WHEN DTL.resource_type IN ( 'DATABASE', 'FILE', 'METADATA' )
             THEN DTL.resource_type
             WHEN DTL.resource_type = 'OBJECT'
             THEN OBJECT_NAME(DTL.resource_associated_entity_id,
                              DTL.[resource_database_id])
             WHEN DTL.resource_type IN ( 'KEY', 'PAGE', 'RID' )
             THEN ( SELECT  OBJECT_NAME([object_id])
                    FROM    sys.partitions
                    WHERE   sys.partitions.hobt_id = DTL.resource_associated_entity_id
                  )
             ELSE 'Unidentified'
        END AS [Parent Object] ,
        DTL.request_mode AS [Lock Type] ,
        DTL.request_status AS [Request Status] ,
        DER.[blocking_session_id] ,
        DES.[login_name] ,
        CASE DTL.request_lifetime
          WHEN 0 THEN DEST_R.TEXT
          ELSE DEST_C.TEXT
        END AS [Statement]
FROM    sys.dm_tran_locks DTL
        LEFT JOIN sys.[dm_exec_requests] DER ON DTL.[request_session_id] = DER.[session_id]
        INNER JOIN sys.dm_exec_sessions DES ON DTL.request_session_id = DES.[session_id]
        INNER JOIN sys.dm_exec_connections DEC ON DTL.[request_session_id] = DEC.[most_recent_session_id]
        OUTER APPLY sys.dm_exec_sql_text(DEC.[most_recent_sql_handle]) AS DEST_C
        OUTER APPLY sys.dm_exec_sql_text(DER.sql_handle) AS DEST_R
WHERE   DTL.[resource_database_id] = DB_ID()
        AND DTL.[resource_type] NOT IN ( 'DATABASE', 'METADATA' )
ORDER BY DTL.[request_session_id];

--查看因为单条UPDATE语句锁住的用户表
SELECT  [resource_type] ,
        DB_NAME([resource_database_id]) AS [Database Name] ,
        CASE WHEN DTL.resource_type IN ( 'DATABASE', 'FILE', 'METADATA' )
             THEN DTL.resource_type
             WHEN DTL.resource_type = 'OBJECT'
             THEN OBJECT_NAME(DTL.resource_associated_entity_id,
                              DTL.[resource_database_id])
             WHEN DTL.resource_type IN ( 'KEY', 'PAGE', 'RID' )
             THEN ( SELECT  OBJECT_NAME([object_id])
                    FROM    sys.partitions
                    WHERE   sys.partitions.hobt_id = DTL.resource_associated_entity_id
                  )
             ELSE 'Unidentified'
        END AS requested_object_name ,
        [request_mode] ,
        [resource_description]
FROM    sys.dm_tran_locks DTL
WHERE   DTL.[resource_type] <> 'DATABASE';

--单库中的锁定和阻塞
SELECT  DTL.[resource_type] AS [resource type] ,
        CASE WHEN DTL.[resource_type] IN ( 'DATABASE', 'FILE', 'METADATA' )
             THEN DTL.[resource_type]
             WHEN DTL.[resource_type] = 'OBJECT'
             THEN OBJECT_NAME(DTL.resource_associated_entity_id)
             WHEN DTL.[resource_type] IN ( 'KEY', 'PAGE', 'RID' )
             THEN ( SELECT  OBJECT_NAME([object_id])
                    FROM    sys.partitions
                    WHERE   sys.partitions.[hobt_id] = DTL.[resource_associated_entity_id]
                  )
             ELSE 'Unidentified'
        END AS [Parent Object] ,
        DTL.[request_mode] AS [Lock Type] ,
        DTL.[request_status] AS [Request Status] ,
        DOWT.[wait_duration_ms] AS [wait duration ms] ,
        DOWT.[wait_type] AS [wait type] ,
        DOWT.[session_id] AS [blocked session id] ,
        DES_blocked.[login_name] AS [blocked_user] ,
        SUBSTRING(dest_blocked.text, der.statement_start_offset / 2,
                  ( CASE WHEN der.statement_end_offset = -1
                         THEN DATALENGTH(dest_blocked.text)
                         ELSE der.statement_end_offset
                    END - der.statement_start_offset ) / 2) AS [blocked_command] ,
        DOWT.[blocking_session_id] AS [blocking session id] ,
        DES_blocking.[login_name] AS [blocking user] ,
        DEST_blocking.[text] AS [blocking command] ,
        DOWT.resource_description AS [blocking resource detail]
FROM    sys.dm_tran_locks DTL
        INNER JOIN sys.dm_os_waiting_tasks DOWT ON DTL.lock_owner_address = DOWT.resource_address
        INNER JOIN sys.[dm_exec_requests] DER ON DOWT.[session_id] = DER.[session_id]
        INNER JOIN sys.dm_exec_sessions DES_blocked ON DOWT.[session_id] = DES_Blocked.[session_id]
        INNER JOIN sys.dm_exec_sessions DES_blocking ON DOWT.[blocking_session_id] = DES_Blocking.[session_id]
        INNER JOIN sys.dm_exec_connections DEC ON DTL.[request_session_id] = DEC.[most_recent_session_id]
        CROSS APPLY sys.dm_exec_sql_text(DEC.[most_recent_sql_handle]) AS DEST_Blocking
        CROSS APPLY sys.dm_exec_sql_text(DER.sql_handle) AS DEST_Blocked
WHERE   DTL.[resource_database_id] = DB_ID()


--识别在行级的锁定和阻塞
SELECT  '[' + DB_NAME(ddios.[database_id]) + '].[' + su.[name] + '].['
        + o.[name] + ']' AS [statement] ,
        i.[name] AS 'index_name' ,
        ddios.[partition_number] ,
        ddios.[row_lock_count] ,
        ddios.[row_lock_wait_count] ,
        CAST (100.0 * ddios.[row_lock_wait_count] / ( ddios.[row_lock_count] ) AS DECIMAL(5,
                                                              2)) AS [%_times_blocked] ,
        ddios.[row_lock_wait_in_ms] ,
        CAST (1.0 * ddios.[row_lock_wait_in_ms] / ddios.[row_lock_wait_count] AS DECIMAL(15,
                                                              2)) AS [avg_row_lock_wait_in_ms]
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddios.[index_id]
        INNER JOIN sys.objects o ON ddios.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
WHERE   ddios.row_lock_wait_count > 0
        AND OBJECTPROPERTY(ddios.[object_id], 'IsUserTable') = 1
        AND i.[index_id] > 0
ORDER BY ddios.[row_lock_wait_count] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]

--识别闩锁等待
SELECT  '[' + DB_NAME() + '].[' + OBJECT_SCHEMA_NAME(ddios.[object_id])
        + '].[' + OBJECT_NAME(ddios.[object_id]) + ']' AS [object_name] ,
        i.[name] AS index_name ,
        ddios.page_io_latch_wait_count ,
        ddios.page_io_latch_wait_in_ms ,
        ( ddios.page_io_latch_wait_in_ms / ddios.page_io_latch_wait_count ) AS avg_page_io_latch_wait_in_ms
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.[object_id] = i.[object_id]
                                    AND i.index_id = ddios.index_id
WHERE   ddios.page_io_latch_wait_count > 0
        AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
ORDER BY ddios.page_io_latch_wait_count DESC ,
        avg_page_io_latch_wait_in_ms DESC

--识别锁升级
SELECT  OBJECT_NAME(ddios.[object_id], ddios.database_id) AS [object_name] ,
        i.name AS index_name ,
        ddios.index_id ,
        ddios.partition_number ,
        ddios.index_lock_promotion_attempt_count ,
        ddios.index_lock_promotion_count ,
        ( ddios.index_lock_promotion_attempt_count
          / ddios.index_lock_promotion_count ) AS percent_success
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.object_id = i.object_id
                                    AND ddios.index_id = i.index_id
WHERE   ddios.index_lock_promotion_count > 0
ORDER BY index_lock_promotion_count DESC;
  
--与锁争用有关的索引
SELECT  OBJECT_NAME(ddios.object_id, ddios.database_id) AS object_name ,
        i.name AS index_name ,
        ddios.index_id ,
        ddios.partition_number ,
        ddios.page_lock_wait_count ,
        ddios.page_lock_wait_in_ms ,
        CASE WHEN DDMID.database_id IS NULL THEN 'N'
             ELSE 'Y'
        END AS missing_index_identified
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.object_id = i.object_id
                                    AND ddios.index_id = i.index_id
        LEFT OUTER JOIN ( SELECT DISTINCT
                                    database_id ,
                                    object_id
                          FROM      sys.dm_db_missing_index_details
                        ) AS DDMID ON DDMID.database_id = ddios.database_id
                                      AND DDMID.object_id = ddios.object_id
WHERE   ddios.page_lock_wait_in_ms > 0
ORDER BY ddios.page_lock_wait_count DESC;