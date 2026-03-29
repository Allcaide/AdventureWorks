SELECT TOP 30
    a.City,
    sum(soh.totaldue) as TotalByCity
from sales.SalesOrderHeader as soh
    inner join Sales.SalesTerritory st on soh.TerritoryID = st.TerritoryID
    inner join sales.Store s on s.SalesPersonID = soh.SalesPersonID
    inner join Person.BusinessEntityAddress as bea on bea.BusinessEntityID = s.BusinessEntityID
    inner join Person.Address a on bea.AddressID = a.AddressID
where st.CountryRegionCode = 'US'
group by a.City, a.StateProvinceID
order by TotalByCity DESC
