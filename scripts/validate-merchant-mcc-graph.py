#!/usr/bin/env python3
"""Validate PickMe's merchant MCC graph seed invariants.

This deliberately uses only the Python standard library so it can run anywhere CI runs.
JSON Schema remains the shape contract; this script checks cross-record invariants that
JSON Schema cannot express cleanly.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH = ROOT / "contracts" / "merchant-mcc-graph.seed.json"


def fail(message: str) -> None:
    print(f"merchant MCC graph invalid: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    data = json.loads(GRAPH.read_text(encoding="utf-8"))

    merchants = data.get("merchants", [])
    profiles = data.get("profiles", {})
    categories = data.get("categories", {})
    observations = data.get("observations", [])

    if len(merchants) != 500:
        fail(f"expected exactly 500 seed merchants, found {len(merchants)}")

    ids = [m["id"] for m in merchants]
    if len(ids) != len(set(ids)):
        fail("merchant ids are not unique")

    names = [m["name"].casefold() for m in merchants]
    if len(names) != len(set(names)):
        fail("merchant display names are not unique case-insensitively")

    for merchant in merchants:
        if merchant["category"] not in categories:
            fail(f"{merchant['id']} references unknown category {merchant['category']!r}")
        if merchant["profile"] not in profiles:
            fail(f"{merchant['id']} references unknown profile {merchant['profile']!r}")

    for profile_id, profile in profiles.items():
        mccs = profile["candidateMccs"]
        weights = profile["weights"]
        if len(mccs) != len(weights):
            fail(f"profile {profile_id} candidateMccs/weights length mismatch")
        if profile["primaryMcc"] != mccs[0]:
            fail(f"profile {profile_id} primaryMcc must be first candidate")
        if len(mccs) != len(set(mccs)):
            fail(f"profile {profile_id} repeats an MCC")
        if not math.isclose(sum(weights), 1.0, abs_tol=1e-9):
            fail(f"profile {profile_id} weights sum to {sum(weights)!r}, expected 1.0")
        if not 0 <= profile["confidence"] <= 0.60:
            fail(f"profile {profile_id} editorial seed confidence must be <= 0.60")

    merchant_ids = set(ids)
    observation_ids: set[str] = set()
    for observation in observations:
        oid = observation["id"]
        if oid in observation_ids:
            fail(f"duplicate observation id {oid}")
        observation_ids.add(oid)

        if observation["merchantId"] not in merchant_ids:
            fail(f"{oid} references unknown merchant {observation['merchantId']}")
        if observation["sourceType"] == "community_directory_location":
            if observation["confidence"] > 0.40:
                fail(f"{oid} community-directory confidence must be <= 0.40")
            if not observation.get("sourceUrl"):
                fail(f"{oid} community-directory evidence requires sourceUrl")
            if not observation.get("scope", {}).get("address"):
                fail(f"{oid} community-directory evidence must stay location-scoped")

    print(
        f"merchant MCC graph OK: {len(merchants)} merchants, "
        f"{len(profiles)} prior profiles, {len(observations)} location observations"
    )


if __name__ == "__main__":
    main()
