--A.1 Top 30 Reseller Cities by Sales 

--Description 
--This query identifies the top 30 resellers in the United States based on total sales and aggregates their sales at the city level. 
--The result is used to determine which cities should be excluded from the brick-and-mortar expansion strategy. 

WITH TopStores AS ( 
   SELECT TOP 30 
       s.BusinessEntityID, 
       a.City, 
       sp.Name AS State, 
       SUM(soh.SubTotal) AS StoreSales 
   FROM Sales.SalesOrderHeader soh 
 
   JOIN Sales.Customer c 
       ON soh.CustomerID = c.CustomerID 
 
   JOIN Sales.Store s 
       ON c.StoreID = s.BusinessEntityID 
 
   JOIN Person.BusinessEntityAddress bea 
       ON s.BusinessEntityID = bea.BusinessEntityID 
 
   JOIN Person.Address a 
       ON bea.AddressID = a.AddressID 
 
   JOIN Person.StateProvince sp 
       ON a.StateProvinceID = sp.StateProvinceID 
 
   JOIN Person.CountryRegion cr 
       ON sp.CountryRegionCode = cr.CountryRegionCode 
 
   WHERE cr.Name = 'United States' 
       AND c.StoreID IS NOT NULL 
 
   GROUP BY 
       s.BusinessEntityID, 
       a.City, 
       sp.Name 
 
   ORDER BY SUM(soh.SubTotal) DESC 
) 
 
SELECT 
   City, 
   State, 
   SUM(StoreSales) AS TotalCitySales 
FROM TopStores 
 
GROUP BY 
   City, 
   State 
 
ORDER BY 
   TotalCitySales DESC; 



--A.2 Ranking of US States by Online and Reseller Sales 

--Description 
--This query ranks U.S. states based on both online direct-to-consumer sales and reseller (physical store) sales. 
--Online sales are identified using OnlineOrderFlag = 1 and PersonType = 'IN', while reseller sales are derived from store-based transactions.
--The comparison supports the identification of high-demand states with lower reseller competition. 

 
WITH OnlineSales AS ( 
   -- Online direct-to-consumer sales by state 
   SELECT 
       sp.Name AS State, 
       SUM(soh.SubTotal) AS OnlineSales 
   FROM Sales.SalesOrderHeader soh 
 
   JOIN Sales.Customer c 
       ON soh.CustomerID = c.CustomerID 
 
   JOIN Person.Person p 
       ON c.PersonID = p.BusinessEntityID 
 
   JOIN Person.Address a 
       ON soh.ShipToAddressID = a.AddressID 
 
   JOIN Person.StateProvince sp 
       ON a.StateProvinceID = sp.StateProvinceID 
 
   JOIN Person.CountryRegion cr 
       ON sp.CountryRegionCode = cr.CountryRegionCode 
 
   WHERE cr.Name = 'United States' 
       AND soh.OnlineOrderFlag = 1 
       AND p.PersonType = 'IN' 
 
   GROUP BY 
       sp.Name 
), 
 
ResellerSales AS ( 
   -- Reseller (physical store) sales by state 
   SELECT 
       sp.Name AS State, 
       SUM(soh.SubTotal) AS ResellerSales 
   FROM Sales.SalesOrderHeader soh 
 
   JOIN Sales.Customer c 
       ON soh.CustomerID = c.CustomerID 
 
   JOIN Sales.Store s 
       ON c.StoreID = s.BusinessEntityID 
 
   JOIN Person.Address a 
       ON soh.ShipToAddressID = a.AddressID 
 
   JOIN Person.StateProvince sp 
       ON a.StateProvinceID = sp.StateProvinceID 
 
   JOIN Person.CountryRegion cr 
       ON sp.CountryRegionCode = cr.CountryRegionCode 
 
   WHERE cr.Name = 'United States' 
       AND c.StoreID IS NOT NULL 
 
   GROUP BY 
       sp.Name 
) 
 
SELECT 
   o.State, 
   o.OnlineSales, 
   ISNULL(r.ResellerSales, 0) AS ResellerSales, 
 
   -- Ranking by online sales 
   RANK() OVER (ORDER BY o.OnlineSales DESC) AS OnlineRank, 
 
   -- Ranking by reseller sales 
   RANK() OVER (ORDER BY ISNULL(r.ResellerSales, 0) DESC) AS ResellerRank 
 
FROM OnlineSales o 
 
LEFT JOIN ResellerSales r 
   ON o.State = r.State 
 
ORDER BY 
   o.OnlineSales DESC; 



 

--A.3 Market Gap Analysis – Oregon 

--Description 
--This query evaluates the market opportunity at the city level in Oregon by comparing online direct-to-consumer sales with reseller sales. 
--Online sales are defined using OnlineOrderFlag = 1 and PersonType = 'IN', while reseller sales are derived from store transactions. 
--The market gap (OnlineSales − ResellerSales) highlights cities with strong unmet demand and limited competition, supporting the selection of optimal locations for new brick-and-mortar stores. 

 
WITH Online AS ( 
   -- Online direct-to-consumer sales by city 

    SELECT 
       a.City, 
       sp.Name AS State, 
       SUM(soh.SubTotal) AS OnlineSales 
   FROM Sales.SalesOrderHeader soh 
 
   JOIN Sales.Customer c 
       ON soh.CustomerID = c.CustomerID 
 
   JOIN Person.Person p 
       ON c.PersonID = p.BusinessEntityID 
 
   JOIN Person.Address a 
       ON soh.ShipToAddressID = a.AddressID 
 
   JOIN Person.StateProvince sp 
       ON a.StateProvinceID = sp.StateProvinceID 
 
   JOIN Person.CountryRegion cr 
       ON sp.CountryRegionCode = cr.CountryRegionCode 
 
   WHERE cr.Name = 'United States' 
       AND sp.Name = 'Oregon' 
       AND soh.OnlineOrderFlag = 1 
       AND p.PersonType = 'IN' 
 
   GROUP BY 
       a.City, 
       sp.Name 
), 
 
Resellers AS ( 
   -- Reseller sales by city 
   SELECT 
       a.City, 
       sp.Name AS State, 
       SUM(soh.SubTotal) AS ResellerSales 
   FROM Sales.SalesOrderHeader soh 
 
   JOIN Sales.Customer c 
       ON soh.CustomerID = c.CustomerID 
 
   JOIN Sales.Store s 
       ON c.StoreID = s.BusinessEntityID 
 
   JOIN Person.Address a 
       ON soh.ShipToAddressID = a.AddressID 
 
   JOIN Person.StateProvince sp 
       ON a.StateProvinceID = sp.StateProvinceID 
 
   JOIN Person.CountryRegion cr 
       ON sp.CountryRegionCode = cr.CountryRegionCode 
 
   WHERE cr.Name = 'United States' 
       AND sp.Name = 'Oregon' 
       AND c.StoreID IS NOT NULL 
 
   GROUP BY 
       a.City, 
       sp.Name 
) 
 
SELECT 
   o.City, 
   o.OnlineSales, 
   ISNULL(r.ResellerSales, 0) AS ResellerSales, 
 
   -- Market gap calculation 
   o.OnlineSales - ISNULL(r.ResellerSales, 0) AS MarketGap 
 
FROM Online o 
 
LEFT JOIN Resellers r 
   ON o.City = r.City 
   AND o.State = r.State 
 
ORDER BY 
   MarketGap DESC; 



--A.4 Online Sales Analysis – Maryland 

--Description 
--This query ranks cities in Maryland based on online direct-to-consumer sales. 
--Online transactions are identified using OnlineOrderFlag = 1 and restricted to individual customers (PersonType = 'IN'). 
--The shipping address is used to accurately assign sales to geographic locations. 
--This analysis supports the identification of high-demand areas in a state with no reseller presence. 

 
SELECT 
   a.City, 
   SUM(soh.SubTotal) AS OnlineSales 
FROM Sales.SalesOrderHeader soh 
 
JOIN Sales.Customer c 
   ON soh.CustomerID = c.CustomerID 
 
JOIN Person.Person p 
   ON c.PersonID = p.BusinessEntityID 
 
JOIN Person.Address a 
   ON soh.ShipToAddressID = a.AddressID 
 
JOIN Person.StateProvince sp 
   ON a.StateProvinceID = sp.StateProvinceID 
 
JOIN Person.CountryRegion cr 
   ON sp.CountryRegionCode = cr.CountryRegionCode 
 
WHERE cr.Name = 'United States' 
   AND sp.Name = 'Maryland' 
   AND soh.OnlineOrderFlag = 1 
   AND p.PersonType = 'IN' 
 
GROUP BY 
   a.City 
 
ORDER BY 
   OnlineSales DESC; 
 

 