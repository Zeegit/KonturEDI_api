SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'external_GetInvoiceeXML', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_GetInvoiceeXML
GO

CREATE PROCEDURE dbo.external_GetInvoiceeXML  (
    @part_ID UNIQUEIDENTIFIER,
	@InvoiceeXML XML OUTPUT)
AS
/*
    <!-- начало блока с данными о получателе счёта -->
    <invoicee>
      <gln>InvoiceeGln</gln>  <!--gln получателя счёта-->
      <selfEmployed>  
        <fullName>      <!--ФИО получателя счёта для ИП-->
          <lastName>Фамилия</lastName>
          <firstName>Имя</firstName>
          <middleName>Отчество</middleName>
        </fullName>
        <inn>InvoiceeInn(12)</inn>  <!--ИНН получателя счёта-->
      </selfEmployed>
      <russianAddress>    <!--российский адрес-->
        <regionISOCode>RegionCode</regionISOCode>
        <district>district</district>
        <city>City</city>
        <settlement>Village</settlement>
        <street>Street</street>
        <house>House</house>
        <flat>Flat</flat>
        <postalCode>>PostalCode</postalCode>
      </russianAddress>
      <additionalInfo>
        <phone>TelephoneNumber</phone> <!--телефон контактного лица-->
        <fax>FaxNumber</fax>  <!--факс контактного лица-->
        <bankAccountNumber>BankAccountNumber</bankAccountNumber>
        <bankName>BankName</bankName>
        <BIK>BankId</BIK>
        <nameOfAccountant>BookkeeperName</nameOfAccountant>  <!--ФИО бухгалтера-->
      </additionalInfo>
    </invoicee>
    <!--конец блока с данными о получателе счёта -->
*/

/*SELECT TOP 1 @part_ID = R.strqt_part_ID_Out
FROM KonturEDI.dbo.edi_Messages M
JOIN tp_StoreRequests           R ON R.strqt_ID = M.doc_ID
--JOIN tp_StoreRequestItems       I ON I.strqti_strqt_ID = M.doc_ID
WHERE M.messageId = @messageId*/

SET @InvoiceeXML = 
(
	SELECT 
	 	 CONVERT(NVARCHAR(MAX), note_Value) N'gln' -- dbo.f_MultiLanguageStringToStringByLanguage1(part_Description, 25) N'gln' --gln поставщика
		,dbo.f_MultiLanguageStringToStringByLanguage1(part_Name, 25) N'organization/name' --наименование поставщика для ЮЛ	
		,dbo.f_MultiLanguageStringToStringByLanguage1(firm_INN, 25) N'organization/inn' --ИНН поставщика для ЮЛ
		,dbo.f_MultiLanguageStringToStringByLanguage1(firm_KPP, 25) N'organization/kpp' --КПП поставщика только для ЮЛ
		--российский адрес
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_RegionCode, 25) N'russianAddress/regionISOCode'
    	,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Area, 25) N'russianAddress/district'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_City, 25) N'russianAddress/city'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Village, 25) N'russianAddress/settlement'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Street, 25) N'russianAddress/street'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_House, 25) N'russianAddress/house'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Apartment, 25) N'russianAddress/flat'
        ,dbo.f_MultiLanguageStringToStringByLanguage1(addr_PostCode, 25) N'russianAddress/postalCode'
		-- Контактная информация
        ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_PhoneWork, ''), 25) N'contactlInfo/CEO/orderContact'--телефон контактного лица
        ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_PhoneCell, ''), 25) N'contactlInfo/CEO/fax'--факс контактного лица
        ,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_EMail, ''), 25) N'contactlInfo/CEO/email'--email контактного лица
       
		
	FROM tp_Partners       P
	LEFT JOIN tp_Firms     F ON F.firm_ID = P.part_firm_ID
	LEFT JOIN tp_Addresses A ON A.addr_obj_ID = F.firm_ID AND addr_Type = 2 -- CASE WHEN T2.part_firm_ID IS NULL THEN 3 ELSE 2 END AdddrType  -- рабочий (ФЛ) или юридический (ЮЛ) адрес
	LEFT JOIN tp_People PD ON PD.pepl_ID = F.firm_pepl_ID_Director
	LEFT JOIN tp_Notes      N ON N.note_obj_ID = P.part_ID AND N.note_nttp_ID = '74D6E928-475B-4F4C-8BC7-C216DEF422D6'
	WHERE part_ID = @part_ID
	FOR XML PATH(N'invoicee'), TYPE
)

