
/*
================================================
Create Database and Schemas
================================================
Script Purpose:
    This script creates a new database named
    'DataWarehouse' after checking whether it
    already exists.

    If the database exists, it is dropped and
    recreated. The script also creates three
    schemas: Bronze, Silver, and Gold.

WARNING:
    Running this script will permanently delete
    the existing 'DataWarehouse' database and
    all its data. Back up your data before running.
*/

USE master;
GO

-- Drop and recreate the database if it exists
IF EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE name = 'DataWarehouse'
)
BEGIN
    ALTER DATABASE DataWarehouse
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    DROP DATABASE DataWarehouse;
END;
GO

-- Create the database
CREATE DATABASE DataWarehouse;
GO

-- Switch to the new database
USE DataWarehouse;
GO

-- Create the Bronze, Silver, and Gold schemas
CREATE SCHEMA Bronze;
GO

CREATE SCHEMA Silver;
GO

CREATE SCHEMA Gold;
GO
