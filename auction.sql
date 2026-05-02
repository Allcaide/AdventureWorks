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

DROP SCHEMA IF EXISTS Auction;
GO

CREATE SCHEMA Auction;
GO

-- Make the current user the owner. 
DECLARE @CurrentUser NVARCHAR(128) = USER_NAME();
DECLARE @Sql NVARCHAR(MAX) = 'ALTER AUTHORIZATION ON SCHEMA::Auction TO [' + @CurrentUser + '];';
EXEC sp_executesql @Sql;

-- Create Auction.Product
-- Select and Insert records from the Production.Product table that meet the requirements.
-- We decided to make a new Product table rather than use Production.Product directly
SELECT
    ProductID,
    [Name],
    ProductNumber,
    Color,
    ListPrice,
    MakeFlag
INTO Auction.Product
FROM Production.Product
WHERE SellEndDate IS NULL
    AND DiscontinuedDate IS NULL
    AND ListPrice > 0;

-- Ensure the column doesn't allow NULLs , as required for a Primary Key
ALTER TABLE Auction.Product 
ALTER COLUMN ProductID INT NOT NULL;

-- Restore the Primary Key constraint
ALTER TABLE Auction.Product
ADD CONSTRAINT PK_Auction_Product PRIMARY KEY (ProductID);

-- Store products listed for auction
CREATE TABLE Auction.Auction
(
    AuctionID INT IDENTITY PRIMARY KEY NOT NULL,
    ProductID INT NOT NULL REFERENCES Auction.Product(ProductID),
    InitialBidPrice MONEY NOT NULL DEFAULT 0,
    [ExpireDate] DATETIME2(0) NULL,
    AuctionStatus NVARCHAR(20) NOT NULL DEFAULT 'Active',
    ListedDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    WinningCustomerID INT NULL
);

-- Ensure Consistency with Sales.Customer for WinningCustomerID
ALTER TABLE Auction.Auction
ADD CONSTRAINT FK_Auction_WinnerCustomer
FOREIGN KEY (WinningCustomerID)
REFERENCES Sales.Customer(CustomerID);

-- Ensure only one Active auction per ProductID (FAQ rule)
CREATE UNIQUE INDEX UX_Auction_ActiveProduct
ON Auction.Auction(ProductID)
WHERE AuctionStatus = 'Active';

-- Store bid history per auction
CREATE TABLE Auction.Bid
(
    BidID INT IDENTITY PRIMARY KEY NOT NULL,
    AuctionID INT NOT NULL REFERENCES Auction.Auction(AuctionID),
    CustomerID INT NOT NULL REFERENCES Sales.Customer(CustomerID),
    BidAmount MONEY NOT NULL DEFAULT 0,
    BidDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Indexes for high workload
CREATE INDEX IX_Bid_AuctionID_BidAmount 
    ON Auction.Bid(AuctionID, BidAmount DESC);

CREATE INDEX IX_Bid_CustomerID_BidDate
    ON Auction.Bid(CustomerID, BidDate DESC);

-- Global Threshold Table
CREATE TABLE Auction.Threshold
(
    Increment MONEY NOT NULL DEFAULT 0,
    MaximumBidLimit DECIMAL(10,4) NOT NULL DEFAULT 1.0
);

-- Insert default threshold once
IF NOT EXISTS (SELECT 1
FROM Auction.Threshold)
BEGIN
    INSERT INTO Auction.Threshold
        (Increment, MaximumBidLimit)
    VALUES
        (0.05, 1.0);
END
GO

-- Stored Procedures

CREATE OR ALTER PROCEDURE Auction.uspAddProductToAuction(
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
        SELECT @MakeFlag = MakeFlag
        FROM Auction.Product
        WHERE ProductID = @ProductID;

        SELECT @InitialBidPrice =
            CASE WHEN @MakeFlag = 0 THEN 0.75 * ListPrice ELSE 0.5 * ListPrice END
        FROM Auction.Product
        WHERE ProductID = @ProductID;
    END

    INSERT INTO Auction.Auction
        (ProductID, InitialBidPrice, [ExpireDate])
    VALUES
        (@ProductID, @InitialBidPrice, @ExpireDate);
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

    DECLARE
        @ActiveAuction INT,
        @ExpireDate DATETIME2(0),
        @inc MONEY,
        @maxmult DECIMAL(10,4),
        @listprice MONEY,
        @maxbid MONEY,
        @current MONEY,
        @minnext MONEY;

    BEGIN TRY
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
    BEGIN
        SELECT @current = InitialBidPrice
        FROM Auction.Auction
        WHERE AuctionID = @ActiveAuction;
    END

    SET @minnext = @current + @inc;

    IF @BidAmount IS NULL
        SET @BidAmount = @minnext;
    IF @BidAmount < @minnext
    BEGIN
        DECLARE @ErrMsg NVARCHAR(200) = 'Bid too low. Minimum bid is ' + CAST(@minnext AS VARCHAR(20));
        THROW 50005, @ErrMsg, 1;
    END
    IF @BidAmount > @maxbid
        SET @BidAmount = @maxbid;

    INSERT INTO Auction.Bid
        (AuctionID, CustomerID, BidAmount)
    VALUES(@ActiveAuction, @CustomerID, @BidAmount);

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
    -- Description: This stored procedure removes the product from being listed as auctioned even if there
    -- might have been bids for that product.
    -- Notes: When users are checking their bid history this product should also show up as an auction cancelled
    UPDATE Auction.Auction 
    SET 
        AuctionStatus = 'Cancelled',
        UpdatedDate = SYSUTCDATETIME()
    WHERE ProductID = @ProductID AND AuctionStatus = 'Active';
END
GO

CREATE OR ALTER PROCEDURE Auction.uspListBidsOffersHistory(
    @CustomerID INT,
    @StartTime DATETIME2,
    @EndTime DATETIME2,
    @Active BIT
)
AS
BEGIN
    -- Description: This stored procedure returns customer bid history for specified date time interval. 
    -- If Active parameter is set to false, then all bids should be returned including ones related to products no longer
    -- auctioned or purchased by customer. If Active set to true (default value) only returns products currently
    -- auctioned
    SELECT
        b.BidID,
        b.AuctionID,
        b.CustomerID,
        b.BidAmount,
        b.BidDate,
        a.AuctionStatus,
        a.ProductID
    FROM Auction.Bid AS b
        INNER JOIN Auction.Auction AS a
        ON a.AuctionID = b.AuctionID
        INNER JOIN Auction.Product AS p
        ON p.ProductID = a.ProductID
    WHERE b.CustomerID = @CustomerID
        AND b.BidDate BETWEEN @StartTime AND @EndTime
        AND
        (@Active = 0 OR a.AuctionStatus = 'Active');
END
GO

CREATE OR ALTER PROCEDURE Auction.uspUpdateProductAuctionStatus
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    WITH
        AuctionResults
        AS
        (
            SELECT
                a.AuctionStatus,
                a.WinningCustomerID,
                a.UpdatedDate,
                b.CustomerID AS NewWinnerID,
                ROW_NUMBER() OVER (PARTITION BY a.AuctionID ORDER BY b.BidAmount DESC) as BidRank
            FROM Auction.Auction a WITH (UPDLOCK, ROWLOCK) -- Locks the rows immediately upon selection
                LEFT JOIN Auction.Bid b ON a.AuctionID = b.AuctionID
            WHERE a.AuctionStatus = 'Active'
        )
    UPDATE AuctionResults
    SET 
        AuctionStatus = CASE WHEN NewWinnerID IS NOT NULL THEN 'Sold' ELSE 'Expired' END,
        WinningCustomerID = NewWinnerID,
        UpdatedDate = SYSUTCDATETIME()
    WHERE BidRank = 1;

    COMMIT;
END
GO
