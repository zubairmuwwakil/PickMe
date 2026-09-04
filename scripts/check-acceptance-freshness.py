#!/usr/bin/env python3
"""
Fails when a merchant-pack row that withholds a card network has not been re-verified in a year.

WHY THIS EXISTS

contracts/schema/merchant-pack.schema.json requires `acceptanceProvenance` on any row narrower
than the open [amex, visa, mastercard] default, because removing a network is an affirmative
negative claim the app renders as text ("does not accept American Express") and which silently
withholds a card the owner may never discover they should have used. That gate is one-time: it
asks whether a source was cited when the row was written, and never asks again.

Acceptance moves without announcement, and it moves in the direction this repo is worst at
noticing. A merchant that STARTS taking Amex does not break anything a test can see — the row
keeps decoding, the pack keeps validating, the app keeps confidently telling the owner to leave
their best card in their pocket. There is no till event, no crash, and no failing assertion. The
only thing that changes is a sentence on a page nobody re-reads.

So the date is the alarm. This runs in document-freshness.yml (advisory), not ci.yml: a row
ageing past the bar is a prompt to go re-read a page, not a reason to block an unrelated merge.

  scripts/check-acceptance-freshness.py [--max-age-days N]
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "contracts" / "merchant-pack.json"

# A year. Acceptance is a slow fact — the Loblaw banners held the same position for years — so a
# shorter bar spends attention on rows that did not move. Long enough that a hit is worth acting
# on, short enough that a hit is still about the merchant a curator remembers researching.
DEFAULT_MAX_AGE_DAYS = 365


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-age-days", type=int, default=DEFAULT_MAX_AGE_DAYS)
    args = parser.parse_args()

    pack = json.loads(PACK.read_text())
    today = date.today()
    open_default = {"amex", "visa", "mastercard"}

    stale: list[tuple[int, str, str, str]] = []
    checked = 0
    ungated: list[str] = []

    for merchant in pack["merchants"]:
        if open_default.issubset(set(merchant["acceptedNetworks"])):
            continue
        provenance = merchant.get("acceptanceProvenance")
        if provenance is None:
            # The schema already forbids this; if it ever gets through, say so rather than
            # skipping the one kind of row this script exists to watch.
            ungated.append(merchant["id"])
            continue
        checked += 1
        verified = date.fromisoformat(provenance["lastVerifiedAt"])
        age = (today - verified).days
        if age > args.max_age_days:
            source = (provenance.get("sources") or ["(no source)"])[0]
            stale.append((age, merchant["id"], provenance["lastVerifiedAt"], source))

    for merchant_id in ungated:
        print(f"check-acceptance-freshness: {merchant_id} narrows acceptance with no "
              f"acceptanceProvenance — run scripts/validate-catalogue-schema.py", file=sys.stderr)

    if stale:
        print(f"check-acceptance-freshness: {len(stale)} row(s) withhold a network on evidence "
              f"older than {args.max_age_days} days.\n", file=sys.stderr)
        for age, merchant_id, verified, source in sorted(stale, reverse=True):
            print(f"  {merchant_id:26} last verified {verified} ({age} days ago)", file=sys.stderr)
            print(f"  {'':26} {source}", file=sys.stderr)
        print("\nRe-read each page. If the claim still holds, move lastVerifiedAt to today; if it "
              "no longer holds, widen acceptedNetworks — a merchant that started taking a network "
              "is the failure nothing else in this repo can see.", file=sys.stderr)
        return 1

    if ungated:
        return 1

    print(f"check-acceptance-freshness: {checked} narrowed row(s) verified within "
          f"{args.max_age_days} days")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
