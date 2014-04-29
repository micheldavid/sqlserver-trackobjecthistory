USE [_Maintenance]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[ObjectHistories](
	[ObjectHistoryId] [int] PRIMARY KEY IDENTITY(1,1) NOT NULL,
	[DatabaseId] [int] NOT NULL,
	[ObjectId] [int] NOT NULL,
	[ObjectType] [char](2) NOT NULL,
	[IndexId] [int] NULL,
	[Hostname] [nvarchar](256) NULL,
	[UserName] [nvarchar](256) NULL,
	[Operation] [char](1) NOT NULL,
	[OperationDate] [datetimeoffset](7) NOT NULL,
	[ComposedName] [nvarchar](1024) NOT NULL,
	[Contents] [nvarchar](max) NULL,
)
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Create, Alter, Drop' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ObjectHistories', @level2type=N'COLUMN',@level2name=N'Operation'
GO
/*
Defines a database object
----------
@ComposedName OUTPUT
Full object name: database.schema.objectname.indexname
----------
@ObjectType OUTPUT

Opt legend
	will not be defined
+	will be defined
++	not a valid sqlserver type but will be defined

Opt	Type	Description
	AF	Aggregate function (CLR)
+	C	CHECK constraint
+	D	DEFAULT (constraint or stand-alone)
+	F	FOREIGN KEY constraint
+	FN	SQL scalar function
	FS	Assembly (CLR) scalar-function
	FT	Assembly (CLR) table-valued function
+	IF	SQL inline table-valued function
	IT	Internal table
+	P	SQL Stored Procedure
	PC	Assembly (CLR) stored-procedure
	PG	Plan guide
+	PK	PRIMARY KEY constraint
	R	Rule (old-style, stand-alone)
	RF	Replication-filter-procedure
	S	System base table
	SN	Synonym
	SQ	Service queue
	TA	Assembly (CLR) DML trigger
+	TF	SQL table-valued-function
	TR	SQL DML trigger
+	U	Table (user-defined)
+	UQ	UNIQUE constraint
++	IX	index
++	UX	UNIQUE index
+	V	View
	X	Extended stored procedure
----------
@Result OUTPUT
The object definition or '' if it is not a type that is defined
*/
CREATE PROCEDURE [dbo].[DatabaseObjectGetDefinition]
	@DatabaseId INT
	,@ObjectId INT
	,@IndexId INT = NULL
	,@ComposedName NVARCHAR(1024) = NULL OUTPUT
	,@ObjectType CHAR(2) = NULL OUTPUT
	,@Result NVARCHAR(MAX) = NULL OUTPUT
AS
/* -- for testing
DECLARE @ComposedName NVARCHAR(1024),@ObjectType CHAR(2),@Result NVARCHAR(MAX)
DECLARE @DatabaseId INT = DB_ID('database'),@ObjectId INT = OBJECT_ID('database.schema.object'),@IndexId INT = NULL
*/
DECLARE @DatabaseName SYSNAME = DB_NAME(@DatabaseId)
DECLARE @ObjectName SYSNAME = OBJECT_NAME(@ObjectId, @DatabaseId)
SET @ComposedName = @DatabaseName + '.' + OBJECT_SCHEMA_NAME(@ObjectId, @DatabaseId) + '.' + @ObjectName

-- load object type and index name
DECLARE @sql NVARCHAR(2000)
IF OBJECT_ID('tempdb..#objtype') IS NOT NULL DROP TABLE #objtype;CREATE TABLE #objtype (ObjectType CHAR(2) NULL, IndexName SYSNAME NULL)
IF @IndexId IS NOT NULL
BEGIN
	DECLARE @IndexName SYSNAME;
	SET @sql = 'DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) + ',@IndexId INT=' + CONVERT(VARCHAR(11), @IndexId) +
		';USE [?];
IF @Db = DB_ID()
	INSERT INTO #objtype
		SELECT
			(
				CASE
					WHEN is_primary_key = 1 THEN ''PK''
					WHEN is_unique_constraint = 1 THEN ''UQ''
					WHEN is_unique = 1 THEN ''UX''
					ELSE ''IX''
				END
			)
			,name
		FROM sys.indexes
		WHERE
			object_id = @ObjectId
			AND index_id = @IndexId
'
	EXEC sp_MSforeachdb @sql
	SELECT @ObjectType = ObjectType, @IndexName = IndexName FROM #objtype
	SET @ComposedName = @ComposedName + '.' + @IndexName
END
ELSE
BEGIN
	SET @sql = 'DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) +
		';USE [?];IF @Db = DB_ID() INSERT INTO #objtype SELECT type, null FROM sys.sysobjects WHERE id = @ObjectId'
	EXEC sp_MSforeachdb @sql
	SELECT @ObjectType = ObjectType FROM #objtype
END

-- load object definition
IF OBJECT_ID('tempdb..#objresult') IS NOT NULL DROP TABLE #objresult;CREATE TABLE #objresult (RESULT NVARCHAR(MAX))

IF @ObjectType = 'U' -- Table (user-defined)
BEGIN
	SET @sql = 'USE [?]
	DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) + '
	IF @Db = DB_ID()
	BEGIN
		DECLARE @tbl nvarchar(max) = ''''
		SELECT
			@tbl = @tbl + '', '' + QUOTENAME(sc.Name) + '' '' +  QUOTENAME(st.Name) + ''('' + CONVERT(VARCHAR(11), sc.[Length]) + '') '' +
			(CASE WHEN sc.IsNullable = 1 THEN ''NULL'' ELSE ''NOT NULL'' END) +
			(CASE WHEN ColumnProperty(sc.id, sc.name, ''IsComputed'') = 1 THEN '' COMPUTED'' ELSE '''' END) +
			(CASE WHEN c.text IS NULL THEN '''' ELSE '' '' + c.text END) 
		FROM sys.sysobjects so
		JOIN sys.syscolumns sc on sc.id = so.id
		JOIN sys.systypes st on st.xusertype = sc.xusertype
		LEFT JOIN sys.syscomments c ON c.id = so.id AND sc.colid = c.number
		WHERE so.id = @ObjectId
		ORDER BY sc.ColID

		IF LEN(@tbl) != 0
			INSERT INTO #objresult SELECT SUBSTRING(@tbl, 3, LEN(@tbl) - 1)
	END
'
	EXEC sp_MSforeachdb @sql
END
ELSE IF @ObjectType = 'F' -- FOREIGN KEY constraint
BEGIN
	SET @sql = 'USE [?]
	DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) + '
	IF @Db = DB_ID()
	BEGIN
		DECLARE @fkeyid int, @fcolumns nvarchar(2126) = ''''	--Length (16*max_identifierLength)+(15*2)+(16*3)
			,@rkeyid int, @rcolumns nvarchar(4000) = ''''-- string to build up index desc

		-- OBTAIN TWO TABLE IDs
		select @fkeyid = parent_object_id, @rkeyid = referenced_object_id
			from sys.foreign_keys where object_id = @ObjectId

		-- USE CURSOR OVER FOREIGN KEY COLUMNS TO BUILD COLUMN LISTS
		--	(NOTE: @fcolumns HAS THE FKEY AND @rcolumns HAS THE RKEY COLUMN LIST)
		select
			@fcolumns = @fcolumns + '', '' + col_name(@fkeyid, parent_column_id)
			,@rcolumns = @rcolumns + '', '' + col_name(@rkeyid, referenced_column_id)
		from sys.foreign_key_columns where constraint_object_id = @ObjectId

		INSERT INTO #objresult VALUES
		(
			''FOREIGN KEY '' + DB_NAME() + ''.'' + OBJECT_SCHEMA_NAME(@ObjectId) + ''.'' + OBJECT_NAME(@ObjectId) + '' ON '' + 
			OBJECT_SCHEMA_NAME(@fkeyid) + ''.'' + OBJECT_NAME(@fkeyid) + '' ('' + SUBSTRING(@fcolumns, 3, LEN(@fcolumns) - 1) + '') REFERENCES '' +
			rtrim(schema_name(ObjectProperty(@rkeyid,''schemaid''))) + ''.'' + object_name(@rkeyid) + '' (''+ SUBSTRING(@rcolumns, 3, LEN(@rcolumns) - 1) + '')'' +
			(CASE WHEN ObjectProperty(@ObjectId, ''CnstIsDisabled'') = 1 THEN '' DISABLED'' ELSE '''' END) +
			(CASE WHEN ObjectProperty(@ObjectId, ''CnstIsNotRepl'') = 1 THEN '' NOREPL'' ELSE '''' END) +
			(CASE WHEN ObjectProperty(@ObjectId, ''CnstIsDeleteCascade'') = 1 THEN '' DELETE CASCADE'' ELSE '''' END) +
			(CASE WHEN ObjectProperty(@ObjectId, ''CnstIsUpdateCascade'') = 1 THEN '' UPDATE CASCADE'' ELSE '''' END)
		)
	END
'
	EXEC sp_MSforeachdb @sql
END
-- 'PK' = PRIMARY KEY constraint
-- 'UQ' = UNIQUE constraint
-- 'UX' = UNIQUE index
-- 'IX' = index
ELSE IF @ObjectType IN ('PK', 'UQ', 'UX', 'IX')
BEGIN
	SET @sql = 'USE [?]
	DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) + ',@IndexId INT=' + CONVERT(VARCHAR(11), @IndexId) + '
	IF @Db = DB_ID()
	BEGIN
		DECLARE @Desc NVARCHAR(MAX);
		SELECT @Desc =
			(CASE is_disabled WHEN 0 THEN '''' ELSE '', DISABLED'' END) +
			(CASE has_filter WHEN 0 THEN '''' ELSE '', FILTER ('' + ISNULL(filter_definition, '''') + '')'' END)
		FROM sys.indexes
		WHERE
			object_id = @ObjectId
			AND index_id = @IndexId

		SELECT
			@Desc = @Desc + '', '' + col.name +
			(
				CASE ic.is_included_column
					WHEN 1 THEN '' INCLUDED''
					ELSE (CASE ic.is_descending_key WHEN 1 THEN '' DESC'' ELSE '' ASC'' END)
				END
			)
		FROM sys.indexes ind 
		JOIN sys.index_columns ic ON  ind.object_id = ic.object_id and ind.index_id = ic.index_id 
		JOIN sys.columns col ON ic.object_id = col.object_id and ic.column_id = col.column_id 
		WHERE
			ind.object_id = @ObjectId
			AND ind.index_id = @IndexId
		ORDER BY ic.index_column_id

		IF LEN(@Desc) != 0
			INSERT INTO #objresult SELECT SUBSTRING(@Desc, 3, LEN(@Desc) - 1)
	END
'
	EXEC sp_MSforeachdb @sql
END
-- 'C' = Check constraint
-- 'D' = DEFAULT (constraint or stand-alone)
-- 'P' = SQL Stored Procedure
-- 'FN' = SQL scalar function
-- 'TR' = SQL trigger (schema-scoped DML trigger, or DDL trigger at either the database or server scope)
-- 'IF' = SQL inline table-valued function
-- 'TF' = SQL table-valued-function
-- 'V' = View
ELSE IF @ObjectType IN ('C', 'D', 'P', 'FN', 'TR', 'IF', 'TF', 'V')
BEGIN
	SET @sql = 'DECLARE @Db INT=' + CONVERT(VARCHAR(11), @DatabaseId) + ',@ObjectId INT=' + CONVERT(VARCHAR(11), @ObjectId) + 
		';USE [?];IF @Db = DB_ID() INSERT INTO #objresult SELECT c.Text FROM sys.syscomments c where c.id = @ObjectId ORDER BY c.colid'
	EXEC sp_MSforeachdb @sql
END

SET @Result = ''
IF EXISTS (SELECT 1 FROM #objresult)
BEGIN
	SELECT @Result = @Result + Result FROM #objresult
END
/* -- for testing
SELECT ComposedName = @ComposedName, ObjectType = @ObjectType, Result = @Result
*/
GO
CREATE PROCEDURE [dbo].[ObjectHistoriesPopulate]
AS
IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'default trace enabled' AND CONVERT(INT, value_in_use) = 1)
BEGIN 

	-- loads changes since last execution or since yesterday, if no last date is found
    DECLARE @MinDate DATETIME = ISNULL((SELECT MAX([OperationDate]) FROM [dbo].[ObjectHistories]), DATEADD(DD, -1, SYSDATETIMEOFFSET()));

	-- remove number (...\log_9999.trc) from default log path
    DECLARE @TraceFilePath varchar(500) = (SELECT TOP 1 [path] FROM sys.traces WHERE is_default = 1);
    SET @TraceFilePath = LEFT(@TraceFilePath, LEN(@TraceFilePath) - PATINDEX('%\%', REVERSE(@TraceFilePath))) + '\log.trc'; 

	DECLARE crs_TraceRow CURSOR LOCAL FAST_FORWARD FOR
		SELECT
			DatabaseID
			,ObjectID
			,IndexID
			,StartTime
			,EventClass
			,ServerName
			,LoginName
		FROM ::fn_trace_gettable( @TraceFilePath, DEFAULT )
		WHERE
			EventClass in (46,47,164)
			AND EventSubclass = 0
			AND ObjectType NOT IN (21587) -- 21587: statistics
			AND DatabaseName NOT IN ('tempdb') -- ignore temporary tables
			AND StartTime > @MinDate
		ORDER BY StartTime
	OPEN crs_TraceRow

	DECLARE
		@DatabaseID INT
		,@ObjectID INT
		,@IndexID INT
		,@StartTime DATETIME
		,@EventClass INT
		,@ServerName NVARCHAR(256)
		,@LoginName NVARCHAR(256)
		,@ComposedName NVARCHAR(1024)
		,@ObjectType CHAR(2)
		,@Result NVARCHAR(MAX)
	FETCH NEXT FROM crs_TraceRow INTO @DatabaseID,@ObjectID,@IndexID,@StartTime,@EventClass,@ServerName,@LoginName
	WHILE @@FETCH_STATUS >= 0
	BEGIN
		SET @ComposedName = NULL

		IF @EventClass = 47 -- dropped
			SELECT
				@ComposedName = [ComposedName]
				,@ObjectType = [ObjectType]
				,@Result = NULL
			FROM [dbo].[ObjectHistories]
			WHERE
				DatabaseId = @DatabaseId
				AND ObjectId = @ObjectId
				AND (@IndexID IS NULL OR IndexId = @IndexId)
		ELSE
			-- ComposedName is null if object does not exist
			EXEC [dbo].[DatabaseObjectGetDefinition]
				@DatabaseID
				,@ObjectID
				,@IndexID
				,@ComposedName = @ComposedName OUTPUT
				,@ObjectType = @ObjectType OUTPUT
				,@Result = @Result OUTPUT

		-- make sure ComposedName was found
		-- and there is no last version or last version is not the same
		IF @ComposedName IS NOT NULL AND NOT EXISTS
			(
				SELECT 1 FROM [dbo].[ObjectHistories]
				WHERE
					ObjectHistoryId =
					(
						SELECT MAX(ObjectHistoryId)
						FROM [dbo].[ObjectHistories]
						WHERE
							DatabaseId = @DatabaseId
							AND ObjectId = @ObjectId
							AND (@IndexID IS NULL OR IndexId = @IndexId)
					)
					AND ((@Result IS NULL AND Contents IS NULL) OR Contents = @Result)
			)
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
				@DatabaseId
				,@ObjectId
				,@ObjectType
				,@IndexID
				,@ServerName
				,@LoginName
				,(CASE @EventClass WHEN 46 THEN 'C' WHEN 47 THEN 'D' WHEN 164 THEN 'A' ELSE '-' END)
				,@StartTime
				,@ComposedName
				,@Result
			)

	FETCH NEXT FROM crs_TraceRow INTO @DatabaseID,@ObjectID,@IndexID,@StartTime,@EventClass,@ServerName,@LoginName
END
DEALLOCATE crs_TraceRow
END
GO
SET ANSI_PADDING OFF
GO
