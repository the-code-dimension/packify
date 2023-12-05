
USE [Database!];
GO

DECLARE @targetLogin NVARCHAR(4000) = 'PackifyLogin';
EXECUTE AS LOGIN = @targetLogin;
GO

    CREATE TYPE HTTP.HeaderList AS TABLE (
        [Name]          NVARCHAR(MAX) NOT NULL,
        [Value]         NVARCHAR(MAX) NOT NULL
    );
    GO

    CREATE TYPE HTTP.JsonType
    FROM NVARCHAR(MAX) NOT NULL;
    GO

    CREATE TYPE HTTP.Response AS TABLE (
        [StatusCode]    INT NOT NULL,
        [StatusText]    NVARCHAR(MAX) NOT NULL,
        [Headers]       HTTP.JsonType,
        [Body]          NVARCHAR(MAX) NOT NULL
    );
    GO

    -- performs a GET request to a provided remote URL
    CREATE PROCEDURE HTTP.Get
        @Uri            NVARCHAR(MAX),
        @Body           NVARCHAR(4000)              = NULL,
        @Timeout        INT,
        @Headers        HTTP.HeaderList READONLY,
        @ResponseOut    HTTP.JsonType   OUTPUT
    AS BEGIN
        SET NOCOUNT ON;

        DECLARE @OBJECT_TYPE NVARCHAR(400) = 'MSXML2.ServerXMLHTTP';
        DECLARE
            @errorMessage   NVARCHAR(MAX),
            @errorNumber    INT,
            @errorType      NVARCHAR(MAX);

        -- construct the OLE object and verify success
        DECLARE
            @hresult    INT,
            @httpObject INT;
        EXEC @hresult = sp_OACreate
            @OBJECT_TYPE,
            @httpObject OUTPUT;
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_CREATE_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                @OBJECT_TYPE,
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- initiate the GET request
        EXEC @hresult = sp_OAMethod
            @httpObject,
            'open',
            NULL,
            'GET',
            @Uri,
            true;
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_OPEN_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                @OBJECT_TYPE,
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- set all of the GET request headers by cursoring over them
        DECLARE
            @headerName     NVARCHAR(MAX),
            @headerValue    NVARCHAR(MAX);
        DECLARE headerCursor CURSOR FOR
        SELECT
            [Name],
            [Value]
        FROM
            @Headers;

        OPEN headerCursor;
        FETCH NEXT FROM
            headerCursor
        INTO
            @headerName,
            @headerValue;

        WHILE @@FETCH_STATUS = 0 BEGIN
            -- call setRequestHeader() for this header/value pair
            EXEC @hresult = sp_OAMethod
                @httpObject,
                'setRequestHeader',
                NULL,
                @headerName,
                @headerValue;
            IF @hresult != 0 BEGIN
                SET @errorType = 'HTTP_SET_REQ_HEAD_FAILED';

                SET @errorNumber = Config.GetErrorNumber(@errorType);
                SET @errorMessage = FORMATMESSAGE(
                    Config.GetErrorMessage(@errorType),
                    @headerName,
                    @headerValue,
                    @hresult
                );

                THROW
                    @errorNumber,
                    @errorMessage,
                    1;
            END;

            FETCH NEXT FROM
                headerCursor
            INTO
                @headerName,
                @headerValue;
        END;

        -- send the HTTP request asynchronously
        SET @Body = COALESCE(@Body, '');
        EXEC @hresult = sp_OAMethod
            @httpObject,
            'send',
            NULL,
            @Body;
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_SEND_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- wait for a response from the server with the provided timeout
        DECLARE @tbvWaitResult TABLE (
            [WaitResult]    INT
        );
        INSERT INTO
            @tbvWaitResult
        EXEC @hresult = sp_OAMethod
            @httpObject,
            'waitForResponse',
            NULL,
            @Timeout;
        IF (
            SELECT
                [WaitResult]
            FROM
                @tbvWaitResult
        ) = 0 BEGIN
            SET @errorType = 'HTTP_TIMEOUT';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @Timeout
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END ELSE IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_WAIT_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- get the results into an HTTP.Response instance
        DECLARE @responseData AS HTTP.Response;
        DECLARE
            @statusCode     INT,
            @statusText     NVARCHAR(4000),
            @allHeaders     NVARCHAR(MAX),
            @headersJson    HTTP.JsonType,
            @responseBody   NVARCHAR(MAX);
        
        -- get the response status code
        EXEC @hresult = sp_OAGetProperty
            @httpObject,
            'status',
            @statusCode OUTPUT;
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_STATUS_CODE_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- get the response status text
        EXEC @hresult = sp_OAGetProperty
            @httpObject,
            'statusText',
            @statusText OUTPUT;
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_STATUS_TEXT_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- get all of the headers and split them out into a JSON object
        DECLARE @tbvResponseHeaders TABLE (
            [Headers]   NVARCHAR(MAX)
        );
        INSERT INTO
            @tbvResponseHeaders
        EXEC @hresult = sp_OAMethod
            @httpObject,
            'getAllResponseHeaders';
        SET @allHeaders = (
            SELECT TOP 1
                [Headers]
            FROM
                @tbvResponseHeaders
        );
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_GET_ALL_HEADERS_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;

        -- parse all of the headers we received
        SET @headersJson = (
            SELECT
                LEFT([value], CHARINDEX(':', [value]) - 1) AS [Header],
                TRIM(RIGHT([value], LEN([value]) - CHARINDEX(':', [value]))) AS [Value]
            FROM (
                SELECT
                    REPLACE(
                        TRIM([value]),
                        CHAR(13),
                        ''
                    ) AS [value]
                FROM
                    STRING_SPLIT(@allHeaders, CHAR(10))
            ) AS a
            WHERE
                LEN([value]) > 0
            FOR
                JSON PATH
        );

        -- get the response body
        DECLARE @tbvResult TABLE (
            [ResultField]   NVARCHAR(MAX)
        );
        INSERT INTO
            @tbvResult
        EXEC @hresult = sp_OAGetProperty
            @httpObject,
            'responseText';
        IF @hresult != 0 BEGIN
            SET @errorType = 'HTTP_GET_RESPONSE_BODY_FAILED';

            SET @errorNumber = Config.GetErrorNumber(@errorType);
            SET @errorMessage = FORMATMESSAGE(
                Config.GetErrorMessage(@errorType),
                'GET',
                @hresult
            );

            THROW
                @errorNumber,
                @errorMessage,
                1;
        END;
        SELECT
            @responseBody = [ResultField]
        FROM
            @tbvResult;

        INSERT INTO
            @responseData
        VALUES (
            @statusCode,
            @statusText,
            @headersJson,
            @responseBody
        );

        -- destroy the request object
        EXEC @hresult = sp_OADestroy
            @httpObject;
        
        -- return the response as a json object
        SET @ResponseOut = (
            SELECT
                *
            FROM
                @responseData
            FOR
                JSON PATH,
                WITHOUT_ARRAY_WRAPPER
        );
    END;
    GO

    -- converts HTTP response json to a selectable table matching
    -- the schema of HTTP.Response
    CREATE FUNCTION HTTP.ConvertResponse (
        @responseJson   NVARCHAR(MAX)
    ) RETURNS @response TABLE (
        [StatusCode]    INT,
        [StatusText]    NVARCHAR(MAX),
        [Headers]       HTTP.JsonType,
        [Body]          NVARCHAR(MAX)
    ) AS BEGIN
        INSERT INTO
            @response
        SELECT
            *
        FROM (
            SELECT
                [key],
                [value]
            FROM
                OPENJSON(@responseJson)
        ) AS a
        PIVOT (
            MAX([value])
            FOR [key] IN (
                [StatusCode],
                [StatusText],
                [Headers],
                [Body]
            )
        ) AS PivotTable;

        RETURN;
    END;
    GO

REVERT;
