IF OBJECT_ID(N'external_GetBoxId ', 'P') IS NOT NULL
  DROP PROCEDURE dbo.external_GetBoxId
GO


CREATE PROCEDURE [dbo].[external_GetBoxId]  (
	@part_ID UNIQUEIDENTIFIER,
	@boxId NVARCHAR(MAX) OUTPUT)
AS

SET @boxId = '5f7426aa-c745-4fbf-ad6d-9e25215c572d'	