
-- impersonate the packify login
DECLARE @targetLogin NVARCHAR(4000) = 'PackifyLogin';
EXECUTE AS LOGIN = @targetLogin;

    -- check if the target database already exists
    DECLARE
        @errorNumber    INT,
        @errorMessage   NVARCHAR(MAX);
    IF (
        SELECT
           COUNT(*)
        FROM
            sys.databases
        WHERE
            [name] = 'Database!'
    ) != 0 BEGIN
        SET @errorNumber = 90100;
        SET @errorMessage = 'Target database ''Database!'' already exists';

        THROW
            @errorNumber,
            @errorMessage,
            1;
    END;

    -- create the packify with the provided name
    CREATE DATABASE
        [Database!];
    GO

REVERT;
