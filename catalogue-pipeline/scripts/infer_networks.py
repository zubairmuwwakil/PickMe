#!/usr/bin/env python3
"""
Infers cardId -> network for the Stage C promoter.

The network is NOT in the aggregator data. openCard carries four fields per card and cc-offers
has no network column; checking cc-offers' prose, notes and source URLs adds only 4 more across
242 rows over the card name alone. So there are exactly two evidence-based signals:

  name-token          the official name says it — "CIBC Costco Mastercard", "RBC British
                      Airways Visa Infinite". Strongest available, and measured: zero cards
                      carry two different network tokens, and zero disagree with the issuer rule.
  issuer-only-network Amex and Discover issue on their own networks, so the issuer settles it.

Every entry records which basis was used. A name token is strong evidence, NOT issuer
confirmation — fine for a `draft` card, which Scorer excludes before it ever reads the network,
and to be re-verified against the issuer before anything is promoted to published.

Cards with no signal are left out, so promote_drafts.py refuses them by name rather than
guessing. Guessing is what makes a card invisible to the wallets that actually accept it.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

PIPELINE = Path(__file__).resolve().parents[1]
QUEUE = PIPELINE / "card-research-queue.json"
OUT = PIPELINE / "card-networks.json"


def from_name(name: str) -> str | None:
    s = (name or "").lower()
    hits = []
    if re.search(r"\bvisa\b", s):
        hits.append("visa")
    # "World Elite" is a Mastercard tier and appears without the word Mastercard.
    if re.search(r"\bmastercard\b|\bworld elite\b", s):
        hits.append("mastercard")
    if re.search(r"\bamerican express\b|\bamex\b", s):
        hits.append("amex")
    if re.search(r"\bdiscover\b", s):
        hits.append("discover")
    hits = list(dict.fromkeys(hits))
    return hits[0] if len(hits) == 1 else None


def from_issuer(issuer: str) -> str | None:
    if re.match(r"^American Express", issuer or "", re.I):
        return "amex"
    if re.match(r"^Discover", issuer or "", re.I):
        return "discover"
    return None


def main() -> int:
    queue = json.loads(QUEUE.read_text())["queue"]
    out, conflicts, unresolved = {}, [], 0

    for e in queue:
        cid = e.get("cardId")
        if not cid or cid == "<batch>" or cid in out:
            continue
        by_name, by_issuer = from_name(e.get("officialName")), from_issuer(e.get("issuer"))

        # A disagreement is a fact, not something to resolve by precedence.
        if by_name and by_issuer and by_name != by_issuer:
            conflicts.append({"cardId": cid, "officialName": e.get("officialName"),
                              "byName": by_name, "byIssuer": by_issuer})
            continue

        if by_name:
            out[cid] = {"network": by_name, "basis": "name-token"}
        elif by_issuer:
            out[cid] = {"network": by_issuer, "basis": "issuer-only-network"}
        else:
            unresolved += 1

    OUT.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
    print(f"resolved {len(out)}, unresolved {unresolved}, conflicts {len(conflicts)}")
    print("  by basis  :", dict(Counter(v["basis"] for v in out.values())))
    print("  by network:", dict(Counter(v["network"] for v in out.values())))
    for c in conflicts:
        print("  CONFLICT:", c)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
