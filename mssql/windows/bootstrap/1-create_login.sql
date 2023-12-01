
USE [master];
GO

-- generate random password for the packify login
DECLARE
    @randomPasswordLength   INT             = 128,
    @randomPassword         NVARCHAR(128)   = '',
    @lowPasswordCharacter   CHAR(1)         = ' ',
    @highPasswordCharacter  CHAR(1)         = '~';
DECLARE @index INT = 0;
WHILE @index < @randomPasswordLength BEGIN
    SET @randomPassword = @randomPassword + (
        CHAR(
            ASCII(@lowPasswordCharacter)
            + CAST(
                RAND()
                * (
                    ASCII(@highPasswordCharacter)
                    - ASCII(@lowPasswordCharacter)
                ) AS INT
            )
        )
    );

    SET @index = @index + 1;
END;

-- ensure that the packify login doesn't already exist
DECLARE @targetLoginName NVARCHAR(MAX) = 'PackifyLogin';
DECLARE
    @errorNumber    INT,
    @errorMessage   NVARCHAR(MAX);
IF (
    SELECT
        COUNT(*)
    FROM
        sys.syslogins
    WHERE
        [name] = @targetLoginName
) != 0 BEGIN
    SET @errorNumber = 90000;
    SET @errorMessage = CONCAT(
        'Target login name ''',
        @targetLoginName,
        ''' already exists'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;

-- generate a dynamic query to create the new instance-level login
DECLARE @queryCreateLogin NVARCHAR(MAX) = CONCAT(
    '
        CREATE LOGIN
            [', @targetLoginName, ']
        WITH
            PASSWORD = ''', REPLACE(@randomPassword, '''', ''''''), ''';
    '
);
PRINT CONCAT(
    'Creating login ''',
    @targetLoginName,
    ''' with query:'
);
PRINT @queryCreateLogin;
EXEC sp_executesql
    @queryCreateLogin;

-- generate a dynamic query to create the master database user
DECLARE @queryCreateUser NVARCHAR(MAX) = CONCAT(
    '
        CREATE USER
            [', @targetLoginName, '];
    '
);
PRINT CONCAT(
    'Creating user ''',
    @targetLoginName,
    ''' in [master] with query:'
);
PRINT @queryCreateUser;
EXEC sp_executesql
    @queryCreateUser;

-- grant sysadmin permissions to the packify login
DECLARE @queryGrantSysadmin NVARCHAR(MAX) = CONCAT(
    '
        EXEC master..sp_addsrvrolemember
            @loginame = N''', @targetLoginName, ''',
            @rolename = N''sysadmin'';
    '
);
PRINT CONCAT(
    'Granting sysadmin to login ''',
    @targetLoginName,
    ''' with query:'
);
PRINT @queryGrantSysadmin;
EXEC sp_executesql
    @queryGrantSysadmin;
