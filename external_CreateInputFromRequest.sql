
IF OBJECT_ID(N'external_CreateInputFromRequest', 'P') IS NOT NULL 
  DROP PROCEDURE dbo.external_CreateInputFromRequest
GO

CREATE PROCEDURE dbo.external_CreateInputFromRequest (
     @strqt_ID UNIQUEIDENTIFIER
	,@name NVARCHAR(200)
	,@date DATETIME
	,@idoc_ID UNIQUEIDENTIFIER OUTPUT
	,@idoc_Name NVARCHAR(MAX) OUTPUT
    ,@idoc_Date DATETIME OUTPUT)
WITH EXECUTE AS OWNER
AS

DECLARE 
	 @idoc_stor_ID UNIQUEIDENTIFIER
	,@idoc_usr_ID UNIQUEIDENTIFIER

DECLARE
     @nttp_ID_idoc_name UNIQUEIDENTIFIER 
    ,@nttp_ID_idoc_date UNIQUEIDENTIFIER 
    ,@note_ID_idoc_name UNIQUEIDENTIFIER
    ,@note_ID_idoc_date UNIQUEIDENTIFIER
    ,@tpsyso_ID UNIQUEIDENTIFIER

SELECT @nttp_ID_idoc_name = nttp_ID_idoc_name, @nttp_ID_idoc_date = nttp_ID_idoc_date
FROM  KonturEDI.dbo.edi_Settings


SELECT @idoc_ID = NEWID(),  @idoc_Date = GETDATE()

SELECT @idoc_stor_ID = strqt_stor_ID_In, @idoc_usr_ID = strqt_usr_ID
FROM StoreRequests
WHERE strqt_ID = @strqt_ID

-- Номер документа
DECLARE @Res INT, @D DATETIME
SET @D = DATEADD(yy, DATEPART(yy, @idoc_Date) - 1900, 0)

EXEC dnf_GetCounter 
      @Name = 'TransparentDocumentCounter', 
      @DataID1 = @idoc_stor_ID, 
      @DataID2 = @idoc_usr_ID, 
      @Date = @D, 
      @Value = @Res OUT

SELECT @idoc_Name = CONVERT(NVARCHAR(50), @Res) 
--

IF OBJECT_ID('tempdb..#StoreRequestItemInputDocumentItems') IS NOT NULL DROP TABLE #StoreRequestItemInputDocumentItems

CREATE TABLE #StoreRequestItemInputDocumentItems (
	sriidi_ID UNIQUEIDENTIFIER,
	sriidi_strqti_ID UNIQUEIDENTIFIER,
	sriidi_idit_ID UNIQUEIDENTIFIER,
	sriidi_Volume NUMERIC(18, 6))

INSERT INTO #StoreRequestItemInputDocumentItems (sriidi_ID, sriidi_strqti_ID, sriidi_idit_ID, sriidi_Volume)
SELECT NEWID(), strqti_ID, NEWID(), strqti_Volume
FROM StoreRequestItems
WHERE strqti_strqt_ID = @strqt_ID

-- Приход
INSERT INTO InputDocuments (idoc_ID, idoc_stor_ID, idoc_part_ID, idoc_usr_ID, idoc_idst_ID, idoc_sens_ID, idoc_Date, idoc_Name, idoc_ExternalName, idoc_Description)
SELECT @idoc_ID, strqt_stor_ID_In, strqt_part_ID_Out, strqt_usr_ID, 0, 0,  GETDATE(), @idoc_Name, @name, 'Автоматически создано'
FROM StoreRequests
WHERE strqt_ID = @strqt_ID

-- Позиции
INSERT INTO InputDocumentItems (idit_ID, idit_idoc_ID, idit_pitm_ID, idit_meit_ID, idit_ItemName, idit_Article, 
    idit_idtp_ID, idit_IdentifierCode, idit_Volume, idit_Price, idit_Sum, idit_VAT, idit_SumVAT, idit_EditIndex, 
	idit_Comment, idit_Order)
SELECT T.sriidi_idit_ID, @idoc_ID, strqti_pitm_ID, strqti_meit_ID, strqti_ItemName, strqti_Article, 
    strqti_idtp_ID, strqti_IdentifierCode, strqti_Volume, strqti_Price, strqti_Sum, strqti_VAT, strqti_SumVAT, strqti_EditIndex,
    strqti_Comment, strqti_Order
FROM #StoreRequestItemInputDocumentItems T
JOIN StoreRequestItems                   I ON I.strqti_ID = T.sriidi_strqti_ID

-- Связки
INSERT INTO StoreRequestItemInputDocumentItems (sriidi_ID, sriidi_strqti_ID, sriidi_idit_ID, sriidi_Volume)
SELECT sriidi_ID, sriidi_strqti_ID, sriidi_idit_ID, sriidi_Volume
FROM #StoreRequestItemInputDocumentItems

UPDATE I
SET I.strqti_strqtist_ID = 1
FROM #StoreRequestItemInputDocumentItems T
JOIN StoreRequestItems                   I ON I.strqti_ID = T.sriidi_strqti_ID

-- Заметки
SELECT @tpsyso_ID = tpsyso_ID
FROM sys_Objects
WHERE tpsyso_Name like '%Приходная накладная%'

IF @tpsyso_ID IS NULL
    EXEC tpsys_RaiseError 50001, 'tpsyso_ID IS NULL'

SELECT @note_ID_idoc_name = note_ID FROM Notes WHERE note_nttp_ID = @nttp_ID_idoc_name AND note_obj_ID = @idoc_ID
SELECT @note_ID_idoc_date = note_ID FROM Notes WHERE note_nttp_ID = @nttp_ID_idoc_date AND note_obj_ID = @idoc_ID
--
DELETE FROM Notes WHERE note_nttp_ID = @nttp_ID_idoc_name AND note_obj_ID = @idoc_ID
DELETE FROM Notes WHERE note_nttp_ID = @nttp_ID_idoc_date AND note_obj_ID = @idoc_ID

--SELECT @note_ID_idoc_name, @note_ID_idoc_date
---SELECT @tpsyso_ID, @nttp_ID_idoc_name, @nttp_ID_idoc_date

INSERT INTO tp_Notes (note_ID, note_nttp_ID, note_obj_ID, note_item_ID, note_Value, note_tpsyso_ID)
VALUES(NEWID(), @nttp_ID_idoc_name, @idoc_ID, @idoc_ID, @name, @tpsyso_ID)

INSERT INTO tp_Notes (note_ID, note_nttp_ID, note_obj_ID, note_item_ID, note_Value, note_tpsyso_ID)
VALUES(NEWID(), @nttp_ID_idoc_date, @idoc_ID, @idoc_ID, @date, @tpsyso_ID)

/*
IF @note_ID_idoc_name IS NULL
    INSERT INTO Notes (note_ID, note_nttp_ID, note_obj_ID, note_item_ID, note_Value, note_tpsyso_ID)
    VALUES(NEWID(), @nttp_ID_idoc_name, @idoc_ID, @idoc_ID, @name, @tpsyso_ID)
ELSE 
    UPDATE Notes
	SET note_Value = @name 
	WHERE note_ID = @note_ID_idoc_name
--
IF @note_ID_idoc_date IS NULL
    INSERT INTO tp_Notes (note_ID, note_nttp_ID, note_obj_ID, note_item_ID, note_Value, note_tpsyso_ID)
    VALUES(NEWID(), @nttp_ID_idoc_date, @idoc_ID, @idoc_ID, @date, @tpsyso_ID)
ELSE 
    UPDATE Notes
	SET note_Value = @date 
	WHERE note_ID = @note_ID_idoc_date
--
*/

