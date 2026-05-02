EXEC Auction.uspAddProductToAuction @ProductID = 514
EXEC Auction.uspAddProductToAuction @ProductID = 515
EXEC Auction.uspAddProductToAuction @ProductID = 516, @ExpireDate = '2024-12-31 23:59:00', @InitialBidPrice = 150
EXEC Auction.uspAddProductToAuction @ProductID = 515
-- duplicate product, should fail
EXEC Auction.uspAddProductToAuction @ProductID = 517
EXEC Auction.uspRemoveProductFromAuction @ProductID = 515
EXEC Auction.uspAddProductToAuction @ProductID = 515
-- re-add after removal, should succeed

SELECT *
FROM Auction.Auction
ORDER BY listeddate asc

EXEC Auction.uspTryBidProduct @ProductID = 3, @CustomerID = 3;
-- no active bid, fail
EXEC Auction.uspTryBidProduct @ProductID = 514, @CustomerID = 3;
EXEC Auction.uspTryBidProduct @ProductID = 514, @CustomerID = 4, @BidAmount = 150;
-- too high, use max bid and wins bid
EXEC Auction.uspTryBidProduct @ProductID = 514, @CustomerID = 3, @BidAmount = 200;
-- some with high bid already won
EXEC Auction.uspTryBidProduct @ProductID = 516, @CustomerID = 3, @BidAmount = 2;
-- expired
EXEC Auction.uspTryBidProduct @ProductID = 517, @CustomerID = 3, @BidAmount = 2;
-- bid too low
EXEC Auction.uspTryBidProduct @ProductID = 517, @CustomerID = 3, @BidAmount = 67;
--
EXEC Auction.uspTryBidProduct @ProductID = 517, @CustomerID = 3, @BidAmount = 67.05;
-- 
EXEC Auction.uspTryBidProduct @ProductID = 517, @CustomerID = 4
-- winning bid
-- no longer available, fail

EXEC Auction.uspListBidsOffersHistory @CustomerID = 3, @StartTime = '2024-01-01', @EndTime = '2027-12-31', @Active = 1
EXEC Auction.uspListBidsOffersHistory @CustomerID = 3, @StartTime = '2024-01-01', @EndTime = '2027-12-31', @Active = 0

EXEC Auction.uspUpdateProductAuctionStatus

SELECT *
FROM Auction.Auction
ORDER BY listeddate asc

--
