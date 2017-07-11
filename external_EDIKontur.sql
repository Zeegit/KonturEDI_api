IF OBJECT_ID('external_EDIKontur', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_EDIKontur
GO

CREATE PROCEDURE dbo.external_EDIKontur  (
@TaskID UNIQUEIDENTIFIER)
WITH EXECUTE AS OWNER
AS
/*
    1. ���������
	2. ������
	3. �������
*/
INSERT INTO KonturEDI.dbo.edi_Errors (ProcedureName, ErrorNumber, ErrorMessage) 
VALUES ('external_EDIKontur', 50001, '������ "'+ISNULL(CONVERT(NVARCHAR(MAX), @TaskID), '<null>')+'" ���������')

DECLARE @TRANCOUNT INT
--SET @TRANCOUNT = @@TRANCOUNT
--IF @TRANCOUNT > 0 COMMIT TRAN

IF @TaskID IS NULL
   EXEC tpsys_RaiseError 50001, '������ TaskID'

DECLARE @cmd VARCHAR(200)

-- ������ 
--IF OBJECT_ID(N'tempdb..#EDIErrors') IS NOT NULL DROP TABLE #EDIErrors
--CREATE TABLE #EDIErrors (ProcedureName NVARCHAR(100), ErrorNumber INT, ErrorMessage NVARCHAR(2047))
TRUNCATE TABLE KonturEDI.dbo.edi_Errors

-- ���������
IF OBJECT_ID(N'tempdb..#EDISettings') IS NOT NULL DROP TABLE #EDISettings
CREATE TABLE #EDISettings (InboxPath NVARCHAR(MAX), OutboxPath NVARCHAR(MAX), ReportsPath NVARCHAR(MAX), 
    ActionsPath NVARCHAR(MAX), nttp_ID_GLN UNIQUEIDENTIFIER, nttp_ID_GTIN UNIQUEIDENTIFIER, nttp_ID_idoc_Name UNIQUEIDENTIFIER,
	nttp_ID_idoc_Date UNIQUEIDENTIFIER, nttp_ID_Status UNIQUEIDENTIFIER, nttp_ID_Log UNIQUEIDENTIFIER, nttp_ID_Measure UNIQUEIDENTIFIER,
	ShowAdditionalInfo INT, Measure_Default NVARCHAR(10), Currency_Default NVARCHAR(10))

INSERT INTO #EDISettings (/*InboxPath, OutboxPath, ReportsPath, ActionsPath,*/ nttp_ID_GLN, nttp_ID_GTIN, nttp_ID_idoc_Name, 
	nttp_ID_idoc_Date, nttp_ID_Status, nttp_ID_Log, nttp_ID_Measure, ShowAdditionalInfo, Measure_Default, Currency_Default)
SELECT TOP 1 /*InboxPath, OutboxPath, ReportsPath, ActionsPath,*/ nttp_ID_GLN, nttp_ID_GTIN, nttp_ID_idoc_Name, 
	nttp_ID_idoc_Date, nttp_ID_Status, nttp_ID_Log, nttp_ID_Measure, 0, Measure_Default, Currency_Default
FROM KonturEDI.dbo.edi_Settings


-- EXEC external_ExportPARTIN
--------------------------------------------------------------------------------
-- ����� ���������� ���������
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ����� �������� �����
--------------------------------------------------------------------------------

-- �������� �������
EXEC external_GetEvents
-- ���������� �������
EXEC external_ProcessEvents
-- ��������� ��������� �������
EXEC external_ExportMessages

--------------------------------------------------------------------------------
-- �������������� ������ �������
EXEC external_PrepareRequests
--  ��������� ��������� ������
EXEC external_ExportMessages 

-- �������������� �������
--z EXEC external_ExportRECADV
--------------------------------------------------------------------------------

-- ��������� ������
DECLARE 
	 @ErrorNumber INT
    ,@ErrorMessage NVARCHAR(2047)

--------------------------------------------------------------------------------

SELECT ErrorNumber, ProcedureName+' '+ErrorMessage
FROM KonturEDI.dbo.edi_Errors

DECLARE ct CURSOR FOR
    SELECT ErrorNumber, ISNULL(ProcedureName, '<proc_name>')+' '+ISNULL(ErrorMessage, '<error_message>')
	FROM KonturEDI.dbo.edi_Errors

OPEN ct
FETCH ct INTO @ErrorNumber, @ErrorMessage

WHILE @@FETCH_STATUS = 0 BEGIN 
 	EXEC tpsrv_AddTaskLogError @TaskID, 1, @ErrorMessage, 1
    FETCH ct INTO @ErrorNumber, @ErrorMessage
END

CLOSE ct
DEALLOCATE ct

TRUNCATE TABLE KonturEDI.dbo.edi_Errors

--IF @TRANCOUNT > @@TRANCOUNT BEGIN TRAN

--IF OBJECT_ID(N'tempdb..#EDIErrors') IS NOT NULL DROP TABLE #EDIErrors
--IF OBJECT_ID(N'tempdb..#EDISettings') IS NOT NULL DROP TABLE #EDISettings