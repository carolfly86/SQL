
http://www.brentozar.com/archive/2012/03/how-talk-your-boss-about-world-backup-day/
---Backup isn't finished
select top 100 * from msdb.dbo.backupset WITH (nolock)
where backup_finish_date is null 
order by backup_set_id desc


----When the last backup finished
SELECT  d.name, MAX(b.backup_finish_date) AS last_backup_finish_date
FROM    master.sys.databases d WITH (NOLOCK)
LEFT OUTER JOIN msdb.dbo.backupset b WITH (NOLOCK) ON d.name = b.database_name AND b.type = 'D'
WHERE d.name <> 'tempdb'
GROUP BY d.name
ORDER BY 2


---backup size and duration
SELECT  @@SERVERNAME AS ServerName ,
        YEAR(backup_finish_date) AS backup_year ,
        MONTH(backup_finish_date) AS backup_month ,
        CAST(AVG(( backup_size / ( DATEDIFF(ss, bset.backup_start_date,
                                            bset.backup_finish_date) )
                   / 1048576 )) AS INT) AS throughput_MB_sec_avg ,
        CAST(MIN(( backup_size / ( DATEDIFF(ss, bset.backup_start_date,
                                            bset.backup_finish_date) )
                   / 1048576 )) AS INT) AS throughput_MB_sec_min ,
        CAST(MAX(( backup_size / ( DATEDIFF(ss, bset.backup_start_date,
                                            bset.backup_finish_date) )
                   / 1048576 )) AS INT) AS throughput_MB_sec_max
FROM    msdb.dbo.backupset bset
WHERE   bset.type = 'D' /* full backups only */
        AND bset.backup_size > 5368709120 /* 5GB or larger */
        AND DATEDIFF(ss, bset.backup_start_date, bset.backup_finish_date) > 1 /* backups lasting over a second */
GROUP BY YEAR(backup_finish_date) ,
        MONTH(backup_finish_date)
ORDER BY @@SERVERNAME ,
        YEAR(backup_finish_date) DESC ,
        MONTH(backup_finish_date) DESC

---BACKING UP CORRUPT DATA?
CREATE TABLE #temp
    (
      ParentObject VARCHAR(255) ,
      [Object] VARCHAR(255) ,
      Field VARCHAR(255) ,
      [Value] VARCHAR(255)
    )   

CREATE TABLE #DBCCResults
    (
      ServerName VARCHAR(255) ,
      DBName VARCHAR(255) ,
      LastCleanDBCCDate DATETIME
    )   

EXEC master.dbo.sp_MSforeachdb @command1 = 'USE [?]; INSERT INTO #temp EXECUTE (''DBCC DBINFO WITH TABLERESULTS'')',
    @command2 = 'INSERT INTO #DBCCResults SELECT @@SERVERNAME, ''?'', Value FROM #temp WHERE Field = ''dbi_dbccLastKnownGood''',
    @command3 = 'TRUNCATE TABLE #temp';

   --Delete duplicates due to a bug in SQL Server 2008

WITH    DBCC_CTE
          AS ( SELECT   ROW_NUMBER() OVER ( PARTITION BY ServerName, DBName,
                                            LastCleanDBCCDate ORDER BY LastCleanDBCCDate ) RowID
               FROM     #DBCCResults
             )
    DELETE  FROM DBCC_CTE
    WHERE   RowID > 1 ;

SELECT  ServerName ,
        DBName ,
        CASE LastCleanDBCCDate
          WHEN '1900-01-01 00:00:00.000' THEN 'Never ran DBCC CHECKDB'
          ELSE CAST(LastCleanDBCCDate AS VARCHAR)
        END AS LastCleanDBCCDate
FROM    #DBCCResults
ORDER BY 1, 2, 3;

DROP TABLE #temp, #DBCCResults ;