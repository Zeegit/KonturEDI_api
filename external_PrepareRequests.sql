SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'external_PrepareRequests ', 'P') IS NOT NULL
  DROP PROCEDURE dbo.external_PrepareRequests
GO

CREATE PROCEDURE dbo.external_PrepareRequests 
WITH EXECUTE AS OWNER
AS

DECLARE 
	 @msg_Id UNIQUEIDENTIFIER
	,@msg_Date DATETIME
	,@boxId NVARCHAR(MAX)

	,@strqt_ID UNIQUEIDENTIFIER
	,@strqt_Name NVARCHAR(MAX)
	,@strqt_DateInput DATETIME
	,@strqt_Date DATETIME
	,@idtp_ID_GTIN UNIQUEIDENTIFIER
	,@part_ID_Out UNIQUEIDENTIFIER
	,@part_ID_Self UNIQUEIDENTIFIER
	,@addr_ID UNIQUEIDENTIFIER

	,@nttp_ID_Measure UNIQUEIDENTIFIER
	,@Measure_Default NVARCHAR(MAX)
	,@Currency_Default NVARCHAR(MAX)
	
	,@LineItem XML
	,@LineItems XML
	,@seller XML
	,@buyer XML
	,@invoicee XML
	,@deliveryInfo XML
	,@Result XML

-- Системные настройки заметок
SELECT @nttp_ID_Measure = nttp_ID_Measure, @Measure_Default = Measure_Default, @Currency_Default = Currency_Default, @idtp_ID_GTIN = idtp_ID_GTIN
FROM KonturEDI.dbo.edi_Settings


DECLARE ct CURSOR FOR
    SELECT R.strqt_ID, R.strqt_Name, R.strqt_DateInput, R.strqt_Date, G.stgr_part_ID, R.strqt_part_ID_Out, addr_ID
	FROM StoreRequests R 
	-- Склады
	JOIN Stores      S ON S.stor_ID = strqt_stor_ID_In
	JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
	-- Своя организация
	-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
	-- Адрес склада
	LEFT JOIN Addresses               ON addr_obj_ID         = S.stor_loc_ID
	--
	LEFT JOIN KonturEDI.dbo.edi_Messages M ON msg_doc_ID = strqt_ID
	WHERE strqt_strqtyp_ID IN (11,12)
		AND strqt_strqtst_ID = 12 
		AND M.msg_doc_ID IS NULL
		AND strqt_Date > '01.05.2017'
	ORDER BY strqt_Date DESC
	

OPEN ct
FETCH ct INTO @strqt_ID, @strqt_Name, @strqt_DateInput, @strqt_Date, @part_ID_Self, @part_ID_Out, @addr_ID

WHILE @@FETCH_STATUS = 0 BEGIN 
	SELECT @msg_Id = NEWID(), @msg_Date = GETDATE()

	-- Получение BoxId
	EXEC external_GetBoxId @part_ID_Self, @boxId OUTPUT

	-- Элементы заказа
	SET @LineItem = 
	(SELECT
		CASE
			WHEN strqti_idtp_ID = @idtp_ID_GTIN THEN strqti_IdentifierCode
			ELSE ''
		END 'gtin'
		-- CONVERT(NVARCHAR(MAX), N.note_Value) N'gtin' -- GTIN товара
		-- ,P.pitm_ID N'internalBuyerCode' --внутренний код присвоенный покупателем
		,P.pitm_ID N'internalBuyerCode' --внутренний код присвоенный покупателем
		,I.strqti_Article N'internalSupplierCode' --артикул товара (код товара присвоенный продавцом)
		,I.strqti_Order N'lineNumber' --порядковый номер товара
		,NULL N'typeOfUnit' --признак возвратной тары, если это не тара, то строки нет
		,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(I.strqti_ItemName, P.pitm_Name), 25) N'description' --название товара
		,dbo.f_MultiLanguageStringToStringByLanguage1(I.strqti_Comment, 25) N'comment' --комментарий к товарной позиции
		,ISNULL(CONVERT(NVARCHAR(MAX), NM.note_Value), @Measure_Default) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,I.strqti_Volume/MI.meit_Rate N'requestedQuantity/text()' --заказанное количество
		,NULL N'onePlaceQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,NULL N'onePlaceQuantity/text()' -- количество в одном месте (чему д.б. кратно общее кол-во)
		,'Direct' N'flowType' --Тип поставки, может принимать значения: Stock - сток до РЦ, Transit - транзит в магазин, Direct - прямая поставка, Fresh - свежие продукты
		,I.strqti_Price*MI.meit_Rate N'netPrice' --цена товара без НДС
		,I.strqti_Price*MI.meit_Rate+I.strqti_Price*MI.meit_Rate*I.strqti_VAT N'netPriceWithVAT' --цена товара с НДС
		,I.strqti_Sum N'netAmount' --сумма по позиции без НДС
		,NULL N'exciseDuty' --акциз товара
		,ISNULL(CONVERT(NVARCHAR(MAX), FLOOR(I.strqti_VAT*100)), 'NOT_APPLICABLE') N'vATRate' --ставка НДС (NOT_APPLICABLE - без НДС, 0 - 0%, 10 - 10%, 18 - 18%)
		,I.strqti_SumVAT N'vATAmount' --сумма НДС по позиции
		,I.strqti_Sum+I.strqti_SumVAT N'amount' --сумма по позиции с НДС
	FROM StoreRequestItems       I 
	JOIN ProductItems            P ON P.pitm_ID = I.strqti_pitm_ID
	JOIN MeasureItems            MI ON MI.meit_ID = strqti_meit_ID
	-- Единица измерения
	LEFT JOIN Notes              NM ON NM.note_obj_ID = strqti_meit_ID AND note_nttp_ID = @nttp_ID_Measure
	-- LEFT JOIN Notes               N ON N.note_obj_ID = P.pitm_ID
	WHERE strqti_strqt_ID = @strqt_ID
	FOR XML PATH(N'lineItem'), TYPE)

	SET @LineItems = 
		(SELECT
			 @Currency_Default N'currencyISOCode' --код валюты (по умолчанию рубли)
			,@LineItem
			,SUM(strqti_Sum) N'totalSumExcludingTaxes' -- сумма заявки без НДС
			,SUM(strqti_SumVAT) N'totalVATAmount' -- сумма НДС по заказу
			,SUM(strqti_Sum + strqti_SumVAT) N'totalAmount' -- --общая сумма заказа всего с НДС
		FROM StoreRequests           R 
		JOIN StoreRequestItems       I ON I.strqti_strqt_ID = R.strqt_ID
		WHERE R.strqt_ID = @strqt_ID
		FOR XML PATH(N'lineItems'), TYPE)    

	/*SELECT TOP 1
		-- Поставщик
		@part_ID_Out = R.strqt_part_ID_Out
		-- Своя организация
		,@part_ID_Self = G.stgr_part_ID
		-- Адрес склада
		,@addr_ID = addr_ID
		,@strqt_DateInput = strqt_DateInput
	FROM StoreRequests R         
	-- Склады
	JOIN Stores      S ON S.stor_ID = strqt_stor_ID_In
	JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
	-- Своя организация
	-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
	-- Адрес склада
	LEFT JOIN Addresses               ON addr_obj_ID         = S.stor_loc_ID
	WHERE strqt_ID = @strqt_ID*/

	EXEC dbo.external_GetSellerXML @part_ID_Out, @seller OUTPUT
	EXEC dbo.external_GetBuyerXML @part_ID_Self, @addr_ID, @buyer OUTPUT
	--EXEC external_GetInvoiceeXML @part_ID, @invoicee OUTPUT
		
	EXEC external_GetDeliveryInfoXML @part_ID_Out, NULL, @part_ID_Self, @addr_ID, @strqt_DateInput, @deliveryInfo OUTPUT

	DECLARE @senderGLN NVARCHAR(MAX), @buyerGLN NVARCHAR(MAX)
	SET @senderGLN = @seller.value('(/seller/gln)[1]', 'NVARCHAR(MAX)')
	SET @buyerGLN = @buyer.value('(/buyer/gln)[1]', 'NVARCHAR(MAX)')

	SET @Result=
		(SELECT
			 @msg_Id N'id'
			,CONVERT(NVARCHAR(MAX), @msg_Date, 127) N'creationDateTime'
			,(SELECT
				@buyerGLN N'sender',
				@senderGLN N'recipient',
				'ORDERS' N'documentType'
				,CONVERT(NVARCHAR(MAX), @msg_Date, 127)  N'creationDateTime'
				,CONVERT(NVARCHAR(MAX), @msg_Date, 127)  N'creationDateTimeBySender'
				,NULL 'IsTest'
				FOR XML PATH(N'interchangeHeader'), TYPE)
			,(SELECT
				--номер документа-заказа, дата документа-заказа, статус документа - оригинальный/отменённый/копия/замена, номер исправления для заказа-замены
				R.strqt_Name N'@number'
				,CONVERT(NVARCHAR(MAX), CONVERT(DATE, R.strqt_Date), 127) N'@date'
				,R.strqt_ID N'@id'
				,N'Original' N'@status'
				,NULL N'@revisionNumber'

				,NULL N'promotionDealNumber'
				-- Договор
				,C.pcntr_Name N'contractIdentificator/@number'
				,CONVERT(NVARCHAR(MAX),  CONVERT(DATE, C.pcntr_DateBegin), 127) N'contractIdentificator/@date'
				,@seller
				,@buyer
				,@invoicee
				,@deliveryInfo
				-- информация о товарах
				,CONVERT(NVARCHAR(MAX), R.strqt_Description) N'comment'
				,@lineItems
				FOR XML PATH(N'order'), TYPE
		)
		FROM StoreRequests R           
		LEFT JOIN PartnerContracts      C ON C.pcntr_part_ID = R.strqt_part_ID_Out
		WHERE strqt_ID = @strqt_ID
		FOR XML RAW(N'eDIMessage'))

	-- Новое сообщение на отправку
	INSERT INTO KonturEDI.dbo.edi_Messages (msg_Id, msg_boxId, msg_Date, msg_RequestXML, msg_doc_ID, msg_doc_Name, msg_doc_Date, msg_doc_Type)
	VALUES (@msg_ID, @boxId, @msg_Date, @Result, @strqt_ID, @strqt_Name, @strqt_Date, 'tp_StoreRequests')

	FETCH ct INTO @strqt_ID, @strqt_Name, @strqt_DateInput, @strqt_Date, @part_ID_Self, @part_ID_Out, @addr_ID
	              
END

CLOSE ct
DEALLOCATE ct

/*
DECLARE @TRANCOUNT INT

-- Необработанные заказы
SET @TRANCOUNT = @@TRANCOUNT
IF @TRANCOUNT = 0 
    BEGIN TRAN external_PrepareORDERS
ELSE              
    SAVE TRAN external_PrepareORDERS

BEGIN TRY
	INSERT INTO KonturEDI.dbo.edi_Messages (doc_ID, doc_Name, doc_Date, doc_Type)
	SELECT strqt_ID, strqt_Name, strqt_Date, 'request'
	FROM StoreRequests R 
	LEFT JOIN edi_Messages M ON msg_doc_ID = strqt_ID
	WHERE strqt_strqtyp_ID IN (11,12)
		AND strqt_strqtst_ID = 12 
		AND M.doc_ID IS NULL
		AND strqt_Date > '01.05.2017'
	ORDER BY strqt_Date DESC
 	
	IF @TRANCOUNT = 0
  		COMMIT TRAN
END TRY
BEGIN CATCH
	-- Ошибка загрузки файла, пишем ошибку приема
	IF @@TRANCOUNT > 0
		IF (XACT_STATE()) = -1
			ROLLBACK
		ELSE
			ROLLBACK TRAN external_PrepareORDERS
	
	IF @TRANCOUNT > @@TRANCOUNT
		BEGIN TRAN

	-- Ошибки в таблицу, обработаем потом
	INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage)
	SELECT 'external_PrepareORDERS', ERROR_NUMBER(), ERROR_MESSAGE()
	EXEC tpsys_ReraiseError
END CATCH
*/