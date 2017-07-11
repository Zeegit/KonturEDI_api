IF OBJECT_ID(N'external_ExportMessages', 'P') IS NOT NULL
  DROP PROCEDURE dbo.external_ExportMessages
GO

CREATE PROCEDURE dbo.external_ExportMessages
AS

DECLARE
	@msg_Id UNIQUEIDENTIFIER,
	@msg_boxId NVARCHAR(MAX),
	@msg_RequestXML XML,
	@msg_doc_ID UNIQUEIDENTIFIER,
	@msg_doc_Type NVARCHAR(MAX),

	@MessageText NVARCHAR(MAX),
	@ActionURL NVARCHAR(MAX),
	@Response NVARCHAR(MAX),
	@ResponseXML XML, 
	@MessageId NVARCHAR(MAX), 
	@DocumentCirculationId NVARCHAR(MAX)

-- Список сообщений для отправки
DECLARE ct CURSOR FOR
    SELECT msg_Id, msg_boxId, msg_RequestXML, msg_doc_ID, msg_doc_Type
	FROM KonturEDI.dbo.edi_Messages 
	WHERE msg_IsProcessed = 0
	ORDER BY msg_Date
	FOR UPDATE 

OPEN ct
FETCH ct INTO @msg_Id, @msg_boxId, @msg_RequestXML, @msg_doc_ID, @msg_doc_Type

WHILE @@FETCH_STATUS = 0 BEGIN 
	SELECT @Response = NULL, @ResponseXML = NULL, @MessageId = NULL, @DocumentCirculationId = NULL

	SELECT 
		 @ActionURL = '/V1/Messages/SendMessage?boxId='+@msg_boxId
		,@MessageText = CONVERT(NVARCHAR(MAX), @msg_RequestXML)

	EXEC external_KonturExec  @ActionURL, 'POST', @MessageText, @Response OUTPUT
	SET @ResponseXML = dbo.fn_json2xml(@Response) 
	
	SELECT
		@MessageId = n.value('MessageId[1]','nvarchar(max)'),
		@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)')
	FROM @ResponseXML.nodes('/root') t(n)

		-- Статус отправлен
	UPDATE KonturEDI.dbo.edi_Messages 
	SET msg_IsProcessed = 1, 
		msg_ResponseText = @Response,
		msg_ResponseXML = @ResponseXML,
		MessageId = @MessageId,
		DocumentCirculationId = @DocumentCirculationId
	WHERE msg_Id = @msg_Id --CURRENT OF ct

	-- Дополнительный статус документа
	IF @msg_doc_Type IN ('tp_StoreRequests', 'tp_InputDocuments')
	    EXEC external_UpdateDocStatus  @msg_doc_ID, @msg_doc_Type, 'Отправлена поставщику'
	
	-- Лог
	-- INSERT INTO KonturEDI.dbo.edi_MessagesLog (log_XML, log_Text, message_ID, doc_ID)
	-- VALUES (@Result, 'Отправлена заявка поставщику', @message_ID, @doc_ID)

    FETCH ct INTO @msg_Id, @msg_boxId, @msg_RequestXML,  @msg_doc_ID, @msg_doc_Type
END

CLOSE ct
DEALLOCATE ct

