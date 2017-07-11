
		/*SELECT
			@MessageId = n.value('MessageId[1]','nvarchar(max)'),
			@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)'),

			@MessageFormat = n.value('DocumentCirculationId[1]','nvarchar(max)'),
			@DocumentType = n.value('DocumentDetails/DocumentType[1]','nvarchar(max)')
		FROM @Event.nodes('/Events/EventContent/InboxMessageMeta') t(n)
		

		-- Поиск документа
		SELECT @doc_ID = doc_ID, @doc_Type = doc_Type
		FROM KonturEDI.dbo.edi_Messages 
		WHERE MessageId = @MessageId AND DocumentCirculationId = @DocumentCirculationId   
	
		IF (@doc_ID IS NULL) OR (@doc_Type IS NULL) BEGIN 
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Не найден документ "'+ISNULL(CONVERT(NVARCHAR(MAX), @doc_ID), '<null>')+'" с типом "'++ISNULL(@doc_Type, '<null>')+'"')
		END 
		ELSE BEGIN
		
			UPDATE KonturEDI.dbo.edi_InboxMessages 
			SET MessageId = @MessageId,
				DocumentCirculationId = @DocumentCirculationId,
				IsProcessed = 0
			WHERE CURRENT OF ct

			EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Сообщение разобрано (NewInboxMessage)', @edt	
		END*/
	END
	ELSE IF @EventType = 'RecognizeMessage' BEGIN
		-- Информация о новом событии - разборе исходящего сообщения и успешном определении его основных параметров (формат, тип, отправитель и получатель). Соответствует BoxEventType = RecognizeMessage.
		SELECT
			@MessageId = n.value('MessageId[1]','nvarchar(max)'),
			@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)')
		FROM @Event.nodes('/Events/EventContent/OutboxMessageMeta') t(n)

		-- Поиск документа
		SELECT @doc_ID = msg_doc_Type, @doc_Type = msg_doc_Type
		FROM KonturEDI.dbo.edi_Messages 
		WHERE MessageId = @MessageId AND DocumentCirculationId = @DocumentCirculationId   
	
		IF (@doc_ID IS NULL) OR (@doc_Type IS NULL) BEGIN 
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Не найден документ "'+ISNULL(CONVERT(NVARCHAR(MAX), @doc_ID), '<null>')+'" с типом "'++ISNULL(@doc_Type, '<null>')+'"')

			GOTO NextStep
		END
		
		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET MessageId = @MessageId,
			DocumentCirculationId = @DocumentCirculationId,
			IsProcessed = 0
		WHERE CURRENT OF ct

		EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Сообщение разобрано (RecognizeMessage)', @edt
	END
	ELSE IF @EventType = 'MessageDelivered' BEGIN
		SELECT
			@MessageId = n.value('MessageId[1]','nvarchar(max)'),
			@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)')
		FROM @Event.nodes('/Events/EventContent/OutboxMessageMeta') t(n)

		-- Поиск документа
		SELECT @doc_ID = msg_doc_ID, @doc_Type = msg_doc_Type
		FROM KonturEDI.dbo.edi_Messages 
		WHERE MessageId = @MessageId AND DocumentCirculationId = @DocumentCirculationId   
	
		IF (@doc_ID IS NULL) OR (@doc_Type IS NULL) BEGIN 
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Не найден документ "'+ISNULL(CONVERT(NVARCHAR(MAX), @doc_ID), '<null>')+'" с типом "'++ISNULL(@doc_Type, '<null>')+'"')

			GOTO NextStep
		END
		
		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET MessageId = @MessageId,
			DocumentCirculationId = @DocumentCirculationId,
			IsProcessed = 0
		WHERE CURRENT OF ct

		EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Сообщение доставлено', @edt
	END
	ELSE IF @EventType = 'MessageUndelivered' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'MessageReadByPartner' BEGIN
		-- Информация о новом событии - прочтении исходящего сообщения контрагентом. Соответствует BoxEventType = MessageReadByPartner.
		SELECT
			@MessageId = n.value('MessageId[1]','nvarchar(max)'),
			@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)')
		FROM @Event.nodes('/Events/EventContent/OutboxMessageMeta') t(n)

		-- Поиск документа
		SELECT @doc_ID = msg_doc_ID, @doc_Type = msg_doc_Type
		FROM KonturEDI.dbo.edi_Messages 
		WHERE MessageId = @MessageId AND DocumentCirculationId = @DocumentCirculationId   
	
		IF (@doc_ID IS NULL) OR (@doc_Type IS NULL) BEGIN 
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Не найден документ "'+ISNULL(CONVERT(NVARCHAR(MAX), @doc_ID), '<null>')+'" с типом "'++ISNULL(@doc_Type, '<null>')+'"')

			GOTO NextStep
		END
		
		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET MessageId = @MessageId,
			DocumentCirculationId = @DocumentCirculationId,
			IsProcessed = 0
		WHERE CURRENT OF ct

		EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Сообщение прочитано получателем (MessageReadByPartner)', @edt	
	END
	ELSE IF @EventType IN ('MessageCheckingOk',  'MessageCheckingFail') BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DraftOfDocumentPackagePostedIntoDiadoc' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DraftOfDocumentPackageSignedByMe' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DraftOfDocumentPackageDeletedFromDiadoc' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DraftOfDocumentPackageSignedBySender' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'ReceivedDiadocRoamingError' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DiadocRevocationAccepted' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	ELSE IF @EventType = 'DiadocRevocationAcceptedForBuyer' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END
	IF @EventType = 'Unknown' BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Событие "'+@EventType+'" не поддерживается')
	END	
	ELSE BEGIN 
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Неизвестное событие  "'+@EventType+'"')

		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET
			IsProcessed = 0
		WHERE CURRENT OF ct
	END




-- Список событий

--DECLARE ct CURSOR FOR
    --SELECT fname, @ReportsPath+'\'+fname AS full_fname FROM @t

/*
------------------------------------------
DECLARE @TRANCOUNT INT

DECLARE @doc_ID UNIQUEIDENTIFIER, @doc_Type NVARCHAR(100), @messageId UNIQUEIDENTIFIER
DECLARE @dateTime NVARCHAR(MAX), @description NVARCHAR(MAX)

-- 
DECLARE @t TABLE (fname NVARCHAR(255), d INT, f INT)
DECLARE @fname NVARCHAR(255), @full_fname NVARCHAR(255),  @xml xml, @sql NVARCHAR(MAX), @cmd NVARCHAR(255), @r INT

-- Настройки путей
DECLARE @ReportsPath NVARCHAR(255)
SELECT @ReportsPath = ReportsPath FROM  KonturEDI.dbo.edi_Settings

-- получаем список файлов для закачки (заказы)
INSERT INTO @t (fname, d, f) EXEC xp_dirtree @ReportsPath, 1, 1

--бежим по списку
DECLARE ct CURSOR FOR
    SELECT fname, @ReportsPath+'\'+fname AS full_fname FROM @t

OPEN ct
FETCH ct INTO @fname, @full_fname

WHILE @@FETCH_STATUS = 0 BEGIN
  
    SET @xml = NULL
    SET @SQL = 'SELECT @xml = CAST(x.data as XML) FROM OPENROWSET(BULK '+QUOTENAME(@full_fname, CHAR(39))+' , SINGLE_BLOB) AS x(data)'
    EXEC sp_executesql @SQL, N'@xml xml out', @xml = @xml out
 
    IF OBJECT_ID('tempdb..#Messages') IS NOT NULL DROP TABLE #Messages 
 
    SET @TRANCOUNT = @@TRANCOUNT
    IF @TRANCOUNT = 0
	    BEGIN TRAN external_ImportReports
    ELSE
 	    SAVE TRAN external_ImportReports

    BEGIN TRY
	  -- Сообщение
      SELECT 
	      n.value('../messageId[1]', 'NVARCHAR(MAX)') AS 'messageId',
          n.value('dateTime[1]', 'NVARCHAR(MAX)') AS 'dateTime',
          n.value('description[1]', 'NVARCHAR(MAX)') AS 'description'
      INTO #Messages
      FROM @xml.nodes('/statusReport/reportItem/statusItem') t(n)
	
      -- На какое сообщение пришел ответ
      SELECT TOP 1 @messageId = messageId, @dateTime = dateTime, @description = description FROM #Messages
	
      -- Внутренний ID документа в Тиллипад
	  SELECT @doc_ID = doc_ID, @doc_Type = doc_Type FROM KonturEDI.dbo.edi_Messages WHERE message_Id =  @messageId 
	
	  IF @doc_ID IS NOT NULL 
	      EXEC external_UpdateDocStatus @doc_ID, @doc_Type, @description, @dateTime

	  -- UPDATE KonturEDI.dbo.edi_Messages SET IsProcessed = 1 WHERE messageId = @messageId
	  -- Лог
	  INSERT INTO KonturEDI.dbo.edi_MessagesLog (log_XML, log_Text, message_ID, doc_ID) 
	  VALUES (@xml, 'Получено статусное сообщение', @messageId, @doc_ID)

	  -- Удалим оригинальное сообщение
	  IF @messageId IS NOT NULL BEGIN
	      SELECT @cmd = 'DEL /f /q "'+ message_FileName +'"' FROM KonturEDI.dbo.edi_Messages WHERE message_Id =  @messageId 
		  EXEC @R = master..xp_cmdshell @cmd, NO_OUTPUT
	  END
	  -- Сообщение обработано, удаляем
      SET @cmd = 'DEL /f /q "'+ @full_fname+'"'
      EXEC @R = master..xp_cmdshell @cmd, NO_OUTPUT
	
	  IF @TRANCOUNT = 0 
  	      COMMIT TRAN
    END TRY
    BEGIN CATCH
        -- Ошибка загрузки файла, пишем ошибку приема
	    IF @@TRANCOUNT > 0
	        IF (XACT_STATE()) = -1
	            ROLLBACK
	        ELSE
	            ROLLBACK TRAN external_ImportReports
  	    IF @TRANCOUNT > @@TRANCOUNT
	        BEGIN TRAN

	    -- Ошибки в таблицу, обработаем потом
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage)
	    SELECT 'ImportReports', ERROR_NUMBER(), ERROR_MESSAGE()
	     -- EXEC tpsys_ReraiseError
    END CATCH
  
    IF OBJECT_ID('tempdb..#Messages') IS NOT NULL DROP TABLE #Messages 
    FETCH ct INTO @fname, @full_fname
END

CLOSE ct
DEALLOCATE ct
*/
