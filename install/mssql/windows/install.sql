/*
 * Packify - Package Manager
 * Installation Script for mssql/windows
 * 
 * Author: will
 * Created: 2023-11-27
 * Updated: 2023-11-30
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
    @packageRepoURL     NVARCHAR(MAX) = 'https://raw.githubusercontent.com/the-code-dimension/packify-packages',
    @installBranch      NVARCHAR(MAX) = 'main',
    @targetDatabase     NVARCHAR(MAX);

-----------------------------------------------------------------
-- Advanced configuration
--
-- NOTE: Editing not recommended unless you know what
-- you're doing
-----------------------------------------------------------------
DECLARE
    @targetDialect      NVARCHAR(MAX) = 'mssql',
    @targetPlatform     NVARCHAR(MAX) = 'windows',
    @platformString     NVARCHAR(MAX),
    @targetPackage      NVARCHAR(MAX) = 'packify';

DECLARE
    @runPlatformCheck   BIT           = 1;

SET @platformString = CONCAT(@targetDialect, '/', @targetPlatform);

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
SET XACT_ABORT ON;

DECLARE
    @indent NVARCHAR(MAX) = '    ',
    @hrule  NVARCHAR(MAX) = REPLICATE('=', 120);

-- global error message and error number variables
DECLARE
    @errorMessage NVARCHAR(MAX),
    @errorNumber INT;

DECLARE @identifiedPlatform NVARCHAR(MAX) = (
    SELECT TOP 1
        LOWER([host_platform])
    FROM
        sys.dm_os_host_info
);
IF @runPlatformCheck = 1 AND @identifiedPlatform != @targetPlatform BEGIN
    SET @errorMessage = CONCAT(
        'Installation script is running on the ',
        @identifiedPlatform,
        ' platform but the target platform is ',
        @targetPlatform
    );
    SET @errorNumber = 99920;

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;
PRINT 'Target platform:'
PRINT CONCAT(@indent, @platformString);

-- initiate a global transaction for this installation
BEGIN TRANSACTION [PackifyInstallation];

-----------------------------------------------------------------
-- Ensure that OLE automation procedures and advanced
-- options are enabled
-----------------------------------------------------------------
BEGIN TRY
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
END TRY
BEGIN CATCH
    SET @errorNumber = 99930;
    SET @errorMessage = CONCAT(
        'Failed updating server configuration (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;

-----------------------------------------------------------------
-- Fetch the packify installation script from the remote
-- repository
-----------------------------------------------------------------
BEGIN TRY
    -- issue an HTTP GET request for the repository.json file
    DECLARE @repositoryJsonPath NVARCHAR(MAX) = CONCAT(
        @packageRepoURL, '/',
        @installBranch, '/',
        'repository.json'
    );
    DECLARE @dynamicQuery NVARCHAR(MAX) = REPLACE(
        @queryHttpGet,
        '?',
        REPLACE(@repositoryJsonPath, '''', '''''')
    );
    DECLARE @repositoryJson NVARCHAR(MAX);
    EXEC sp_executesql
        @dynamicQuery,
        N'@responseOut NVARCHAR(MAX) OUTPUT',
        @responseOut = @repositoryJson OUTPUT;

    -- extract repository details from what was returned
    DECLARE
        @repositoryName         NVARCHAR(MAX),
        @repositoryDescription  NVARCHAR(MAX),
        @endpointsJson          NVARCHAR(MAX);
    SELECT
        @repositoryName         = [name],
        @repositoryDescription  = [description],
        @endpointsJson          = [endpoints]
    FROM (
        SELECT
            [key],
            [value]
        FROM
            OPENJSON(@repositoryJson)
    ) AS a
    PIVOT (
        MAX([value])
        FOR [key] IN (
            [name],
            [description],
            [endpoints]
        )
    ) AS PivotTable;

    PRINT 'Installation target repo:';
    PRINT CONCAT(
        @indent,
        @repositoryName,
        ' (', @repositoryDescription, ')'
    );

    -- get the endpoints for requesting a directory listing as well
    -- as retrieving the raw contents of a file
    DECLARE
        @listingUrl NVARCHAR(MAX),
        @rawFileUrl NVARCHAR(MAX);
    SELECT
        @listingUrl = [listing],
        @rawFileUrl = [raw_file]
    FROM (
        SELECT
            [key],
            [value]
        FROM
            OPENJSON(@endpointsJson)
    ) AS a
    PIVOT (
        MAX([value])
        FOR [key] IN ([listing], [raw_file])
    ) AS PivotTable;

    -- fetch a directory listing from the remote repository
    SET @dynamicQuery = REPLACE(
        @queryHttpGet,
        '?',
        REPLACE(@listingUrl, '''', '''''')
    );
    DECLARE @listingJson NVARCHAR(MAX);
    EXEC sp_executesql
        @dynamicQuery,
        N'@responseOut NVARCHAR(MAX) OUTPUT',
        @responseOut = @listingJson OUTPUT;
END TRY
BEGIN CATCH
    SET @errorNumber = 99940;
    SET @errorMessage = CONCAT(
        'Failed getting details for remote repository (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;

-- check that the request didn't fail
IF (
    SELECT
        COUNT(*)
    FROM
        OPENJSON(@listingJson)
    WHERE
        [key] = 'message'
) != 0 BEGIN
    SET @errorMessage = CONCAT(
        'Failed to retrieve directory listing from remote repository (',
        (
            SELECT TOP 1
                [value]
            FROM
                OPENJSON(@listingJson)
            WHERE
                [key] = 'message'
        ),
        ')'
    );
    SET @errorNumber = 99950;

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;

-- parse the incoming json into a directory listing
DECLARE @tbvDirectoryListing TABLE (
    [filepath] NVARCHAR(MAX)
);
INSERT INTO
    @tbvDirectoryListing
SELECT DISTINCT
    JSON_VALUE([value], '$.path')
FROM
    OPENJSON(@listingJson, '$.tree');

-- get the latest version number of the packify package in the repo
--
-- NOTE: we're assuming that the version specifier will always be
-- a.b.c here. this will need to be changed if it's not
BEGIN TRY
    DECLARE @tbvAllVersions TABLE (
        [Rank]      INT,
        [Version]   NVARCHAR(MAX)
    );
    WITH cteAllVersionsRanked AS (
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    [MajorVersion] DESC,
                    [MinorVersion] DESC
            ) AS [Rank],
            *
        FROM (
            SELECT
                [Version],
                CAST(
                    LEFT(
                        [Version],
                        CHARINDEX(
                            '.', [Version]
                        ) - 1
                    ) AS INT
                ) AS MajorVersion,
                CAST(
                    RIGHT(
                        [Version],
                        LEN([Version]) - CHARINDEX(
                            '.', [Version]
                        )
                    ) AS FLOAT
                ) AS MinorVersion
            FROM (
                SELECT
                    RIGHT(
                        [filepath],
                        CHARINDEX(
                            '/',
                            REVERSE([filepath])
                        ) - 1
                    ) AS Version
                FROM
                    @tbvDirectoryListing
                WHERE
                    [filepath] LIKE CONCAT('packages/', @targetPackage, '/%')
                    AND [filepath] NOT LIKE CONCAT('packages/', @targetPackage, '/%/%')
            ) AS a
        ) AS b
    )
    INSERT INTO
        @tbvAllVersions
    SELECT
        [Rank],
        [Version]
    FROM
        cteAllVersionsRanked;

    -- find the latest packify version that supports our platform
    SET @index = 1;
    DECLARE @targetVersion NVARCHAR(MAX) = NULL;
    WHILE @index <= (
        SELECT
            MAX([Rank])
        FROM
            @tbvAllVersions
    ) BEGIN
        -- get the current version in the ranking
        DECLARE @currentVersion NVARCHAR(MAX) = (
            SELECT
                [Version]
            FROM
                @tbvAllVersions
            WHERE
                [Rank] = @index
        );

        -- build the local path for the install target
        DECLARE @localPackagePath NVARCHAR(MAX) = CONCAT(
            'packages/', @targetPackage, '/',
            @currentVersion, '/',
            @platformString
        );

        -- see if the current version supports our platform
        IF EXISTS (
            SELECT
                *
            FROM
                @tbvDirectoryListing
            WHERE
                [filepath] = @localPackagePath
        ) BEGIN
            SET @targetVersion = @currentVersion;
            BREAK;
        END;

        -- go to the next ranked version
        SET @index = @index + 1;
    END;
END TRY
BEGIN CATCH
    SET @errorNumber = 99960;
    SET @errorMessage = CONCAT(
        'Failed getting package version details from remote repository (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;

-- check that we actually found a version to install
IF @targetVersion IS NULL BEGIN
    SET @errorNumber = 99970;
    SET @errorMessage = CONCAT(
        'Failed to find a ', @targetPackage, ' version that supports the ',
        @platformString,
        ' platform'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;
PRINT 'Found supported version:';
PRINT CONCAT(
    @indent,
    @targetPackage, ' ',
    @targetVersion
);

-- build up the local path to the packify package.json file in the repo
-- and request it
BEGIN TRY
    DECLARE @packagePath NVARCHAR(MAX) = CONCAT(
        'packages/',
        @targetPackage, '/',
        @targetVersion, '/',
        @platformString, '/'
    );
    DECLARE @packageJsonPath NVARCHAR(MAX) = CONCAT(
        @packagePath,
        'package.json'
    );
    SET @dynamicQuery = REPLACE(
        @queryHttpGet,
        '?',
        REPLACE(
            REPLACE(
                @rawFileUrl,
                '%',
                @packageJsonPath
            ),
            '''',
            ''''''
        )
    );
    DECLARE @packageJson NVARCHAR(MAX);
    EXEC sp_executesql
        @dynamicQuery,
        N'@responseOut NVARCHAR(MAX) OUTPUT',
        @responseOut = @packageJson OUTPUT;

    -- get local repo paths for all of the installation files
    DECLARE @tbvInstallPaths TABLE (
        [index] INT,
        [path]  NVARCHAR(MAX)
    );
    INSERT INTO
        @tbvInstallPaths
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY
                [key] ASC
        ) AS [Rank],
        CONCAT(
            @packagePath,
            [value]
        )
    FROM
        OPENJSON(@packageJson, '$.files.installation');
END TRY
BEGIN CATCH
    SET @errorNumber = 99980;
    SET @errorMessage = CONCAT(
        'Failed getting installation for ', @targetPackage, ' package (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;

-- verify that the packify package is instance scoped
DECLARE @packageScope NVARCHAR(MAX) = (
    SELECT
        LOWER([value])
    FROM
        OPENJSON(@packageJson)
    WHERE
        [key] = 'scope'
);
IF @packageScope != 'instance' BEGIN
    SET @errorNumber = 99985;
    SET @errorMessage = CONCAT(
        @targetPackage, ' ', @targetVersion,
        ' has scope of ''', @packageScope, ''', not ''instance'''
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;

-- get/validate the database parameter spec (and default value if needed)
BEGIN TRY
    DECLARE
        @databaseParamMethod    NVARCHAR(MAX),
        @databaseParamValue     NVARCHAR(MAX),
        @databaseParamDefault   NVARCHAR(MAX);
    SELECT
        @databaseParamMethod    = [method],
        @databaseParamValue     = [value],
        @databaseParamDefault   = [default]
    FROM (
        SELECT
            [key],
            [value] AS [data]
        FROM
            OPENJSON(@packageJson, '$.parameters.targets.database')
    ) AS a
    PIVOT (
        MAX([data])
        FOR [key] IN (
            [method],
            [value],
            [default]
        )
    ) AS PivotTable;
END TRY
BEGIN CATCH
    SET @errorNumber = 99986;
    SET @errorMessage = CONCAT(
        'Failed getting database parameter specification (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;
IF @databaseParamMethod != 'substitution' BEGIN
    SET @errorNumber = 99987;
    SET @errorMessage = CONCAT(
        'Invalid database parameter method ''',
        @databaseParamMethod,
        ''' for ', @targetPackage, ' ', @targetVersion
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END;
IF @targetDatabase IS NULL BEGIN
    SET @targetDatabase = @databaseParamDefault;
END;

-- loop over all of the relative paths for installation files, issue
-- GET requests for them, then execute all of the results
BEGIN TRY
    PRINT @hrule;

    SET @index = 1;
    WHILE @index <= (
        SELECT
            MAX([index])
        FROM
            @tbvInstallPaths
    ) BEGIN
        -- get the current relative filepath
        DECLARE @relativePath NVARCHAR(MAX) = (
            SELECT
                [path]
            FROM
                @tbvInstallPaths
            WHERE
                [index] = @index
        );

        -- convert the relative path to a full url
        DECLARE @fullPath NVARCHAR(MAX) = REPLACE(
            @rawFileUrl,
            '%',
            REPLACE(@relativePath, '''', '''''')
        );

        -- issue a request for the full url and get the results
        DECLARE @remoteSource NVARCHAR(MAX);
        SET @dynamicQuery = REPLACE(
            @queryHttpGet,
            '?',
            @fullPath
        );
        EXEC sp_executesql
            @dynamicQuery,
            N'@responseOut NVARCHAR(MAX) OUTPUT',
            @responseOut = @remoteSource OUTPUT;
        
        -- perform the database parameter substitution
        SET @remoteSource = REPLACE(
            @remoteSource,
            @databaseParamValue,
            @targetDatabase
        );

        -- execute the contents of the remote file
        EXEC sp_executesql
            @remoteSource;

        -- go to the next path
        SET @index = @index + 1;
    END;
END TRY
BEGIN CATCH
    SET @errorNumber = 99990;
    SET @errorMessage = CONCAT(
        'Failed during installation of ', @targetPackage, ' package (',
        ERROR_MESSAGE(),
        ')'
    );

    THROW
        @errorNumber,
        @errorMessage,
        1;
END CATCH;

-- on success commit the global transaction for installation
COMMIT;
PRINT @hrule;
PRINT CONCAT(
    'Successfully installed ',
    @targetPackage, ' ',
    @targetVersion
);
