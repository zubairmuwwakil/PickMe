#!/usr/bin/env python3
"""
Validates contracts/*.json against their contracts/schema/*.schema.json definitions.

WHY THIS EXISTS

Nothing else in this repo does this. programs.json shipped a schema violation for a full day
(fixed 2026-08-27, commit 929dbb1) because no script, no CI job, and no test ever ran a JSON
Schema validator over it — the schema files exist purely as documentation that Swift/Kotlin
decoders and the Python pipeline scripts read fields out of by hand (e.g. promote_drafts.py's
legal_program_ids()), never as a gate. This closes that hole for the files that carry it worst:
card-catalogue.schema.json's cardProduct now has a three-clause allOf/if/then invariant (network
privateLabel <-> acceptance present <-> scope closedLoop, added by commit 9fbbfb2) that is exactly
the kind of conditional logic that silently rots when nothing evaluates it.

Only the files that have a schema AND resolve with no cross-file $ref are checked here.
owner-state.json has no schema at all. programs.schema.json exists but $refs
card-catalogue.schema.json#/$defs/programId across files — resolving that needs a local
schema registry (a $id -> file map) so jsonschema does not try to fetch https://pickme.local/...
over the network. Left out of this pass; a natural follow-up once that registry exists.

  scripts/validate-catalogue-schema.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
CONTRACTS = ROOT / "contracts"
SCHEMA_DIR = CONTRACTS / "schema"

# (data file, schema file) pairs. Every pair here must both exist.
PAIRS = [
    ("card-catalogue.json", "card-catalogue.schema.json"),
    ("benefits-catalogue.json", "benefits-catalogue.schema.json"),
    ("candidate-catalogue.json", "candidate-catalogue.schema.json"),
    ("application-requirements.json", "application-requirements.schema.json"),
    ("application-requirements-fixtures.json", "application-requirements-fixtures.schema.json"),
    ("owner-conditions.json", "owner-conditions.schema.json"),
    ("purchase-categories.json", "purchase-categories.schema.json"),
    # engine-fixtures shipped a schema inside the release digest that nothing ever ran. It is
    # the only thing standing between a typo'd override key and a fixture that silently asserts
    # against the UNMODIFIED base owner state, because cardStateOverride is
    # additionalProperties:false.
    #
    # programs.json is NOT here yet: programs.schema.json $refs
    # card-catalogue.schema.json#/$defs/programId, and resolving a cross-file $ref needs a
    # jsonschema `referencing` registry this script does not build. That schema is also in the
    # digest and also unrun.
    ("engine-fixtures.json", "engine-fixtures.schema.json"),
    # Added 2026-09-01, when the pack stopped being generated FROM Swift and became the source
    # of truth Swift loads. `generate-merchant-pack.mjs --check` used to be its only gate, and it
    # only ever asserted "the JSON matches the Swift array" — a question that no longer exists.
    # The schema is now the thing keeping a hand-edited row honest.
    ("merchant-pack.json", "merchant-pack.schema.json"),
]


def format_path(error, instance=None) -> str:
    if not error.absolute_path:
        return "$"
    parts = []
    cursor = instance
    for step in error.absolute_path:
        # An array index tells a curator nothing. Every record in these files carries a stable
        # human key ("costco-wholesale", "amex-cobalt"), and the whole value of this script is
        # that the person who broke a rule can find the row they broke it in.
        label = str(step)
        if isinstance(step, int) and isinstance(cursor, list) and step < len(cursor):
            record = cursor[step]
            if isinstance(record, dict):
                for key in ("id", "cardId", "merchantId", "ruleId", "programId", "caseId"):
                    if isinstance(record.get(key), str):
                        label = f"{step}({record[key]})"
                        break
        parts.append(label)
        if cursor is not None:
            try:
                cursor = cursor[step]
            except (KeyError, IndexError, TypeError):
                cursor = None
    return "$." + ".".join(parts)


def validate_pair(data_name: str, schema_name: str) -> int:
    data_path = CONTRACTS / data_name
    schema_path = SCHEMA_DIR / schema_name

    schema = json.loads(schema_path.read_text())
    Draft202012Validator.check_schema(schema)

    instance = json.loads(data_path.read_text())
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: e.absolute_path)

    if not errors:
        print(f"OK    {data_name} against {schema_name}")
        return 0

    print(f"FAIL  {data_name} against {schema_name}: {len(errors)} error(s)")
    for error in errors:
        print(f"  {format_path(error, instance)}: {error.message}")
    return len(errors)


def main() -> int:
    total_errors = 0
    for data_name, schema_name in PAIRS:
        total_errors += validate_pair(data_name, schema_name)
    if total_errors:
        print(f"\nvalidate-catalogue-schema: {total_errors} schema violation(s)", file=sys.stderr)
        return 1
    print(f"\nvalidate-catalogue-schema: {len(PAIRS)} file(s) valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
