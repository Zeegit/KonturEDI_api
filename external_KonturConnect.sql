SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('external_KonturExec', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_KonturExec

GO

CREATE PROCEDURE dbo.external_KonturExec (

	 @@URL		NVARCHAR(MAX)
	,@@Method varchar(100)
    
	,@@Text		varchar(8000)
	,@@Response	NText	OUTPUT
) AS BEGIN
	DECLARE @BaseURL NVARCHAR(MAX) = ''
	DECLARE @ActionURL NVARCHAR(MAX)
	DECLARE @Authorization VARCHAR(8000)
	DECLARE @konturediauth_api_client_id NVARCHAR(MAX) 
	DECLARE @konturediauth_login NVARCHAR(MAX) 
	DECLARE @konturediauth_password NVARCHAR(MAX)
	DECLARE @konturediauth_token NVARCHAR(MAX)
	DECLARE @HTTPStatus	INT
	DECLARE @IsTokenRequested INT = 0
	DECLARE @r INT

	DECLARE 
	 @ErrMethod		SysName 
	,@ErrSource		SysName 
	,@ErrDescription	SysName 

	Request:

	SET @@Response = NULL;

	SELECT @BaseURL = konturedi_baseURL, @konturediauth_api_client_id = konturediauth_api_client_id, @konturediauth_login = konturediauth_login , @konturediauth_password = konturediauth_password, @konturediauth_token = konturediauth_token 
	FROM KonturEDI.dbo.edi_Settings

	SET @ActionURL  = @BaseURL + @@URL
	-- SELECT @ActionURL 'ActionURL'
	SELECT @Authorization = 
		'KonturEdiAuth '+
		'konturediauth_api_client_id='+ISNULL(@konturediauth_api_client_id, '')+','+
		--'konturediauth_login='+@konturediauth_login+','+
		--'konturediauth_password='+@konturediauth_password+','+
		'konturediauth_token='+ISNULL(@konturediauth_token, '')

	EXEC @R = dbo.external_KonturConnect @ActionURL, @@Method, @Authorization, @@Text, @@Response OUTPUT, @HTTPStatus OUTPUT, @ErrMethod OUTPUT, @ErrSource OUTPUT, @ErrDescription OUTPUT
	-- SELECT @r, @Authorization, @@Response , @HTTPStatus , @ErrMethod , @ErrSource , @ErrDescription 

	IF @R <> 0 BEGIN
		RAISERROR('Ошибка при выполнении метода "%s" в "%s": %s', 18, 1, @ErrMethod, @ErrSource, @ErrDescription)
		RETURN	@@Error
	END
	
	IF @HTTPStatus = 200 BEGIN
	  RETURN 0
	END
	ELSE IF @HTTPStatus = 401 AND @IsTokenRequested = 0 BEGIN
		-- Презапрос токена
		SET @ActionURL  = @BaseURL + '/v1/Authenticate'
		
		SELECT @@Response = NULL, @HTTPStatus = NULL
		SELECT @Authorization = 
			'KonturEdiAuth '+
			'konturediauth_api_client_id='+ISNULL(@konturediauth_api_client_id, '')+','+
			'konturediauth_login='+ISNULL(@konturediauth_login, '')+','+
			'konturediauth_password='+ISNULL(@konturediauth_password, '')
		
		EXEC dbo.external_KonturConnect @ActionURL, 'POST', @Authorization, '', @@Response OUTPUT, @HTTPStatus OUTPUT, @ErrMethod OUTPUT, @ErrSource OUTPUT, @ErrDescription OUTPUT 
		
		-- Запросили токен
		SET @IsTokenRequested = 1
		
		IF @R <> 0 BEGIN
			RAISERROR('Ошибка при выполнении метода "%s" в "%s": %s', 18, 1, @ErrMethod, @ErrSource, @ErrDescription)
			RETURN	@@Error
		END
		
		IF @HTTPStatus = 200 BEGIN
			-- Обновление токена
		    UPDATE KonturEDI.dbo.edi_Settings
			SET konturediauth_token = @@Response
			WHERE 1=1

			GOTO Request
		END
		ELSE BEGIN
			EXEC tpsys_RaiseError 50001, 'Ошибка запроса токена'
			RETURN @@Error
		END

	END
	ELSE BEGIN
		EXEC tpsys_RaiseError 50001, 'Ошибка выполнеия запроса'
		RETURN	@@Error
	END

	RETURN 0
END

GO

IF OBJECT_ID('external_KonturConnect', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_KonturConnect

GO

CREATE PROCEDURE dbo.external_KonturConnect (
	 @@URL		NVARCHAR(MAX)
	,@@Method varchar(100)
    ,@@Authorization		varchar(8000)
	,@@Text		varchar(8000)
	,@@Response	NText	OUTPUT
	,@HTTPStatus	Int OUTPUT
	,@ErrMethod		SysName OUTPUT
	,@ErrSource		SysName OUTPUT
	,@ErrDescription	SysName OUTPUT
) AS BEGIN
	-- Для установки Proxy воспользуйтесь "proxycfg -u"
	DECLARE	 
		 @OLEObject		Int
		,@ErrCode		Int
		

	EXEC @ErrCode = sys.sp_OACreate 'MSXML2.ServerXMLHTTP', @OLEObject OUT
	IF (@ErrCode = 0) BEGIN
		EXEC @ErrCode = sys.sp_OAMethod @OLEObject ,'Open',NULL ,@@Method ,@@URL ,'false'		IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'open'	GOTO Error END
		EXEC @ErrCode = sys.sp_OAMethod @OLEObject, 'setRequestHeader', null, 'Content-Type', 'text/xml; charset=utf-8' IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'setRequestHeader'	GOTO Error END
		EXEC @ErrCode = sys.sp_OAMethod @OLEObject, 'setRequestHeader', null, 'Authorization', @@Authorization IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'setRequestHeader'	GOTO Error END
		EXEC @ErrCode = sys.sp_OAMethod @OLEObject, 'setOption', null, 2 ,13056				IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'setOption'	GOTO Error END
		EXEC @ErrCode = sys.sp_OAMethod @OLEObject ,'send',NULL ,@@Text						IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'send'	GOTO Error END
		EXEC @ErrCode = sys.sp_OAGetProperty @OLEObject ,'status' ,@HTTPStatus OUT			IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'status'	GOTO Error END
		
		-- testr
		EXEC sys.sp_OAGetProperty @OLEObject ,'responseText'

		IF (@HTTPStatus = 200) BEGIN
			DECLARE	@Response TABLE ( Response NText )
			INSERT	@Response
			EXEC @ErrCode = sys.sp_OAGetProperty @OLEObject ,'responseText'					IF (@ErrCode != 0) BEGIN SET @ErrMethod = 'responseText' GOTO Error END
			SELECT @@Response = Response FROM @Response
			
		END /*ELSE 
			SELECT	 
				 @ErrMethod	= 'send'
				,@ErrSource	= 'MSXML2.ServerXMLHTTP'
				,@ErrDescription= 'Ошибочный статус HTTP ответа "' + Convert(VarChar,@HTTPStatus) + '"'*/
		
		GOTO Destroy
		
		Error:	
		EXEC @ErrCode = sys.sp_OAGetErrorInfo @OLEObject ,@ErrSource OUT ,@ErrDescription OUT

		Destroy:
		EXEC @ErrCode = sys.sp_OADestroy @OLEObject

		/*IF (@ErrSource IS NOT NULL) BEGIN
			RAISERROR('Ошибка при выполнении метода "%s" в "%s": %s',18,1,@ErrMethod,@ErrSource,@ErrDescription)
			RETURN	@@Error
		END*/

		IF (@ErrSource IS NOT NULL) 
			RETURN	1
		ELSE
			RETURN 0

	END ELSE BEGIN
		/*RAISERROR('Ошибка при создании OLE объекта "MSXML2.ServerXMLHTTP"',18,1)
		RETURN	@@Error*/
		SELECT	 
				 @ErrMethod	= 'create'
				,@ErrSource	= 'MSXML2.ServerXMLHTTP'
				,@ErrDescription= 'Ошибка при создании OLE объекта "MSXML2.ServerXMLHTTP"'

		RETURN 1
	END
END

GO
