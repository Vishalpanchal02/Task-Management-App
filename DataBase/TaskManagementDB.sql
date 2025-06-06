USE [TaskManagementDB]
GO
/****** Object:  Table [dbo].[taskData]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[taskData](
	[taskID] [int] IDENTITY(1,1) NOT NULL,
	[title] [nvarchar](max) NOT NULL,
	[description] [nvarchar](max) NOT NULL,
	[dueDate] [datetime] NOT NULL,
	[status] [nvarchar](50) NOT NULL,
	[remarks] [nvarchar](max) NULL,
	[createdOn] [datetime] NOT NULL,
	[updatedOn] [datetime] NULL,
	[createdBy] [int] NOT NULL,
	[updatedBy] [int] NULL,
 CONSTRAINT [PK_taskData] PRIMARY KEY CLUSTERED 
(
	[taskID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[userData]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[userData](
	[userID] [int] IDENTITY(100,1) NOT NULL,
	[firstName] [nvarchar](50) NOT NULL,
	[lastName] [nvarchar](50) NULL,
	[email] [nvarchar](50) NOT NULL,
	[password] [nvarchar](50) NOT NULL,
 CONSTRAINT [PK_userData] PRIMARY KEY CLUSTERED 
(
	[userID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  StoredProcedure [dbo].[spCreateUser]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[spCreateUser]
    @FirstName  NVARCHAR(50),
    @LastName   NVARCHAR(50)   = NULL,
    @Email      NVARCHAR(50),
    @Password   NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    -- Optional: check for existing email
    IF EXISTS (SELECT 1 FROM dbo.userData WHERE email = @Email)
    BEGIN
        RAISERROR('Email already in use.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.userData (firstName, lastName, email, password)
    VALUES (@FirstName, @LastName, @Email, @Password);

    SELECT SCOPE_IDENTITY() AS NewUserID;
END
GO
/****** Object:  StoredProcedure [dbo].[spValidateLogin]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[spValidateLogin]
    @Email    NVARCHAR(50),
    @Password NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM dbo.userData
        WHERE email    = @Email
          AND password = @Password
    )
    BEGIN
        SELECT
            CAST(1 AS BIT)   AS LoginSuccess,
            userID           AS UserID,
            firstName        AS FirstName,
            lastName         AS LastName
        FROM dbo.userData
        WHERE email    = @Email
          AND password = @Password;
    END
    ELSE
    BEGIN
        SELECT
            CAST(0 AS BIT)   AS LoginSuccess,
            NULL             AS UserID,
            NULL             AS FirstName,
            NULL             AS LastName;
    END
END
GO
/****** Object:  StoredProcedure [dbo].[UpsertTask]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[UpsertTask]
    @taskID      INT               = NULL,         -- pass NULL or omit for INSERT
    @title       NVARCHAR(MAX),                     -- required
    @description NVARCHAR(MAX),                     -- required
    @dueDate     DATETIME,                          -- required
    @status      NVARCHAR(50)      = NULL,         -- pass 'Completed' or leave NULL on update
    @remarks     NVARCHAR(MAX)      = NULL,         -- optional
    @userID      INT                              -- who creates/updates
AS
BEGIN
	begin try
		SET NOCOUNT ON;

		IF @taskID IS NULL OR @taskID = 0
		BEGIN
			-- INSERT new row, status always starts as 'Pending'
			INSERT INTO dbo.taskData
				(title, description, dueDate, status, remarks, createdOn, createdBy)
			VALUES
				(@title,
				 @description,
				 @dueDate,
				 'Pending',       -- default status on create
				 @remarks,
				 GETDATE(),       -- createdOn
				 @userID);        -- createdBy
	
		END
		ELSE
		BEGIN
			UPDATE dbo.taskData
			SET
				title      = @title,
				description= @description,
				dueDate    = @dueDate,
				status     = COALESCE(@status, status),
				remarks    = @remarks,
				updatedOn  = GETDATE(),     -- stamp update time
				updatedBy  = @userID        -- who updated
			WHERE
				taskID = @taskID;

		END
		select 'success' as message
	end try
	begin catch
		select 'Some Erro Occured' as Message
	end catch
END;
GO
/****** Object:  StoredProcedure [dbo].[usp_GetTaskById]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[usp_GetTaskById]
    @TaskID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
      t.taskID,
      t.title,
      t.description,
      t.dueDate,
      t.status,
      t.remarks,
      t.createdOn,
      t.updatedOn,
      cu.email    AS CreatedByEmail,
      uu.email    AS UpdatedByEmail
    FROM taskData AS t
    LEFT JOIN userData AS cu
      ON t.createdBy = cu.userID
    LEFT JOIN userData AS uu
      ON t.updatedBy = uu.userID
    WHERE t.taskID = @TaskID;
END
GO
/****** Object:  StoredProcedure [dbo].[usp_SearchTasks]    Script Date: 05-05-2025 15:13:04 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[usp_SearchTasks]
    @Query   NVARCHAR(200)    = NULL,
    @Offset  INT,
    @Limit   INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Paged list of tasks + creator/updater emails
    SELECT
      t.taskID,
      t.title,
      t.description,
      t.dueDate,
      t.status,
      t.remarks,
      t.createdOn,
      t.updatedOn,
      cu.email    AS CreatedByEmail,
      uu.email    AS UpdatedByEmail
    FROM taskData AS t
    LEFT JOIN userData AS cu
      ON t.createdBy = cu.userID
    LEFT JOIN userData AS uu
      ON t.updatedBy = uu.userID
    WHERE (@Query IS NULL OR t.title LIKE '%' + @Query + '%')
    ORDER BY t.taskID DESC
    OFFSET @Offset ROWS
    FETCH NEXT @Limit ROWS ONLY;

    -- 2) Total count for pagination
    SELECT
      COUNT(*) AS TotalCount
    FROM taskData AS t
    WHERE (@Query IS NULL OR t.title LIKE '%' + @Query + '%');
END
GO
