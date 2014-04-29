-- 1 means it is enabled
SELECT name, value, value_in_use FROM sys.configurations WHERE name = 'default trace enabled'
GO

-- you will need 'show advanced options' to configure 'default trace enabled'
SELECT name, value, value_in_use FROM sys.configurations WHERE name = 'show advanced options'
GO
sp_configure 'show advanced options', 1;
GO
RECONFIGURE
GO
sp_configure 'default trace enabled', 1;
GO
RECONFIGURE
GO
