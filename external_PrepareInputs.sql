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
<eDIMessage id="messageId" creationDateTime="creationDateTime">  <!--������������� ���������, ����� ���������-->
  <!-- ������ ��������� ��������� -->
  <interchangeHeader>
    <sender>SenderGLN</sender>    <!--GLN ����������� ���������-->
    <recipient>RecipientGLN</recipient>   <!--GLN ���������� ���������-->
    <documentType>RECADV</documentType>  <!--��� ���������-->
    <creationDateTime>creationDateTimeT00:00:00.000Z</creationDateTime> <!--���� � ����� �������� ���������-->
    <creationDateTimeBySender>creationDateTimeBySenderT00:00:00.000Z</creationDateTimeBySender> <!--���� � ����� �������� ��������� ��������-->
    <isTest>1</isTest>    <!--�������� ����-->
  </interchangeHeader>
  <!-- ����� ��������� ��������� -->
  <receivingAdvice number="recadvNumber" date="recadvDate">  <!--����� ������, ���� ����������� � ������-->
    <originOrder number="ordersNumber" date="ordersDate" />      <!--����� ������, ���� ������-->
    <contractIdentificator number="contractNumber" date="contractDate" />
    <!--����� ��������/ ���������, ���� ��������/ ���������-->
    <despatchIdentificator number="DespatchAdviceNumber" date="DespatchDate0000" />
    <!--����� ���������, ���� ���������-->
    <blanketOrderIdentificator number="BlanketOrdersNumber" />     <!--����� ����� �������-->
    <!-- ������ ����� ������ � ���������� -->
    <seller/>
    <buyer/>
    <invoicee/>
    <deliveryInfo/>
    <!-- ����� ����� ������ � ���������������� � ��������������� -->
    <!-- ������ ����� � ������� � ������ -->
    <lineItems>
      <lineItem>
        <gtin>GTIN</gtin>       <!--GTIN ������-->
        <internalBuyerCode>BuyerProductId</internalBuyerCode>     <!--���������� ��� ����������� �����������-->
        <internalSupplierCode>SupplierProductId</internalSupplierCode>
        <!--������� ������ (��� ������ ����������� ���������)-->
        <orderLineNumber>orderLineNumber</orderLineNumber>     <!--����� ������� � ������-->
        <typeOfUnit>R�</typeOfUnit>   <!--������� ���������� ����, ���� ��� �� ����, �� ������ ���-->
        <description>Name</description>         <!--������������ ������-->
        <comment>LineItemComment</comment>          <!--����������� � �������� �������-->
        <orderedQuantity unitOfMeasure="MeasurementUnitCode">OrderedQuantity</orderedQuantity>
        <!--���������� ����������-->
        <despatchedQuantity unitOfMeasure="MeasurementUnitCode">DespatchQuantity</despatchedQuantity>
        <!--����������� ����������� ����������-->
        <deliveredQuantity unitOfMeasure="MeasurementUnitCode">DesadvQuantity</deliveredQuantity>
        <!--������������ ���������� ����������-->
        <acceptedQuantity unitOfMeasure="MeasurementUnitCode">RecadvQuantity</acceptedQuantity>
        <!--�������� ����������-->
        <onePlaceQuantity unitOfMeasure="MeasurementUnitCode">OnePlaceQuantity</onePlaceQuantity>
        <!-- ���������� � ����� ����� (���� �.�. ������ ����� ���-��) -->
        <netPrice>Price</netPrice>     <!--���� ������� ������ ��� ���-->
        <netPriceWithVAT>PriceWithVAT</netPriceWithVAT>     <!--���� ������� ������ � ���-->
        <netAmount>PriceSummary</netAmount>      <!--����� �� ������� ��� ���-->
        <exciseDuty>exciseSum</exciseDuty>       <!--����� ������-->
        <vATRate>VATRate</vATRate>  <!--������ ��� (NOT_APPLICABLE - ��� ���, 0 - 0%, 10 - 10%, 18 - 18%)-->
        <vATAmount>vatSum</vATAmount>  <!--����� ���-->
        <amount>PriceSummaryWithVAT</amount>       <!--����� �� ������� � ���-->
        <countryOfOriginISOCode>CountriesOfOriginCode</countryOfOriginISOCode>     <!--��� ������ ������������-->
        <customsDeclarationNumber>CustomDeclarationNumbers</customsDeclarationNumber>
        <!--����� ���������� ����������-->
      </lineItem>
      <!-- ������ ����������� �������� ������� ������ ���� � ��������� ���� <lineItem> -->

      <totalSumExcludingTaxes>RecadvTotal</totalSumExcludingTaxes>      <!--����� ��� ���-->
      <totalAmount>RecadvTotalWithVAT</totalAmount>
      <!--����� ����� �� �������, �� ������� ����������� ��� (125/86)-->
      <totalVATAmount>RecadvTotalVAT</totalVATAmount>    <!--����� ���, �������� ����� �� orders/ordrsp-->
    </lineItems>
  </receivingAdvice>
</eDIMessage>
*/

-- ������� ���������

DECLARE  
@idoc_Name NVARCHAR(MAX)

DECLARE @LineItem XML, @LineItems XML
DECLARE
     @nttp_ID_idoc_name UNIQUEIDENTIFIER 
    ,@nttp_ID_idoc_date UNIQUEIDENTIFIER 

-- ������� ���������
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
	 -- ���������
	 @part_ID_Out = R.idoc_part_ID
	 -- ���� �����������
	,@part_ID_Self = G.stgr_part_ID
	-- ����� ������
	,@addr_ID = addr_ID
	,@idoc_Date = idoc_Date
	,@idoc_Name = idoc_Name
FROM InputDocuments           R
-- ������
JOIN Stores      S ON S.stor_ID = idoc_stor_ID
JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
-- ���� �����������
-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
-- ����� ������
LEFT JOIN Addresses               ON addr_obj_ID         = S.stor_loc_ID
WHERE R.idoc_ID = @idoc_ID

SELECT @strqt_Name = strqt_Name, @strqt_Date = strqt_Date FROM StoreRequests WHERE strqt_ID = @strqt_ID

-- �������� ������
SET @LineItem = 
	(SELECT 
			CONVERT(NVARCHAR(MAX), N.note_Value) N'gtin' -- GTIN ������
		,P.pitm_ID N'internalBuyerCode' --���������� ��� ����������� �����������
		,I.idit_Article N'internalSupplierCode' --������� ������ (��� ������ ����������� ���������)
		,I.idit_Order N'lineNumber' --���������� ����� ������
		,NULL N'typeOfUnit' --������� ���������� ����, ���� ��� �� ����, �� ������ ���
		,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(I.idit_ItemName, P.pitm_Name), 25) N'description' --�������� ������
		,dbo.f_MultiLanguageStringToStringByLanguage1(I.idit_Comment, 25) N'comment' --����������� � �������� �������
		-- ,dbo.f_MultiLanguageStringToStringByLanguage1(MI.meit_Name, 25) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,ISNULL(CONVERT(NVARCHAR(MAX), NM.note_Value), @Measure_Default) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,I.idit_Volume N'requestedQuantity/text()' --���������� ����������
		,NULL N'onePlaceQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,NULL N'onePlaceQuantity/text()' -- ���������� � ����� ����� (���� �.�. ������ ����� ���-��)
	--	,'Direct' N'flowType' --��� ��������, ����� ��������� ��������: Stock - ���� �� ��, Transit - ������� � �������, Direct - ������ ��������, Fresh - ������ ��������
		,I.idit_Price N'netPrice' --���� ������ ��� ���
		,I.idit_Price+I.idit_Price*I.idit_VAT N'netPriceWithVAT' --���� ������ � ���
		,I.idit_Sum N'netAmount' --����� �� ������� ��� ���
		--,NULL N'exciseDuty' --����� ������
		,I.idit_VAT*100 N'VATRate' --������ ��� (NOT_APPLICABLE - ��� ���, 0 - 0%, 10 - 10%, 18 - 18%)
		,I.idit_SumVAT N'VATAmount' --����� ��� �� �������
		,I.idit_Sum+I.idit_SumVAT N'amount' --����� �� ������� � ���
	FROM InputDocumentItems       I 
	JOIN ProductItems             P ON P.pitm_ID = I.idit_pitm_ID
	JOIN MeasureItems            MI ON MI.meit_ID = idit_meit_ID
	LEFT JOIN Notes              NM ON NM.note_obj_ID = idit_meit_ID AND note_nttp_ID = @nttp_ID_Measure
	LEFT JOIN Notes               N ON N.note_obj_ID = P.pitm_ID
	WHERE I.idit_idoc_ID = @idoc_ID
	FOR XML PATH(N'lineItem'), TYPE)

SET @LineItems = (
SELECT
	 @Currency_Default N'currencyISOCode' --��� ������ (�� ��������� �����)
	,@LineItem
	,SUM(idit_Sum) N'totalSumExcludingTaxes' -- ����� ������ ��� ���
	,SUM(idit_SumVAT) N'totalVATAmount' -- ����� ��� �� ������
	,SUM(idit_Sum +idit_SumVAT) N'totalAmount' -- --����� ����� ������ ����� � ���
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
			--����� ���������-������, ���� ���������-������, ������ ��������� - ������������/���������/�����/������, ����� ����������� ��� ������-������
			I.idoc_Name N'@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, I.idoc_Date), 127) N'@date'

			-- ����� ������, ���� ������
			,@strqt_Name N'originOrder/@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, @strqt_Date), 127) N'originOrder/@date'

			-- �������
			,C.pcntr_Name N'contractIdentificator/@number'
			,CONVERT(NVARCHAR(MAX), CONVERT(DATE, C.pcntr_DateBegin), 127) N'contractIdentificator/@date'
				   
			--����� ���������, ���� ���������
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



-- ����� ��������� �� ��������
INSERT INTO KonturEDI.dbo.edi_Messages (msg_Id, msg_boxId, msg_Date, msg_RequestXML, msg_doc_ID, msg_doc_Name, msg_doc_Date, msg_doc_Type, msg_doc_ID_original)
VALUES (@msg_ID, @boxId, @msg_Date, @Result, @idoc_ID,  @idoc_Name, @idoc_Date, 'tp_InputDocuments', @strqt_ID)




