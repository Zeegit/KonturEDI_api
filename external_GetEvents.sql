IF OBJECT_ID('external_GetEvents', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_GetEvents
GO

CREATE PROCEDURE dbo.external_GetEvents
WITH EXECUTE AS OWNER
AS

DECLARE 
	@BoxId NVARCHAR(MAX),
	@LastEventId NVARCHAR(MAX),

	@ActionURL NVARCHAR(MAX), 
	@Response NVARCHAR(MAX), 
	@ResponseXML XML

DECLARE c_boxes CURSOR FOR
	SELECT BoxId, LastEventId
	FROM KonturEDI.dbo.edi_Boxes
	FOR UPDATE OF LastEventId

OPEN c_boxes
FETCH c_boxes INTO @BoxId, @LastEventId

WHILE @@FETCH_STATUS = 0 BEGIN
	SELECT @Response = NULL, @ResponseXML = NULL

	SET @ActionURL = '/V1/Messages/GetEvents?boxId='+CONVERT(NVARCHAR(50), @BoxId)
	IF @LastEventId IS NOT NULL 
		SET @ActionURL = @ActionURL+'&exclusiveEventId='+CONVERT(NVARCHAR(50), @LastEventId)

	EXEC external_KonturExec @ActionURL, 'GET', NULL, @Response OUTPUT
	SET @ResponseXML = dbo.fn_json2xml(@response) 

	INSERT INTO KonturEDI.dbo.edi_InboxMessages (BoxId, PartyId, EventId, EventDateTime, EventType, Event)	
	SELECT 
		n.value('BoxId[1]','nvarchar(max)') AS [BoxId],
		n.value('PartyId[1]','nvarchar(max)') AS [PartyId],
		n.value('EventId[1]','nvarchar(max)') AS [EventId],
		n.value('EventDateTime[1]','nvarchar(max)') AS [EventDateTime],
		n.value('EventType[1]','nvarchar(max)') AS [EventType],
		n.query('.') AS [Event]
	FROM @ResponseXML.nodes('/root/Events') t(n)
	WHERE n.value('EventId[1]','nvarchar(max)') IS NOT NULL

	UPDATE KonturEDI.dbo.edi_Boxes
	SET LastEventId = @ResponseXML.value('(/root/LastEventId)[1]', 'NVARCHAR(MAX)')
	WHERE CURRENT OF c_boxes
   
    FETCH c_boxes INTO @BoxId, @LastEventId
END

CLOSE c_boxes
DEALLOCATE c_boxes