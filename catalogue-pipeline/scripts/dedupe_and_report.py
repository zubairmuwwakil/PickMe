#!/usr/bin/env python3
"""
Deterministic deduplication across every discovery source, plus the two
next-agent artifacts (Phases 4/8/9 of the catalogue-expansion brief):

  card-research-queue.json   — what to verify next, and how, per card/field
  card-data-gaps.json        — what is missing, with severity

Sources read (all RAW, never mutated):
  contracts/card-catalogue.json                                  (41 published CA cards)
  catalogue-pipeline/.raw-cache/cc-offers-us-2026-08-27/cc-offers-export-2026-08-27.json
                                                               (242 US rows, prose rewards)
  catalogue-pipeline/locators/clearfin_slugs.txt                (127 CA URLs, discovery-only)

OpenCard snapshots and ClearFin page/extraction copies are deliberately NOT inputs. Their
2026-08-27 licence review found no redistribution permission, so they were removed from the
public tree. See RAW_SOURCE_POLICY.md and raw/MANIFEST.json. Fetch the cleared cc-offers
snapshot by its manifest hash before running this script. ClearFin slugs are locator metadata only;
agents must go from a slug/card name to the issuer's own site, never fetch ClearFin for facts.

Matching is deliberately conservative: normalized (issuer, name-token-overlap) equality only.
A false NON-match (two records treated as different cards) costs a duplicate row a human can
merge later. A false match (two different cards silently merged) hides one of them — the worse
failure — so ambiguous cases are reported as "possible duplicate, needs a human", never merged
automatically.
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # PickMe/
PIPELINE = ROOT / "catalogue-pipeline"

STOPWORDS = {
    "card", "credit", "mastercard", "visa", "the", "from", "american", "express",
    "world", "elite", "infinite", "visa*", "no", "fee",
}

NAME_NORMALIZE_RE = re.compile(r"[^a-z0-9 ]+")


def _load_aliases() -> dict:
    path = PIPELINE / "issuer-aliases.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("aliases", {})


ISSUER_ALIASES = _load_aliases()


def canonical_issuer(issuer: str, market: str | None) -> str:
    """The reviewed canonical issuer name, or the raw string when this one is not mapped.

    Market-keyed on purpose: the vendor string "Capital One" appears in both markets and
    Capital One Canada issues Canadian-only products. Falls back to any market only when the
    caller has no market to offer (the published catalogue's own issuer strings), because a
    cross-market fallback is exactly the conflation the keying exists to prevent.
    """
    if market and issuer in ISSUER_ALIASES.get(market, {}):
        return ISSUER_ALIASES[market][issuer]
    if market is None:
        for table in ISSUER_ALIASES.values():
            if issuer in table:
                return table[issuer]
    return issuer


def norm_issuer(issuer: str, market: str | None = None) -> str:
    """Comparison key for issuer equality.

    Resolves through issuer-aliases.json FIRST. Before that existed this was an ad-hoc replace
    list, and it is what let one product reach two canonical ids: "American Express National
    Bank" normalized to "amex national" while "American Express" normalized to "amex", so the
    cross-source merge gated on issuer equality and never fired. Eight duplicate pairs reached
    the draft set that way (Amex Gold, Green, Platinum, Business Gold, Business Platinum; Citi
    Secured; two U.S. Bank cards) and ~10% of the US canonical count was duplicate rows.

    The heuristic below is KEPT as a fallback, because the published catalogue's own issuer
    strings ("TD Canada Trust", "American Express Canada") are not in the alias map — that map
    covers vendor strings.
    """
    issuer = canonical_issuer(issuer, market).lower()
    issuer = issuer.replace("bank of montreal", "bmo").replace("royal bank of canada", "rbc")
    issuer = issuer.replace("canadian imperial bank of commerce", "cibc")
    issuer = issuer.replace("scotiabank", "scotia").replace("td canada trust", "td")
    issuer = issuer.replace("american express", "amex")
    for suffix in [" canada", " financial services", " financial", " n.a.", ", n.a.", " bank",
                   " national association", " national", " usa"]:
        issuer = issuer.replace(suffix, "")
    return issuer.strip()


def name_tokens(name: str) -> set[str]:
    name = NAME_NORMALIZE_RE.sub(" ", name.lower())
    return {t for t in name.split() if t and t not in STOPWORDS}


def token_overlap(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / max(len(a), len(b))


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_catalogue_cards():
    data = load_json(ROOT / "contracts" / "card-catalogue.json")
    return [
        {
            "recordId": c["cardId"],
            "officialName": c["officialName"],
            "issuer": c["issuer"],
            "market": c.get("market", "CA"),
            "annualFee": (c.get("fee", {}).get("annual") or {}).get("amount"),
            "sourceProvider": "catalogue",
        }
        for c in data["cards"]
    ]


def load_cc_offers():
    manifest = json.loads((PIPELINE / "raw/MANIFEST.json").read_text())
    snapshots = [s for s in manifest["snapshots"] if s["sourceId"] == "cc-offers"]
    if len(snapshots) != 1:
        raise RuntimeError(f"Expected one cc-offers snapshot in raw/MANIFEST.json, found {len(snapshots)}")
    snapshot = snapshots[0]
    cache = Path(os.environ.get("PICKME_RAW_CACHE", PIPELINE / ".raw-cache"))
    path = cache / snapshot["snapshotId"] / snapshot["filename"]
    if not path.is_file():
        raise RuntimeError(
            f"cc-offers snapshot is not materialized at {path}. Run "
            f"scripts/fetch-raw-snapshot.sh {snapshot['sha256']} first."
        )
    data = load_json(Path(path))
    out = []
    for r in data["rows"]:
        out.append(
            {
                "recordId": f"cc-offers-{r['id']}",
                "officialName": r["card_offer"],
                "issuer": r["issuer"],
                "market": "US",
                "annualFee": r.get("base_annual_fee_usd"),
                "sourceProvider": "ccOffers",
                "sourceUrl": r.get("source_url"),
                "rewardsProse": r.get("rewards_key_perks"),
                "welcomeOffer": r.get("welcome_intro_offer"),
                "retrievedAt": r.get("retrieved"),
            }
        )
    return out


def load_clearfin_discovery_slugs():
    path = PIPELINE / "locators/clearfin_slugs.txt"
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def best_match(record, candidates):
    """Returns (best_candidate, score) among same-market candidates, or (None, 0).

    Issuer-name tokens are stripped from BOTH sides before scoring name overlap. Without this,
    two short, otherwise-unrelated names from the same issuer (e.g. "CIBC Costco Mastercard" vs
    "CIBC Dividend Visa Infinite Card") share only the issuer's own name as a token and can clear
    the threshold on that alone — the issuer match is already a separate, required gate below, so
    letting it also inflate the name-similarity score double-counts one signal as two.
    """
    record_tokens = name_tokens(record["officialName"])
    record_issuer = norm_issuer(record["issuer"], record.get("market"))
    record_tokens -= name_tokens(record["issuer"])
    best, best_score = None, 0.0
    for cand in candidates:
        if cand["market"] != record["market"]:
            continue
        cand_issuer = norm_issuer(cand["issuer"], cand.get("market"))
        issuer_match = cand_issuer == record_issuer or cand_issuer in record_issuer or record_issuer in cand_issuer
        if not issuer_match:
            continue
        cand_tokens = name_tokens(cand["officialName"]) - name_tokens(cand["issuer"])
        score = token_overlap(record_tokens, cand_tokens)
        if score > best_score:
            best, best_score = cand, score
    return best, best_score


MATCH_THRESHOLD = 0.6  # majority of the smaller (issuer-stripped) token set must overlap


def main():
    catalogue = load_catalogue_cards()
    cc_offers = load_cc_offers()
    clearfin_slugs = load_clearfin_discovery_slugs()

    print(f"catalogue: {len(catalogue)}  ccOffers: {len(cc_offers)}  "
          f"clearFin discovery-only slugs: {len(clearfin_slugs)}",
          file=sys.stderr)

    # --- Dedup: match every non-catalogue record against the existing 41 catalogue cards ---
    dedup_report = {"matchedToExisting": [], "possibleDuplicates": [], "newCandidates": []}

    for record in cc_offers:
        match, score = best_match(record, catalogue)
        if score >= MATCH_THRESHOLD:
            dedup_report["matchedToExisting"].append(
                {
                    "source": record["sourceProvider"],
                    "sourceRecordId": record["recordId"],
                    "sourceName": record["officialName"],
                    "matchedCardId": match["recordId"],
                    "matchedName": match["officialName"],
                    "tokenOverlap": round(score, 2),
                    "feeAgrees": (
                        record["annualFee"] is not None
                        and match["annualFee"] is not None
                        and abs(record["annualFee"] - match["annualFee"]) < 1
                    ),
                }
            )
        elif score > 0.2:
            dedup_report["possibleDuplicates"].append(
                {
                    "source": record["sourceProvider"],
                    "sourceRecordId": record["recordId"],
                    "sourceName": record["officialName"],
                    "closestCardId": match["recordId"] if match else None,
                    "closestName": match["officialName"] if match else None,
                    "tokenOverlap": round(score, 2),
                    "reason": "below match threshold — needs a human to confirm same-vs-different product",
                }
            )
        else:
            dedup_report["newCandidates"].append(
                {
                    "source": record["sourceProvider"],
                    "sourceRecordId": record["recordId"],
                    "officialName": record["officialName"],
                    "issuer": record["issuer"],
                    "market": record["market"],
                    "annualFee": record.get("annualFee"),
                    "sourceUrl": record.get("sourceUrl"),
                    "rewardsProse": record.get("rewardsProse"),
                    "welcomeOffer": record.get("welcomeOffer"),
                }
            )

    # Dedup among new candidates themselves so repeated source rows do not ask two different
    # agents to source the same card twice.
    new_candidates = dedup_report["newCandidates"]
    canonical_groups: list[dict] = []
    for cand in new_candidates:
        placed = False
        for group in canonical_groups:
            # Market must match before issuer: with issuers now resolved through the alias
            # map, a US "TD Bank" and a CA "TD Canada Trust" both reduce to "td", and only the
            # market keeps them apart. best_match already gates this way; this loop did not.
            if group["market"] != cand["market"]:
                continue
            if norm_issuer(group["issuer"], group["market"]) != norm_issuer(cand["issuer"], cand["market"]):
                continue
            group_tokens = name_tokens(group["officialName"]) - name_tokens(group["issuer"])
            cand_tokens = name_tokens(cand["officialName"]) - name_tokens(cand["issuer"])
            if token_overlap(group_tokens, cand_tokens) >= MATCH_THRESHOLD:
                group["sources"].append(cand)
                placed = True
                break
        if not placed:
            canonical_groups.append({
                "officialName": cand["officialName"],
                "issuer": cand["issuer"],
                "market": cand["market"],
                "sources": [cand],
            })

    print(f"matched to existing catalogue: {len(dedup_report['matchedToExisting'])}", file=sys.stderr)
    print(f"possible duplicates (needs human): {len(dedup_report['possibleDuplicates'])}", file=sys.stderr)
    print(f"new candidates (raw records): {len(new_candidates)} -> {len(canonical_groups)} canonical groups after cross-source merge",
          file=sys.stderr)

    (PIPELINE / "dedup-report.json").write_text(json.dumps(dedup_report, indent=2, ensure_ascii=False), encoding="utf-8")

    build_gaps_and_queue(canonical_groups, clearfin_slugs, dedup_report)


MAX_ID_LEN = 45   # published cardIds run 11-37 chars; stay inside that range
TRAILING_FILLER = {"from", "the", "for", "and", "a", "of", "with", "american", "credit"}
IDMAP_PATH = PIPELINE / "idmap.json"


def _load_idmap() -> dict:
    if not IDMAP_PATH.exists():
        return {}
    return json.loads(IDMAP_PATH.read_text(encoding="utf-8")).get("map", {})


ID_MAP = _load_idmap()          # "source|sourceRecordId" -> cardId, append-only
_MINTED: dict[str, str] = {}    # ids minted this run, for collision detection


def _slug(issuer: str, name: str, market: str | None = None) -> str:
    """A stable, readable cardId.

    Two rules learned the hard way, both from ids that would have been PERMANENT:

    1. The issuer is resolved through the alias map first. Slugging the raw vendor string gave
       one product two ids — `american-express-gold-card` from one source and
       `american-express-national-bank-american-express-gold-card` from another.
    2. Trim on a word boundary, never mid-word. The old 60-character hard cut produced
       `american-express-national-bank-the-platinum-card-from-americ` and
       `alliant-credit-union-alliant-cashback-visa-signature-credit-`.
    """
    issuer = canonical_issuer(issuer, market)
    # Sources write the same issuer long or short ("Amex Cash Magnet" vs "American Express
    # Gold Card"); expanding first keeps the prefix test from doubling the issuer into the id.
    name_cmp = re.sub(r"^amex\b", "american express", name.strip(), flags=re.I)
    base = name_cmp if name_cmp.lower().startswith(issuer.lower()) else f"{issuer} {name_cmp}"
    base = re.sub(r"[^a-z0-9]+", "-", base.lower()).strip("-")

    if len(base) > MAX_ID_LEN:
        kept: list[str] = []
        for word in base.split("-"):
            if kept and len("-".join(kept + [word])) > MAX_ID_LEN:
                break
            kept.append(word)
        # Trimming mid-phrase leaves a dangling connective ("...-the-platinum-card-from").
        # These ids are permanent, so drop trailing filler rather than live with it.
        while len(kept) > 1 and kept[-1] in TRAILING_FILLER:
            kept.pop()
        base = "-".join(kept) or base[:MAX_ID_LEN].rstrip("-")
    return base


def mint_id(issuer: str, name: str, market: str | None, source_keys: list[str]) -> str:
    """Resolve a group's cardId, reusing any id its source records already carry.

    cardIds are permanent — prediction rows, owner state, MoneyTalks and Android all key on
    them. So a record that has been seen before keeps its id even if the vendor renames the
    product, and only genuinely new records mint. Collisions get a numeric suffix rather than
    silently merging two products onto one id.
    """
    for key in source_keys:
        if key in ID_MAP:
            found = ID_MAP[key]
            for k in source_keys:
                ID_MAP.setdefault(k, found)
            return found

    base = _slug(issuer, name, market)
    candidate, n = base, 1
    while _MINTED.get(candidate, name) != name:
        n += 1
        candidate = f"{base}-{n}"
    _MINTED[candidate] = name
    for key in source_keys:
        ID_MAP[key] = candidate
    return candidate


def write_idmap() -> None:
    IDMAP_PATH.write_text(
        json.dumps(
            {
                "_note": "APPEND-ONLY. 'source|sourceRecordId' -> cardId. cardIds are permanent: "
                         "prediction rows, owner state, MoneyTalks and the Android consumer key on "
                         "them, and check-id-permanence.sh fails when a published id vanishes. Never "
                         "edit or delete an entry — a vendor renaming a product must resolve to the "
                         "id it already has, not mint a new one.",
                "map": dict(sorted(ID_MAP.items())),
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


def build_gaps_and_queue(canonical_groups, clearfin_slugs, dedup_report):
    gaps = []
    queue = []

    # 1. Every canonical new-candidate group (US, from cc-offers) — CRITICAL/HIGH gaps,
    #    since nothing about their earn structure is known at all yet.
    for group in canonical_groups:
        candidate_id = mint_id(
            group["issuer"], group["officialName"], group["market"],
            [f"{s['source']}|{s['sourceRecordId']}" for s in group["sources"]],
        )
        cc_source = next((s for s in group["sources"] if s["source"] == "ccOffers"), None)
        sources_checked = [s.get("sourceUrl") for s in group["sources"] if s.get("sourceUrl")]
        sources_checked = sources_checked or ["cc-offers aggregator (no per-card URL)"]

        gaps.append({
            "cardId": candidate_id,
            "field": "earnRules",
            "status": "missing",
            "importance": "CRITICAL",
            "reason": (
                "Card is not in the catalogue at all. "
                + (f"cc-offers has prose rewards: {cc_source['rewardsProse']!r}. " if cc_source and cc_source.get("rewardsProse") else "")
                + "No structured MCC/category/cap data exists yet for any source."
            ),
            "sourcesChecked": sources_checked,
            "recommendedNextAction": f"Read the issuer's own rewards terms for \"{group['officialName']}\" and author earnRules with issuerConfirmed sourcing.",
        })
        gaps.append({
            "cardId": candidate_id,
            "field": "fee.annual",
            "status": "conflicting" if _fees_conflict(group["sources"]) else "unverified",
            "importance": "HIGH",
            "reason": _fee_reason(group["sources"]),
            "sourcesChecked": sources_checked,
            "recommendedNextAction": "Confirm current annual fee on the issuer's own product page (fees change more often than aggregators update).",
        })

        queue.append({
            "cardId": candidate_id,
            "officialName": group["officialName"],
            "issuer": group["issuer"],
            "country": group["market"],
            "missingField": "earnRules, caps, fxRules, credits — entire card",
            "currentValue": {
                "annualFeeCandidates": [s.get("annualFee") for s in group["sources"]],
                "rewardsProse": cc_source["rewardsProse"] if cc_source else None,
                "welcomeOffer": cc_source["welcomeOffer"] if cc_source else None,
            },
            "sourceOfCurrentValue": [s["source"] for s in group["sources"]],
            "reasonItNeedsResearch": "Discovered via aggregator only; zero issuer-verified fields.",
            "likelyAuthoritativeSource": sources_checked[0],
            "suggestedSearch": f"\"{group['officialName']}\" {group['issuer']} rewards terms and conditions",
            "priority": "CRITICAL",
            "affectsCheckoutScoring": True,
            "affectsAcquisitionScoring": True,
            "affectsBenefitsDisplay": True,
        })

    # 2. ClearFin URL locators are retained as discovery leads only. The site's pages and
    #    extracted copies are licence-blocked, so agents go directly from a slug/card name to
    #    issuer material. No ClearFin content is fetched or treated as a fact source.
    if clearfin_slugs:
        gaps.append({
            "cardId": "<multiple — see recommendedNextAction>",
            "field": "entire record",
            "status": "missing",
            "importance": "MEDIUM",
            "reason": (
                f"{len(clearfin_slugs)} card URL slugs were discovered in ClearFin's sitemap. "
                "ClearFin page content is licence-blocked and was not fetched or extracted."
            ),
            "sourcesChecked": ["https://www.clearfin.ca/sitemap.xml"],
            "recommendedNextAction": (
                "Use each slug only as a candidate-name lead; locate the issuer's own product "
                "page and terms, and do not fetch or copy the ClearFin page."
            ),
        })
        queue.append({
            "cardId": "<batch>",
            "officialName": f"{len(clearfin_slugs)} ClearFin sitemap locator leads",
            "issuer": "various",
            "country": "CA",
            "missingField": "everything — locator metadata only",
            "currentValue": {"locatorSlugs": clearfin_slugs},
            "sourceOfCurrentValue": "ClearFin sitemap URL locator only; no page content retained",
            "reasonItNeedsResearch": (
                "Discovery-only. ClearFin has no located redistribution licence, so its pages "
                "must not be fetched into or copied within this public pipeline."
            ),
            "likelyAuthoritativeSource": "Each issuer's own product page and terms",
            "suggestedSearch": "<slug/card name> Canada official issuer credit card terms",
            "priority": "MEDIUM",
            "affectsCheckoutScoring": False,
            "affectsAcquisitionScoring": False,
            "affectsBenefitsDisplay": False,
        })

    # 3. Possible duplicates — needs a human, not a script, to resolve.
    for pd in dedup_report["possibleDuplicates"]:
        gaps.append({
            "cardId": pd["closestCardId"] or "<unresolved>",
            "field": "identity (possible duplicate)",
            "status": "conflicting",
            "importance": "MEDIUM",
            "reason": (
                f"{pd['source']} record \"{pd['sourceName']}\" ({pd['sourceRecordId']}) is a "
                f"{pd['tokenOverlap']:.0%} name-token match to existing card \"{pd['closestName']}\" "
                "— below the auto-merge threshold, so NOT merged. Could be the same product "
                "under a different name, or a genuinely different tier."
            ),
            "sourcesChecked": [],
            "recommendedNextAction": "A human compares the two names/issuers and either records an alias or confirms they are distinct products.",
        })

    (PIPELINE / "card-data-gaps.json").write_text(
        json.dumps({"generatedAt": "2026-08-27", "gapCount": len(gaps), "gaps": gaps}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (PIPELINE / "card-research-queue.json").write_text(
        json.dumps({"generatedAt": "2026-08-27", "queueLength": len(queue), "queue": queue}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    write_idmap()
    print(f"wrote {len(gaps)} gaps, {len(queue)} research-queue entries, "
          f"{len(ID_MAP)} idmap entries", file=sys.stderr)


def _fees_conflict(sources) -> bool:
    fees = {s.get("annualFee") for s in sources if s.get("annualFee") is not None}
    return len(fees) > 1


def _fee_reason(sources) -> str:
    fees = [(s["source"], s.get("annualFee")) for s in sources]
    return "Fee reported by source: " + ", ".join(f"{s}={f}" for s, f in fees)


if __name__ == "__main__":
    main()
