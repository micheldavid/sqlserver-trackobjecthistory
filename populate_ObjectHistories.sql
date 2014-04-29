USE [_Maintenance]
GO

-- load database objects
-- ignore tempdb and objects where is_ms_shipped = 1
IF OBJECT_ID('tempdb..#dbobjects') IS NOT NULL DROP TABLE #dbobjects;CREATE TABLE #dbobjects (db INT, obj_id INT, idxid INT NULL, idxname sysname null, [type] CHAR(2))
DECLARE @sql NVARCHAR(2000) = 'USE [?];IF db_name() != ''tempdb'' INSERT INTO #dbobjects SELECT dbid = DB_ID(), object_id, null, null, type = [type] FROM sys.objects where is_ms_shipped = 0'
EXEC sp_MSforeachdb @sql

-- load indexes
-- ignore tempdb, heap indexes (index_id = 0) and indexes from objects where is_ms_shipped = 1
SET @sql = 'USE [?];IF db_name() != ''tempdb'' INSERT INTO #dbobjects SELECT dbid = DB_ID(), i.object_id, i.index_id, name, type = ''IX'' FROM sys.indexes i where i.index_id <> 0 and i.object_id in (select obj_id from #dbobjects where db = db_id())'
EXEC sp_MSforeachdb @sql

/* -- for testing
SELECT
	*
FROM
	(
		SELECT
			Name = DB_NAME(db) +
				'.' + OBJECT_SCHEMA_NAME(obj_id, db) +
				'.' + OBJECT_NAME(obj_id, db) +
				(CASE WHEN idxname IS NULL THEN '' ELSE '.' + idxname END)
			,[type]
		FROM #dbobjects
	) T
ORDER BY T.Name
*/

DECLARE @ComposedName NVARCHAR(1024)
	,@ObjectType CHAR(2)
	,@Result NVARCHAR(MAX)
	,@CreateDate DATETIMEOFFSET = CONVERT(DATETIMEOFFSET, GETDATE() - 1)

DECLARE @db INT, @obj_id INT, @idxid INT

DECLARE crs_objs CURSOR LOCAL FAST_FORWARD FOR
	SELECT db, obj_id, idxid
	FROM #dbobjects
OPEN crs_objs
FETCH crs_objs INTO @db, @obj_id, @idxid

WHILE @@fetch_status >= 0
BEGIN

	EXEC [dbo].[DatabaseObjectGetDefinition]
		@db
		,@obj_id
		,@idxid
		,@ComposedName = @ComposedName OUTPUT
		,@ObjectType = @ObjectType OUTPUT
		,@Result = @Result OUTPUT

	INSERT INTO [dbo].[ObjectHistories]
		(
			[DatabaseId]
			,[ObjectId]
			,[ObjectType]
			,[IndexId]
			,[Hostname]
			,[UserName]
			,[Operation]
			,[OperationDate]
			,[ComposedName]
			,[Contents]
		)
		VALUES
		(
			@db
			,@obj_id
			,@ObjectType
			,@idxid
			,NULL
			,NULL
			,'C'
			,@CreateDate
			,@ComposedName
			,@Result
		)

	FETCH crs_objs INTO @db, @obj_id, @idxid
END
DEALLOCATE crs_objs
GO
/* -- for testing
SELECT * FROM [dbo].[ObjectHistories]
*/
