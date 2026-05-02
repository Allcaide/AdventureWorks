WITH
    US_STORES_CUSTOMERS
    AS
    (
        SELECT DISTINCT
            c.CustomerID,
            s.[BusinessEntityID] AS RetailerID,
            s.[Name] AS Retailer,
            a.[City],
            sp.[Name] AS [State],
            cr.[Name] AS [Country]
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
            c.RetailerID,
            c.Retailer
        FROM [Sales].[SalesOrderHeader] soh
            INNER JOIN US_STORES_CUSTOMERS c
            ON soh.CustomerID = c.CustomerID
        GROUP BY 
        c.RetailerID, 
        c.Retailer
        ORDER BY Revenue DESC
    )
SELECT DISTINCT u.City, u.State, u.Country
FROM US_STORES_CUSTOMERS u
    INNER JOIN TOP_30_RETAILERS t
    ON u.RetailerID = t.RetailerID
