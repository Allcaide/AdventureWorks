--TOP 30 RESELLERS

SELECT TOP 30
    s.BusinessEntityID AS StoreID,
    s.Name AS StoreName,
    a.City,
    sp.Name AS State,
    SUM(soh.SubTotal) AS TotalSales
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
    s.Name,
    a.City,
    sp.Name

ORDER BY TotalSales DESC;





-- Total reseller sales by city (from top 30 resellers)

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





-- Online demand by city (individual customers)

SELECT
    a.City,
    sp.Name AS State,
    SUM(soh.SubTotal) AS OnlineSales
FROM Sales.SalesOrderHeader soh

JOIN Sales.Customer c
    ON soh.CustomerID = c.CustomerID

JOIN Person.Person p
    ON c.PersonID = p.BusinessEntityID

JOIN Person.BusinessEntityAddress bea
    ON p.BusinessEntityID = bea.BusinessEntityID

JOIN Person.Address a
    ON bea.AddressID = a.AddressID

JOIN Person.StateProvince sp
    ON a.StateProvinceID = sp.StateProvinceID

JOIN Person.CountryRegion cr
    ON sp.CountryRegionCode = cr.CountryRegionCode

WHERE cr.Name = 'United States'
    AND p.PersonType = 'IN'

GROUP BY
    a.City,
    sp.Name

ORDER BY OnlineSales DESC




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
    a.City,
    sp.Name

ORDER BY ResellerSales DESC




-- Final ranking for store location based on online demand and reseller gap

WITH Online AS (
    -- Online demand (individual customers)
    SELECT
        a.City,
        sp.Name AS State,
        SUM(soh.SubTotal) AS OnlineSales
    FROM Sales.SalesOrderHeader soh

    JOIN Sales.Customer c
        ON soh.CustomerID = c.CustomerID

    JOIN Person.Person p
        ON c.PersonID = p.BusinessEntityID

    JOIN Person.BusinessEntityAddress bea
        ON p.BusinessEntityID = bea.BusinessEntityID

    JOIN Person.Address a
        ON bea.AddressID = a.AddressID

    JOIN Person.StateProvince sp
        ON a.StateProvinceID = sp.StateProvinceID

    JOIN Person.CountryRegion cr
        ON sp.CountryRegionCode = cr.CountryRegionCode

    WHERE cr.Name = 'United States'
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
        a.City,
        sp.Name
),

TopResellers AS (
    -- Top 30 resellers by sales
    SELECT TOP 30
        s.BusinessEntityID,
        a.City,
        sp.Name AS State,
        SUM(soh.SubTotal) AS TotalSales
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
),

TopResellerCities AS (
    -- Distinct cities to exclude
    SELECT DISTINCT
        City,
        State
    FROM TopResellers
)

SELECT TOP 10
    o.City,
    o.State,
    o.OnlineSales,
    ISNULL(r.ResellerSales, 0) AS ResellerSales,

    -- Market gap indicator
    o.OnlineSales - ISNULL(r.ResellerSales, 0) AS MarketGap

FROM Online o

LEFT JOIN Resellers r
    ON o.City = r.City
    AND o.State = r.State

WHERE NOT EXISTS (
    SELECT 1
    FROM TopResellerCities t
    WHERE t.City = o.City
      AND t.State = o.State
)

ORDER BY MarketGap DESC;



-- Ranking of US states by online sales and reseller (physical store) sales

WITH OnlineSales AS (
    -- Online sales by state (individual customers)
    SELECT
        sp.Name AS State,
        SUM(soh.SubTotal) AS OnlineSales
    FROM Sales.SalesOrderHeader soh

    JOIN Sales.Customer c
        ON soh.CustomerID = c.CustomerID

    JOIN Person.Person p
        ON c.PersonID = p.BusinessEntityID

    JOIN Person.BusinessEntityAddress bea
        ON p.BusinessEntityID = bea.BusinessEntityID

    JOIN Person.Address a
        ON bea.AddressID = a.AddressID

    JOIN Person.StateProvince sp
        ON a.StateProvinceID = sp.StateProvinceID

    JOIN Person.CountryRegion cr
        ON sp.CountryRegionCode = cr.CountryRegionCode

    WHERE cr.Name = 'United States'
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
        sp.Name
)

SELECT
    o.State,
    o.OnlineSales,
    r.ResellerSales,

    -- Ranking by online sales
    RANK() OVER (ORDER BY o.OnlineSales DESC) AS OnlineRank,

    -- Ranking by reseller sales
    RANK() OVER (ORDER BY r.ResellerSales DESC) AS ResellerRank

FROM OnlineSales o

LEFT JOIN ResellerSales r
    ON o.State = r.State

ORDER BY
    o.OnlineSales DESC;



    -- Ranking of cities in Oregon by market gap (online demand vs reseller sales)

WITH Online AS (
    -- Online sales by city (individual customers)
    SELECT
        a.City,
        sp.Name AS State,
        SUM(soh.SubTotal) AS OnlineSales
    FROM Sales.SalesOrderHeader soh

    JOIN Sales.Customer c
        ON soh.CustomerID = c.CustomerID

    JOIN Person.Person p
        ON c.PersonID = p.BusinessEntityID

    JOIN Person.BusinessEntityAddress bea
        ON p.BusinessEntityID = bea.BusinessEntityID

    JOIN Person.Address a
        ON bea.AddressID = a.AddressID

    JOIN Person.StateProvince sp
        ON a.StateProvinceID = sp.StateProvinceID

    JOIN Person.CountryRegion cr
        ON sp.CountryRegionCode = cr.CountryRegionCode

    WHERE cr.Name = 'United States'
        AND sp.Name = 'Oregon'
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

    JOIN Person.BusinessEntityAddress bea
        ON s.BusinessEntityID = bea.BusinessEntityID

    JOIN Person.Address a
        ON bea.AddressID = a.AddressID

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





-- Ranking of cities in Maryland by online sales (individual customers)

SELECT
    a.City,
    SUM(soh.SubTotal) AS OnlineSales
FROM Sales.SalesOrderHeader soh

JOIN Sales.Customer c
    ON soh.CustomerID = c.CustomerID

JOIN Person.Person p
    ON c.PersonID = p.BusinessEntityID

JOIN Person.BusinessEntityAddress bea
    ON p.BusinessEntityID = bea.BusinessEntityID

JOIN Person.Address a
    ON bea.AddressID = a.AddressID

JOIN Person.StateProvince sp
    ON a.StateProvinceID = sp.StateProvinceID

JOIN Person.CountryRegion cr
    ON sp.CountryRegionCode = cr.CountryRegionCode

WHERE cr.Name = 'United States'
    AND sp.Name = 'Maryland'
    AND p.PersonType = 'IN'

GROUP BY
    a.City

ORDER BY
    OnlineSales DESC;



-- Final recommendation for brick & mortar locations:
-- Lebanon (Oregon) and Baltimore (Maryland) have been selected based on a combination
-- of high online demand and limited or non-existent reseller presence.

-- California was excluded despite high market gap values because target cities are
-- geographically close to existing reseller hubs, which would likely lead to channel
-- conflict and internal competition (e.g., similar to opening a store in Almada while
-- having strong reseller presence in Lisbon).

-- Maryland represents an emerging market with no reseller presence, minimizing
-- cannibalization risk. Baltimore, as the top city in terms of online sales within the state,
-- provides the best opportunity to capture unmet demand.

-- Oregon ranks 3rd in online sales and 7th in reseller sales, indicating strong demand
-- with moderate competition. Lebanon stands out as the city with the highest online sales
-- in the state, while the nearest reseller location is approximately one hour away by car,
-- suggesting a clear geographic gap in physical coverage.

-- This dual-location strategy balances expansion into a high-demand market (Oregon)
-- with entry into an underserved market (Maryland), maximizing revenue potential while
-- minimizing conflict with existing reseller channels.