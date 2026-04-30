USE AdventureWorks
GO

DROP TABLE IF EXISTS Auction.Bid;
DROP TABLE IF EXISTS Auction.Auction;
DROP TABLE IF EXISTS Auction.Threshold;
DROP TABLE IF EXISTS Auction.Product;
DROP PROCEDURE IF EXISTS Auction.uspAddProductToAuction;
DROP PROCEDURE IF EXISTS Auction.uspTryBidProduct;
DROP PROCEDURE IF EXISTS Auction.uspListBidsOffersHistory;
DROP PROCEDURE IF EXISTS Auction.uspRemoveProductFromAuction;
DROP PROCEDURE IF EXISTS Auction.uspUpdateProductAuctionStatus;
GO

DROP SCHEMA IF EXISTS Auction;
GO

CREATE SCHEMA Auction;
GO

-- Make dbo the owner. 
-- TODO: make the authorization work for the current user
ALTER AUTHORIZATION ON SCHEMA::Auction TO dbo;

-- Create Auction.Product
-- Select and Insert records from the Production.Product table that meet the requirements
-- TODO: Confirm if this table is necessary or use Production.Product directly
-- TODO: Select specific columns, not ALL
SELECT *
INTO Auction.Product
FROM Production.Product
WHERE SellEndDate IS NULL
  AND DiscontinuedDate IS NULL
  AND ListPrice > 0;

-- Ensure the column doesn't allow NULLs , as required for a Primary Key
ALTER TABLE Auction.Product 
ALTER COLUMN ProductID INT NOT NULL;
GO

-- Add the Primary Key constraint
ALTER TABLE Auction.Product
ADD CONSTRAINT PK_Auction_Product PRIMARY KEY (ProductID);
GO

-- Auction table
-- Products listed for auction
CREATE TABLE Auction.Auction
(
    AuctionID INT IDENTITY PRIMARY KEY NOT NULL,
    ProductID INT NOT NULL REFERENCES Auction.Product(ProductID),
    InitialBidPrice MONEY NOT NULL DEFAULT 0,
    ExpireDate DATETIME2(0) NULL,
    AuctionStatus NVARCHAR(20) NOT NULL DEFAULT 'Active',
    ListedDate DATETIME NOT NULL DEFAULT GETUTCDATE(),
    UpdatedDate DATETIME,
    WinningCustomerID INT NULL
);
GO

-- Winning customer FK
ALTER TABLE Auction.Auction
ADD CONSTRAINT FK_Auction_WinnerCustomer
FOREIGN KEY (WinningCustomerID)
REFERENCES Sales.Customer(CustomerID);
GO

-- Only one ACTIVE auction per ProductID (FAQ rule)
CREATE UNIQUE INDEX UX_Auction_ActiveProduct
ON Auction.Auction(ProductID)
WHERE AuctionStatus = 'Active';
GO

-- Bid table
-- Stores bid history per auction
CREATE TABLE Auction.Bid
(
    BidID INT IDENTITY PRIMARY KEY NOT NULL,
    AuctionID INT NOT NULL REFERENCES Auction.Auction(AuctionID),
    CustomerID INT NOT NULL REFERENCES Sales.Customer(CustomerID),
    BidAmount MONEY NOT NULL DEFAULT 0,
    BidDate DATETIME NOT NULL DEFAULT GETDATE()
);
GO

-- Indexes for high workload
CREATE INDEX IX_Bid_AuctionID_BidAmount
    ON Auction.Bid(AuctionID, BidAmount DESC);
GO

CREATE INDEX IX_Bid_CustomerID_BidDate
    ON Auction.Bid(CustomerID, BidDate DESC);
GO

-- Global Threshold Table
CREATE TABLE Auction.Threshold
(
    Increment MONEY NOT NULL DEFAULT 0,
    MaximumBidLimit DECIMAL(10,4) NOT NULL DEFAULT 1.0
);
GO

-- Insert default threshold once
IF NOT EXISTS (SELECT 1 FROM Auction.Threshold)
BEGIN
    INSERT INTO Auction.Threshold (Increment, MaximumBidLimit)
    VALUES (0.05, 1.0);
END
GO

-- Stored Procedures

CREATE PROCEDURE Auction.uspAddProductToAuction(
    @ProductID INT,
    @ExpireDate DATETIME2(0) = NULL,
    @InitialBidPrice MONEY = NULL
)
AS
BEGIN
    IF @ExpireDate IS NULL
        SET @ExpireDate = DATEADD(WEEK, 1, SYSUTCDATETIME());

    IF @InitialBidPrice IS NULL
    BEGIN
        DECLARE @MakeFlag INT;
        SELECT @MakeFlag = MakeFlag FROM Auction.Product WHERE ProductID = @ProductID;

        SELECT @InitialBidPrice =
            CASE WHEN @MakeFlag = 0 THEN 0.75 * ListPrice ELSE 0.5 * ListPrice END
        FROM Auction.Product
        WHERE ProductID = @ProductID;
    END

    INSERT INTO Auction.Auction (ProductID, InitialBidPrice, ExpireDate)
    VALUES (@ProductID, @InitialBidPrice, @ExpireDate);
END
GO

CREATE OR ALTER PROCEDURE Auction.uspTryBidProduct(
    @ProductID INT,
    @CustomerID INT,
    @BidAmount MONEY = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @ActiveAuction INT,
            @ExpireDate DATETIME2(0),
            @inc MONEY,
            @maxmult DECIMAL(10,4),
            @listprice MONEY,
            @maxbid MONEY,
            @current MONEY,
            @minnext MONEY;

        SELECT
            @inc = Increment,
            @maxmult = MaximumBidLimit
        FROM Auction.Threshold;

        IF @inc IS NULL OR @maxmult IS NULL
            THROW 50010, 'Threshold configuration missing.', 1;

        SELECT @listprice = ListPrice
        FROM Auction.Product
        WHERE ProductID = @ProductID;

        IF @listprice IS NULL
            THROW 50011, 'Invalid ProductID.', 1;

        SET @maxbid = @maxmult * @listprice;

        BEGIN TRAN;

        SELECT TOP 1
            @ActiveAuction = AuctionID,
            @ExpireDate = ExpireDate
        FROM Auction.Auction WITH (UPDLOCK, HOLDLOCK)
        WHERE ProductID = @ProductID
            AND AuctionStatus = 'Active';

        IF @ActiveAuction IS NULL
            THROW 50003, 'No active auction.', 1;

        IF @ExpireDate IS NOT NULL AND @ExpireDate <= SYSUTCDATETIME()
            THROW 50004, 'Auction expired.', 1;

        SELECT @current = MAX(BidAmount)
        FROM Auction.Bid WITH (UPDLOCK, HOLDLOCK)
        WHERE AuctionID = @ActiveAuction;

        IF @current IS NULL
            SELECT @current = InitialBidPrice FROM Auction.Auction WHERE AuctionID = @ActiveAuction;

        SET @minnext = @current + @inc;

        IF @BidAmount IS NULL
            SET @BidAmount = @minnext;

        IF @BidAmount < @minnext
            THROW 50005, 'Bid too low.', 1;

        IF @BidAmount > @maxbid
            SET @BidAmount = @maxbid;

        INSERT INTO Auction.Bid (AuctionID, CustomerID, BidAmount)
        VALUES (@ActiveAuction, @CustomerID, @BidAmount);

        -- If bid reached the maximum allowed bid, close the auction and set the winner
        IF @BidAmount = @maxbid
        BEGIN
            UPDATE Auction.Auction
            SET AuctionStatus = 'Sold',
                WinningCustomerID = @CustomerID,
                UpdatedDate = SYSUTCDATETIME()
            WHERE AuctionID = @ActiveAuction;
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE Auction.uspRemoveProductFromAuction(@ProductID INT)
AS
BEGIN
    SELECT @@VERSION;
END
GO

CREATE OR ALTER PROCEDURE Auction.uspListBidsOffersHistory(
    @CustomerID INT,
    @StartTime DATETIME,
    @EndTime DATETIME,
    @Active BIT
)
AS
BEGIN
    SELECT @@VERSION;
END
GO

CREATE OR ALTER PROCEDURE Auction.uspUpdateProductAuctionStatus
AS
BEGIN
    -- NOCOUNT ON to avoid printing affected rows
    -- XACT_ABORT ON so if anything blows up, everything gets rolled back
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;

    -- 1) Auctions that expired AND had bids
    -- These are considered SOLD. Winner = customer with the highest bid
    -- Possible problem eheh, BidAmount ties are not expected in the system’s normal operation; in any case, the procedure consistently selects the highest bid

    UPDATE Auction.Auction
    SET AuctionStatus = 'Sold',

        -- Get the customer who placed the highest bid for this auction
        WinningCustomerID =
        (
            SELECT TOP 1 b.CustomerID
            FROM Auction.Bid b
            WHERE b.AuctionID = Auction.Auction.AuctionID
            ORDER BY
                b.BidAmount DESC   -- highest bid first

        ),

        -- Update timestamp
        UpdatedDate = @now

    WHERE AuctionStatus = 'Active'          -- only active auctions
      AND ExpireDate IS NOT NULL
      AND ExpireDate <= @now               -- auction already expired
      AND EXISTS
      (
          -- make sure this auction actually had bids
          SELECT 1
          FROM Auction.Bid b
          WHERE b.AuctionID = Auction.Auction.AuctionID
      );


    -- 2) Auctions that expired BUT had no bids, These are marked as Expired w/no winner here
 
    UPDATE Auction.Auction
    SET AuctionStatus = 'Expired',
        UpdatedDate = @now

    WHERE AuctionStatus = 'Active'
      AND ExpireDate IS NOT NULL
      AND ExpireDate <= @now
      AND NOT EXISTS
      (
          -- no bids were placed for this auction
          SELECT 1
          FROM Auction.Bid b
          WHERE b.AuctionID = Auction.Auction.AuctionID
      );

    COMMIT;
END
GO