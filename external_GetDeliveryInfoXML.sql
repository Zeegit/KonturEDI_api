SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'external_GetDeliveryInfoXML', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_GetDeliveryInfoXML
GO

CREATE PROCEDURE dbo.external_GetDeliveryInfoXML  (
    @part_ID_From UNIQUEIDENTIFIER,
	@addr_ID_From UNIQUEIDENTIFIER,
    @part_ID_To UNIQUEIDENTIFIER,
	@addr_ID_To UNIQUEIDENTIFIER,
	@requestedDeliveryDateTime DATETIME,
	@DeliveryInfoXML XML OUTPUT)
AS
/*
    <!-- ������ ����� ������ � ���������������� � ��������������� -->
    <deliveryInfo>
      <requestedDeliveryDateTime>deliveryOrdersDateT00:00:00.000Z</requestedDeliveryDateTime>   <!--���� �������� �� ������ (������)-->
      <exportDateTimeFromSupplier>shipmentOrdersDateT00:00:00.000Z</exportDateTimeFromSupplier>   <!--���� ������ ������ �� ����������-->
      <shipFrom>
        <gln>ShipperGln</gln>  <!--gln ����������������-->
        <organization>
          <name>ShipperName</name>  <!--������������ ����������������-->
          <inn>ShipperInn(10)</inn>
          <kpp>ShipperKpp</kpp>
        </organization>
        <russianAddress>  <!--���������� �����-->
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
          <phone>TelephoneNumber</phone>   <!--������� ����������� ����-->
          <fax>FaxNumber</fax>     <!--���� ����������� ����-->
          <bankAccountNumber>BankAccountNumber</bankAccountNumber>
          <bankName>BankName</bankName>
          <BIK>BankId</BIK>
          <nameOfAccountant>BookkeeperName</nameOfAccountant>       <!--��� ����������-->
        </additionalInfo>
      </shipFrom>
      <shipTo>
        <gln>DeliveryGln</gln>  <!--gln ���������������-->
        <organization>
          <name>DeliveryName</name>  <!--������������ ���������������-->
          <inn>DeliveryInn(10)</inn>  <!--��� ���������������-->
          <kpp>DeliveryKpp</kpp>  <!--��� ���������������-->
        </organization>
        <russianAddress>  <!--���������� �����-->
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
          <phone>TelephoneNumber</phone> <!--������� ����������� ����-->
          <fax>FaxNumber</fax>   <!--���� ����������� ����-->
          <bankAccountNumber>BankAccountNumber</bankAccountNumber>
          <bankName>BankName</bankName>
          <BIK>BankId</BIK>
          <nameOfCEO>ChiefName</nameOfCEO>   <!--��� ������������-->
        </additionalInfo>
      </shipTo>
	  <ultimateCustomer>
        <gln>UltimateCustomerGln</gln>  <!--gln �������� ����� ��������-->
        <organization>
          <name>UltimateCustomerName</name>  <!--������������ �������� ����� ��������-->
          <inn>UltimateCustomerInn(10)</inn>  <!--��� �������� ����� ��������-->
          <kpp>UltimateCustomerKpp</kpp>  <!--��� �������� ����� ��������-->
        </organization>
        <russianAddress>  <!--���������� �����-->
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
          <phone>TelephoneNumber</phone> <!--������� ����������� ����-->
          <fax>FaxNumber</fax>   <!--���� ����������� ����-->
          <bankAccountNumber>BankAccountNumber</bankAccountNumber>
          <bankName>BankName</bankName>
          <BIK>BankId</BIK>
          <nameOfCEO>ChiefName</nameOfCEO>   <!--��� ������������-->
        </additionalInfo>
      </ultimateCustomer>
      <transportation>
        <vehicleArrivalDateTime>deliveryDateForVehicleT00:00:00.000Z</vehicleArrivalDateTime> <!--���������� � ��������� ����� ��� ������� ������ �����������. ������ ����� ��������� ���� - � ��������� �������� "transportation"-->
      </transportation>
      <transportBy>TransportBy</transportBy>  <!--��� ���������� � ��������� ������-->
    </deliveryInfo>
    <!-- ����� ����� ������ � ���������������� � ��������������� -->
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

SET @DeliveryInfoXML = 
	(SELECT
		  CONVERT(NVARCHAR(MAX), @requestedDeliveryDateTime, 127) N'requestedDeliveryDateTime'
		 ,NULL N'exportDateTimeFromSupplier'
		,(SELECT 
			CONVERT(NVARCHAR(MAX), note_Value) N'gln' --gln ����������
			,(SELECT 
				NULL N'additionalInfoHere'
			WHERE @ShowAdditionalInfo = 1
			FOR XML PATH(N''), TYPE)
		FROM Partners        P
		LEFT JOIN tp_Notes      N ON N.note_obj_ID = P.part_ID AND N.note_nttp_ID = @nttp_ID_GLN
		WHERE part_ID = @part_ID_From
		FOR XML PATH(N'shipFrom'), TYPE)
		,(SELECT
			 CONVERT(NVARCHAR(MAX), note_Value) N'gln'
			,(SELECT 
			    NULL N'NULL'
				--���������� �����
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
				WHERE addr_ID = @addr_ID_To
				FOR XML PATH(N'russianAddress'), TYPE)
			WHERE @ShowAdditionalInfo = 1
			FOR XML PATH(N''), TYPE)
     	FROM Partners        P
		LEFT JOIN Firms      F ON F.firm_ID = P.part_firm_ID
		LEFT JOIN Notes      N ON N.note_obj_ID = P.part_ID AND N.note_nttp_ID = @nttp_ID_GLN
		WHERE part_ID = @part_ID_To
		FOR XML PATH(N'shipTo'), TYPE)
	FOR XML PATH(N'deliveryInfo'), TYPE)

