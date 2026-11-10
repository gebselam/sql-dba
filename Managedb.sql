-- @mssql Chat Query Editor (SELAM\SQLEXPRESS:RetailPractice:undefined)
use RetailPractice; 
GO

/*
DATABASE: RetailPractice
For SQL Server 


Schema:
Customers 1----many Orders
Orders    1----many OrderItems
Products  1----many OrderItems

Includes PK/FK, sample rows, scalar function, view, stored procedure, indexes,
and hands-on execution-plan/query-tuning.
*/

USE master;
GO
-- IF DB_ID(N'RetailPractice') IS NOT NULL
BEGIN
    ALTER DATABASE RetailPractice SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RetailPractice;
END;
GO
CREATE DATABASE RetailPractice;
GO
USE RetailPractice;
GO

-- 1) TABLE DESIGN: primary keys, foreign keys, checks, and defaults
CREATE TABLE dbo.Customers
(
    CustomerID       INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customers PRIMARY KEY,
    FirstName        NVARCHAR(50) NOT NULL,
    LastName         NVARCHAR(50) NOT NULL,
    Email            NVARCHAR(255) NOT NULL
        CONSTRAINT UQ_Customers_Email UNIQUE,
    City             NVARCHAR(100) NOT NULL,
    CreatedAt        DATETIME2(0) NOT NULL
        CONSTRAINT DF_Customers_CreatedAt DEFAULT SYSUTCDATETIME(),
    IsActive         BIT NOT NULL
        CONSTRAINT DF_Customers_IsActive DEFAULT (1)
);
GO

CREATE TABLE dbo.Products
(
    ProductID        INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Products PRIMARY KEY,
    ProductName      NVARCHAR(150) NOT NULL,
    Category         NVARCHAR(60) NOT NULL,
    UnitPrice        DECIMAL(10,2) NOT NULL
        CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice >= 0),
    IsActive         BIT NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1)
);
GO

CREATE TABLE dbo.Orders
(
    OrderID          INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerID       INT NOT NULL,
    OrderDate        DATETIME2(0) NOT NULL,
    OrderStatus      VARCHAR(20) NOT NULL,
    CONSTRAINT FK_Orders_Customers
        FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID),
    CONSTRAINT CK_Orders_Status
        CHECK (OrderStatus IN ('Pending','Shipped','Delivered','Cancelled'))
);
GO

CREATE TABLE dbo.OrderItems
(
    OrderItemID      BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_OrderItems PRIMARY KEY,
    OrderID          INT NOT NULL,
    ProductID        INT NOT NULL,
    Quantity         INT NOT NULL CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    UnitPrice        DECIMAL(10,2) NOT NULL CONSTRAINT CK_OrderItems_UnitPrice CHECK (UnitPrice >= 0),
    CONSTRAINT FK_OrderItems_Orders
        FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT FK_OrderItems_Products
        FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID)
);
GO

-- 2) SAMPLE DATA
-- 1,000 customers
;WITH N AS
(
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Customers (FirstName, LastName, Email, City, CreatedAt, IsActive)
SELECT
    CONCAT('First', n),
    CONCAT('Last', n),
    CONCAT('customer', n, '@example.com'),
    CASE n % 8
        WHEN 0 THEN 'Seattle' WHEN 1 THEN 'Bellevue' WHEN 2 THEN 'Redmond'
        WHEN 3 THEN 'Everett' WHEN 4 THEN 'Tacoma' WHEN 5 THEN 'Renton'
        WHEN 6 THEN 'Kirkland' ELSE 'Lynnwood'
    END,
    DATEADD(DAY, -(n % 1500), SYSUTCDATETIME()),
    CASE WHEN n % 10 = 0 THEN 0 ELSE 1 END
FROM N;
GO
-- select * from customers
-- 500 products
;WITH N AS
(
    SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Products (ProductName, Category, UnitPrice, IsActive)
SELECT
    CONCAT('Product-', n),
    CASE n % 5 WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Home'
        WHEN 2 THEN 'Clothing' WHEN 3 THEN 'Sports' ELSE 'Office' END,
    CAST(5.00 + (n % 250) * 3.17 AS DECIMAL(10,2)),
    CASE WHEN n % 20 = 0 THEN 0 ELSE 1 END
FROM N;
GO
-- select * from Products
-- 10,000 orders, distributed among customers
;WITH N AS
(
    SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Orders (CustomerID, OrderDate, OrderStatus)
SELECT
    ((n * 37) % 1000) + 1,
    DATEADD(DAY, -(n % 730), SYSUTCDATETIME()),
    CASE n % 4 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Shipped'
        WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END
FROM N;
GO

-- 30,000 order lines: 3 items per order
;WITH N AS
(
    SELECT TOP (30000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice)
SELECT
    ((n - 1) / 3) + 1,
    ((n * 13) % 500) + 1,
    (n % 5) + 1,
    p.UnitPrice
FROM N
JOIN dbo.Products p ON p.ProductID = ((n * 13) % 500) + 1;
GO

-- 3) VERIFY ROW COUNTS
SELECT 'Customers' AS TableName, COUNT_BIG(*) AS [RowCount] FROM dbo.Customers
UNION ALL SELECT 'Products', COUNT_BIG(*) FROM dbo.Products
UNION ALL SELECT 'Orders', COUNT_BIG(*) FROM dbo.Orders
UNION ALL SELECT 'OrderItems', COUNT_BIG(*) FROM dbo.OrderItems;
GO

-- 4) FUNCTION: total amount for a given order
CREATE FUNCTION dbo.fn_OrderTotal (@OrderID INT)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Total DECIMAL(18,2);
    SELECT @Total = SUM(CAST(Quantity AS DECIMAL(18,2)) * UnitPrice)
    FROM dbo.OrderItems
    WHERE OrderID = @OrderID;
    RETURN COALESCE(@Total, 0);
END;
GO

-- 5) VIEW: order header plus customer and computed order amount
CREATE VIEW dbo.vw_OrderSummary
AS
SELECT
    o.OrderID,
    o.OrderDate,
    o.OrderStatus,
    c.CustomerID,
    CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
    c.Email,
    SUM(CAST(oi.Quantity AS DECIMAL(18,2)) * oi.UnitPrice) AS OrderTotal
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerID = o.CustomerID
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
GROUP BY o.OrderID, o.OrderDate, o.OrderStatus, c.CustomerID,
         c.FirstName, c.LastName, c.Email;
GO

-- 6) STORED PROCEDURE: retrieve customer's orders for a date range
CREATE PROCEDURE dbo.usp_GetCustomerOrders
    @CustomerID INT,
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartDate > @EndDate
    BEGIN
        THROW 50001, 'StartDate must be on or before EndDate.', 1;
    END;

    SELECT OrderID, OrderDate, OrderStatus, CustomerID, CustomerName, OrderTotal
    FROM dbo.vw_OrderSummary
    WHERE CustomerID = @CustomerID
      AND OrderDate >= @StartDate
      AND OrderDate < DATEADD(DAY, 1, @EndDate)
    ORDER BY OrderDate DESC;
END;
GO

-- 7) BASIC PRACTICE QUERIES
-- PK / FK relationships: inspect constraints
SELECT name, type_desc
FROM sys.objects
WHERE type IN ('PK','F','UQ','C')
ORDER BY type_desc, name;
GO

-- Join 3 tables: orders with customer and line item
SELECT TOP (20)
    o.OrderID, CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName ,
    p.ProductName, oi.Quantity, oi.UnitPrice,
    LineTotal = oi.Quantity * oi.UnitPrice
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerID = o.CustomerID
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
JOIN dbo.Products p ON p.ProductID = oi.ProductID
ORDER BY o.OrderDate DESC;
GO

-- Call function, view, procedure
SELECT dbo.fn_OrderTotal(1) AS Order1Total;
SELECT TOP (20) * FROM dbo.vw_OrderSummary ORDER BY OrderDate DESC;
EXEC dbo.usp_GetCustomerOrders @CustomerID = 25,
    @StartDate = '2025-01-01', @EndDate = '2026-12-31';
GO

/*
8) EXECUTION PLAN / QUERY OPTIMIZATION LAB

A. Baseline (no custom indexes yet):
   In SSMS press Ctrl+M (Include Actual Execution Plan), then execute query.
   Also run SET STATISTICS IO, TIME ON. Record logical reads and elapsed/CPU time.
*/
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Baseline: filter by customer, date range, join order items, calculate total
DECLARE @CustomerID INT = 25;
DECLARE @StartDate DATETIME2(0) = '2025-01-01';
DECLARE @EndDate DATETIME2(0) = '2026-01-01';

SELECT
    o.OrderID, o.OrderDate, o.OrderStatus,
    SUM(CAST(oi.Quantity AS DECIMAL(18,2)) * oi.UnitPrice) AS OrderTotal
FROM dbo.Orders o
JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
WHERE o.CustomerID = @CustomerID
  AND o.OrderDate >= @StartDate
  AND o.OrderDate < @EndDate
GROUP BY o.OrderID, o.OrderDate, o.OrderStatus
ORDER BY o.OrderDate DESC;
GO

/*
B. Add indexes. Re-run the exact same query and compare plan, logical reads,
   CPU and elapsed time. SQL Server may choose a different plan depending on
   statistics, cardinality and version.
*/
CREATE INDEX IX_Orders_CustomerID_OrderDate
ON dbo.Orders (CustomerID, OrderDate)
INCLUDE (OrderStatus);
GO

CREATE INDEX IX_OrderItems_OrderID
ON dbo.OrderItems (OrderID)
INCLUDE (ProductID, Quantity, UnitPrice);
GO

-- Product category filtering example
CREATE INDEX IX_Products_Category
ON dbo.Products (Category)
INCLUDE (ProductName, UnitPrice, IsActive);
GO

/*
C. SARGability lab:
   Compare the two queries below. The first applies a function to the column
   and can inhibit a seek; the second uses a half-open range.
*/
-- Less seek-friendly:
SELECT COUNT(*) AS OrdersIn2025
FROM dbo.Orders
WHERE YEAR(OrderDate) = 2025;
GO

-- Usually more seek-friendly:
SELECT COUNT(*) AS OrdersIn2025
FROM dbo.Orders
WHERE OrderDate >= '2025-01-01'
  AND OrderDate <  '2026-01-01';
GO

/*
D. View/procedure/index exercises:
   1. EXEC dbo.usp_GetCustomerOrders for different customer/date ranges.
   2. Compare selecting from vw_OrderSummary with the direct join query.
   3. Use the function in a query over many orders; compare with one set-based
      GROUP BY query. Scalar UDFs can introduce overhead depending on version/
      inlining eligibility.
   4. Right-click an execution-plan operator > Properties. Look for:
      Actual vs Estimated Rows, Logical Operation, Predicate, Seek Predicates,
      Actual Number of Rows, Estimated Subtree Cost.
   5. Do not assume an Index Seek is always better. Check rows read, logical
      reads, key lookups, sorts, spills, and overall work.
*/
EXEC dbo.usp_GetCustomerOrders @CustomerID = 1000,
    @StartDate = '2024-01-01', @EndDate = '2026-12-31';
 -- Compare selecting from vw_OrderSummary with the direct join query.

    Use the function in a query over many orders; 
    compare with one set-based
      GROUP BY query. Scalar UDFs can introduce overhead depending on version/
      inlining eligibility. 

SELECT dbo.fn_OrderTotal(1090) AS Order1Total;

-- Set statistics off after your lab
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/*
9) INTERVIEW CHALLENGES (try without looking up answers)
1. Explain why CustomerID is a PK in Customers and an FK in Orders.
2. Try inserting an Order with CustomerID=999999. What error occurs and why?
3. Try inserting duplicate customer email. What constraint protects it?
4. Write a query for top 10 customers by total spend.
5. Write a query for monthly revenue for Delivered orders only.
6. Find products never ordered.
7. Find customers who have no orders.
8. Add an index for a query filtering OrderStatus and OrderDate; justify key order.
9. Compare execution plans before/after indexes using actual rows and STATISTICS IO.
10. Rewrite WHERE YEAR(OrderDate)=2025 as a SARGable range.
11. Create a stored procedure to return orders for a status.
12. Create a view for customer lifetime spend.
13. Discuss index tradeoffs: reads can improve; inserts/updates/deletes and storage may increase.
*/
