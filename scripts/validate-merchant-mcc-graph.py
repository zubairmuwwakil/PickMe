#!/usr/bin/env python3
"""Validate PickMe's merchant MCC graph seed invariants.

Uses only the Python standard library. The graph is intentionally sharded so the
500-merchant seed stays reviewable; manifest.json defines the shard set.
"""
from __future__ import annotations

import base64
import json
import math
import sys
import zlib
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


def load_runtime_seed(path: Path):
    try:
        encoded = "".join(path.read_text(encoding="utf-8").split())
        payload = zlib.decompress(base64.b64decode(encoded, validate=True))
        return json.loads(payload)
    except FileNotFoundError:
        fail(f"missing {path.relative_to(ROOT)}")
    except (ValueError, zlib.error, json.JSONDecodeError) as exc:
        fail(f"{path.relative_to(ROOT)} is not valid zlib+base64 JSON: {exc}")


def main() -> None:
    manifest = load_json(MANIFEST)
    files = manifest.get("files", {})
    categories = manifest.get("categories", {})
    profiles = load_json(GRAPH_DIR / files["profiles"])
    observations = load_json(GRAPH_DIR / files["observations"])

    shard_names = files.get("merchantShards", [])
    if len(shard_names) != 10:
        fail(f"expected 10 merchant shards, found {len(shard_names)}")

    merchants = []
    for shard_name in shard_names:
        shard = load_json(GRAPH_DIR / shard_name)
        if not isinstance(shard, list) or len(shard) != 50:
            fail(f"{shard_name} must contain exactly 50 merchants")
        merchants.extend(shard)

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

    runtime_name = files.get("runtimeSeed")
    if not runtime_name:
        fail("manifest files.runtimeSeed is required")
    runtime = load_runtime_seed(GRAPH_DIR / runtime_name)
    if runtime.get("graphVersion") != manifest.get("graphVersion"):
        fail("runtime seed graphVersion does not match manifest")
    runtime_merchants = runtime.get("merchants")
    if not isinstance(runtime_merchants, list) or len(runtime_merchants) != 500:
        fail("runtime seed must contain exactly 500 merchants")
    if [m.get("id") for m in runtime_merchants] != ids:
        fail("runtime seed merchant ids/order do not match canonical shards")
    if [m.get("name", "").casefold() for m in runtime_merchants] != names:
        fail("runtime seed merchant names/order do not match canonical shards")

    for merchant in runtime_merchants:
        mccs = merchant.get("candidateMccs", [])
        weights = merchant.get("weights", [])
        seed_mcc = merchant.get("seedMcc")
        confidence = merchant.get("confidence")
        if len(mccs) != len(weights):
            fail(f"runtime {merchant['id']} candidateMccs/weights length mismatch")
        if len(mccs) != len(set(mccs)):
            fail(f"runtime {merchant['id']} repeats an MCC")
        if seed_mcc is not None and seed_mcc not in mccs:
            fail(f"runtime {merchant['id']} seedMcc is not a candidate")
        if any(weight < 0 for weight in weights):
            fail(f"runtime {merchant['id']} has a negative prior weight")
        if weights and not math.isclose(sum(weights), 1.0, abs_tol=1e-6):
            fail(f"runtime {merchant['id']} weights must sum to 1.0")
        if not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
            fail(f"runtime {merchant['id']} confidence must be in [0,1]")

    print(
        f"merchant MCC graph OK: {len(merchants)} merchants, "
        f"{len(profiles)} prior profiles, {len(observations)} location observations, "
        f"{len(runtime_merchants)} runtime seeds"
    )


if __name__ == "__main__":
    main()
