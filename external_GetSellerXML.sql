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
    <!-- начало блока данных о поставщике -->
    <seller>
      <gln>SupplierGln</gln>  <!--gln поставщика-->
      <organization>
        <name>SupplierName</name>  <!--наименование поставщика для ЮЛ-->
        <inn>SupplierInn(10)</inn>       <!--ИНН поставщика для ЮЛ-->
        <kpp>SupplierKpp</kpp>       <!--КПП поставщика только для ЮЛ-->
      </organization>
      <russianAddress>      <!--российский адрес-->
        <regionISOCode>RegionCode</regionISOCode>
        <district>District</district>
        <city>City</city>
        <settlement>Village</settlement>
        <street>Street</street>
        <house>House</house>
        <flat>Flat</flat>
        <postalCode>PostalCode</postalCode>
      </russianAddress>
      <additionalIdentificator>SupplierCodeInBuyerSystem</additionalIdentificator>  <!--код поставщика в системе покупателя-->
      <additionalInfo>
        <phone>TelephoneNumber</phone>  <!--телефон контактного лица-->
        <fax>FaxNumber</fax>    <!--факс контактного лица-->
        <bankAccountNumber>BankAccountNumber</bankAccountNumber>     <!--номер счёта в банке-->
        <bankName>BankName</bankName>     <!--наименование банка-->
        <BIK>BankId</BIK>      <!--БИК-->
        <nameOfCEO>ChiefName</nameOfCEO>   <!--ФИО руководителя организации-->
        <orderContact>OrderContactName</orderContact> <!--ФИО контактного лица заказа-->
      </additionalInfo>
    </seller>
    <!-- конец блока данных о поставщике -->
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
	 	 CONVERT(NVARCHAR(MAX), note_Value) N'gln' --gln поставщика
        ,(SELECT
		     dbo.f_MultiLanguageStringToStringByLanguage1(part_Name, 25) N'organization/name' --наименование поставщика для ЮЛ	
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(firm_INN, 25) N'organization/inn' --ИНН поставщика для ЮЛ
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(firm_KPP, 25) N'organization/kpp' --КПП поставщика только для ЮЛ
		    -- российский адрес
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
		    ,dbo.f_MultiLanguageStringToStringByLanguage1(PD.pepl_PhoneWork, 25) N'additionalInfo/phone' --телефон контактного лица
            ,NULL N'additionalInfo/fax'--факс контактного лица
            ,firm_AccountNumber N'additionalInfo/bankAccountNumber'--номер счёта в банке
            ,NULL N'additionalInfo/bankName'--наименование банка
            ,NULL N'additionalInfo/BIK'--БИК
            ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_SecondName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_FirstName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_Patronymic, ''), 25) N'additionalInfo/nameOfCEO'--ФИО руководителя организации
            ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_SecondName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_FirstName, ''), 25) + ' ' +
		     dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_Patronymic, ''), 25) N'additionalInfo/orderContact'--ФИО контактного лица заказа
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
-- CASE WHEN T2.part_firm_ID IS NULL THEN 3 ELSE 2 END AdddrType  -- рабочий (ФЛ) или юридический (ЮЛ) адрес