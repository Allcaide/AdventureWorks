-- by cities, excluding the cities of the top 30 retailers in the US
WITH
    US_STORES_CUSTOMERS
    AS
    (
        SELECT DISTINCT
            c.CustomerID,
            s.[BusinessEntityID] AS RetailerID,
            a.[City],
            sp.[Name] AS [State]
        FROM [Sales].Customer c
            INNER JOIN [Sales].[Store] s
            ON c.StoreID = s.BusinessEntityID
            INNER JOIN [Person].[BusinessEntityAddress] bea
            ON bea.[BusinessEntityID] = s.[BusinessEntityID]
            INNER JOIN [Person].[Address] a
            ON a.[AddressID] = bea.[AddressID]
            INNER JOIN [Person].[StateProvince] sp
            ON sp.[StateProvinceID] = a.[StateProvinceID]
            INNER JOIN [Person].[CountryRegion] cr
            ON cr.[CountryRegionCode] = sp.[CountryRegionCode] AND cr.[Name] = 'United States'
            INNER JOIN [Person].[AddressType] at
            ON at.[AddressTypeID] = bea.[AddressTypeID]
    ),
    TOP_30_RETAILERS
    AS
    (
        SELECT TOP 30
            sum(soh.SubTotal) as Revenue,
            c.RetailerID
        FROM [Sales].[SalesOrderHeader] soh
            INNER JOIN US_STORES_CUSTOMERS c
            ON soh.CustomerID = c.CustomerID
        GROUP BY c.RetailerID
        ORDER BY Revenue DESC
    ),
    RETAILER_LOCATIONS
    AS
    (
        SELECT DISTINCT u.City, u.State
        FROM US_STORES_CUSTOMERS u
            INNER JOIN TOP_30_RETAILERS t
            ON u.RetailerID = t.RetailerID
    ),
    CITY_SALES
    AS
    (
        SELECT
            a.City,
            sp.[Name] AS [State],
            SUM(soh.SubTotal) as TotalSales,
            DENSE_RANK() OVER(ORDER BY SUM(soh.SubTotal) DESC) AS TotalRank,
            SUM(CASE WHEN soh.OnlineOrderFlag = 1 THEN soh.SubTotal ELSE 0 END) AS OnlineSales,
            DENSE_RANK() OVER(ORDER BY SUM(CASE WHEN soh.OnlineOrderFlag = 1 THEN soh.SubTotal ELSE 0 END) DESC) AS OnlineRank,
            SUM(CASE WHEN soh.OnlineOrderFlag = 0 THEN soh.SubTotal ELSE 0 END) AS ResellerSales,
            DENSE_RANK() OVER(ORDER BY SUM(CASE WHEN soh.OnlineOrderFlag = 0 THEN soh.SubTotal ELSE 0 END) DESC) AS ResellerRank
        FROM Sales.SalesOrderHeader soh
            INNER JOIN Person.Address a ON soh.ShipToAddressID = a.AddressID
            INNER JOIN [Person].[StateProvince] sp ON sp.[StateProvinceID] = a.[StateProvinceID]
            INNER JOIN [Person].[CountryRegion] cr ON cr.[CountryRegionCode] = sp.[CountryRegionCode]
        WHERE cr.Name = 'United States'
        GROUP BY a.City, sp.[Name]
    )
SELECT cs.*
FROM CITY_SALES cs
WHERE NOT EXISTS (
    SELECT 1
FROM RETAILER_LOCATIONS rl
WHERE rl.City = cs.City
    AND rl.[State] = cs.[State]
)
ORDER BY cs.TotalSales DESC;
