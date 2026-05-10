"""
Forge Table Map Builder — from all_metadata.json

Converts forge-core's all_metadata.json output into a forge_tables
map suitable for the avalon-public dbt package.

Used by:
  - SaaS pipeline: reads metadata from GCS after each forge-core run
  - CLI: reads local metadata file for testing

The all_metadata.json is produced by forge-core's UnnestingResult
and saved to GCS at: {artifacts_gcs_path}/schema/all_metadata.json

Each entry has:
  - model_name: actual table name (e.g. "root__raw_1__exte1")
  - table_path: canonical FHIR path (e.g. "root__extension")
  - depth: nesting level
"""

import json
import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

# Maps FHIR semantic paths to our forge_tables config keys.
# table_path value → (resource_key, semantic_key)
PATH_TO_KEY = {
    # Patient
    "root__extension":                             ("patient", "extension"),
    "root__extension__extension":                  ("patient", "ext_ext"),
    "root__extension__extension__valueCoding":     ("patient", "ext_ext_val"),
    # Encounter
    "root__class":                                 ("encounter", "class"),
    "root__period":                                ("encounter", "period"),
    "root__participant":                           ("encounter", "participant"),
    "root__participant__individual":               ("encounter", "part_indiv"),
    "root__subject":                               ("encounter", "subject"),
    # Condition
    "root__code":                                  ("condition", "code"),
    "root__code__coding":                          ("condition", "code_coding"),
    # Also used by: procedure, observation
    # Procedure
    "root__performedPeriod":                        ("procedure", "performed"),
    # Observation
    "root__valueQuantity":                          ("observation", "value"),
    # MedicationRequest
    "root__medicationCodeableConcept":              ("medication_request", "med_concept"),
    "root__medicationCodeableConcept__coding":      ("medication_request", "med_coding"),
    # Claim
    "root__billablePeriod":                         ("claim", "billable_period"),
    "root__provider":                               ("claim", "provider"),
    "root__patient":                                ("claim", "patient"),
    "root__facility":                               ("claim", "facility"),
    "root__priority":                               ("claim", "priority"),
    "root__priority__coding":                       ("claim", "priority_coding"),
    "root__item":                                   ("claim", "item"),
    "root__item__encounter":                        ("claim", "item_encounter"),
    "root__item__net":                              ("claim", "item_net"),
    "root__item__productOrService__coding":         ("claim", "item_product_coding"),
    # EOB
    "root__insurer":                                ("eob", "insurer"),
    "root__total":                                  ("eob", "total"),
    "root__total__amount":                          ("eob", "total_amount"),
    "root__payment":                                ("eob", "payment"),
    "root__payment__amount":                        ("eob", "payment_amount"),
}

# Shared paths (same FHIR path, different resource contexts)
SHARED_PATHS = {
    "root__subject":       [("encounter", "subject"), ("condition", "subject"),
                                  ("procedure", "subject"), ("observation", "subject"),
                                  ("medication_request", "subject")],
    "root__encounter":     [("condition", "encounter"), ("procedure", "encounter"),
                                  ("observation", "encounter"), ("medication_request", "encounter")],
    "root__code":          [("condition", "code"), ("procedure", "code"),
                                  ("observation", "code")],
    "root__code__coding":  [("condition", "code_coding"), ("procedure", "code_coding"),
                                  ("observation", "code_coding")],
    "root__patient":       [("claim", "patient"), ("eob", "patient")],
}


def build_forge_table_map(
    metadata_entries: List[Dict],
    resource_type: Optional[str] = None,
) -> Dict[str, Dict[str, str]]:
    """
    Build a forge_tables map from all_metadata.json entries.

    Args:
        metadata_entries: List of metadata dicts from forge-core
        resource_type: Optional FHIR resource type to scope the mapping
                      (e.g. "Patient", "Encounter")

    Returns:
        Dict[resource_key, Dict[semantic_key, actual_table_name]]
    """
    result = {}

    for entry in metadata_entries:
        table_path = entry.get("table_path", "")
        model_name = entry.get("model_name", "")

        if not table_path or not model_name:
            continue

        # Every resource has raw_1 as first child
        if table_path.count("__") == 1 and table_path.startswith("root__"):
            # This is root level — skip, we use root directly
            continue

        # Check for raw (first child of root)
        depth = len(table_path.split("__"))
        if depth == 2 and "root" in table_path:
            # root__<field> — this could be raw_1
            if entry.get("field_name") == "root":
                # This IS the raw table
                # Determine resource type and set raw for all possible resources
                _set_all_resources(result, "raw", model_name)
                continue

        # Check shared paths first
        if table_path in SHARED_PATHS:
            for resource_key, semantic_key in SHARED_PATHS[table_path]:
                _set(result, resource_key, semantic_key, model_name)
            continue

        # Check specific paths
        if table_path in PATH_TO_KEY:
            resource_key, semantic_key = PATH_TO_KEY[table_path]
            _set(result, resource_key, semantic_key, model_name)

    return result


def _set(result: dict, resource_key: str, semantic_key: str, model_name: str):
    if resource_key not in result:
        result[resource_key] = {}
    result[resource_key][semantic_key] = model_name


def _set_all_resources(result: dict, semantic_key: str, model_name: str):
    for rk in ["patient", "encounter", "condition", "procedure",
                "observation", "medication_request", "claim", "eob"]:
        _set(result, rk, semantic_key, model_name)


def from_gcs(bucket_name: str, gcs_path: str) -> Dict:
    """Load all_metadata.json from GCS and build the map."""
    from google.cloud import storage
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(gcs_path)
    content = blob.download_as_text()
    metadata = json.loads(content)
    return build_forge_table_map(metadata)


def from_file(file_path: str) -> Dict:
    """Load all_metadata.json from local file and build the map."""
    with open(file_path) as f:
        metadata = json.load(f)
    return build_forge_table_map(metadata)


def to_dbt_vars(table_map: Dict) -> str:
    """Format the table map as dbt --vars YAML string."""
    import yaml
    return yaml.dump({"forge_tables": table_map}, default_flow_style=False)


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python build_table_map.py <all_metadata.json>")
        sys.exit(1)

    table_map = from_file(sys.argv[1])
    print(to_dbt_vars(table_map))
