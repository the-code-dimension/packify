/*
 * Packify - Package Manager
 * Installation Script for mssql/windows
 * 
 * Author: will
 * Created: 2023-11-27
 * Updated: 2023-11-27
 *
 * This file should be executed in order to install
 * the Packify package manager on a target database
 * server.
 */

-----------------------------------------------------------------
-- Installation configuration
--
-- NOTE: Change these variables to configure the installation
-- process
-----------------------------------------------------------------
DECLARE
    @packageRepoURL NVARCHAR(MAX) = 'https://raw.githubusercontent.com/the-code-dimension/packify-packages',
    @installBranch  NVARCHAR(MAX) = 'main';

-----------------------------------------------------------------
-- Dynamic query definitions
--
-- NOTE: Not recommended to edit these unless you know
-- what you're doing
-----------------------------------------------------------------
DECLARE @queryHttpGet NVARCHAR(MAX) = '
    DECLARE @targetUrl NVARCHAR(MAX) = ''?'';
    DECLARE
        @hresult        INT,
        @responseText   NVARCHAR(MAX),
        @xmlHttpObject  INT;

    -- instantiate a new request object
    EXEC @hresult = sp_OACreate
        ''MSXML2.ServerXMLHTTP'',
        @xmlHttpObject OUTPUT;

    -- construct/send an HTTP GET request
    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''open'',
        NULL,
        ''GET'',
        @targetUrl,
        false;

    EXEC @hresult = sp_OAMethod
        @xmlHttpObject,
        ''send'',
        NULL,
        '''';

    -- get the response
    DECLARE @tbvResult TABLE (
        [ResultField]   NVARCHAR(MAX)
    );
    INSERT INTO
        @tbvResult
    EXEC @hresult = sp_OAGetProperty
        @xmlHttpObject,
        ''responseText'';

    -- free the request object
    EXEC sp_OADestroy
        @xmlHttpObject;

    SELECT
        @responseOut = [ResultField]
    FROM
        @tbvResult;
';

-----------------------------------------------------------------
-- Environment setup and checks
-----------------------------------------------------------------
SET NOCOUNT ON;

-----------------------------------------------------------------
-- Ensure that OLE automation procedures and advanced
-- options are enabled
-----------------------------------------------------------------
DECLARE @tbvTargetOptions TABLE (
    [index]         INT,
    [option_name]   NVARCHAR(MAX),
    [option_value]  INT
);
INSERT INTO
    @tbvTargetOptions
SELECT
    *
FROM (
    VALUES
        (1, 'Show Advanced Options', 1),
        (2, 'Ole Automation Procedures', 1)
) Targets (
    [index],
    [option_name],
    [option_value]
);
DECLARE @tbvCurrentConfig TABLE (
    [name]          NVARCHAR(MAX),
    [minimum]       INT,
    [maximum]       INT,
    [config_value]  INT,
    [run_value]     INT
);

DECLARE @index INT = 1;
WHILE @index <= (
    SELECT
        MAX([index])
    FROM
        @tbvTargetOptions
) BEGIN
    -- get the current target option and value to set
    DECLARE
        @optionName     NVARCHAR(MAX),
        @optionValue    INT;
    SELECT
        @optionName = [option_name],
        @optionValue = [option_value]
    FROM
        @tbvTargetOptions
    WHERE
        [index] = @index;

    -- get the current configuration value
    INSERT INTO
        @tbvCurrentConfig
    EXEC sp_configure
        @optionName;
    
    -- set the new configuration value if it differs from the existing one
    IF (
        SELECT TOP 1
            [config_value]
        FROM
            @tbvCurrentConfig
    ) != @optionValue BEGIN
        EXEC sp_configure
            @optionName,
            @optionValue;

        RECONFIGURE;
    END;

    -- go to the next target option
    DELETE FROM
        @tbvCurrentConfig;
    SET @index = @index + 1;
END;
