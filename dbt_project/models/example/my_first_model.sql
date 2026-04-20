-- models/example/my_first_model.sql
--
-- Simplest possible model: returns a single row so we can confirm dbt can
-- compile, connect to Oracle, and materialize a view.

{{ config(materialized='view') }}

SELECT 1 AS id, 'hello dbt-oracle' AS message FROM dual
