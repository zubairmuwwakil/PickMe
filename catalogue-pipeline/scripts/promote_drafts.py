#!/usr/bin/env python3
"""
Stage C: turn canonical discovery candidates into `status: draft` catalogue cards.

WHAT THIS IS FOR

Stage B discovered 329 canonical products and wrote a 339-entry research queue, but nothing
entered `contracts/card-catalogue.json` — the `status: draft` mechanism exists and is unused.
This is the step that uses it: it mints schema-valid catalogue entries carrying ONLY the facts
an aggregator actually gets right (identity and annual fee), marked `draft`, so the products
exist and are findable while nothing about them can reach a checkout pick.

WHAT IT REFUSES TO DO, AND WHY THAT IS THE POINT

An aggregator record has nine fields: source, sourceRecordId, officialName, issuer, market,
annualFee, sourceUrl, rewardsProse, welcomeOffer. The catalogue requires fourteen, two of which
the aggregators simply do not carry:

  network  - required, closed enum (amex|visa|mastercard|discover). Inferable from the issuer
             for Amex and Discover (71 of 466 US candidates) and for nobody else: Chase, Citi,
             Capital One and BofA each issue both Visa and Mastercard products.
  program  - required; programId is a closed enum. Which rewards currency a card earns is a
             per-card fact, not an issuer fact.

Both are cheap to research (one lookup each) and catastrophic to guess: a wrong `network` makes
Scorer exclude the card from wallets that would accept it, and a wrong `programId` values the
card in someone else's points. So this script REFUSES a card it cannot fill from an explicit
map, names it, and exits non-zero. Refusals are the queue for the next research pass, not errors.

It NEVER writes: earnRules (always []), sourceType issuerConfirmed, status published. It never
overwrites a card that is already published, and it never reassigns a cardId.

USAGE

  scripts/promote_drafts.py --market US --dry-run     # report what would land and what refuses
  scripts/promote_drafts.py --market US               # write the drafts
  scripts/promote_drafts.py --market US --limit 25    # a reviewable first batch

Then, as a separate human step: bump catalogueVersion, scripts/release-catalogue.sh,
scripts/publish-catalogue.sh, and sync-contracts.sh in MoneyTalks.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "catalogue-pipeline"
CATALOGUE = ROOT / "contracts" / "card-catalogue.json"
SCHEMA = ROOT / "contracts" / "schema" / "card-catalogue.schema.json"

QUEUE = PIPELINE / "card-research-queue.json"
ISSUER_ALIASES = PIPELINE / "issuer-aliases.json"
NETWORKS = PIPELINE / "card-networks.json"   # cardId -> amex|visa|mastercard|discover
PROGRAMS = PIPELINE / "card-programs.json"   # cardId -> {programId, unit}

# The snapshot date these candidates were discovered on. A draft's lastVerifiedAt records WHEN
# THE SNAPSHOT WAS TAKEN, never when a human read the issuer's terms — promotion to published
# overwrites it with the real verification date. Conflating the two forges the provenance the
# whole catalogue is built on.
SNAPSHOT_DATE = "2026-08-27"

MARKET_CURRENCY = {"US": "USD", "CA": "CAD"}


def load(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text())


def legal_program_ids() -> set[str]:
    """The closed enum, read from the schema rather than restated here so the two cannot drift."""
    schema = load(SCHEMA)
    return set(schema["$defs"]["programId"]["enum"])


def build_drafts(market: str, limit: int | None):
    queue = load(QUEUE)["queue"]
    catalogue = load(CATALOGUE)
    # Keyed by market on purpose: the vendor string "Capital One" appears in both markets and
    # Capital One Canada issues Canadian-only products. A flat map merges two issuers silently.
    aliases = ((load(ISSUER_ALIASES) or {}).get("aliases", {})).get(market, {})
    networks = load(NETWORKS) or {}
    programs = (load(PROGRAMS) or {}).get("programs", {})
    valid_program_ids = legal_program_ids()

    existing = {c["cardId"]: c for c in catalogue["cards"]}

    drafts, refusals = [], []

    def refuse(entry, reason, detail=""):
        refusals.append(
            {
                "cardId": entry.get("cardId"),
                "officialName": entry.get("officialName"),
                "issuer": entry.get("issuer"),
                "reason": reason,
                "detail": detail,
            }
        )

    for entry in queue:
        if entry.get("country") != market:
            continue

        card_id = entry.get("cardId")
        if not card_id:
            refuse(entry, "no-canonical-id", "queue entry carries no cardId")
            continue

        # A published card is issuer-verified. Never touch one from an aggregator feed.
        prior = existing.get(card_id)
        if prior is not None:
            if (prior.get("status") or "published") == "published":
                refuse(entry, "collides-with-published", "cardId already published; needs a human")
            else:
                refuse(entry, "already-draft", "already present as a draft")
            continue

        issuer_raw = entry.get("issuer")
        if issuer_raw not in aliases:
            refuse(
                entry,
                "unmapped-issuer",
                f"add {issuer_raw!r} to issuer-aliases.json under aliases.{market}",
            )
            continue

        # {"network": ..., "basis": ...} — basis records HOW the network was determined so the
        # promotion pass knows what still needs an issuer check. "name-token" means the official
        # name says it ("CIBC Costco Mastercard"); that is strong evidence but not issuer-
        # confirmed, which is fine for a draft and must be re-verified before publishing.
        entry_net = networks.get(card_id) or {}
        network = entry_net.get("network") if isinstance(entry_net, dict) else entry_net
        if network not in ("amex", "visa", "mastercard", "discover"):
            refuse(entry, "unknown-network", "add cardId -> network in card-networks.json")
            continue

        program = programs.get(card_id)
        if not program or program.get("programId") not in valid_program_ids:
            got = (program or {}).get("programId")
            refuse(
                entry,
                "unknown-program",
                f"add cardId -> program in card-programs.json"
                + (f"; {got!r} is not in the programId enum" if got else ""),
            )
            continue

        fee_candidates = [
            f for f in (entry.get("currentValue") or {}).get("annualFeeCandidates", []) if f is not None
        ]
        if not fee_candidates:
            refuse(entry, "no-annual-fee", "no source stated an annual fee")
            continue
        if len(set(fee_candidates)) > 1:
            # Two sources disagreeing is a fact worth keeping, not a coin to flip.
            refuse(entry, "conflicting-annual-fee", f"sources disagree: {sorted(set(fee_candidates))}")
            continue

        drafts.append(
            {
                "cardId": card_id,
                "officialName": entry["officialName"],
                "issuer": aliases[issuer_raw],
                "market": market,
                "billingCurrency": MARKET_CURRENCY[market],
                "status": "draft",
                "network": network,
                "kind": "credit",
                "fee": {"annual": {"amount": fee_candidates[0], "currency": MARKET_CURRENCY[market]}},
                # Built explicitly, never spread: card-programs.json carries provenance keys
                # (basis, officialName) and `program` is additionalProperties: false, so
                # passing the map entry through would emit a schema-invalid card.
                "program": {"programId": program["programId"], "unit": program["unit"]},
                "fxRules": [],
                # Deliberately empty. The schema sets no minItems, so this validates — and it is
                # the honest import: aggregators carry rewards as free prose, and a guessed rate
                # in a published-shaped record is exactly the drift the catalogue exists to stop.
                "earnRules": [],
                "caps": [],
                "perTransactionRewardVisibility": "unknown",
                "lastVerifiedAt": SNAPSHOT_DATE,
            }
        )
        if limit and len(drafts) >= limit:
            break

    return catalogue, drafts, refusals


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--market", required=True, choices=sorted(MARKET_CURRENCY))
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    catalogue, drafts, refusals = build_drafts(args.market, args.limit)

    print(f"drafts ready : {len(drafts)}")
    print(f"refused      : {len(refusals)}")
    for reason, n in Counter(r["reason"] for r in refusals).most_common():
        print(f"  {reason:<26} {n}")

    # Per market: a single shared file meant a CA run silently clobbered the US worklist.
    out = PIPELINE / f"promote-refusals-{args.market.lower()}.json"
    out.write_text(json.dumps(refusals, indent=2) + "\n")
    print(f"\nrefusals written to {out} — this is the research queue")

    if args.dry_run:
        print("\n--dry-run: catalogue untouched")
        return 0
    if not drafts:
        print("\nnothing to promote", file=sys.stderr)
        return 1

    catalogue["cards"].extend(drafts)
    catalogue["cards"].sort(key=lambda c: c["cardId"])
    CATALOGUE.write_text(json.dumps(catalogue, indent=2, ensure_ascii=False) + "\n")
    print(f"\nwrote {len(drafts)} drafts into {CATALOGUE}")
    print("NEXT (human): bump catalogueVersion, then release-catalogue.sh, publish-catalogue.sh,")
    print("              then sync-contracts.sh in MoneyTalks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
