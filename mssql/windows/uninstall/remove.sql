USE [master];
GO

-- drop the packify database. we also set it to single user to kill
-- any existing connections and ensure we can drop it
ALTER DATABASE
    [Database!]
SET
    SINGLE_USER
    WITH ROLLBACK IMMEDIATE;
GO
DROP DATABASE
    [Database!];
GO

-- drop the packify login and user in [master]
DROP USER
    [PackifyLogin];
GO

DROP LOGIN
    [PackifyLogin];
GO
