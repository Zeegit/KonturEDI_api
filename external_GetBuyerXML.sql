SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'external_GetBuyerXML', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_GetBuyerXML
GO

CREATE PROCEDURE dbo.external_GetBuyerXML  (
     @part_ID UNIQUEIDENTIFIER
	,@addr_ID UNIQUEIDENTIFIER
	,@BuyerXML XML OUTPUT)
AS
/*
    <!-- начало блока с данными о покупателе -->
    <buyer>
      <gln>BuyerGln</gln> <!--gln покупателя-->
      <organization>
        <name>Buyer</name>  <!--наименование покупателя-->
        <inn>BuyerInn(10)</inn>  <!--ИНН покупателя для ЮЛ-->
        <kpp>BuyerKpp</kpp>  <!--КПП покупателя только для ЮЛ-->
      </organization>
      <russianAddress>  <!--российский адрес-->
        <regionISOCode>RegionCode</regionISOCode>
        <district>district</district>
        <city>City</city>
        <settlement>Village</settlement>
        <street>Street</street>
        <house>House</house>
        <flat>Flat</flat>
        <postalCode>>PostalCode</postalCode>
      </russianAddress>
      <contactlInfo>
        <CEO>
          <orderContact>TelephoneNumber</orderContact> <!--телефон контактного лица-->
          <fax>FaxNumber</fax> <!--факс контактного лица-->
          <email>Email</email> <!--email контактного лица-->
        </CEO>
        <accountant>
          <orderContact>TelephoneNumber</orderContact> <!--телефон контактного лица-->
          <fax>FaxNumber</fax> <!--факс контактного лица-->
          <email>Email</email> <!--email контактного лица-->
        </accountant>
        <salesManager>
          <orderContact>TelephoneNumber</orderContact> <!--телефон контактного лица-->
          <fax>FaxNumber</fax> <!--факс контактного лица-->
          <email>Email</email> <!--email контактного лица-->
        </salesManager>
        <orderContact>
          <orderContact>TelephoneNumber</orderContact> <!--телефон контактного лица-->
          <fax>FaxNumber</fax> <!--факс контактного лица-->
          <email>Email</email> <!--email контактного лица-->
        </orderContact>
      </contactlInfo>
    </buyer>
    <!-- конец блока данных о покупателе -->
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

SET @BuyerXML = 
	(SELECT 
	 	 CONVERT(NVARCHAR(MAX), N.note_Value) N'gln' --gln поставщика
        ,(SELECT
			 dbo.f_MultiLanguageStringToStringByLanguage1(part_Name, 25) N'organization/name' --наименование поставщика для ЮЛ	
			,dbo.f_MultiLanguageStringToStringByLanguage1(firm_INN, 25) N'organization/inn' --ИНН поставщика для ЮЛ
			,dbo.f_MultiLanguageStringToStringByLanguage1(firm_KPP, 25) N'organization/kpp' --КПП поставщика только для ЮЛ

			--российский адрес
			,(SELECT
				 dbo.f_MultiLanguageStringToStringByLanguage1(addr_RegionCode, 25) N'regionISOCode'
    			,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Area, 25) N'district'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_City, 25) N'city'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Village, 25) N'settlement'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Street, 25) N'street'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_House, 25) N'house'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_Apartment, 25) N'flat'
				,dbo.f_MultiLanguageStringToStringByLanguage1(addr_PostCode, 25) N'postalCode'
			FROM Addresses
			WHERE addr_ID = @addr_ID 
			FOR XML PATH(N'russianAddress'), TYPE) AS [*]
			-- Контактная информация
			,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_PhoneWork, ''), 25) N'contactlInfo/CEO/orderContact'--телефон контактного лица
			,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_PhoneCell, ''), 25) N'contactlInfo/CEO/fax'--факс контактного лица
			,dbo.f_MultiLanguageStringToStringByLanguage1(ISNULL(PD.pepl_EMail, ''), 25) N'contactlInfo/CEO/email'--email контактного лица
		  WHERE @ShowAdditionalInfo = 1
		  FOR XML PATH(N''), TYPE)

	FROM Partners       P
	LEFT JOIN Firms     F ON F.firm_ID = P.part_firm_ID 
	--LEFT JOIN tp_Addresses A ON A.addr_obj_ID = F.firm_ID AND addr_Type = 2 -- CASE WHEN T2.part_firm_ID IS NULL THEN 3 ELSE 2 END AdddrType  -- рабочий (ФЛ) или юридический (ЮЛ) адрес
	LEFT JOIN People   PD ON PD.pepl_ID = F.firm_pepl_ID_Director 
	LEFT JOIN Notes     N ON N.note_obj_ID = P.part_ID AND note_nttp_ID = @nttp_ID_GLN
    WHERE part_ID = @part_ID
	FOR XML PATH(N'buyer'), TYPE
)
