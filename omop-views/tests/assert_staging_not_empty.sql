-- Contract test: ensure forge_join produces non-zero rows
-- If this returns results, the staging layer is producing empty joins
-- which indicates a table_path / table name mismatch

SELECT 'stg_patient' AS model, COUNT(*) AS row_count FROM {{ ref('stg_patient') }} WHERE patient_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_encounter', COUNT(*) FROM {{ ref('stg_encounter') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_condition', COUNT(*) FROM {{ ref('stg_condition') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_procedure', COUNT(*) FROM {{ ref('stg_procedure') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_observation', COUNT(*) FROM {{ ref('stg_observation') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_medication_request', COUNT(*) FROM {{ ref('stg_medication_request') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
