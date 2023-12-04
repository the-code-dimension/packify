SET NOCOUNT ON;
USE [Database!];
GO

DECLARE @targetLogin NVARCHAR(4000) = 'PackifyLogin';
EXECUTE AS LOGIN = @targetLogin;
GO

    -- create/populate a table to hold global configuration settings
    CREATE TABLE Config.Settings (
        [SettingName]   NVARCHAR(400),
        [SettingValue]  NVARCHAR(MAX),

        CONSTRAINT
            AK_SettingName
        UNIQUE (
            [SettingName]
        )
    );
    GO

    INSERT INTO
        Config.Settings
    VALUES
        ('HTTP Timeout', '30.0');
    GO

    -- scalar-valued function that returns the value of a setting
    -- given its name (NULL if it doesn't exist)
    CREATE FUNCTION Config.GetSetting (
        @settingName    NVARCHAR(400)
    )
    RETURNS NVARCHAR(MAX) AS BEGIN
        DECLARE @settingValue NVARCHAR(MAX) = (
            SELECT TOP 1
                [SettingValue]
            FROM
                Config.Settings
            WHERE
                [SettingName] = @settingName
        );

        RETURN @settingValue;
    END;
    GO

    -- register a global errors table
    CREATE TABLE Config.Errors (
        [ErrorName]     NVARCHAR(400),
        [ErrorNumber]   INT,
        [ErrorMessage]  NVARCHAR(MAX),

        CONSTRAINT
            AK_ErrorName
        UNIQUE (
            [ErrorName]
        ),

        CONSTRAINT
            AK_ErrorNumber
        UNIQUE (
            [ErrorNumber]
        )
    );
    GO

    INSERT INTO
        Config.Errors
    VALUES
        ('HTTP_CREATE_FAILED',              80900,  'Failed creating %s object (hresult %d)'),
        ('HTTP_OPEN_FAILED',                80910,  'Failed opening %s object (hresult %d)'),
        ('HTTP_SET_REQ_HEAD_FAILED',        80920,  'Failed setting request header ''%s'' with value ''%s'' (hresult %d)'),
        ('HTTP_SEND_FAILED',                80930,  'Failed sending HTTP %s request (hresult %d)'),
        ('HTTP_TIMEOUT',                    80940,  'HTTP %s request timed out after %d seconds'),
        ('HTTP_WAIT_FAILED',                80945,  'HTTP %s request failed waiting for response (hresult %d)'),
        ('HTTP_STATUS_CODE_FAILED',         80950,  'Failed getting status code for HTTP %s request (hresult %d)'),
        ('HTTP_STATUS_TEXT_FAILED',         80955,  'Failed getting status text for HTTP %s request (hresult %d)'),
        ('HTTP_GET_ALL_HEADERS_FAILED',     80960,  'Failed getting response headers for HTTP %s request (hresult %d)'),
        ('HTTP_GET_RESPONSE_BODY_FAILED',   80970, 'Failed getting response body for HTTP %s request (hresult %d)');
    GO

    -- scalar-valued function that returns the format string of an error
    -- given its name (NULL if it doesn't exist)
    CREATE FUNCTION Config.GetErrorMessage (
        @errorName      NVARCHAR(400)
    )
    RETURNS NVARCHAR(MAX) AS BEGIN
        RETURN CONCAT(
            @errorName, ': ',
            (
                SELECT TOP 1
                    [ErrorMessage]
                FROM
                    Config.Errors
                WHERE
                    [ErrorName] = @errorName
            )
        );
    END;
    GO

    -- scalar-valued function that returns the number of an error
    -- given its name (NULL if it doesn't exist)
    CREATE FUNCTION Config.GetErrorNumber (
        @errorName      NVARCHAR(400)
    )
    RETURNS INT AS BEGIN
        RETURN (
            SELECT TOP 1
                [ErrorNumber]
            FROM
                Config.Errors
            WHERE
                [ErrorName] = @errorName
        );
    END;
    GO

REVERT;
