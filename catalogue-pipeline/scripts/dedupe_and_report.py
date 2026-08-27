#!/usr/bin/env python3
"""
Deterministic deduplication across every discovery source, plus the two
next-agent artifacts (Phases 4/8/9 of the catalogue-expansion brief):

  card-research-queue.json   — what to verify next, and how, per card/field
  card-data-gaps.json        — what is missing, with severity

Sources read (all RAW, never mutated):
  contracts/card-catalogue.json                                  (41 published CA cards)
  catalogue-pipeline/raw/us/opencard/opencard-cards-*.json        (224 US cards, 4 fields each)
  catalogue-pipeline/raw/us/cc-offers/cc-offers-export-*.json     (242 US rows, prose rewards)
  catalogue-pipeline/raw/ca/clearfin/clearfin-extracted-sample-*.json (10 CA sample pages)
  catalogue-pipeline/raw/ca/clearfin/clearfin_slugs.txt           (127 CA URLs, discovery-only)

Matching is deliberately conservative: normalized (issuer, name-token-overlap) equality only.
A false NON-match (two records treated as different cards) costs a duplicate row a human can
merge later. A false match (two different cards silently merged) hides one of them — the worse
failure — so ambiguous cases are reported as "possible duplicate, needs a human", never merged
automatically.
"""
import glob
import json
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


def norm_issuer(issuer: str) -> str:
    issuer = issuer.lower()
    issuer = issuer.replace("bank of montreal", "bmo").replace("royal bank of canada", "rbc")
    issuer = issuer.replace("canadian imperial bank of commerce", "cibc")
    issuer = issuer.replace("scotiabank", "scotia").replace("td canada trust", "td")
    issuer = issuer.replace("td bank", "td").replace("american express", "amex")
    for suffix in [" canada", " financial services", " financial", " n.a.", ", n.a.", " bank"]:
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


def load_opencard():
    path = sorted(glob.glob(str(PIPELINE / "raw/us/opencard/opencard-cards-*.json")))[-1]
    data = load_json(Path(path))
    out = []
    for group in data:
        for c in group["cards"]:
            out.append(
                {
                    "recordId": c["card_id"],
                    "officialName": c["name"],
                    "issuer": c["issuer"],
                    "market": "US",
                    "annualFee": c.get("annual_fee"),
                    "sourceProvider": "openCard",
                }
            )
    return out


def load_cc_offers():
    path = sorted(glob.glob(str(PIPELINE / "raw/us/cc-offers/cc-offers-export-*.json")))[-1]
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


def load_clearfin_sample():
    files = sorted(glob.glob(str(PIPELINE / "raw/ca/clearfin/clearfin-extracted-sample-*.json")))
    if not files:
        return []
    data = load_json(Path(files[-1]))
    out = []
    for c in data:
        out.append(
            {
                "recordId": c["sourceRecordId"],
                "officialName": c["officialName"],
                "issuer": c["issuer"],
                "market": "CA",
                "annualFee": _parse_clearfin_fee(c["facts"].get("Annual fee")),
                "sourceProvider": "clearFin",
                "sourceUrl": c["sourceUrl"],
                "facts": c["facts"],
            }
        )
    return out


def _parse_clearfin_fee(raw):
    if not raw:
        return None
    digits = re.sub(r"[^0-9.]", "", raw)
    return float(digits) if digits else None


def load_clearfin_discovery_slugs():
    path = PIPELINE / "raw/ca/clearfin/clearfin_slugs.txt"
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
    record_issuer = norm_issuer(record["issuer"])
    record_tokens -= name_tokens(record["issuer"])
    best, best_score = None, 0.0
    for cand in candidates:
        if cand["market"] != record["market"]:
            continue
        cand_issuer = norm_issuer(cand["issuer"])
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
    opencard = load_opencard()
    cc_offers = load_cc_offers()
    clearfin = load_clearfin_sample()
    clearfin_slugs = load_clearfin_discovery_slugs()

    print(f"catalogue: {len(catalogue)}  openCard: {len(opencard)}  ccOffers: {len(cc_offers)}  "
          f"clearFin sample: {len(clearfin)}  clearFin discovery-only slugs: {len(clearfin_slugs)}",
          file=sys.stderr)

    # --- Dedup: match every non-catalogue record against the existing 41 catalogue cards ---
    dedup_report = {"matchedToExisting": [], "possibleDuplicates": [], "newCandidates": []}

    for record in opencard + cc_offers + clearfin:
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

    # Cross-source dedup among the new candidates themselves (openCard vs ccOffers, both US) —
    # so the research queue doesn't ask two different agents to source the same new card twice.
    new_candidates = dedup_report["newCandidates"]
    canonical_groups: list[dict] = []
    for cand in new_candidates:
        placed = False
        for group in canonical_groups:
            if norm_issuer(group["issuer"]) != norm_issuer(cand["issuer"]):
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

    build_gaps_and_queue(canonical_groups, clearfin, clearfin_slugs, dedup_report)


def _slug(issuer: str, name: str) -> str:
    # Many source names already carry the issuer's name (e.g. "American Express Gold Card"), so
    # only prefix it when the card name doesn't already start with it — otherwise every American
    # Express candidate id doubles it.
    base = name.lower() if name.lower().startswith(issuer.lower()) else f"{issuer}-{name}".lower()
    base = re.sub(r"[^a-z0-9]+", "-", base).strip("-")
    return base[:60]


def build_gaps_and_queue(canonical_groups, clearfin_sample, clearfin_slugs, dedup_report):
    gaps = []
    queue = []

    # 1. Every canonical new-candidate group (US, from openCard/ccOffers) — CRITICAL/HIGH gaps,
    #    since nothing about their earn structure is known at all yet.
    for group in canonical_groups:
        candidate_id = _slug(group["issuer"], group["officialName"])
        cc_source = next((s for s in group["sources"] if s["source"] == "ccOffers"), None)
        oc_source = next((s for s in group["sources"] if s["source"] == "openCard"), None)
        sources_checked = [s.get("sourceUrl") for s in group["sources"] if s.get("sourceUrl")]
        sources_checked = sources_checked or ["openCard aggregator (no per-card URL)"]

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

    # 2. ClearFin sample records not matched to the existing catalogue (issuers we have zero
    #    coverage for at all: Capital One, Neo Financial, Brim).
    matched_clearfin_ids = {
        m["sourceRecordId"] for m in dedup_report["matchedToExisting"] if m["source"] == "clearFin"
    }
    for c in clearfin_sample:
        if c["recordId"] in matched_clearfin_ids:
            continue
        candidate_id = _slug(c["issuer"], c["officialName"])
        facts = c["facts"]
        gaps.append({
            "cardId": candidate_id,
            "field": "earnRules",
            "status": "missing",
            "importance": "CRITICAL",
            "reason": f"Card is not in the catalogue. ClearFin lists reward type \"{facts.get('Reward type', facts.get('Card type', 'unknown'))}\" but no per-category rates or MCCs.",
            "sourcesChecked": [c["sourceUrl"]],
            "recommendedNextAction": f"Read {c['issuer']}'s own rewards terms and author earnRules with issuerConfirmed sourcing.",
        })
        queue.append({
            "cardId": candidate_id,
            "officialName": c["officialName"],
            "issuer": c["issuer"],
            "country": "CA",
            "missingField": "earnRules, caps, fxRules, credits — entire card",
            "currentValue": {
                "annualFee": c.get("annualFee"),
                "clearFinFacts": facts,
            },
            "sourceOfCurrentValue": "clearFin (comparisonSite, unverified)",
            "reasonItNeedsResearch": f"{c['issuer']} has zero cards in the catalogue today; this is the first.",
            "likelyAuthoritativeSource": c["sourceUrl"].replace("clearfin.ca/credit-cards/", "<issuer-domain>/") + " (find the issuer's own page)",
            "suggestedSearch": f"\"{c['officialName']}\" official rewards terms",
            "priority": "CRITICAL",
            "affectsCheckoutScoring": True,
            "affectsAcquisitionScoring": True,
            "affectsBenefitsDisplay": True,
        })

    # 3. Every ClearFin URL we have NOT yet fetched/extracted at all — pure discovery gap, LOW/
    #    MEDIUM severity (we don't even know what these cards charge yet).
    fetched_slugs = {c["recordId"] for c in clearfin_sample}
    unfetched = [s for s in clearfin_slugs if s not in fetched_slugs]
    if unfetched:
        gaps.append({
            "cardId": "<multiple — see recommendedNextAction>",
            "field": "entire record",
            "status": "missing",
            "importance": "MEDIUM",
            "reason": f"{len(unfetched)} ClearFin card pages were discovered (sitemap) but not yet fetched/extracted in this pass.",
            "sourcesChecked": ["https://www.clearfin.ca/sitemap.xml"],
            "recommendedNextAction": (
                "Run scripts/extract_clearfin.py against each remaining URL in "
                "raw/ca/clearfin/clearfin_slugs.txt, then re-run dedupe_and_report.py."
            ),
        })
        queue.append({
            "cardId": "<batch>",
            "officialName": f"{len(unfetched)} undiscovered ClearFin cards",
            "issuer": "various",
            "country": "CA",
            "missingField": "everything — not yet fetched",
            "currentValue": {"unfetchedSlugs": unfetched},
            "sourceOfCurrentValue": "clearFin sitemap (URL only, no content fetched)",
            "reasonItNeedsResearch": "Discovery-only; this session fetched a 10-card representative sample of 127 known URLs.",
            "likelyAuthoritativeSource": "https://www.clearfin.ca/credit-cards/<slug>, then the issuer's own page",
            "suggestedSearch": "n/a — URLs already known, just needs fetching",
            "priority": "MEDIUM",
            "affectsCheckoutScoring": False,
            "affectsAcquisitionScoring": False,
            "affectsBenefitsDisplay": False,
        })

    # 4. Possible duplicates — needs a human, not a script, to resolve.
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
    print(f"wrote {len(gaps)} gaps, {len(queue)} research-queue entries", file=sys.stderr)


def _fees_conflict(sources) -> bool:
    fees = {s.get("annualFee") for s in sources if s.get("annualFee") is not None}
    return len(fees) > 1


def _fee_reason(sources) -> str:
    fees = [(s["source"], s.get("annualFee")) for s in sources]
    return "Fee reported by source: " + ", ".join(f"{s}={f}" for s, f in fees)


if __name__ == "__main__":
    main()
