
DECLARE @targetLogin NVARCHAR(4000) = 'PackifyLogin';
EXECUTE AS LOGIN = @targetLogin;
GO

    USE [Database!];
    GO

    CREATE SCHEMA
        [Config];
    GO
    CREATE SCHEMA
        [HTTP];
    GO

    -- for debugging purposes: revert the ide to master
    USE [master];
    GO

REVERT;
