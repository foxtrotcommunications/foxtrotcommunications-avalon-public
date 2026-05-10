{{ config(materialized='view') }}

-- Staging: flatten forge-core ExplanationOfBenefit from child tables
--
-- Tree (depth):
--   root__root (2) → eob_raw (3) → eob_patient (4)
--                                → eob_insurer (4)
--                                → eob_insurance (4)
--                                → eob_total (4) → eob_total_amount (5)
--                                → eob_item (4)
--                                → eob_payment (4) → eob_payment_amount (5)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  raw.status,
  raw.outcome,
  REPLACE(COALESCE(pat.reference, ''), 'urn:uuid:', '') AS patient_id,
  CAST(NULL AS STRING) AS insurer_reference,
  ins_org.display AS insurer_display,
  total_amt.value AS total_amount,
  total_amt.currency AS total_currency,
  pay_amt.value AS payment_amount,
  pay_amt.currency AS payment_currency

FROM {{ source('forge_eob', 'root__root') }} r

{{ forge_join('raw',       'forge_eob', 'eob_raw',              'r',   2) }}
{{ forge_join('pat',       'forge_eob', 'eob_patient',          'raw', 3) }}
{{ forge_join('ins_org',   'forge_eob', 'eob_insurer',          'raw', 3) }}
{{ forge_join('total',     'forge_eob', 'eob_total',            'raw', 3) }}
{{ forge_join('total_amt', 'forge_eob', 'eob_total_amount',     'total', 4) }}
{{ forge_join('pay',       'forge_eob', 'eob_payment',          'raw', 3) }}
{{ forge_join('pay_amt',   'forge_eob', 'eob_payment_amount',   'pay', 4) }}
