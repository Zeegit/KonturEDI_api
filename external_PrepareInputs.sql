IF OBJECT_ID('external_PrepareInputs', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_PrepareInputs
GO

CREATE PROCEDURE dbo.external_PrepareInputs (
	@idoc_ID UNIQUEIDENTIFIER,
	@strqt_ID UNIQUEIDENTIFIER,
	@boxId NVARCHAR(MAX))
WITH EXECUTE AS OWNER
AS
/*
<eDIMessage id="messageId" creationDateTime="creationDateTime">  <!--идентификатор сообщения, время сообщения-->
  <!-- начало заголовка сообщения -->
  <interchangeHeader>
    <sender>SenderGLN</sender>    <!--GLN отправителя сообщения-->
    <recipient>RecipientGLN</recipient>   <!--GLN получателя сообщения-->
    <documentType>RECADV</documentType>  <!--тип документа-->
    <creationDateTime>creationDateTimeT00:00:00.000Z</creationDateTime> <!--дата и время создания сообщения-->
    <creationDateTimeBySender>creationDateTimeBySenderT00:00:00.000Z</creationDateTimeBySender> <!--дата и время создания сообщения клиентом-->
    <isTest>1</isTest>    <!--тестовый флаг-->
  </interchangeHeader>
  <!-- конец заголовка сообщения -->
  <receivingAdvice number="recadvNumber" date="recadvDate">  <!--номер приёмки, дата уведомления о приёмке-->
    <originOrder number="ordersNumber" date="ordersDate" />      <!--номер заказа, дата заказа-->
    <contractIdentificator number="contractNumber" date="contractDate" />
    <!--номер договора/ контракта, дата договора/ контракта-->
    <despatchIdentificator number="DespatchAdviceNumber" date="DespatchDate0000" />
    <!--номер накладной, дата накладной-->
    <blanketOrderIdentificator number="BlanketOrdersNumber" />     <!--номер серии заказов-->
    <!-- начало блока данных о поставщике -->
    <seller/>
    <buyer/>
    <invoicee/>
    <deliveryInfo/>
    <!-- конец блока данных о грузоотправителе и грузополучателе -->
    <!-- начало блока с данными о товаре -->
    <lineItems>
      <lineItem>
        <gtin>GTIN</gtin>       <!--GTIN товара-->
        <internalBuyerCode>BuyerProductId</internalBuyerCode>     <!--внутренний код присвоенный покупателем-->
        <internalSupplierCode>SupplierProductId</internalSupplierCode>
        <!--артикул товара (код товара присвоенный продавцом)-->
        <orderLineNumber>orderLineNumber</orderLineNumber>     <!--номер позиции в заказе-->
        <typeOfUnit>RС</typeOfUnit>   <!--признак возвратной тары, если это не тара, то строки нет-->
        <description>Name</description>         <!--наименование товара-->
        <comment>LineItemComment</comment>          <!--комментарий к товарной позиции-->
        <orderedQuantity unitOfMeasure="MeasurementUnitCode">OrderedQuantity</orderedQuantity>
        <!--заказанное количество-->
        <despatchedQuantity unitOfMeasure="MeasurementUnitCode">DespatchQuantity</despatchedQuantity>
        <!--отгруженное поставщиком количество-->
        <deliveredQuantity unitOfMeasure="MeasurementUnitCode">DesadvQuantity</deliveredQuantity>
        <!--поставленное покупателю количество-->
        <acceptedQuantity unitOfMeasure="MeasurementUnitCode">RecadvQuantity</acceptedQuantity>
        <!--принятое количество-->
        <onePlaceQuantity unitOfMeasure="MeasurementUnitCode">OnePlaceQuantity</onePlaceQuantity>
        <!-- количество в одном месте (чему д.б. кратно общее кол-во) -->
        <netPrice>Price</netPrice>     <!--цена единицы товара без НДС-->
        <netPriceWithVAT>PriceWithVAT</netPriceWithVAT>     <!--цена единицы товара с НДС-->
        <netAmount>PriceSummary</netAmount>      <!--сумма по позиции без НДС-->
        <exciseDuty>exciseSum</exciseDuty>       <!--акциз товара-->
        <vATRate>VATRate</vATRate>  <!--ставка НДС (NOT_APPLICABLE - без НДС, 0 - 0%, 10 - 10%, 18 - 18%)-->
        <vATAmount>vatSum</vATAmount>  <!--сумма НДС-->
        <amount>PriceSummaryWithVAT</amount>       <!--сумма по позиции с НДС-->
        <countryOfOriginISOCode>CountriesOfOriginCode</countryOfOriginISOCode>     <!--код страны производства-->
        <customsDeclarationNumber>CustomDeclarationNumbers</customsDeclarationNumber>
        <!--номер таможенной декларации-->
      </lineItem>
      <!-- каждая последующая товарная позиция должна идти в отдельном теге <lineItem> -->

      <totalSumExcludingTaxes>RecadvTotal</totalSumExcludingTaxes>      <!--сумма без НДС-->
      <totalAmount>RecadvTotalWithVAT</totalAmount>
      <!--общая сумма по товарам, на которую начисляется НДС (125/86)-->
      <totalVATAmount>RecadvTotalVAT</totalVATAmount>    <!--сумма НДС, значение берем из orders/ordrsp-->
    </lineItems>
  </receivingAdvice>
</eDIMessage>
*/

-- Единица измерения

DECLARE  
@idoc_Name NVARCHAR(MAX)

DECLARE @LineItem XML, @LineItems XML
DECLARE
     @nttp_ID_idoc_name UNIQUEIDENTIFIER 
    ,@nttp_ID_idoc_date UNIQUEIDENTIFIER 

-- Единица измерения
DECLARE @nttp_ID_Measure UNIQUEIDENTIFIER
DECLARE @Measure_Default NVARCHAR(10) 
DECLARE @Currency_Default NVARCHAR(10)
DECLARE 
	 @part_ID_Out UNIQUEIDENTIFIER
	,@part_ID_Self UNIQUEIDENTIFIER
	,@addr_ID UNIQUEIDENTIFIER

DECLARE @seller XML, @buyer XML, @invoicee XML, @deliveryInfo XML
DECLARE @idoc_Date DATETIME

DECLARE
	@strqt_Name NVARCHAR(MAX),
	@strqt_Date DATETIME

DECLARE 
	 @msg_Id UNIQUEIDENTIFIER
	,@msg_Date DATETIME

SELECT @msg_Id = NEWID(), @msg_Date = GETDATE()

SELECT 
    @nttp_ID_Measure = nttp_ID_Measure, @nttp_ID_idoc_name = nttp_ID_idoc_name, @nttp_ID_idoc_date = nttp_ID_idoc_date,
    @Measure_Default = Measure_Default, @Currency_Default = Currency_Default
FROM  KonturEDI.dbo.edi_Settings

SELECT TOP 1 
	 -- Поставщик
	 @part_ID_Out = R.idoc_part_ID
	 -- Своя организация
	,@part_ID_Self = G.stgr_part_ID
	-- Адрес склада
	,@addr_ID = addr_ID
	,@idoc_Date = idoc_Date
	,@idoc_Name = idoc_Name
FROM InputDocuments           R
-- Склады
JOIN Stores      S ON S.stor_ID = idoc_stor_ID
JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
-- Своя организация
-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
-- Адрес склада
LEFT JOIN Addresses               ON addr_obj_ID         = S.stor_loc_ID
WHERE R.idoc_ID = @idoc_ID

SELECT @strqt_Name = strqt_Name, @strqt_Date = strqt_Date FROM StoreRequests WHERE strqt_ID = @strqt_ID

-- Элементы заказа
SET @LineItem = 
	(SELECT 
			CONVERT(NVARCHAR(MAX), N.note_Value) N'gtin' -- GTIN товара
		,P.pitm_ID N'internalBuyerCode' --внутренний код присвоенный покупателем
		,I.idit_Article N'internalSupplierCode' --артикул товара (код товара присвоенный продавцом)
		,I.idit_Order N'lineNumber' --порядковый номер товара
		,NULL N'typeOfUnit' --признак возвратной тары, если это не тара, то строки нет
		,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(I.idit_ItemName, P.pitm_Name), 25) N'description' --название товара
		,dbo.f_MultiLanguageStringToStringByLanguage1(I.idit_Comment, 25) N'comment' --комментарий к товарной позиции
		-- ,dbo.f_MultiLanguageStringToStringByLanguage1(MI.meit_Name, 25) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,ISNULL(CONVERT(NVARCHAR(MAX), NM.note_Value), @Measure_Default) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,I.idit_Volume N'requestedQuantity/text()' --заказанное количество
		,NULL N'onePlaceQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,NULL N'onePlaceQuantity/text()' -- количество в одном месте (чему д.б. кратно общее кол-во)
	--	,'Direct' N'flowType' --Тип поставки, может принимать значения: Stock - сток до РЦ, Transit - транзит в магазин, Direct - прямая поставка, Fresh - свежие продукты
		,I.idit_Price N'netPrice' --цена товара без НДС
		,I.idit_Price+I.idit_Price*I.idit_VAT N'netPriceWithVAT' --цена товара с НДС
		,I.idit_Sum N'netAmount' --сумма по позиции без НДС
		--,NULL N'exciseDuty' --акциз товара
		,I.idit_VAT*100 N'VATRate' --ставка НДС (NOT_APPLICABLE - без НДС, 0 - 0%, 10 - 10%, 18 - 18%)
		,I.idit_SumVAT N'VATAmount' --сумма НДС по позиции
		,I.idit_Sum+I.idit_SumVAT N'amount' --сумма по позиции с НДС
	FROM InputDocumentItems       I 
	JOIN ProductItems             P ON P.pitm_ID = I.idit_pitm_ID
	JOIN MeasureItems            MI ON MI.meit_ID = idit_meit_ID
	LEFT JOIN Notes              NM ON NM.note_obj_ID = idit_meit_ID AND note_nttp_ID = @nttp_ID_Measure
	LEFT JOIN Notes               N ON N.note_obj_ID = P.pitm_ID
	WHERE I.idit_idoc_ID = @idoc_ID
	FOR XML PATH(N'lineItem'), TYPE)

SET @LineItems = (
SELECT
	 @Currency_Default N'currencyISOCode' --код валюты (по умолчанию рубли)
	,@LineItem
	,SUM(idit_Sum) N'totalSumExcludingTaxes' -- сумма заявки без НДС
	,SUM(idit_SumVAT) N'totalVATAmount' -- сумма НДС по заказу
	,SUM(idit_Sum +idit_SumVAT) N'totalAmount' -- --общая сумма заказа всего с НДС
FROM InputDocuments              R 
JOIN InputDocumentItems       I ON I.idit_idoc_ID = R.idoc_ID
WHERE R.idoc_ID = @idoc_ID
FOR XML PATH(N'lineItems'), TYPE)

EXEC dbo.external_GetSellerXML @part_ID_Out, @seller OUTPUT
EXEC dbo.external_GetBuyerXML @part_ID_Self, @addr_ID, @buyer OUTPUT
--EXEC external_GetInvoiceeXML @part_ID, @invoicee OUTPUT
EXEC external_GetDeliveryInfoXML @part_ID_Out, NULL, @part_ID_Self, @addr_ID, @idoc_Date, @deliveryInfo OUTPUT

DECLARE @senderGLN NVARCHAR(MAX), @buyerGLN NVARCHAR(MAX)
SET @senderGLN = @seller.value('(/seller/gln)[1]', 'NVARCHAR(MAX)')
SET @buyerGLN = @buyer.value('(/buyer/gln)[1]', 'NVARCHAR(MAX)')

DECLARE @Result XML

SET @Result =
(SELECT
	@msg_Id N'id', 
    CONVERT(NVARCHAR(MAX), @msg_Date, 127)  N'creationDateTime',
	(
		SELECT
			@buyerGLN N'sender',
			@senderGLN N'recipient',
			'RECADV' N'documentType'
			,CONVERT(NVARCHAR(MAX), @msg_Date, 127)  N'creationDateTime'
			,CONVERT(NVARCHAR(MAX), @msg_Date, 127)  N'creationDateTimeBySender'
			,NULL 'IsTest'
		FOR XML PATH(N'interchangeHeader'), TYPE
	)
	,(
		SELECT 
			--номер документа-заказа, дата документа-заказа, статус документа - оригинальный/отменённый/копия/замена, номер исправления для заказа-замены
			I.idoc_Name N'@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, I.idoc_Date), 127) N'@date'

			-- номер заказа, дата заказа
			,@strqt_Name N'originOrder/@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, @strqt_Date), 127) N'originOrder/@date'

			-- Договор
			,C.pcntr_Name N'contractIdentificator/@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, C.pcntr_DateBegin), 127) N'contractIdentificator/@date'
				   
			--номер накладной, дата накладной
			,NN.note_Value N'despatchIdentificator/@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, ND.note_Value), 127) N'despatchIdentificator/@date'
				   
			,@seller
			,@buyer
			,@invoicee
			,@deliveryInfo
			,@lineItems

		FOR XML PATH(N'receivingAdvice'), TYPE
            
	)

FROM InputDocuments             I
LEFT JOIN PartnerContracts      C ON C.pcntr_part_ID = I.idoc_part_ID
LEFT JOIN Notes                NN ON NN.note_obj_ID = I.idoc_ID AND NN.note_nttp_ID = @nttp_ID_idoc_name
LEFT JOIN Notes                ND ON ND.note_obj_ID = I.idoc_ID AND ND.note_nttp_ID = @nttp_ID_idoc_date
WHERE I.idoc_ID  = @idoc_ID
FOR XML RAW(N'eDIMessage'))



-- Новое сообщение на отправку
INSERT INTO KonturEDI.dbo.edi_Messages (msg_Id, msg_boxId, msg_Date, msg_RequestXML, msg_doc_ID, msg_doc_Name, msg_doc_Date, msg_doc_Type, msg_doc_ID_original)
VALUES (@msg_ID, @boxId, @msg_Date, @Result, @idoc_ID,  @idoc_Name, @idoc_Date, 'tp_InputDocuments', @strqt_ID)




