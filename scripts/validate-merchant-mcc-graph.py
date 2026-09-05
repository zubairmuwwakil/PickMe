#!/usr/bin/env python3
"""Validate PickMe's merchant MCC graph seed invariants.

Uses only the Python standard library. The graph is intentionally sharded so the
seed stays reviewable in 50-merchant shards; manifest.json defines the shard set.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH_DIR = ROOT / "contracts" / "merchant-mcc-graph"
MANIFEST = GRAPH_DIR / "manifest.json"


def fail(message: str) -> None:
    print(f"merchant MCC graph invalid: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing {path.relative_to(ROOT)}")
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)} is invalid JSON: {exc}")


def main() -> None:
    manifest = load_json(MANIFEST)
    files = manifest.get("files", {})
    categories = manifest.get("categories", {})
    profiles = load_json(GRAPH_DIR / files["profiles"])
    observations = load_json(GRAPH_DIR / files["observations"])

    shard_names = files.get("merchantShards", [])
    if not shard_names:
        fail("expected at least one merchant shard")

    merchants = []
    for shard_name in shard_names:
        shard = load_json(GRAPH_DIR / shard_name)
        if not isinstance(shard, list) or len(shard) != 50:
            fail(f"{shard_name} must contain exactly 50 merchants")
        merchants.extend(shard)

    if len(merchants) != len(shard_names) * 50:
        fail(f"expected {len(shard_names) * 50} seed merchants, found {len(merchants)}")

    ids = [m["id"] for m in merchants]
    if len(ids) != len(set(ids)):
        fail("merchant ids are not unique")

    names = [(m["country"], m["name"].casefold()) for m in merchants]
    if len(names) != len(set(names)):
        fail("merchant display names are not unique within a country")

    for merchant in merchants:
        if merchant["category"] not in categories:
            fail(f"{merchant['id']} references unknown category {merchant['category']!r}")
        if merchant["profile"] not in profiles:
            fail(f"{merchant['id']} references unknown profile {merchant['profile']!r}")
        if merchant["country"] == "US":
            for field in ("sourceUrl", "sourceMcc", "sourceChecked"):
                if not merchant.get(field):
                    fail(f"{merchant['id']} needs cited US MCC field {field}")
            if merchant["sourceMcc"] != profiles[merchant["profile"]]["primaryMcc"]:
                fail(f"{merchant['id']} cited MCC must match its profile primary MCC")

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
