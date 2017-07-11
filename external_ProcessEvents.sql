IF OBJECT_ID('external_ProcessEvents', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_ProcessEvents
GO

CREATE PROCEDURE dbo.external_ProcessEvents
WITH EXECUTE AS OWNER
AS

DECLARE 
	@BoxId NVARCHAR(MAX),
	@PartyId NVARCHAR(MAX),
	@EventId NVARCHAR(MAX),
	@EventDateTime NVARCHAR(MAX),
	@EventType NVARCHAR(MAX),
	@Event XML,
	@MessageId NVARCHAR(MAX),
	@DocumentCirculationId NVARCHAR(MAX),
	@doc_ID UNIQUEIDENTIFIER,
	@doc_Name NVARCHAR(MAX),
	@doc_Type NVARCHAR(MAX),
	@edt DATETIME,
	@MessageFormat NVARCHAR(MAX),
	@DocumentType NVARCHAR(MAX),
	@eDIMessage XML,
	@ActionURL NVARCHAR(MAX),
	@Response NVARCHAR(MAX),
	@ResponseXML XML,
	@StatusText NVARCHAR(MAX)

IF OBJECT_ID('tempdb..#Messages') IS NOT NULL 
	DROP TABLE #Messages 

CREATE TABLE  #Messages (			
	msgId NVARCHAR(MAX),
	senderGLN NVARCHAR(MAX),
	recipientGLN NVARCHAR(MAX), 
	documentType NVARCHAR(MAX), 
	msg_number NVARCHAR(MAX),
	msg_date NVARCHAR(MAX),
	msg_status NVARCHAR(MAX),
	originOrder_number NVARCHAR(MAX),
	originOrder_date NVARCHAR(MAX))

DECLARE
		@strqti_ID uniqueidentifier
	,@strqti_ID_orig uniqueidentifier
	-- ,@strqti_strqt_ID uniqueidentifier
	,@strqti_pitm_ID uniqueidentifier
	,@strqti_meit_ID uniqueidentifier
	,@strqti_strqtist_ID int
	,@strqti_IdentifierCode nvarchar(max) 
	,@strqti_ItemName nvarchar(max) 
	,@strqti_Article nvarchar(max) 
	,@strqti_idtp_ID uniqueidentifier 
	,@strqti_Remains numeric(18, 6) 
	,@strqti_ConsumptionPerDay numeric(18, 6) 
	,@strqti_Volume NUMERIC(18, 6)
	,@strqti_Price numeric(30, 10) 
	,@strqti_Sum numeric(18, 4) 
	,@strqti_VAT numeric(18, 3) 
	,@strqti_SumVAT numeric(18, 4) 
	,@strqti_EditIndex int 
	,@strqti_Comment nvarchar(max) 
	,@strqti_Order int 
	,@meit_Rate numeric(18, 6)
DECLARE
		@status NVARCHAR(MAX)
	,@gtin NVARCHAR(MAX)
	,@internalBuyerCode NVARCHAR(MAX)
	,@internalSupplierCode NVARCHAR(MAX)
	,@serialNumber NVARCHAR(MAX)
	,@orderLineNumber NVARCHAR(MAX)
	,@typeOfUnit NVARCHAR(MAX)
	,@description NVARCHAR(MAX)
	,@comment NVARCHAR(MAX)
	,@orderedQuantity NVARCHAR(MAX)
	,@orderedQuantity_unitOfMeasure NVARCHAR(MAX)
	,@confirmedQuantity NVARCHAR(MAX)
	,@confirmedQuantity_unitOfMeasure NVARCHAR(MAX)
	,@onePlaceQuantity NVARCHAR(MAX)
	,@onePlaceQuantity_unitOfMeasure NVARCHAR(MAX)
	,@expireDate NVARCHAR(MAX)
	,@manufactoringDate NVARCHAR(MAX)
	,@netPrice NVARCHAR(MAX)
	,@netPriceWithVAT NVARCHAR(MAX)
	,@netAmount NVARCHAR(MAX)
	,@exciseDuty NVARCHAR(MAX)
	,@vATRate NVARCHAR(MAX)
	,@vATAmount NVARCHAR(MAX)
	,@amount  NVARCHAR(MAX)
					
DECLARE @idtp_ID_GTIN UNIQUEIDENTIFIER
SELECT @idtp_ID_GTIN = idtp_ID_GTIN FROM KonturEDI.dbo.edi_Settings

DECLARE c_events CURSOR FOR
	SELECT MessageId, BoxId, PartyId, EventId, EventDateTime, EventType, Event 
	FROM KonturEDI.dbo.edi_InboxMessages
	WHERE IsProcessed = 0
	FOR UPDATE -- OF MessageId, DocumentCirculationId, IsProcessed, eDIMessage

OPEN c_events
FETCH c_events INTO @MessageId, @BoxId, @PartyId, @EventId, @EventDateTime, @EventType, @Event

WHILE @@FETCH_STATUS = 0 BEGIN
    -- Unknown, NewOutboxMessage, NewInboxMessage,RecognizeMessage,MessageDelivered,MessageUndelivered,MessageReadByPartner,MessageCheckingOk,MessageCheckingFail,DraftOfDocumentPackagePostedIntoDiadoc,DraftOfDocumentPackageSignedByMe,DraftOfDocumentPackageDeletedFromDiadoc,DraftOfDocumentPackageSignedBySender,ReceivedDiadocRoamingError,DiadocRevocationAccepted,DiadocRevocationAcceptedForBuyer
	SET @edt = CONVERT(DATETIME2, @EventDateTime)
	SET @doc_ID = NULL
	SET @doc_Type = NULL
	SET @doc_Name = NULL

	-- SELECT @MessageId, @BoxId, @PartyId, @EventId, @EventDateTime, @EventType, @Event
	TRUNCATE TABLE #Messages
	
	-- получении входящего сообщения. Соответствует BoxEventType = NewInboxMessage.
	IF @EventType = 'NewInboxMessage' BEGIN
		--- EXEC external_ProcessingNewInboxMessage
		SELECT
			@MessageId = n.value('MessageId[1]','nvarchar(max)'),
			@DocumentCirculationId = n.value('DocumentCirculationId[1]','nvarchar(max)'),
			
			@MessageFormat = n.value('MessageFormat[1]','nvarchar(max)'),
			@DocumentType = UPPER(n.value('(DocumentDetails/DocumentType)[1]','nvarchar(max)'))
		FROM @Event.nodes('/Events/EventContent/InboxMessageMeta') t(n)
		
		IF @MessageFormat <> 'KonturXml' BEGIN
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Формат сообщения "'+ISNULL(@MessageFormat, '<null>')+'" не поддерживается')

			GOTO NextStep
		END

		-- Получение содержимого входящего сообщения.
		
		SET @ActionURL = '/V1/Messages/GetInboxMessage?Boxid='+CONVERT(NVARCHAR(50), @BoxId)+'&MessageId='+CONVERT(NVARCHAR(50), @MessageId)
		EXEC external_KonturExec @ActionURL, 'GET', NULL, @Response OUTPUT
		SET @ResponseXML =  dbo.fn_json2xml(@Response) 
		
		SELECT @eDIMessage = CONVERT(XML, n.value('MessageBody[1]','varbinary(max)'))
		FROM @ResponseXML.nodes('/root/Data') t(n)
	
		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET eDIMessage = @eDIMessage
		WHERE EventId = @EventId

		--SELECT @DocumentType = UPPER(n.value('documentType[1]','nvarchar(max)'))
		--FROM @eDIMessage.nodes('/eDIMessage/interchangeHeader') t(n)

		DECLARE /*@doc_ID UNIQUEIDENTIFIER, @doc_Type NVARCHAR(MAX),*/ @message_ID UNIQUEIDENTIFIER, @msg_status NVARCHAR(MAX), @Text NVARCHAR(MAX)

		IF @DocumentType = 'ORDRSP' BEGIN
			-- Сообщение ORDRSP
			INSERT INTO #Messages (msgId, senderGLN, recipientGLN, documentType, msg_number, msg_date, msg_status, originOrder_number, originOrder_date)
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
			FROM @eDIMessage.nodes('/eDIMessage') t(n)

			-- Надо бы проверку на свои GLN
 			SELECT @msg_status = NULL, @doc_ID = NULL, @doc_Type = NULL, @doc_Name = NULL
	
			-- По какому документу пришли данные
 			SELECT @msg_status = msg_status, @doc_ID = msg_doc_ID, @doc_Type =  msg_doc_Type, @doc_Name = msg_doc_Name
			FROM #Messages
			LEFT JOIN KonturEDI.dbo.edi_Messages ON  msg_doc_Name = originOrder_number AND CONVERT(DATE, msg_doc_Date) = CONVERT(DATE, originOrder_date)
			WHERE msg_doc_Type = 'tp_StoreRequests'

			IF @doc_ID IS NULL BEGIN 
				SELECT @Text = @DocumentType+' Не найден документ N'+originOrder_number+' от '+originOrder_date FROM #Messages

				INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
				VALUES ('external_ProcessEvents', 50001, @Text)

				GOTO NextStep
			END
			
			-- Лог
			--INSERT INTO KonturEDI.dbo.edi_MessagesLog (log_XML, log_Text, message_ID, doc_ID) 
			--VALUES (@xml, 'Получено подтверждение заказа', @message_ID, @doc_ID)

			-- Accepted/Rejected/Changed
			IF @msg_status = 'Changed' BEGIN

				-- Собираем таблицу с изменениями
				IF OBJECT_ID('tempdb..#MessageItems') IS NOT NULL 
					DROP TABLE #MessageItems 
		
				SELECT 
					 n.value('@status', 'NVARCHAR(MAX)') AS 'status'
					,n.value('gtin[1]', 'NVARCHAR(MAX)') AS 'gtin' --GTIN товара
					,n.value('internalBuyerCode[1]', 'NVARCHAR(MAX)') AS 'internalBuyerCode'
					,n.value('internalSupplierCode[1]', 'NVARCHAR(MAX)') AS 'internalSupplierCode'
					,n.value('serialNumber[1]', 'NVARCHAR(MAX)') AS 'serialNumber'
					,n.value('orderLineNumber[1]', 'NVARCHAR(MAX)') AS 'orderLineNumber'
					,n.value('typeOfUnit[1]', 'NVARCHAR(MAX)') AS 'typeOfUnit'
					,n.value('description[1]', 'NVARCHAR(MAX)') AS 'description'
					,n.value('comment[1]', 'NVARCHAR(MAX)') AS 'comment'
					,n.value('orderedQuantity[1]', 'NUMERIC(18, 6)') AS 'orderedQuantity'
					,n.value('orderedQuantity[1]/@unitOfMeasure', 'NVARCHAR(MAX)') AS 'orderedQuantity_unitOfMeasure'
					,n.value('confirmedQuantity[1]', 'NUMERIC(18, 6)') AS 'confirmedQuantity'
					,n.value('confirmedQuantity[1]/@unitOfMeasure', 'NVARCHAR(MAX)') AS 'confirmedQuantity_unitOfMeasure'
					,n.value('onePlaceQuantity[1]', 'NVARCHAR(MAX)') AS 'onePlaceQuantity'
					,n.value('onePlaceQuantity[1]/@unitOfMeasure', 'NVARCHAR(MAX)') AS 'onePlaceQuantity_unitOfMeasure'
					,n.value('expireDate[1]', 'NVARCHAR(MAX)') AS 'expireDate'
					,n.value('manufactoringDate[1]', 'NVARCHAR(MAX)') AS 'manufactoringDate'
					,n.value('netPrice[1]', 'NUMERIC(18, 6)') AS 'netPrice'
					,n.value('netPriceWithVAT[1]', 'NUMERIC(18, 6)') AS 'netPriceWithVAT'
					,n.value('netAmount[1]', 'NUMERIC(18, 6)') AS 'netAmount'
					,n.value('exciseDuty[1]', 'NUMERIC(18, 6)') AS 'exciseDuty'
					,n.value('vATRate[1]', 'NUMERIC(18, 6)') AS 'vATRate'
					,n.value('vATAmount[1]', 'NUMERIC(18, 6)') AS 'vATAmount'
					,n.value('amount[1]', 'NUMERIC(18, 6)') AS 'amount'
/*      <gtin>GTIN</gtin>   <-->
        <internalBuyerCode>BuyerProductId</internalBuyerCode>   <!--внутренний код присвоенный покупателем-->
        <internalSupplierCode>SupplierProductId</internalSupplierCode>  <!--артикул товара (код товара присвоенный продавцом)-->
		<serialNumber>SerialNumber</serialNumber>  <!--серийный номер товара-->
        <orderLineNumber>orderLineNumber</orderLineNumber>  <!--номер позиции в заказе-->
        <typeOfUnit>RС</typeOfUnit>   <!--признак возвратной тары, если это не тара, то строки нет-->        
		<description>Name</description>   <!--название товара-->

        <comment>LineItemComment</comment> <!--комментарий к товарной позиции-->
        <orderedQuantity unitOfMeasure="MeasurementUnitCode">OrdersQuantity</orderedQuantity>    <!--заказанное количество-->
        <confirmedQuantity unitOfMeasure="MeasurementUnitCode">OrdrspQuantity</confirmedQuantity>    <!--подтвержденнное количество-->
        <onePlaceQuantity unitOfMeasure="MeasurementUnitCode">OnePlaceQuantity</onePlaceQuantity>  <!-- количество в одном месте (чему д.б. кратно общее кол-во) -->

        <expireDate>expireDate</expireDate>  <!--срок годности-->		
		<manufactoringDate>manufactoringDate</manufactoringDate>  <!--дата производства-->
        <netPrice>Price</netPrice>    <!--цена товара без НДС-->
        <netPriceWithVAT>Price</netPriceWithVAT>     <!--цена товара с НДС-->
        <netAmount>PriceSummary</netAmount>     <!--сумма по позиции без НДС-->
        <exciseDuty>exciseSum</exciseDuty>     <!--акциз товара-->
        <vATRate>VATRate</vATRate>     <!--ставка НДС (NOT_APPLICABLE - без НДС, 0 - 0%, 10 - 10%, 18 - 18%)-->
        <vATAmount>VATSummary</vATAmount>    <!--сумма НДС по позиции-->
        <amount>PriceSummaryWithVAT</amount>   <!--сумма по позиции с НДС-->
*/
		--INTO #MessageItems
				INTO #MessageItems
				FROM @eDIMessage.nodes('/eDIMessage/orderResponse/lineItems/lineItem') t(n)

				-- Новая заявка
				DECLARE @strqt_ID UNIQUEIDENTIFIER = NEWID()
				
				IF OBJECT_ID('tempdb..#StoreRequestItems') IS NOT NULL 
					DROP TABLE #StoreRequestItems

				CREATE TABLE #StoreRequestItems(
					strqti_ID uniqueidentifier NOT NULL,
					strqti_strqt_ID uniqueidentifier NOT NULL,
					strqti_pitm_ID uniqueidentifier NOT NULL,
					strqti_meit_ID uniqueidentifier NOT NULL,
					strqti_strqtist_ID int NOT NULL,
					strqti_IdentifierCode nvarchar(max) NULL,
					strqti_ItemName nvarchar(max) NULL,
					strqti_Article nvarchar(max) NULL,
					strqti_idtp_ID uniqueidentifier NULL,
					strqti_Remains numeric(18, 6) NULL,
					strqti_ConsumptionPerDay numeric(18, 6) NULL,
					strqti_Volume numeric(18, 6) NOT NULL,
					strqti_Price numeric(30, 10) NULL,
					strqti_Sum numeric(18, 4) NULL,
					strqti_VAT numeric(18, 3) NULL,
					strqti_SumVAT numeric(18, 4) NULL,
					strqti_EditIndex int NULL,
					strqti_Comment nvarchar(max) NULL,
					strqti_Order int NULL)
				
        
				-- WHERE 
				-- Позиции заявки
				/*INSERT INTO StoreRequestItems (strqti_ID,strqti_strqt_ID,strqti_pitm_ID,strqti_meit_ID,strqti_strqtist_ID,strqti_IdentifierCode,strqti_ItemName,strqti_Article,strqti_idtp_ID,strqti_Remains,strqti_ConsumptionPerDay,strqti_Volume,strqti_Price,strqti_Sum,strqti_VAT,strqti_SumVAT,strqti_EditIndex,strqti_Comment,strqti_Order)
				SELECT NEWID(),@strqt_ID,strqti_pitm_ID,strqti_meit_ID,CASE WHEN status = 'Rejected' THEN 2 ELSE 0 END 'strqti_strqtist_ID',strqti_IdentifierCode,strqti_ItemName,strqti_Article,strqti_idtp_ID,strqti_Remains,strqti_ConsumptionPerDay,strqti_Volume,strqti_Price,strqti_Sum,strqti_VAT,strqti_SumVAT,strqti_EditIndex,strqti_Comment,strqti_Order
				FROM #MessageItems
				-- связка по GTIN
				JOIN tp_StoreRequestItems ON strqti_idtp_ID = @tralala AND strqti_IdentifierCode = gtin 
				*/
				DECLARE
					@WasError INT = 0

				DECLARE ci CURSOR FOR
					SELECT status,gtin ,internalBuyerCode ,internalSupplierCode ,serialNumber ,orderLineNumber ,typeOfUnit ,description ,comment ,orderedQuantity 
					,orderedQuantity_unitOfMeasure ,confirmedQuantity ,confirmedQuantity_unitOfMeasure ,onePlaceQuantity ,onePlaceQuantity_unitOfMeasure ,expireDate 
					,manufactoringDate ,netPrice ,netPriceWithVAT ,netAmount ,exciseDuty ,vATRate ,vATAmount ,amount  
					FROM #MessageItems
				
				OPEN ci
				FETCH ci INTO @status,@gtin ,@internalBuyerCode ,@internalSupplierCode ,@serialNumber ,@orderLineNumber ,@typeOfUnit ,@description ,@comment ,@orderedQuantity 
					,@orderedQuantity_unitOfMeasure ,@confirmedQuantity ,@confirmedQuantity_unitOfMeasure ,@onePlaceQuantity ,@onePlaceQuantity_unitOfMeasure ,@expireDate 
					,@manufactoringDate ,@netPrice ,@netPriceWithVAT ,@netAmount ,@exciseDuty ,@vATRate ,@vATAmount ,@amount  
				
				WHILE @@FETCH_STATUS = 0 BEGIN
					-- Ищем позицию заявки по GTIN в заявке 
					SELECT @strqti_ID_orig = strqti_ID 
					FROM StoreRequestItems 
					WHERE strqti_strqt_ID = @doc_ID AND strqti_IdentifierCode = @gtin AND strqti_idtp_ID = @idtp_ID_GTIN

					-- TODO: Второй поиск через товарные номенклатуры (если заменили)

					-- Позиция заявки найдена, нужно обработать статусы
					IF @strqti_ID_orig IS NOT NULL BEGIN
						-- Новые значения для заявки
						SELECT 
							 @strqti_ID = NEWID()
							-- ,@strqti_strqt_ID
							,@strqti_pitm_ID = strqti_pitm_ID
							,@strqti_meit_ID = strqti_meit_ID
							,@strqti_strqtist_ID = strqti_strqtist_ID
							,@strqti_IdentifierCode = strqti_IdentifierCode
							,@strqti_ItemName = strqti_ItemName
							,@strqti_Article = strqti_Article
							,@strqti_idtp_ID = strqti_idtp_ID
							,@strqti_Remains = strqti_Remains
							,@strqti_ConsumptionPerDay = strqti_ConsumptionPerDay
							,@strqti_Volume = strqti_Volume
							,@strqti_Price = strqti_Price
							,@strqti_Sum = strqti_Sum
							,@strqti_VAT = strqti_VAT
							,@strqti_SumVAT = strqti_SumVAT
							,@strqti_EditIndex = strqti_EditIndex
							,@strqti_Comment = strqti_Comment
							,@strqti_Order = strqti_Order
							,@meit_Rate = MI.meit_Rate
						FROM StoreRequestItems  I
						JOIN ProductItems            P  ON P.pitm_ID = I.strqti_pitm_ID
						JOIN MeasureItems            MI ON MI.meit_ID = I.strqti_meit_ID
						WHERE strqti_ID = @strqti_ID_orig

						IF @status = 'Changed' BEGIN
							SET @strqti_Comment = 'Изменено поставщиком: '
							IF @strqti_Volume <> @confirmedQuantity*@meit_Rate
								SET @strqti_Comment = @strqti_Comment + ' Кол-во ['+CONVERT(NVARCHAR(MAX), CONVERT(NUMERIC(18,2), @strqti_Volume/@meit_Rate))+'->'+CONVERT(NVARCHAR(MAX), CONVERT(NUMERIC(18,2), @confirmedQuantity))+']'
							IF @strqti_Price <> @netPrice/@meit_Rate
								SET @strqti_Comment = @strqti_Comment + ' Цена ['+CONVERT(NVARCHAR(MAX), CONVERT(NUMERIC(18,2), @strqti_Price*@meit_Rate))+'->'+CONVERT(NVARCHAR(MAX), CONVERT(NUMERIC(18,2), @netPrice))+']'

							SELECT
								 @strqti_Volume = @confirmedQuantity*@meit_Rate
								,@strqti_Price = @netPrice/@meit_Rate
								,@strqti_Sum = @netAmount
								,@strqti_VAT = CONVERT(NUMERIC(18,6), @vATRate)/100
								,@strqti_SumVAT = @vATAmount
						END
						ELSE IF @status = 'Rejected' BEGIN
							SELECT 
								 @strqti_Volume = 0
								,@strqti_Comment = 'Отвергнута поставщиком'
						END
						ELSE IF @status = 'Accepted' BEGIN
							SELECT 
								@strqti_Comment = 'Принята поставщиком'
						END
						-- Вставляем обработанные значения
				
						INSERT INTO #StoreRequestItems (strqti_ID,strqti_strqt_ID,strqti_pitm_ID,strqti_meit_ID,strqti_strqtist_ID,strqti_IdentifierCode,strqti_ItemName,strqti_Article,strqti_idtp_ID,strqti_Remains,strqti_ConsumptionPerDay,strqti_Volume,strqti_Price,strqti_Sum,strqti_VAT,strqti_SumVAT,strqti_EditIndex,strqti_Comment,strqti_Order)
						VALUES (@strqti_ID, @strqt_ID, @strqti_pitm_ID, @strqti_meit_ID, @strqti_strqtist_ID, @strqti_IdentifierCode, @strqti_ItemName, @strqti_Article, @strqti_idtp_ID, @strqti_Remains, @strqti_ConsumptionPerDay, @strqti_Volume, @strqti_Price, @strqti_Sum, @strqti_VAT, @strqti_SumVAT, @strqti_EditIndex, @strqti_Comment, @strqti_Order)
				
					END
					-- Если не нашли позицию заявки
					ELSE BEGIN
						SELECT @Text = 'Не найдена позиция заявки c GTIN ['+@gtin+']. Пока ошибка, возможно нужно делать создание новой позиции?'
						
						INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
						VALUES ('external_ProcessEvents', 50001, @Text)

						SET @WasError = 1 
					END

					FETCH ci INTO @status,@gtin ,@internalBuyerCode ,@internalSupplierCode ,@serialNumber ,@orderLineNumber ,@typeOfUnit ,@description ,@comment ,@orderedQuantity 
						,@orderedQuantity_unitOfMeasure ,@confirmedQuantity ,@confirmedQuantity_unitOfMeasure ,@onePlaceQuantity ,@onePlaceQuantity_unitOfMeasure ,@expireDate 
						,@manufactoringDate ,@netPrice ,@netPriceWithVAT ,@netAmount ,@exciseDuty ,@vATRate ,@vATAmount ,@amount  
					END

				CLOSE ci
				DEALLOCATE ci

				IF EXISTS (
					SELECT * FROM StoreRequestItems I1
					LEFT JOIN StoreRequestItems I2 ON I2.strqti_ID = I1.strqti_ID
					WHERE I1.strqti_strqt_ID = @doc_ID AND I2.strqti_strqt_ID = @strqt_ID AND I2.strqti_ID IS NULL)
				BEGIN
					INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
					VALUES ('external_ProcessEvents', 50001, 'Пришли не все позиции заявки')

					SET @WasError = 1
					-- EXEC tpsys_RaiseError 50001, 'Пришли не все позиции заявки'
				END

				-- Если все прошло без ошибок, переименовываем струю заявку, создаем новую

				-- Начало изменений
				-- Поставить статус "Не готова" у оринальной заявки


				DECLARE
					 @strqt_Name NVARCHAR(MAX)
					,@strqt_Date DATETIME
				
				IF @WasError = 1 
				BEGIN
					GOTO NextStep
				END
				ELSE BEGIN
					SELECT @strqt_Name = strqt_Name, @strqt_Date = strqt_Date FROM StoreRequests WHERE strqt_ID = @doc_ID
					SET @strqt_Name = @strqt_Name+'_'+REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR, GETDATE(), 120), ':', ''), '-', ''), ' ', '')
		
					UPDATE StoreRequests 
					SET  strqt_strqtst_ID = 10
						,strqt_Name = @strqt_Name
					WHERE strqt_ID = @doc_ID

					UPDATE KonturEDI.dbo.edi_Messages 
					SET msg_doc_Name = @strqt_Name  
					WHERE msg_doc_ID = @doc_ID

					-- Обновляем дополнительный статус
					EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Пришли изменения от поставщика. СОздана новая заявка'
				
					INSERT INTO StoreRequests (strqt_ID,strqt_strqtyp_ID,strqt_stor_ID_In,strqt_stor_ID_Out,strqt_part_ID_Out,strqt_usr_ID,strqt_strqtst_ID,strqt_DateInput,strqt_DateLimit,strqt_Date,strqt_Name,strqt_Description)
					SELECT @strqt_ID, strqt_strqtyp_ID, strqt_stor_ID_In, strqt_stor_ID_Out, strqt_part_ID_Out, strqt_usr_ID, strqt_strqtst_ID, strqt_DateInput, strqt_DateLimit, strqt_Date, @doc_Name, strqt_Description 
					FROM StoreRequests WHERE strqt_ID = @doc_ID

					INSERT INTO StoreRequestItems(strqti_ID,strqti_strqt_ID,strqti_pitm_ID,strqti_meit_ID,strqti_strqtist_ID,
						strqti_IdentifierCode,strqti_ItemName,strqti_Article,strqti_idtp_ID,strqti_Remains,strqti_ConsumptionPerDay,
						strqti_Volume,strqti_Price,strqti_Sum,strqti_VAT,strqti_SumVAT,strqti_EditIndex,strqti_Comment,strqti_Order)
					SELECT strqti_ID,strqti_strqt_ID,strqti_pitm_ID,strqti_meit_ID,strqti_strqtist_ID,
						strqti_IdentifierCode,strqti_ItemName,strqti_Article,strqti_idtp_ID,strqti_Remains,strqti_ConsumptionPerDay,
						strqti_Volume,strqti_Price,strqti_Sum,strqti_VAT,strqti_SumVAT,strqti_EditIndex,strqti_Comment,strqti_Order
					FROM #StoreRequestItems

					SET @Text =  'Создана на основе заявки N '+@strqt_Name

					EXEC external_UpdateDocStatus @strqt_ID, @doc_Type, @Text

					-- EXEC external_PrepareStatusReport @BoxId, 'Ok', 'Сообщение доставлено'
				END

		/*		BEGIN
					-- Нет позиции оригинальной заявки, нужно создать новую на основе пришедших данных (наверно и такое может случится)
					IF @strqti_ID IS NULL BEGIN
						-- Ищем 
						SELECT parpit_pitm_ID
						FROM tp_PartnerProductItems 
						JOIN tp_PartnerProductItemIdentifiers ON parpidnt_parpit_ID = parpit_ID AND parpidnt_idtp_ID = @tralala
						WHERE parpidnt_Code = @gtin AND parpit_part_ID = @blablabla

						INSERT 
					END
					--
					--
				END
		*/
				-- FULL JOIN (SELECT * FROM StoreRequestItems WHERE strqti_strqt_ID = @doc_ID) A ON CONVERT(NVARCHAR(MAX),strqti_pitm_ID) = internalBuyerCode 
				-- JOIN StoreRequestItems ON CONVERT(NVARCHAR(MAX),strqti_pitm_ID) = internalBuyerCode
				-- WHERE strqti_strqt_ID = @doc_ID

				-- Изменение заказов не поддерживается учетной системой
				-- EXEC external_ExportStatusReport @message_ID, @doc_ID, @OutboxPath, @fname, 'Fail', 'При обработке сообщения произошла ошибка', 'Изменение заказов не поддерживается учетной системой'

				-- Конец изменений
				-- Изменение заказов не поддерживается учетной системой
				-- EXEC external_PrepareStatusReport @BoxId, 'Fail', 'При обработке сообщения произошла ошибка', 'Изменение заказов не поддерживается учетной системой'
			END
			ELSE IF @msg_status = 'Rejected' BEGIN
 				 -- Поставить статус "заказ отменен"
				UPDATE StoreRequests SET strqt_strqtst_ID = 10 WHERE strqt_ID = @doc_ID
      
				EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Отвергнута'

				EXEC external_PrepareStatusReport @BoxId, 'Ok', 'Сообщение доставлено'
			END
			ELSE IF @msg_status = 'Accepted' BEGIN
				-- Меняем статус на "Подтверждена"
				UPDATE StoreRequests SET strqt_strqtst_ID = 11 WHERE strqt_ID = @doc_ID

				EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Принята'

				EXEC external_PrepareStatusReport @BoxId, 'Ok', 'Сообщение доставлено', ''
			END
			ELSE BEGIN
				INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
				VALUES ('external_ProcessEvents', 50001, 'Неизвестное событие "'+ISNULL(@msg_status, '<null>')+'"')

				GOTO NextStep
			END

		END
		ELSE IF @DocumentType = 'DESADV' BEGIN
			-- Сообщение DESADV

			INSERT INTO #Messages (msgId, senderGLN, recipientGLN, documentType, msg_number, msg_date, msg_status, originOrder_number, originOrder_date)
			SELECT 
			  n.value('@id', 'NVARCHAR(MAX)') AS 'msgId',
			  n.value('interchangeHeader[1]/sender[1]', 'NVARCHAR(MAX)') AS 'senderGLN',
			  n.value('interchangeHeader[1]/recipient[1]', 'NVARCHAR(MAX)') AS 'recipientGLN', 
			  n.value('interchangeHeader[1]/documentType[1]', 'NVARCHAR(MAX)') AS 'documentType', 
			  n.value('despatchAdvice[1]/@number', 'NVARCHAR(MAX)') AS 'msg_number',
			  n.value('despatchAdvice[1]/@date', 'DATETIME') AS 'msg_date',
			  n.value('despatchAdvice[1]/@status', 'NVARCHAR(MAX)') AS 'msg_status',
			  n.value('despatchAdvice[1]/originOrder[1]/@number', 'NVARCHAR(MAX)') AS 'originOrder_number',
			  n.value('despatchAdvice[1]/originOrder[1]/@date', 'NVARCHAR(MAX)') AS 'originOrder_date'
			FROM @eDIMessage.nodes('/eDIMessage') t(n)
			
			DECLARE @despatchAdvice_number NVARCHAR(MAX), @despatchAdvice_date DATETIME
			SELECT @despatchAdvice_number = msg_number, @despatchAdvice_date = msg_date FROM #Messages
		
			-- По какому документу пришли данные
 			SELECT @doc_ID =  msg_doc_ID, @doc_Type =  msg_doc_Type
			FROM #Messages
			LEFT JOIN KonturEDI.dbo.edi_Messages ON  msg_doc_Name = originOrder_number AND CONVERT(DATE,  msg_doc_Date) = CONVERT(DATE, originOrder_date)
			WHERE msg_doc_Type = 'tp_StoreRequests'

			IF @doc_ID IS NULL BEGIN 
				SELECT @Text = @DocumentType+' Не найден документ N'+originOrder_number+' от '+originOrder_date FROM #Messages

				INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
				VALUES ('external_GetEvents', 50001, @Text)

				GOTO NextStep
			END
			DECLARE @idoc_ID UNIQUEIDENTIFIER, @idoc_Name NVARCHAR(MAX), @idoc_Date DATETIME
			SELECT 'external_CreateInputFromRequest', @doc_ID, @despatchAdvice_number, @despatchAdvice_date
			EXEC external_CreateInputFromRequest @doc_ID, @despatchAdvice_number, @despatchAdvice_date, @idoc_ID OUTPUT, @idoc_Name OUTPUT, @idoc_Date OUTPUT
			SELECT 'external_PrepareInputs', @idoc_ID, @doc_ID, @BoxId
			EXEC external_PrepareInputs @idoc_ID, @doc_ID, @BoxId


			-- Статус заявки на закупку
			SET @StatusText = 'Создана приходная накладная N'+@idoc_Name+' дата '+CONVERT(NVARCHAR(50), @idoc_Date, 104)
			EXEC external_UpdateDocStatus @doc_ID, @doc_Type, @StatusText
		  
			-- Статусноое сообщение
			EXEC external_PrepareStatusReport @BoxId, 'Ok', 'Сообщение доставлено'
		END
		ELSE IF @DocumentType = 'STSMSG' BEGIN
			DECLARE @dateTime NVARCHAR(MAX), @mdescription NVARCHAR(MAX)

			SELECT TOP 1
				@messageId = n.value('../messageId[1]', 'NVARCHAR(MAX)'), -- AS 'messageId',
				@dateTime = n.value('dateTime[1]', 'NVARCHAR(MAX)'), -- AS 'dateTime',
				@mdescription = n.value('description[1]', 'NVARCHAR(MAX)') -- AS 'description'
			--INTO #Messages
			FROM @eDIMessage.nodes('/statusReport/reportItem/statusItem') t(n)

			-- На какое сообщение пришел ответ
			-- SELECT TOP 1 @messageId = messageId, @dateTime = dateTime, @description = description FROM #Messages
	
			-- Внутренний ID документа в Тиллипад
			SELECT @doc_ID = msg_doc_ID, @doc_Type = msg_doc_Type 
			FROM KonturEDI.dbo.edi_Messages 
			WHERE msg_Id =  @messageId 
	
			--SELECT @doc_ID, @doc_Type
			IF @doc_ID IS NOT NULL 
				--EXEC external_UpdateDocStatus @doc_ID, @doc_Type, @description, @dateTime
				EXEC external_UpdateDocStatus @doc_ID, @doc_Type, @mdescription

		END
		ELSE BEGIN
			INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
			VALUES ('external_GetEvents', 50001, 'Неизвестный тип документа "'+ISNULL(@DocumentType, '<null>')+'"'+CONVERT(NVARCHAR(MAX), @Event))

			GOTO NextStep
		END

		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET	IsProcessed = 1
		WHERE EventId = @EventId
	END
	ELSE IF @EventType = 'NewOutboxMessage' BEGIN
		SET  @doc_ID = NULL
		
		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET	IsProcessed = 1
		WHERE EventId = @EventId
		
		/*SELECT
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

		EXEC external_UpdateDocStatus @doc_ID, @doc_Type, 'Отправка исходящего сообщения', @edt*/
	END
	ELSE IF @EventType IN ('ProcessingTimesReport', 'MessageDelivered', 'ProcessingTimesReport', 'RecognizeMessage', 'MessageReadByPartner', 'MessageUndelivered') BEGIN
		SET  @doc_ID = NULL

		UPDATE KonturEDI.dbo.edi_InboxMessages 
		SET	IsProcessed = 1
		WHERE EventId = @EventId
	END
	ELSE BEGIN
		INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
		VALUES ('external_GetEvents', 50001, 'Неизвестный тип сообщения "'+ISNULL(@EventType, '<null>')+'"')

		GOTO NextStep
	END

    
NextStep:
    
    FETCH c_events INTO @MessageId, @BoxId, @PartyId, @EventId, @EventDateTime, @EventType, @Event
END

CLOSE c_events
DEALLOCATE c_events

GO
