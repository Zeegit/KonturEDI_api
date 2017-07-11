SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'external_GetSellerXML', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_GetSellerXML
GO

CREATE PROCEDURE dbo.external_GetSellerXML (
    @part_ID UNIQUEIDENTIFIER,
	@SellerXML XML OUTPUT)
  
AS
/*
    <!-- ������ ����� ������ � ���������� -->
    <seller>
      <gln>SupplierGln</gln>  <!--gln ����������-->
      <organization>
        <name>SupplierName</name>  <!--������������ ���������� ��� ��-->
        <inn>SupplierInn(10)</inn>       <!--��� ���������� ��� ��-->
        <kpp>SupplierKpp</kpp>       <!--��� ���������� ������ ��� ��-->
      </organization>
      <russianAddress>      <!--���������� �����-->
        <regionISOCode>RegionCode</regionISOCode>
        <district>District</district>
        <city>City</city>
        <settlement>Village</settlement>
        <street>Street</street>
        <house>House</house>
        <flat>Flat</flat>
        <postalCode>PostalCode</postalCode>
      </russianAddress>
      <additionalIdentificator>SupplierCodeInBuyerSystem</additionalIdentificator>  <!--��� ���������� � ������� ����������-->
      <additionalInfo>
        <phone>TelephoneNumber</phone>  <!--������� ����������� ����-->
        <fax>FaxNumber</fax>    <!--���� ����������� ����-->
        <bankAccountNumber>BankAccountNumber</bankAccountNumber>     <!--����� ����� � �����-->
        <bankName>BankName</bankName>     <!--������������ �����-->
        <BIK>BankId</BIK>      <!--���-->
        <nameOfCEO>ChiefName</nameOfCEO>   <!--��� ������������ �����������-->
        <orderContact>OrderContactName</orderContact> <!--��� ����������� ���� ������-->
      </additionalInfo>
    </seller>
    <!-- ����� ����� ������ � ���������� -->
*/

/*SELECT TOP 1 @part_ID = R.strqt_part_ID_Out
FROM KonturEDI.dbo.edi_Messages M
JOIN tp_StoreRequests           R ON R.strqt_ID = M.doc_ID
--JOIN tp_StoreRequestItems       I ON I.strqti_strqt_ID = M.doc_ID
WHERE M.messageId = @messageId*/

DECLARE 
     @nttp_ID_GLN UNIQUEIDENTIFIER
    ,@ShowAdditionalInfo INT 

SELECT @nttp_ID_GLN = nttp_ID_GLN, @ShowAdditionalInfo = ShowAdditionalInfo
FROM KonturEDI.dbo.edi_Settings

SET @SellerXML = 
    (SELECT 
	 	 CONVERT(NVARCHAR(MAX), note_Value) N'gln' --gln ����������
        ,(SELECT
		     dbo.f_MultiLanguageStringToStringByLanguage1(part_Name, 25) N'organization/name' --������������ ���������� ��� ��	
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(firm_INN, 25) N'organization/inn' --��� ���������� ��� ��
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(firm_KPP, 25) N'organization/kpp' --��� ���������� ������ ��� ��
		    -- ���������� �����
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_RegionCode, 25) N'russianAddress/regionISOCode'
    	    ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Area, 25) N'russianAddress/district'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_City, 25) N'russianAddress/city'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Village, 25) N'russianAddress/settlement'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Street, 25) N'russianAddress/street'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_House, 25) N'russianAddress/house'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Apartment, 25) N'russianAddress/flat'
            ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_PostCode, 25) N'russianAddress/postalCode'
		    -- GUID
		    ,P.part_ID N'additionalIdentificator'	
		    -- additionalInfo
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(PD.pepl_PhoneWork, 25) N'additionalInfo/phone' --������� ����������� ����
            ,NULL N'additionalInfo/fax'--���� ����������� ����
            ,firm_AccountNumber N'additionalInfo/bankAccountNumber'--����� ����� � �����
            ,NULL N'additionalInfo/bankName'--������������ �����
            ,NULL N'additionalInfo/BIK'--���
            ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_SecondName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_FirstName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_Patronymic, ''), 25) N'additionalInfo/nameOfCEO'--��� ������������ �����������
            ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_SecondName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_FirstName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_Patronymic, ''), 25) N'additionalInfo/orderContact'--��� ����������� ���� ������
		  WHERE @ShowAdditionalInfo = 1
		  FOR XML PATH(N''), TYPE)
    FROM Partners        P
	LEFT JOIN Notes      N ON N.note_obj_ID = P.part_ID AND N.note_nttp_ID = @nttp_ID_GLN
	LEFT JOIN Firms      F ON F.firm_ID = P.part_firm_ID 
    LEFT JOIN Addresses  A ON A.addr_obj_ID = F.firm_ID AND addr_Type = 2
	LEFT JOIN People    PD ON PD.pepl_ID = F.firm_pepl_ID_Director 
	WHERE part_ID = @part_ID
	FOR XML PATH(N'seller'), TYPE)

-- SELECT @SellerXML
-- CASE WHEN T2.part_firm_ID IS NULL THEN 3 ELSE 2 END AdddrType  -- ������� (��) ��� ����������� (��) �����