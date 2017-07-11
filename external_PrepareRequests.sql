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

-- ��������� ��������� �������
SELECT @nttp_ID_Measure = nttp_ID_Measure, @Measure_Default = Measure_Default, @Currency_Default = Currency_Default, @idtp_ID_GTIN = idtp_ID_GTIN
FROM KonturEDI.dbo.edi_Settings


DECLARE ct CURSOR FOR
    SELECT R.strqt_ID, R.strqt_Name, R.strqt_DateInput, R.strqt_Date, G.stgr_part_ID, R.strqt_part_ID_Out, addr_ID
	FROM StoreRequests R 
	-- ������
	JOIN Stores      S ON S.stor_ID = strqt_stor_ID_In
	JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
	-- ���� �����������
	-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
	-- ����� ������
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

	-- ��������� BoxId
	EXEC external_GetBoxId @part_ID_Self, @boxId OUTPUT

	-- �������� ������
	SET @LineItem = 
	(SELECT
		CASE
			WHEN strqti_idtp_ID = @idtp_ID_GTIN THEN strqti_IdentifierCode
			ELSE ''
		END 'gtin'
		-- CONVERT(NVARCHAR(MAX), N.note_Value) N'gtin' -- GTIN ������
		-- ,P.pitm_ID N'internalBuyerCode' --���������� ��� ����������� �����������
		,P.pitm_ID N'internalBuyerCode' --���������� ��� ����������� �����������
		,I.strqti_Article N'internalSupplierCode' --������� ������ (��� ������ ����������� ���������)
		,I.strqti_Order N'lineNumber' --���������� ����� ������
		,NULL N'typeOfUnit' --������� ���������� ����, ���� ��� �� ����, �� ������ ���
		,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(I.strqti_ItemName, P.pitm_Name), 25) N'description' --�������� ������
		,dbo.f_MultiLanguageStringToStringByLanguage1(I.strqti_Comment, 25) N'comment' --����������� � �������� �������
		,ISNULL(CONVERT(NVARCHAR(MAX), NM.note_Value), @Measure_Default) N'requestedQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,I.strqti_Volume/MI.meit_Rate N'requestedQuantity/text()' --���������� ����������
		,NULL N'onePlaceQuantity/@unitOfMeasure' -- MeasurementUnitCode
		,NULL N'onePlaceQuantity/text()' -- ���������� � ����� ����� (���� �.�. ������ ����� ���-��)
		,'Direct' N'flowType' --��� ��������, ����� ��������� ��������: Stock - ���� �� ��, Transit - ������� � �������, Direct - ������ ��������, Fresh - ������ ��������
		,I.strqti_Price*MI.meit_Rate N'netPrice' --���� ������ ��� ���
		,I.strqti_Price*MI.meit_Rate+I.strqti_Price*MI.meit_Rate*I.strqti_VAT N'netPriceWithVAT' --���� ������ � ���
		,I.strqti_Sum N'netAmount' --����� �� ������� ��� ���
		,NULL N'exciseDuty' --����� ������
		,ISNULL(CONVERT(NVARCHAR(MAX), FLOOR(I.strqti_VAT*100)), 'NOT_APPLICABLE') N'vATRate' --������ ��� (NOT_APPLICABLE - ��� ���, 0 - 0%, 10 - 10%, 18 - 18%)
		,I.strqti_SumVAT N'vATAmount' --����� ��� �� �������
		,I.strqti_Sum+I.strqti_SumVAT N'amount' --����� �� ������� � ���
	FROM StoreRequestItems       I 
	JOIN ProductItems            P ON P.pitm_ID = I.strqti_pitm_ID
	JOIN MeasureItems            MI ON MI.meit_ID = strqti_meit_ID
	-- ������� ���������
	LEFT JOIN Notes              NM ON NM.note_obj_ID = strqti_meit_ID AND note_nttp_ID = @nttp_ID_Measure
	-- LEFT JOIN Notes               N ON N.note_obj_ID = P.pitm_ID
	WHERE strqti_strqt_ID = @strqt_ID
	FOR XML PATH(N'lineItem'), TYPE)

	SET @LineItems = 
		(SELECT
			 @Currency_Default N'currencyISOCode' --��� ������ (�� ��������� �����)
			,@LineItem
			,SUM(strqti_Sum) N'totalSumExcludingTaxes' -- ����� ������ ��� ���
			,SUM(strqti_SumVAT) N'totalVATAmount' -- ����� ��� �� ������
			,SUM(strqti_Sum + strqti_SumVAT) N'totalAmount' -- --����� ����� ������ ����� � ���
		FROM StoreRequests           R 
		JOIN StoreRequestItems       I ON I.strqti_strqt_ID = R.strqt_ID
		WHERE R.strqt_ID = @strqt_ID
		FOR XML PATH(N'lineItems'), TYPE)    

	/*SELECT TOP 1
		-- ���������
		@part_ID_Out = R.strqt_part_ID_Out
		-- ���� �����������
		,@part_ID_Self = G.stgr_part_ID
		-- ����� ������
		,@addr_ID = addr_ID
		,@strqt_DateInput = strqt_DateInput
	FROM StoreRequests R         
	-- ������
	JOIN Stores      S ON S.stor_ID = strqt_stor_ID_In
	JOIN StoreGroups G ON G.stgr_ID = S.stor_stgr_ID
	-- ���� �����������
	-- LEFT JOIN tp_Partners SelfParnter ON SelfParnter.part_ID = stgr_part_ID
	-- ����� ������
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
				--����� ���������-������, ���� ���������-������, ������ ��������� - ������������/���������/�����/������, ����� ����������� ��� ������-������
				R.strqt_Name N'@number'
				,CONVERT(NVARCHAR(MAX), CONVERT(DATE, R.strqt_Date), 127) N'@date'
				,R.strqt_ID N'@id'
				,N'Original' N'@status'
				,NULL N'@revisionNumber'

				,NULL N'promotionDealNumber'
				-- �������
				,C.pcntr_Name N'contractIdentificator/@number'
				,CONVERT(NVARCHAR(MAX),  CONVERT(DATE, C.pcntr_DateBegin), 127) N'contractIdentificator/@date'
				,@seller
				,@buyer
				,@invoicee
				,@deliveryInfo
				-- ���������� � �������
				,CONVERT(NVARCHAR(MAX), R.strqt_Description) N'comment'
				,@lineItems
				FOR XML PATH(N'order'), TYPE
		)
		FROM StoreRequests R           
		LEFT JOIN PartnerContracts      C ON C.pcntr_part_ID = R.strqt_part_ID_Out
		WHERE strqt_ID = @strqt_ID
		FOR XML RAW(N'eDIMessage'))

	-- ����� ��������� �� ��������
	INSERT INTO KonturEDI.dbo.edi_Messages (msg_Id, msg_boxId, msg_Date, msg_RequestXML, msg_doc_ID, msg_doc_Name, msg_doc_Date, msg_doc_Type)
	VALUES (@msg_ID, @boxId, @msg_Date, @Result, @strqt_ID, @strqt_Name, @strqt_Date, 'tp_StoreRequests')

	FETCH ct INTO @strqt_ID, @strqt_Name, @strqt_DateInput, @strqt_Date, @part_ID_Self, @part_ID_Out, @addr_ID
	              
END

CLOSE ct
DEALLOCATE ct

/*
DECLARE @TRANCOUNT INT

-- �������������� ������
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
	-- ������ �������� �����, ����� ������ ������
	IF @@TRANCOUNT > 0
		IF (XACT_STATE()) = -1
			ROLLBACK
		ELSE
			ROLLBACK TRAN external_PrepareORDERS
	
	IF @TRANCOUNT > @@TRANCOUNT
		BEGIN TRAN

	-- ������ � �������, ���������� �����
	INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage)
	SELECT 'external_PrepareORDERS', ERROR_NUMBER(), ERROR_MESSAGE()
	EXEC tpsys_ReraiseError
END CATCH
*/