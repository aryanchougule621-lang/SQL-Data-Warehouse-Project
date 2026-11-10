/*
================================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
================================================================================

Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to
    populate the 'silver' schema tables from the 'bronze' schema.

Actions Performed:
    - Truncates Silver tables.
    - Inserts transformed and cleansed data from Bronze into Silver tables.

Parameters:
    None.
    This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;

================================================================================
*/
CREATE OR ALTER PROCEDURE [Silver].[load_silver]
AS
BEGIN
    DECLARE
        @start_time DATETIME,
        @end_time DATETIME,
        @batch_start_time DATETIME,
        @batch_end_time DATETIME;

    BEGIN TRY

        -- ==============================================
        -- Loading the Silver Layer
        -- ==============================================

        SET @batch_start_time = GETDATE();

        PRINT '==============================================';
        PRINT 'Loading the Silver Layer';
        PRINT '==============================================';

        -- ----------------------------------------------
        -- Loading the CRM Tables
        -- ----------------------------------------------

        PRINT '----------------------------------------------';
        PRINT ' Loading the CRM Tables ';
        PRINT '----------------------------------------------';

        -- >> Truncating and Inserting Data: Silver.crm_cust_info
        -- Remove existing records before loading the transformed customer data.

        PRINT '>> Truncating Table: Silver.crm_cust_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.crm_cust_info;

        PRINT '>> Inserting Into: Silver.crm_cust_info';

        INSERT INTO Silver.crm_cust_info(
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                ELSE 'N/A'
            END AS cst_marital_status,
            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                ELSE 'N/A'
            END AS cst_gndr,
            cst_create_date
        FROM
        (
            SELECT
                ROW_NUMBER() OVER (
                    PARTITION BY cst_id
                    ORDER BY cst_create_date DESC
                ) AS flag_last,
                *
            FROM Bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) t
        WHERE flag_last = 1;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- >> Truncating and Inserting Data: Silver.crm_prd_info
        -- Transform product information, extract category and product keys,
        -- handle missing costs, standardize product lines, and calculate end dates.

        PRINT '>> Truncating Table: Silver.crm_prd_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.crm_prd_info;

        PRINT '>> Inserting Into: Silver.crm_prd_info';

        INSERT INTO Silver.crm_prd_info(
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
            SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
            prd_nm,
            ISNULL(prd_cost, 0) AS prd_cost,
            CASE TRIM(UPPER(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'N/A'
            END AS prd_line,
            CAST(prd_start_dt AS DATE) AS prd_start_dt,
            CAST(
                LEAD(prd_start_dt) OVER (
                    PARTITION BY prd_key
                    ORDER BY prd_start_dt
                ) - 1 AS DATE
            ) AS prd_end_dt
        FROM Bronze.crm_prd_info;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- >> Truncating and Inserting Data: Silver.crm_sales_details
        -- Validate date values, handle incorrect sales and prices,
        -- and maintain consistency between sales, quantity, and price.

        PRINT '>> Truncating Table: Silver.crm_sales_details';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.crm_sales_details;

        PRINT '>> Inserting Into: Silver.crm_sales_details';

        INSERT INTO Silver.crm_sales_details(
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_date,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE
                WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END AS sls_order_dt,
            CASE
                WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END AS sls_ship_dt,
            CASE
                WHEN sls_due_date = 0 OR LEN(sls_due_date) != 8 THEN NULL
                ELSE CAST(CAST(sls_due_date AS VARCHAR) AS DATE)
            END AS sls_due_date,
            CASE
                WHEN sls_sales IS NULL
                     OR sls_sales <= 0
                     OR sls_sales != sls_quantity * ABS(sls_price)
                THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,
            sls_quantity,
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                THEN sls_sales / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS sls_price
        FROM Bronze.crm_sales_details;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- ----------------------------------------------
        -- Loading the ERP Tables
        -- ----------------------------------------------

        PRINT '----------------------------------------------';
        PRINT ' Loading the ERP Tables ';
        PRINT '----------------------------------------------';


        -- >> Truncating and Inserting Data: Silver.erp_cust_az12
        -- Remove the NAS prefix from customer IDs, handle future birth dates,
        -- and standardize gender values.

        PRINT '>> Truncating Table: Silver.erp_cust_az12';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.erp_cust_az12;

        PRINT '>> Inserting Into: Silver.erp_cust_az12';

        INSERT INTO Silver.erp_cust_az12(
            cid,
            bdate,
            gen
        )
        SELECT DISTINCT
            CASE
                WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE cid
            END AS cid,
            CASE
                WHEN bdate > GETDATE() THEN NULL
                ELSE bdate
            END AS bdate,
            CASE
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
                ELSE 'n/a'
            END AS gen
        FROM Bronze.erp_cust_az12;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- >> Truncating and Inserting Data: Silver.erp_loc_a101
        -- Standardize customer IDs by removing hyphens
        -- and normalize country names and missing country values.

        PRINT '>> Truncating Table: Silver.erp_loc_a101';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.erp_loc_a101;

        PRINT '>> Inserting Into: Silver.erp_loc_a101';

        INSERT INTO Silver.erp_loc_a101(
            cid,
            cntry
        )
        SELECT
            REPLACE(cid, '-', '') AS cid,
            CASE
                WHEN TRIM(cntry) IN ('USA', 'UNITED STATES', 'US')
                    THEN 'United States'
                WHEN TRIM(cntry) = 'DE'
                    THEN 'Germany'
                WHEN TRIM(cntry) = ' ' OR cntry IS NULL
                    THEN 'N/A'
                ELSE cntry
            END AS cntry
        FROM Bronze.erp_loc_a101;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- >> Truncating and Inserting Data: Silver.erp_px_cat_g1v2
        -- Load product category information from the Bronze Layer
        -- into the Silver Layer.

        PRINT '>> Truncating Table: Silver.erp_px_cat_g1v2';

        SET @start_time = GETDATE();

        TRUNCATE TABLE Silver.erp_px_cat_g1v2;

        PRINT '>> Inserting Into: Silver.erp_px_cat_g1v2';

        INSERT INTO Silver.erp_px_cat_g1v2(
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,
            cat,
            subcat,
            maintenance
        FROM Bronze.erp_px_cat_g1v2;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @start_time, @end_time) AS VARCHAR) +
            ' seconds';


        -- ==============================================
        -- Total Loading Time
        -- ==============================================

        PRINT '----------------------------------------------';
        PRINT ' TOTAL LOADING TIME ';
        
        SET @batch_end_time = GETDATE();

        PRINT '>> Load Duration: ' +
            CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS VARCHAR) +
            ' seconds';

        PRINT '==============================================';
        PRINT 'Silver Layer Loading Completed Successfully';
        PRINT '==============================================';

    END TRY

    BEGIN CATCH

        -- ==============================================
        -- Error Handling
        -- ==============================================

        PRINT '================================================================';
        PRINT 'ERROR OCCURRED DURING LOADING SILVER LAYER';
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT 'Error Line: ' + CAST(ERROR_LINE() AS NVARCHAR);
        PRINT '================================================================';

        THROW;

    END CATCH

END;
GO
