# Forge Table Contract

This directory defines the **interface contract** between [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) and the OMOP analytics layer.

## What Is This?

The `contract.json` file specifies exactly which forge-core sub-tables and columns the OMOP dbt models depend on. It serves three purposes:

1. **For analytics authors**: Know which columns are guaranteed to exist when writing new OMOP views or analytics packages
2. **For forge-core developers**: Know which outputs are consumed downstream — changes to these tables are breaking changes
3. **For CI**: The contract is validated on every PR to prevent accidental breaks

## How Forge-Core Produces These Tables

When forge-core processes FHIR JSON, it decomposes nested structures into a tree of relational tables:

```
frg__root                          ← ingestion metadata (hash, timestamp, idx)
└── frg__root__raw_1               ← first-level FHIR fields (id, status, etc.)
    ├── frg__root__raw_1__code1    ← CodeableConcept
    │   └── code1__codi1           ← Coding[] array items (code, display, system)
    ├── frg__root__raw_1__subj1    ← subject reference
    ├── frg__root__raw_1__enco1    ← encounter reference
    ├── frg__root__raw_1__valu1    ← valueQuantity
    ├── frg__root__raw_1__peri1    ← period (start, end)
    ├── frg__root__raw_1__exte1    ← extensions
    │   └── exte1__exte1           ← nested extensions
    │       └── exte1__valu1       ← extension values
    └── ...
```

Each forge-core normalized dataset (e.g., `fhir_normalized_patient`, `fhir_normalized_encounter`) contains this tree for one FHIR resource type.

## Naming Convention

Forge-core truncates FHIR field names to 4 characters and appends a sequence number:

| FHIR Field | Forge Table Suffix |
|------------|-------------------|
| `code` | `code1` |
| `code.coding` | `code1__codi1` |
| `subject` | `subj1` |
| `encounter` | `enco1` |
| `valueQuantity` | `valu1` |
| `performedPeriod` | `perf1` |
| `extension` | `exte1` |
| `medicationCodeableConcept` | `medi1` |
| `maritalStatus` | `mari1` |

## Joining Sub-Tables

Sub-tables are joined using the `idx` column — a positional segment-based key:

```sql
-- Parent has N segments in idx (e.g., "1_1" = 2 segments)
-- Child has N+1 segments (e.g., "1_1_1" = 3 segments)
-- Join: match first N segments positionally

LEFT JOIN frg__root__raw_1 raw
  ON raw.ingestion_hash = r.ingestion_hash
  AND SPLIT(raw.idx, '_')[SAFE_OFFSET(0)] = SPLIT(r.idx, '_')[SAFE_OFFSET(0)]
  AND SPLIT(raw.idx, '_')[SAFE_OFFSET(1)] = SPLIT(r.idx, '_')[SAFE_OFFSET(1)]
```

The `forge_join` macro in `omop-views/macros/` handles this automatically.

## Modifying the Contract

Changes to `contract.json` require explicit approval from `@foxtrotcommunications/core` and may constitute a breaking change for downstream consumers.
