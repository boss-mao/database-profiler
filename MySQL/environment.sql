--查看连接信息以及连接执行的命令
SHOW  PROCESSLIST

--查看当前被锁住的表
show OPEN TABLES where In_use > 0;

--开启会话级别的profile
SET profiling=1
--查看所有的数据库操作执行过程
SHOW PROFILES
--查询单条语句profile
SHOW PROFILE FOR QUERY 1


--查看整个数据库服务的线程数
show global status like 'Thread%';
--刷新会话级别的计数器
FLUSH STATUS
--查看当前会话的状态信息
SHOW STATUS

--查看所表参数信息
SHOW  TABLE STATUS

