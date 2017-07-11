IF OBJECT_ID(N'external_PrepareStatusReport', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_PrepareStatusReport
GO

CREATE PROCEDURE dbo.external_PrepareStatusReport (
    @boxId NVARCHAR(MAX),
    @state NVARCHAR(MAX),
    @description NVARCHAR(MAX),
	@error NVARCHAR(MAX) = NULL)
AS
/*
    Формирование статусного сообщения в ответ на входяжее сообщение
	На входе ожидается таблица #Messages   

	SELECT 
		n.value('@id', 'NVARCHAR(MAX)') AS 'msgId',
		n.value('interchangeHeader[1]/sender[1]', 'NVARCHAR(MAX)') AS 'senderGLN',
		n.value('interchangeHeader[1]/recipient[1]', 'NVARCHAR(MAX)') AS 'recipientGLN', 
		n.value('interchangeHeader[1]/documentType[1]', 'NVARCHAR(MAX)') AS 'documentType', 
		n.value('orderResponse[1]/@number', 'NVARCHAR(MAX)') AS 'msg_number',
		n.value('orderResponse[1]/@date', 'NVARCHAR(MAX)') AS 'msg_date',
		n.value('orderResponse[1]/@status', 'NVARCHAR(MAX)') AS 'msg_status',
		n.value('orderResponse[1]/originOrder[1]/@number', 'NVARCHAR(MAX)') AS 'originOrder_number',
		n.value('orderResponse[1]/originOrder[1]/@date', 'NVARCHAR(MAX)') AS 'originOrder_date'
	INTO #Messages
	FROM @eDIMessage.nodes('/eDIMessage') t(n)
*/

DECLARE 
	 @msg_Id UNIQUEIDENTIFIER,
	 @msg_Date DATETIME,
	 @Request XML

SET @Request = (
	SELECT 
		GETDATE() N'reportDateTime'
		,senderGLN N'reportRecipient'
		,msgId N'reportItem/messageId'
		,msgId N'reportItem/documentId'
		,senderGLN N'reportItem/messageSender'
		,recipientGLN N'reportItem/messageRecepient'
		,documentType N'reportItem/documentType'
		,msg_number N'reportItem/documentNumber'
		,msg_date N'reportItem/documentDate'
		,GETDATE() N'reportItem/statusItem/dateTime'
		,'Checking' N'reportItem/statusItem/stage'
		,@state N'reportItem/statusItem/state'
		,@description N'reportItem/statusItem/description'
		,@error N'reportItem/statusItem/error'
    FROM #Messages
	FOR XML PATH(N'statusReport'), TYPE
)

SELECT @msg_Id = NEWID(), @msg_Date = GETDATE()

INSERT INTO KonturEDI.dbo.edi_Messages (msg_Id, msg_boxId, msg_Date, msg_RequestXML, msg_doc_ID, msg_doc_Name, msg_doc_Date, msg_doc_Type)
VALUES (@msg_Id, @boxId, @msg_Date, @Request, NULL, NULL, NULL, 'StatusMessage')
