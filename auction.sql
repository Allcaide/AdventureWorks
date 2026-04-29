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
ALTER AUTHORIZATION on SCHEMA::Auction to dbo;

/**
    Create Auction.Product
    Select and Insert records from the Production.Product table that 
    The requirements

    TODO: Confirm if this table is necessary or use the Production.Product table directly.
    If we decide to do this, we'll need to make sure the Auction.uspAddProductToAuction respects
    the DiscontinuedDate and ListPrice requirements.

    TODO: Select specific columns, not ALL.
**/
SELECT *
INTO Auction.Product
FROM Production.Product
WHERE SellEndDate IS NULL
    AND DiscontinuedDate IS NULL
    AND ListPrice > 0

-- Ensure the column doesn't allow NULLs , as required for a Primary Key
ALTER TABLE Auction.Product 
ALTER COLUMN ProductID INT NOT NULL;
GO

-- Add the Primary Key constraint
ALTER TABLE Auction.Product
ADD CONSTRAINT PK_Auction_Product PRIMARY KEY (ProductID);
GO

/**
    Auction table
    =============
    The products on Auction are inserted into this table via Auction.uspAddProductToAuction
    Only products in this table are available for bidding.
**/
CREATE TABLE Auction.Auction
(
    AuctionID INT IDENTITY PRIMARY KEY NOT NULL,
    ProductID INT NOT NULL REFERENCES Auction.Product(ProductID),
    InitialBidPrice MONEY NOT NULL DEFAULT 0,
    ExpireDate DATE,---The bid logic asks fot the timestamp with exat date and time, maybe change it to ExpireDate DATETIME2(0),
    AuctionStatus NVARCHAR(20) NOT NULL DEFAULT 'Active',
    ListedDate DATETIME NOT NULL DEFAULT GETUTCDATE(),
    UpdatedDate DATETIME,
    WinningCustomerID NVARCHAR(50)---I dont know if it works like this with the sales.customer(customerID)
)
/**
    Something like this for the winning customer
    
ALTER TABLE Auction.Auction
ADD CONSTRAINT FK_Auction_WinnerCustomer
FOREIGN KEY (WinningCustomerID)
REFERENCES Sales.Customer(CustomerID);

**/
/**
    On FAQ says only one auction can be active per productID
Maybe we should implemment some CREATE UNIQUE INDEX on Auction.Auction idk
**/

/**
    Bid
    ===
    Holds the customer bid history.
    References a particular Auction by AuctionID, 
    Actions list product for one with a single productID active at a time. This 
    means that a single product can appear in the Auction table multiple times to 
    the particular instance is represented by the AuctionID
**/
CREATE TABLE Auction.Bid
(
    BidID INT IDENTITY PRIMARY KEY NOT NULL,
    AuctionID INT NOT NULL REFERENCES Auction.Auction(AuctionID),
    CustomerID INT NOT NULL REFERENCES Person.Person(BusinessEntityID),
    BidAmount MONEY NOT NULL DEFAULT 0,
    BidDate DATETIME NOT NULL DEFAULT GetDate()
);

/**
Create Indexes for high workload like MAX(BIdAmount) maybe 
CREATE INDEX IX_Bid_AuctionID_BidAmount
    ON Auction.Bid(AuctionID, BidAmount DESC);

CREATE INDEX IX_Bid_CustomerID_BidDate
    ON Auction.Bid(CustomerID, BidDate DESC);
**/

/*Create Global Threshold Table for Bids; applies to all Products*/
CREATE TABLE Auction.Threshold
(
    Increment MONEY NOT NULL DEFAULT 0,
    MaximumBidLimit DECIMAL NOT NULL DEFAULT 1
);

/**Downhere
If alrteady exist thrshold there's no need to add the line
We can check the if before adding it

IF NOT EXISTS (SELECT 1 FROM Auction.Threshold)
BEGIN
INSERT INTO Auction.Threshold
    (Increment, MaximumBidLimit)
VALUES(0.05, 1.0);

END
GO

**/
INSERT INTO Auction.Threshold
    (Increment, MaximumBidLimit)
VALUES(0.05, 1.0);
GO

/* Stored Procedures */
CREATE PROCEDURE Auction.uspAddProductToAuction(
    @ProductID INT,
    @ExpireDate DATE = NULL,---add specific time with datetime2(0) = null
    @InitialBidPrice MONEY = NULL
)
AS
BEGIN
    -- Description: This stored procedure adds a product as auctioned.
    IF @ExpireDate IS NULL
    BEGIN
        SELECT @ExpireDate = DATEADD(week, 1, GETUTCDATE());
    END

    IF @InitialBidPrice IS NULL
    BEGIN
        DECLARE @MakeFlag INT = 0
        -- 0 is purchased by AdventureWorks, 1 is manufactured in-house.
        SELECT @MakeFlag = MakeFlag
        from Auction.Product
        WHERE ProductID = @ProductID
        -- UPDATE Auction.Product SET BidPrice = 0.75 * ListPrice WHERE MakeFlag = 0;
        -- UPDATE Auction.Product SET BidPrice = 0.50 * ListPrice WHERE MakeFlag <> 0;
        SELECT @InitialBidPrice = CASE @MakeFlag WHEN 0 THEN 0.75 * ListPrice ELSE 0.5 * ListPrice END
        FROM Auction.Product
        where ProductID = @ProductID
    END

    -- TODO: Address the issue of two active products.
    INSERT INTO Auction.Auction
        (ProductID, InitialBidPrice, ExpireDate)
    VALUES(@ProductID, @InitialBidPrice, @ExpireDate)

END
GO

CREATE OR ALTER PROCEDURE Auction.uspTryBidProduct(
    @ProductID INT,
    @CustomerID INT,
    @BidAmount MONEY = NULL
)
AS
BEGIN
    -- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    -- Description: This stored procedure adds a bid on behalf of that customer
    -- TODO: Add the bidding logic:
    -- If BidAmount is in range, OK
    -- If BidAmount is null, then bidamount = threshold.increment more than last bid.
    -- If BidAmount > threshold.maxbidprice * ListPrice, make BidAmount = threshold.maxbidprice * ListPrice
    DECLARE @ActiveAuction INT;
    SELECT @ActiveAuction = AuctionID
    from Auction.Auction
    where ProductID = @ProductID AND AuctionStatus = 'Active';

    INSERT INTO Auction.Bid
        (AuctionID, CustomerID, BidAmount)
    VALUES(@ActiveAuction, @CustomerID, @BidAmount);

END
GO

CREATE OR ALTER PROCEDURE Auction.uspRemoveProductFromAuction(
    @ProductID INT
)
AS
BEGIN
    -- Description: This stored procedure removes the product from being listed as auctioned even if there
    -- might have been bids for that product.
    -- Notes: When users are checking their bid history this product should also show up as an auction cancelled
    UPDATE Auction.Auction SET STATUS = 'Cancelled' WHERE ProductID = @ProductID;
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
    WHERE a.CustomerID = @CustomerID
        AND BidDate BETWEEN @StartTime AND @EndTime
        AND
        (@Active = 0 OR a.AuctionStatus = 'Active');
END
GO

CREATE OR ALTER PROCEDURE Auction.uspUpdateProductAuctionStatus
AS
BEGIN
    -- Description: This stored procedure updates auction status for all auctioned products. This stored
    -- procedure will be manually invoked before processing orders for dispatch.
    UPDATE Auction.Auction set AuctionStatus = 'CLOSED';

-- Note: To determine the winners of each bid, we can get the max bid for each auction, any auction without bids can be marked as 'No Bids'.
END
GO
