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
    ),
    OTHER_STORES_CUSTOMERS
    AS
    (
        --EXCLUDING TOP 30 RETAILERS TO GET OTHER CITIES WITH SALES
        SELECT DISTINCT
            c.CustomerID,
            c.RetailerID,
            c.Retailer,
            c.City,
            c.State,
            c.Country
        FROM US_STORES_CUSTOMERS c
            LEFT JOIN TOP_30_RETAILERS t
            ON c.RetailerID = t.RetailerID
        WHERE t.RetailerID IS NULL
    ),
    RETAILER_SALES_OTHER_CITIES
    AS
    (
        SELECT
            sum(soh.SubTotal) as Revenue,
            c.City,
            c.[State],
            c.Country
        FROM [Sales].[SalesOrderHeader] soh
            INNER JOIN OTHER_STORES_CUSTOMERS c
            ON soh.CustomerID = c.CustomerID
        GROUP BY 
        c.City, 
        c.State,
        c.Country
    ),
    INDIVIDUAL_CUSTOMER_SALES
    AS
    (
        SELECT
            sum(soh.SubTotal) as Revenue,
            /*c.CustomerID,*/
            a.City,
            sp.[Name] as [State],
            cr.[Name] as Country
        FROM [Sales].[SalesOrderHeader] soh
            INNER JOIN SALES.CUSTOMER c
            ON soh.CustomerID = c.CustomerID
            INNER JOIN Person.Person p
            ON c.PersonID = p.BusinessEntityID AND p.PersonType = 'IN'
            INNER JOIN Person.BusinessEntityAddress bea
            ON p.BusinessEntityID = bea.BusinessEntityID
            INNER JOIN Person.Address a
            ON bea.AddressID = a.AddressID
            INNER JOIN Person.StateProvince sp
            ON a.StateProvinceID = sp.StateProvinceID
            INNER JOIN Person.CountryRegion cr
            ON sp.CountryRegionCode = cr.CountryRegionCode AND cr.[Name] = 'United States'
        GROUP BY
        a.City,
        sp.[Name],
        cr.[Name]
    ),
    COMBINED_SALES_OTHER_CITIES
    AS
    (
                    SELECT Revenue, City, [State], Country
            FROM RETAILER_SALES_OTHER_CITIES
        UNION ALL
            SELECT Revenue, City, [State], Country
            FROM INDIVIDUAL_CUSTOMER_SALES
    )
SELECT TOP 2
    SUM(Revenue) AS TotalRevenue,
    City,
    [State],
    Country
FROM COMBINED_SALES_OTHER_CITIES
GROUP BY City, [State], Country
ORDER BY TotalRevenue DESC;
