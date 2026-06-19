-- Drop all schemas used in the project (CASCADE drops all objects inside)
DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS cleaned CASCADE;
DROP SCHEMA IF EXISTS logs CASCADE;
DROP SCHEMA IF EXISTS dwh CASCADE;