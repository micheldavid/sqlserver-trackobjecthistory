SqlServer Track Object History
=============

Description
-------------

Tracks object history in SQL Servers.

This is a set of scripts which allow you to track changes in most system objects across all databases in a SQL Server installation.

Scripts have been tested on SQL Server 2008 R2 only, but they should work on versions as earlier as SQL Server 2005 and later with few modifications.

### Objects tracked

Type | Description
--- | ---
C	| CHECK constraint
D	| DEFAULT (constraint or stand-alone)
F	| FOREIGN KEY constraint
FN	| SQL scalar function
IF	| SQL inline table-valued function
P	| SQL Stored Procedure
PK	| PRIMARY KEY constraint
TF	| SQL table-valued-function
U	| Table (user-defined)
UQ	| UNIQUE constraint
V	| View
IX	| Index (not a SQL Server object type)

### Objects not tracked

Type | Description
--- | ---
AF	| Aggregate function (CLR)
FS	| Assembly (CLR) scalar-function
FT	| Assembly (CLR) table-valued function
IT	| Internal table
PC	| Assembly (CLR) stored-procedure
PG	| Plan guide
R	| Rule (old-style, stand-alone)
RF	| Replication-filter-procedure
S	| System base table
SN	| Synonym
SQ	| Service queue
TA	| Assembly (CLR) DML trigger
TR	| SQL DML trigger
X	| Extended stored procedure

Contents
-------------
- prereq_DefaultTraceEnabled.sql : Helps verifying and enabling default trace.
- install.sql : Creates table ObjectHistories, stored procedures DatabaseObjectGetDefinition and ObjectHistoriesPopulate
- init_ObjectHistories.sql : Initializes ObjectHistories table with all database object descriptions (may take a while)
- schedule_ObjectHistoriesPopulate.sql : Sample for scheduling the execution of ObjectHistoriesPopulate hourly

Limitations
-------------
Tracking relies on 'default trace enabled' advanced setting being enabled.

If your server's default trace gets corrupted, you will lose changes until it clears out.

If an object is changed more than once between two scheduled updates, you will lose the changes that happened in between.

Installation
-------------
1. Make sure you have default trace enabled. File prereq_DefaultTraceEnabled.sql should help.
2. Open file install.sql
	1. Edit the database ([_Maintenance] by default) and schema ([dbo] by default) you want to install on
	2. Run
3. Run init_ObjectHistories.sql if you would like to prepopulate [ObjectHistories] table with all database's object descriptions (may take a while)
4. You will have to setup a scheduled task to run [ObjectHistoriesPopulate] every hour. There is a sample on schedule_ObjectHistoriesPopulate.sql

Improvements
-------------
- Add more definitions (stored procedure [DatabaseObjectGetDefinition])
- Build create scripts instead of listing object details (stored procedure [DatabaseObjectGetDefinition])
- Test and make code compatible in SQL Server 2005 and later

License
-------------
The MIT License (MIT)

Copyright (c) 2014 Michel David

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
