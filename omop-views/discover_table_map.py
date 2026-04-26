"""
Forge Table Map Discovery Script

Reads table_path from all forge-core sub-tables in a normalized dataset
and generates a forge_table_map.yml for the OMOP dbt models.

Usage:
    python discover_table_map.py --project your-project

    # Specific resource types only
    python discover_table_map.py --project your-project --resources patient encounter

    # Output to custom path
    python discover_table_map.py --project your-project --output ./my_map.yml
"""

import argparse
import json
import logging
import os
import sys
import yaml
from typing import Dict, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("forge-table-map-discovery")

# Map of OMOP resource key → forge normalized dataset name
RESOURCE_DATASETS = {
    "patient": "fhir_normalized_patient",
    "encounter": "fhir_normalized_encounter",
    "condition": "fhir_normalized_condition",
    "procedure": "fhir_normalized_procedure",
    "observation": "fhir_normalized_observation",
    "medication_request": "fhir_normalized_medicationrequest",
    "immunization": "fhir_normalized_immunization",
    "claim": "fhir_normalized_claim",
    "explanation_of_benefit": "fhir_normalized_explanationofbenefit",
}

# FHIR paths we need for OMOP staging models
# Maps: semantic_key → expected table_path value
REQUIRED_PATHS = {
    "patient": {
        "raw": "frg__root",
        "extension": "frg__root__extension",
        "extension.extension": "frg__root__extension__extension",
        "extension.extension.valueCoding": "frg__root__extension__extension__valueCoding",
    },
    "encounter": {
        "raw": "frg__root",
        "class": "frg__root__class",
        "period": "frg__root__period",
        "participant": "frg__root__participant",
        "participant.individual": "frg__root__participant__individual",
        "subject": "frg__root__subject",
    },
    "condition": {
        "raw": "frg__root",
        "code": "frg__root__code",
        "code.coding": "frg__root__code__coding",
        "subject": "frg__root__subject",
        "encounter": "frg__root__encounter",
    },
    "procedure": {
        "raw": "frg__root",
        "code": "frg__root__code",
        "code.coding": "frg__root__code__coding",
        "performedPeriod": "frg__root__performedPeriod",
        "subject": "frg__root__subject",
        "encounter": "frg__root__encounter",
    },
    "observation": {
        "raw": "frg__root",
        "code": "frg__root__code",
        "code.coding": "frg__root__code__coding",
        "valueQuantity": "frg__root__valueQuantity",
        "subject": "frg__root__subject",
        "encounter": "frg__root__encounter",
    },
    "medication_request": {
        "raw": "frg__root",
        "medicationCodeableConcept": "frg__root__medicationCodeableConcept",
        "medicationCodeableConcept.coding": "frg__root__medicationCodeableConcept__coding",
        "subject": "frg__root__subject",
        "encounter": "frg__root__encounter",
    },
}


def discover_table_map(
    project_id: str,
    resources: Optional[List[str]] = None,
    credentials=None,
) -> Dict:
    """
    Query each forge-core normalized dataset to discover actual table names
    by reading the table_path column.

    Returns a dict mapping semantic keys → actual table names.
    """
    from google.cloud import bigquery

    bq = bigquery.Client(project=project_id, credentials=credentials)

    # Which resources to discover
    target_resources = resources or list(REQUIRED_PATHS.keys())
    available_datasets = {ds.dataset_id for ds in bq.list_datasets()}

    table_map = {}

    for resource_key in target_resources:
        dataset = RESOURCE_DATASETS.get(resource_key)
        if not dataset:
            logger.warning(f"Unknown resource key: {resource_key}")
            continue

        if dataset not in available_datasets:
            logger.warning(f"⏭ Dataset {dataset} not found, skipping {resource_key}")
            continue

        logger.info(f"Discovering {resource_key} → {dataset}...")
        resource_map = {}

        # List all tables in the dataset
        tables = list(bq.list_tables(f"{project_id}.{dataset}"))
        table_names = [t.table_id for t in tables]

        # For each table that has a table_path column, read its value
        for table_name in table_names:
            if not table_name.startswith("frg__"):
                continue

            try:
                query = f"""
                    SELECT DISTINCT table_path
                    FROM `{project_id}.{dataset}.{table_name}`
                    WHERE table_path IS NOT NULL
                    LIMIT 1
                """
                result = bq.query(query).result()
                rows = list(result)
                if rows:
                    table_path = rows[0].table_path
                    resource_map[table_path] = table_name
                    logger.info(f"  {table_path} → {table_name}")
            except Exception as e:
                # frg__root won't have table_path as a queryable value
                # in the same way — handle gracefully
                if table_name == "frg__root":
                    resource_map["frg"] = "frg__root"
                else:
                    logger.debug(f"  Could not read table_path from {table_name}: {e}")

        # Now map our semantic keys to discovered table names
        required = REQUIRED_PATHS.get(resource_key, {})
        resolved = {}

        for semantic_key, expected_path in required.items():
            if semantic_key == "raw":
                # raw_1 is always the first child of root
                # Find the table whose path is frg__root
                candidates = [
                    tn for tn in table_names
                    if tn.startswith("frg__root__") and tn.count("__") == 2
                ]
                if candidates:
                    resolved[semantic_key] = candidates[0]
                else:
                    resolved[semantic_key] = "frg__root__raw_1"  # default
            elif expected_path in resource_map:
                resolved[semantic_key] = resource_map[expected_path]
            else:
                # Try partial match on the last segment
                last_segment = expected_path.split("__")[-1]
                matches = [
                    (path, name) for path, name in resource_map.items()
                    if path.endswith(f"__{last_segment}")
                ]
                if matches:
                    resolved[semantic_key] = matches[0][1]
                    logger.info(
                        f"  ⚠ Fuzzy match: {semantic_key} → {matches[0][1]} "
                        f"(path: {matches[0][0]})"
                    )
                else:
                    logger.warning(f"  ✗ Could not resolve: {semantic_key} ({expected_path})")
                    resolved[semantic_key] = None

        table_map[resource_key] = resolved

    return table_map


def generate_yaml(table_map: Dict, output_path: str):
    """Write the discovered table map to a YAML file."""
    output = {
        "_comment": (
            "Auto-generated by discover_table_map.py. "
            "Maps semantic FHIR paths to actual forge-core table names. "
            "Override values if your deployment uses different table names."
        ),
        "forge_tables": table_map,
    }

    with open(output_path, "w") as f:
        yaml.dump(output, f, default_flow_style=False, sort_keys=False)

    logger.info(f"\n✅ Wrote table map to {output_path}")
    logger.info(f"   {sum(len(v) for v in table_map.values())} mappings across {len(table_map)} resources")


def main():
    parser = argparse.ArgumentParser(
        description="Discover forge-core table names from table_path column"
    )
    parser.add_argument("--project", required=True, help="GCP project ID")
    parser.add_argument(
        "--resources", nargs="*",
        help="Resource types to discover (default: all)",
    )
    parser.add_argument(
        "--output", default="omop-views/forge_table_map.yml",
        help="Output YAML path (default: omop-views/forge_table_map.yml)",
    )
    parser.add_argument("--json", action="store_true", help="Also output JSON")

    args = parser.parse_args()

    table_map = discover_table_map(
        project_id=args.project,
        resources=args.resources,
    )

    generate_yaml(table_map, args.output)

    if args.json:
        json_path = args.output.replace(".yml", ".json")
        with open(json_path, "w") as f:
            json.dump(table_map, f, indent=2)
        logger.info(f"   Also wrote JSON to {json_path}")


if __name__ == "__main__":
    main()
