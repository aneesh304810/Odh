-- models/example/my_second_model.sql
--
-- References my_first_model to confirm the ref() macro and the DAG
-- dependency graph work end-to-end.

{{ config(materialized='view') }}

SELECT
    id,
    UPPER(message) AS shouty_message
FROM {{ ref('my_first_model') }}
