-- By Cities
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
ORDER BY TotalSales DESC;
