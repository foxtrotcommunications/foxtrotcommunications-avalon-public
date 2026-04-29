#!/usr/bin/env python3
"""
Avalon OMOP Vocabulary — Analytics Hub Publisher
==================================================
One-time script (run by Foxtrot Communications) to publish the
forge-poc-452521.omop_vocab dataset to BigQuery Analytics Hub.

After running this, users subscribe via the Console or gcloud and
the vocab dataset appears in their own project — no data movement,
no egress costs, no redistribution concerns.

Prerequisites:
  pip install google-cloud-bigquery-analyticshub
  gcloud auth application-default login

Usage:
  python scripts/publish_vocab.py [--dry-run]

What this creates:
  Analytics Hub Exchange:  forge-poc-452521 / US / avalon_omop_vocab
  Listing:                 omop_vocabulary_snomed_loinc_rxnorm
  Linked dataset source:   forge-poc-452521.omop_vocab

Users subscribe at:
  https://console.cloud.google.com/bigquery/analytics-hub
  → Search "Avalon OMOP Vocabulary"
"""

import argparse
import logging
import sys

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT = "forge-poc-452521"
LOCATION = "US"
DATASET = "omop_vocab"

EXCHANGE_ID = "avalon_omop_vocab"
EXCHANGE_DISPLAY_NAME = "Avalon OMOP Vocabulary"
EXCHANGE_DESCRIPTION = (
    "Filtered OHDSI Standardized Vocabularies (SNOMED CT, LOINC, RxNorm) "
    "for FHIR → OMOP CDM 5.4 concept resolution. "
    "Built for use with the Avalon open source analytics platform: "
    "github.com/foxtrotcommunications/foxtrotcommunications-avalon-public"
)

LISTING_ID = "omop_vocabulary_snomed_loinc_rxnorm"
LISTING_DISPLAY_NAME = "OMOP Vocabulary — SNOMED + LOINC + RxNorm"
LISTING_DESCRIPTION = (
    "OHDSI Standardized Vocabularies filtered for FHIR → OMOP mapping.\n\n"
    "Contents:\n"
    "  • concept               — SNOMED CT, LOINC, RxNorm concepts\n"
    "  • concept_relationship  — 'Maps to' relationships for standard concept resolution\n"
    "  • concept_map           — Pre-joined view: source_code + vocabulary → standard_concept_id\n\n"
    "License: Apache 2.0. SNOMED CT distributed under SNOMED International affiliate license.\n"
    "Vocabulary source: OHDSI Athena (athena.ohdsi.org). Updated annually.\n\n"
    "Usage:\n"
    "  1. Subscribe to this listing\n"
    "  2. Set omop_vocab_project in your dbt_project.yml\n"
    "  3. Run: dbt run"
)
# ─────────────────────────────────────────────────────────────────────────────


def parse_args():
    p = argparse.ArgumentParser(description="Publish omop_vocab to BigQuery Analytics Hub")
    p.add_argument("--dry-run", action="store_true", help="Print actions without executing")
    return p.parse_args()


def get_client():
    try:
        from google.cloud import bigquery_analyticshub_v1
        return bigquery_analyticshub_v1.AnalyticsHubServiceClient()
    except ImportError:
        log.error("google-cloud-bigquery-analyticshub not installed.")
        log.error("Run: pip install google-cloud-bigquery-analyticshub")
        sys.exit(1)


def ensure_exchange(client, dry_run):
    from google.cloud import bigquery_analyticshub_v1

    parent = f"projects/{PROJECT}/locations/{LOCATION}"
    exchange_name = f"{parent}/dataExchanges/{EXCHANGE_ID}"

    try:
        existing = client.get_data_exchange(name=exchange_name)
        log.info(f"✓ Exchange already exists: {existing.name}")
        return existing.name
    except Exception:
        pass  # doesn't exist yet

    exchange = bigquery_analyticshub_v1.DataExchange(
        display_name=EXCHANGE_DISPLAY_NAME,
        description=EXCHANGE_DESCRIPTION,
        primary_contact="engineering@foxtrotcommunications.net",
        documentation="https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public",
    )

    if dry_run:
        log.info(f"[dry-run] Would create exchange: {exchange_name}")
        log.info(f"          display_name: {EXCHANGE_DISPLAY_NAME}")
        return exchange_name

    result = client.create_data_exchange(
        parent=parent,
        data_exchange_id=EXCHANGE_ID,
        data_exchange=exchange,
    )
    log.info(f"✓ Exchange created: {result.name}")
    return result.name


def ensure_listing(client, exchange_name, dry_run):
    from google.cloud import bigquery_analyticshub_v1

    listing_name = f"{exchange_name}/listings/{LISTING_ID}"
    source_dataset = f"projects/{PROJECT}/datasets/{DATASET}"

    try:
        existing = client.get_listing(name=listing_name)
        log.info(f"✓ Listing already exists: {existing.name}")
        log.info(f"  Updating description and source…")
    except Exception:
        pass  # will create below

    listing = bigquery_analyticshub_v1.Listing(
        display_name=LISTING_DISPLAY_NAME,
        description=LISTING_DESCRIPTION,
        bigquery_dataset=bigquery_analyticshub_v1.Listing.BigQueryDatasetSource(
            dataset=source_dataset,
        ),
        state=bigquery_analyticshub_v1.Listing.State.ACTIVE,
    )

    if dry_run:
        log.info(f"[dry-run] Would create listing: {listing_name}")
        log.info(f"          source dataset: {source_dataset}")
        return

    try:
        result = client.create_listing(
            parent=exchange_name,
            listing_id=LISTING_ID,
            listing=listing,
        )
        log.info(f"✓ Listing created: {result.name}")
    except Exception as e:
        if "already exists" in str(e).lower():
            result = client.update_listing(listing=listing)
            log.info(f"✓ Listing updated: {result.name}")
        else:
            raise


def make_exchange_public(client, exchange_name, dry_run):
    """Set IAM policy to allow allUsers to subscribe (public listing)."""
    from google.iam.v1 import iam_policy_pb2, policy_pb2

    if dry_run:
        log.info(f"[dry-run] Would set allUsers subscriber IAM on {exchange_name}")
        return

    policy = client.get_iam_policy(
        request=iam_policy_pb2.GetIamPolicyRequest(resource=exchange_name)
    )
    subscriber_binding = policy_pb2.Binding(
        role="roles/analyticshub.subscriber",
        members=["allUsers"],
    )
    policy.bindings.append(subscriber_binding)
    client.set_iam_policy(
        request=iam_policy_pb2.SetIamPolicyRequest(
            resource=exchange_name, policy=policy
        )
    )
    log.info("✓ Analytics Hub exchange set to public (allUsers can subscribe)")


def main():
    args = parse_args()
    client = get_client()

    log.info(f"Project:  {PROJECT}")
    log.info(f"Location: {LOCATION}")
    log.info(f"Source:   {PROJECT}.{DATASET}")
    log.info("")

    exchange_name = ensure_exchange(client, args.dry_run)
    ensure_listing(client, exchange_name, args.dry_run)
    make_exchange_public(client, exchange_name, args.dry_run)

    log.info("")
    log.info("✅  Analytics Hub listing published.")
    log.info("")
    log.info("Users can now subscribe at:")
    log.info("  https://console.cloud.google.com/bigquery/analytics-hub")
    log.info('  → Search: "Avalon OMOP Vocabulary"')
    log.info("")
    log.info("Or direct link:")
    log.info(f"  https://console.cloud.google.com/bigquery/analytics-hub/exchanges"
             f";project={PROJECT}/locations/{LOCATION.lower()}"
             f"/dataExchanges/{EXCHANGE_ID}/listings/{LISTING_ID}")


if __name__ == "__main__":
    main()
