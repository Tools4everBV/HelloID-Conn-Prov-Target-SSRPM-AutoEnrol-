
/*
#####################################################
# HelloID-Conn-Prov-Target-SSRPM-AutoEnroll-stored-procedures
#
# Version: 2.0.0
#####################################################
*/


/****** Object:  StoredProcedure [dbo].[EnrollUser]    Script Date: 22/01/2024 10:34:17 ******/
USE [MSSQLSSRPM] --change into your database name

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		JK@Tools4Ever
-- Create date: 10/16/2013
-- Description:	Auto enrolls a user into SSRPM and sets specific answers to the questions contained within the profile
---			@XML_Answers = <answers><a1>John</a1><a2>Pat</a2>...</answers>
--- RN: 2024-01-22: Answers are optional; added option to add mobile and personal e-mail
-- =============================================
CREATE PROCEDURE [dbo].[EnrollUser]
	@ProfileID int,
	@AD_CanonicalName varchar(max),
	@AD_sAMAccountName varchar(255),
	@AD_ObjectSID varchar(255),
	@AD_CommonName varchar(255) = null,
	@AD_DisplayName varchar(255) = null,
	@AD_SurName varchar(255) = null,
	@AD_GivenName varchar(255) = null,
	@AD_EmailAddress varchar(255),
	@Private_Mobile varchar(255) = null,
	@Private_EmailAddress varchar(255) = null,
	@XML_Answers XML = null
AS
BEGIN

-----------DEBUGGING VARIABLES----------------
	--DECLARE @ProfileID int
	--DECLARE @AD_CanonicalName varchar(max)
	--DECLARE @AD_sAMAccountName varchar(255)
	--DECLARE @AD_ObjectSID varchar(255)
	--DECLARE @XML_Answers XML
	
	--SET @ProfileID = 10
	--SET @AD_CanonicalName = 'sbdom.sbcusd/Administrative/BOED/COMM/Sb2000Guy'
	--SET @AD_sAMAccountName = 'Sb2000Guy'
	--SET @AD_ObjectSID = 'S-1-5-21-345178246-944841410-569397357-13077'
	--SET @XML_Answers = '<answers><a id="31">1111</a><a id="32">1111</a></answers>'
	
-----------END DEBUGGING VARIABLES--------------
	DECLARE @AnswerType int
	SET @AnswerType = 3
	
	declare @ProfileName varchar(255),
			@Options bigint,
			@NewUserID int
			
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	select @ProfileName = [Profile Name],
			@Options = [Options]
		from Profiles where [ProfileID] = @ProfileID

	declare @ExistingCount int
	set @ExistingCount = 0
	select @ExistingCount = COUNT(*) From [Enrolled Users] 
		  where sAMAccountName = @AD_sAMAccountName and 
				[Account SID] = @AD_ObjectSID and
				[Profile Name] = @ProfileName
	if(@ExistingCount > 0)
		begin
			return;
		end		
	select pq.[ProfileID]
		  ,pq.[QuestionID]
		  ,q.Question into #questions
		from [Profile Questions] pq
			inner join Questions q on pq.questionid = q.questionid where pq.profileid = @ProfileID

	insert into [Enrolled Users] ([Account Name] 
		,[Enrollment Time] 
		,[Block Time] 
		,[Block Count] 
		,[Reset Time] 
		,[Reset Count] 
		,[Failed Reset Count] 
		,[Profile Name] 
		,[Profile Options] 
		,[Account SID] 
		,[Blocked] 
		,[IncorrectAnswerCount] 
		,[LastIncorrectAnswer Time] 
		,[Mobile Phone Number] 
		,[Email Address] 
		,[sAMAccountName] 
		,[InternalEmailAddress]
		,[AD_CommonName]
		,[AD_DisplayName]
		,[AD_SurName]
		,[AD_GivenName]
		,[AD_Name]
		,[AD_UserPrincipalName])
	values (@AD_CanonicalName
		,GETDATE() 
		,'1900-01-01 00:00:00.000' 
		,0 
		,'1900-01-01 00:00:00.000' 
		,0 
		,0 
		,@ProfileName 
		,@Options 
		,@AD_ObjectSID 
		,NULL
		,NULL
		,NULL
		,ISNULL(@Private_Mobile,'')
		,ISNULL(@Private_EmailAddress,'')
		,@AD_sAMAccountName 
		,ISNULL(@AD_EmailAddress,'')
		,@AD_CommonName
		,@AD_DisplayName
		,@AD_SurName
		,@AD_GivenName
		,@AD_sAMAccountName
		,@AD_EmailAddress
		)
	select @NewUserID = SCOPE_IDENTITY()

	--now loop thru the questions to insert all the q/a's into the User Answers table
	DECLARE @MaxQuestionID int,
				@MinQuestionID int,
				@UserQuestion varchar(255),
				@UserAnswer varchar(255)
	
	
	SELECT @MaxQuestionID = MAX(QuestionID), 
			@MinQuestionID = MIN(QuestionID) FROM #questions
	
	WHILE (@MinQuestionID <= @MaxQuestionID)
	BEGIN
	
		select @UserQuestion = Question from #questions where QuestionID = @MinQuestionID

		select @UserAnswer = @XML_Answers.value('(/answers/a[@id=sql:variable("@MinQuestionID")])[1]', 'varchar(255)')
	if (@UserAnswer is not null)
		begin
			insert into [User Answers] ([Account ID] 
				,[Question] 
				,[Answer] 
				,[MD5Hash] 
				,[Type] 
				,[HelpdeskAuthRequiredCharacterIndices] 
				,[HelpdeskAuthGeneratedOn] 
				,[EncryptedAnswer])
			values (@NewUserID
				,@UserQuestion 
				,@UserAnswer 
				,'' 
				,@AnswerType
				,NULL 
				,NULL 
				,NULL)
		end
		SELECT @MinQuestionID = MIN(QuestionID) 
			FROM #questions 
			WHERE QuestionID > @MinQuestionID
		
	END
		
	drop table #questions
END
GO

USE [MSSQLSSRPM]
GO

/****** Object:  StoredProcedure [dbo].[UpdateUser]    Script Date: 22/01/2024 10:35:51 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		JK@Tools4Ever
-- Create date: 10/16/2013
-- Description:	Auto enrolls a user into SSRPM and sets specific answers to the questions contained within the profile
---			@XML_Answers = <answers><a1>John</a1><a2>Pat</a2>...</answers>
--- RN: 2024-01-22: Answers are optional; added option to add mobile and personal e-mail
-- =============================================
CREATE PROCEDURE [dbo].[UpdateUser]
	@SSRPM_ID varchar(255),
	@AD_CanonicalName varchar(max),
	@AD_sAMAccountName varchar(255),
	@AD_ObjectSID varchar(255),
	@AD_EmailAddress varchar(255),
	@Private_Mobile varchar(255) = null,
	@Private_EmailAddress varchar(255) = null,
	@AD_CommonName varchar(255) = null,
	@AD_DisplayName varchar(255) = null,
	@AD_SurName varchar(255) = null,
	@AD_GivenName varchar(255) = null,
	@XML_Answers XML = null

AS
BEGIN

-----------DEBUGGING VARIABLES----------------
	--DECLARE @ProfileID int
	--DECLARE @AD_CanonicalName varchar(max)
	--DECLARE @AD_sAMAccountName varchar(255)
	--DECLARE @AD_ObjectSID varchar(255)
	--DECLARE @XML_Answers XML
	
	--SET @ProfileID = 10
	--SET @AD_CanonicalName = 'sbdom.sbcusd/Administrative/BOED/COMM/Sb2000Guy'
	--SET @AD_sAMAccountName = 'Sb2000Guy'
	--SET @AD_ObjectSID = 'S-1-5-21-345178246-944841410-569397357-13077'
	--SET @XML_Answers = '<answers><a id="31">1111</a><a id="32">1111</a></answers>'
	
-----------END DEBUGGING VARIABLES--------------
	DECLARE @AnswerType int = 3

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	declare @ExistingCount int
	declare @profileName varchar(255)

	set @ExistingCount = 0
	select @ExistingCount = COUNT(*)From [Enrolled Users] 
		  WHERE id = @SSRPM_ID 
	
	select @profileName = [Profile Name] From [Enrolled Users] 
		  WHERE id = @SSRPM_ID 

	select pq.[ProfileID]
		  ,pq.[QuestionID]
		  ,q.Question into #questions
		from [Profile Questions] pq
			inner join Questions q on pq.questionid = q.questionid 
			INNER JOIN Profiles p on pq.ProfileID = p.ProfileID
			WHERE P.[Profile Name] = @profileName
				
	if(@ExistingCount = 1)
		begin
		update [Enrolled Users]
		set sAMAccountName = @AD_sAMAccountName
			,[Account SID] = @AD_ObjectSID
			,[Account Name] = @AD_CanonicalName
			,[InternalEmailAddress] = @AD_EmailAddress
			,[Email Address] = @Private_EmailAddress
			,[Mobile Phone Number] = @Private_Mobile
			,[AD_CommonName] = @AD_CommonName
			,[AD_DisplayName] = @AD_DisplayName
			,[AD_SurName] = @AD_SurName
			,[AD_GivenName] = @AD_GivenName
			,[AD_Name] = @AD_sAMAccountName
			,[AD_UserPrincipalName] = @AD_EmailAddress
		WHERE ID = @SSRPM_ID
		end


	DECLARE @MaxQuestionID int,
				@MinQuestionID int,
				@UserQuestion varchar(255),
				@UserAnswer varchar(255)
	
	
	SELECT @MaxQuestionID = MAX(QuestionID), 
			@MinQuestionID = MIN(QuestionID) FROM questions
	
	WHILE (@MinQuestionID <= @MaxQuestionID)
	BEGIN

		select @UserQuestion = Question from questions where QuestionID = @MinQuestionID
		select @UserAnswer = @XML_Answers.value('(/answers/a[@id=sql:variable("@MinQuestionID")])[1]', 'varchar(255)')
		
	if (@UserAnswer is not null)
		begin
		print 'userquestion: '+@UserQuestion
		print '@UserAnswer: '+@UserAnswer
		print '@UserAnswer: '+@UserAnswer


		UPDATE [dbo].[User Answers]
		   SET 
			  [Answer] = @UserAnswer 
			  ,[MD5Hash] = ''
			  ,[Type] = @AnswerType
		 WHERE [Account ID] = @SSRPM_ID
		       AND [Question] = @UserQuestion

		-- insert if user-answer combination does not exists
		IF @@ROWCOUNT = 0
		BEGIN
			INSERT INTO [dbo].[User Answers]
				([Account ID]
				,[Question]
				,[Answer]
				,[MD5Hash]
				,[Type]
				)
			VALUES
				(@SSRPM_ID
				,@userQuestion
				,@UserAnswer
				,''
				,@AnswerType
				)
		END

		END
		SELECT @MinQuestionID = MIN(QuestionID) 
			FROM #questions 
			WHERE QuestionID > @MinQuestionID
	END
		
	drop table #questions
	
END
GO


USE [MSSQLSSRPM]
GO

/****** Object:  StoredProcedure [dbo].[deleteUser]    Script Date: 22/01/2024 10:36:17 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		JK@Tools4Ever
-- Create date: 10/16/2013
-- Description:	Auto enrolls a user into SSRPM and sets specific answers to the questions contained within the profile
---			@XML_Answers = <answers><a1>John</a1><a2>Pat</a2>...</answers>
-- =============================================
CREATE PROCEDURE [dbo].[deleteUser]
	@SSRPM_ID varchar(255)
AS
BEGIN

	DELETE [Enrolled Users]
		WHERE ID = @SSRPM_ID

	DELETE [User Answers]
		WHERE [Account ID] = @SSRPM_ID
	
END
GO

