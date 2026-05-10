{{ config(materialized='view') }}

-- Staging: flatten forge-core Claim from child tables only
--
-- Tree (depth):
--   root (2) → claim_raw (3) → claim_billable_period (4)
--                                  → claim_provider (4)
--                                  → claim_patient (4)
--                                  → claim_facility (4)
--                                  → claim_priority (4) → claim_priority_coding (5)
--                                  → claim_item (4) → claim_item_encounter (5)
--                                                    → claim_item_net (5)
--                                                    → claim_item_product_coding (5)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  raw.status,
  raw.use,
  raw.created,
  REPLACE(COALESCE(pat.reference, ''), 'urn:uuid:', '') AS patient_id,
  prov.reference AS provider_reference,
  prov.display AS provider_name,
  fac.reference AS facility_reference,
  bill.start AS billable_period_start,
  bill.`end` AS billable_period_end,
  prio_c.code AS priority_code,
  -- Encounter FK from item-level encounter references
  REPLACE(COALESCE(item_enc.reference, ''), 'urn:uuid:', '') AS encounter_id,
  item_net.value AS item_net_value,
  item_net.currency AS item_currency,
  item_prod.code AS item_product_code,
  item_prod.display AS item_product_display

FROM {{ source('forge_claim', 'root') }} r

{{ forge_join('raw',       'forge_claim', 'claim_raw',              'r',    2) }}
{{ forge_join('bill',      'forge_claim', 'claim_billable_period',  'raw',  3) }}
{{ forge_join('prov',      'forge_claim', 'claim_provider',         'raw',  3) }}
{{ forge_join('pat',       'forge_claim', 'claim_patient',          'raw',  3) }}
{{ forge_join('fac',       'forge_claim', 'claim_facility',         'raw',  3) }}
{{ forge_join('prio',      'forge_claim', 'claim_priority',         'raw',  3) }}
{{ forge_join('prio_c',    'forge_claim', 'claim_priority_coding',  'prio', 4) }}
{{ forge_join('item',      'forge_claim', 'claim_item',             'raw',  3) }}
{{ forge_join('item_enc',  'forge_claim', 'claim_item_encounter',   'item', 4) }}
{{ forge_join('item_net',  'forge_claim', 'claim_item_net',         'item', 4) }}
{{ forge_join('item_prod', 'forge_claim', 'claim_item_product_coding', 'item', 4) }}
