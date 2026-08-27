#!/usr/bin/env node
// Generates contracts/merchant-pack.json from CanadianMerchantPreIndex.swift
// plus scripts/merchant-pack-overrides.json.
//
//   node scripts/generate-merchant-pack.mjs           # write the pack
//   node scripts/generate-merchant-pack.mjs --check    # fail if it is stale
//
// WHY THIS EXISTS
//
// CanadianMerchantPreIndex is ~150 rows of "this brand is this category, and
// codes as this MCC" — editorial research, not observed network data, and the
// only table of its kind in the ecosystem. It was written for PickMe's
// autocomplete, but the hub needs exactly the same facts to categorize a
// payment descriptor, and hand-writing a second copy in TypeScript is the
// duplication this repo's decision log records twice (2026-08-19 duplicate
// rate engine, 2026-08-24 duplicate card corpus). A card defined twice always
// drifts; so does a merchant.
//
// So the Swift table stays the authoring surface and this script publishes it
// as a contract. The eventual direction is the reverse — Swift reads the JSON
// resource the way SeedLoader reads card-catalogue.json — but that flip needs
// a Swift toolchain to verify and is deliberately NOT done here; until then
// `--check` in CI is what keeps the published pack honest against its source.
//
// NOT part of card-contracts@N. The pack is versioned on its own (packVersion)
// and stays out of scripts/release-catalogue.sh's digest on purpose: merchant
// facts change on a completely different cadence from card rate facts, and
// folding them together would invalidate every consumer's catalogue pin every
// time somebody adds a coffee chain.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SWIFT = path.join(ROOT, "Store/Sources/CardCopilotStore/CanadianMerchantPreIndex.swift");
const OVERRIDES = path.join(ROOT, "scripts/merchant-pack-overrides.json");
const OUT = path.join(ROOT, "contracts/merchant-pack.json");

// Bump on any shape change. MAJOR is what a consumer refuses to load when it
// doesn't recognize it; MINOR moves when rows change.
const PACK_VERSION = "1.0";

/** Same normalization consumers apply to a merchant string before matching. */
function normalize(value) {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function slug(name) {
  return normalize(name).replace(/ /g, "-");
}

/**
 * Parses the `PreIndexedMerchant(...)` literals. Deliberately strict: a row it
 * cannot read is an error, never a silent omission — a pack that quietly drops
 * Costco is worse than one that fails to build.
 */
function parseSwift(source) {
  const body = source.slice(source.indexOf("public static let all:"));
  const rows = [];
  const re = /PreIndexedMerchant\(([\s\S]*?)\),\n/g;
  let match;
  while ((match = re.exec(body)) !== null) {
    const args = match[1];
    const str = (key) => {
      const m = args.match(new RegExp(`${key}:\\s*"((?:[^"\\\\]|\\\\.)*)"`));
      return m ? m[1].replace(/\\"/g, '"') : null;
    };
    const name = str("name");
    const category = str("category");
    if (!name || !category) throw new Error(`unparseable PreIndexedMerchant row: ${args.slice(0, 120)}`);
    const mccMatch = args.match(/mcc:\s*(\d+)/);
    const networksMatch = args.match(/acceptedNetworks:\s*\[([^\]]*)\]/);
    rows.push({
      id: slug(name),
      displayName: name,
      category,
      mcc: mccMatch ? Number(mccMatch[1]) : null,
      merchantBrand: str("merchantBrand"),
      acceptedNetworks: networksMatch
        ? networksMatch[1].split(",").map((n) => n.trim().replace(/^\./, "")).filter(Boolean).sort()
        : ["amex", "mastercard", "visa"],
      notes: str("notes"),
    });
  }
  if (rows.length === 0) throw new Error("parsed zero merchants — the Swift literal shape changed");
  return rows;
}

/**
 * Alternative names a display name already contains: "Couche-Tard / Circle K"
 * is two brands, "TTC (Toronto Transit Commission)" is a short form and a long
 * one. Splitting them here means the overrides file only carries needles that
 * genuinely cannot be derived.
 */
function derivedKeys(displayName) {
  const keys = new Set([normalize(displayName)]);
  for (const part of displayName.split("/")) keys.add(normalize(part));
  const paren = displayName.match(/^([^(]+)\(([^)]+)\)/);
  if (paren) {
    keys.add(normalize(paren[1]));
    keys.add(normalize(paren[2]));
  }
  return [...keys].filter((k) => k.length >= 3);
}

const rows = parseSwift(readFileSync(SWIFT, "utf8"));
const { overrides } = JSON.parse(readFileSync(OVERRIDES, "utf8"));

const byId = new Map(rows.map((r) => [r.id, r]));
const unknown = Object.keys(overrides).filter((id) => !byId.has(id));
if (unknown.length > 0) {
  // An override that matches nothing is a merchant that was renamed or removed
  // upstream. Failing here is the whole point: silently dropping it would take
  // its match keys out of the pack without anyone noticing.
  throw new Error(`overrides reference unknown merchant ids:\n  ${unknown.join("\n  ")}`);
}

const merchants = rows
  .map((row) => {
    const extra = overrides[row.id] ?? {};
    const matchKeys = [...new Set([...derivedKeys(row.displayName), ...(extra.matchKeys ?? []).map(normalize)])]
      // Longest first so a consumer scanning in order lets the most specific
      // needle win: "walmart supercentre" must beat "walmart".
      .sort((a, b) => b.length - a.length || a.localeCompare(b));
    const out = {
      id: row.id,
      displayName: row.displayName,
      category: row.category,
      matchKeys,
    };
    if (row.mcc != null) out.mcc = row.mcc;
    if (row.merchantBrand) out.merchantBrand = row.merchantBrand;
    if (extra.emailDomains) out.emailDomains = [...extra.emailDomains].sort();
    out.acceptedNetworks = row.acceptedNetworks;
    if (row.notes) out.notes = row.notes;
    return out;
  })
  .sort((a, b) => a.id.localeCompare(b.id));

const pack = {
  packVersion: PACK_VERSION,
  _provenance: {
    source: "Store/Sources/CardCopilotStore/CanadianMerchantPreIndex.swift",
    generator: "scripts/generate-merchant-pack.mjs",
    overrides: "scripts/merchant-pack-overrides.json",
    note: "Categories and MCCs are editorial research, not observed network data. A consumer must disclose an MCC it did not observe.",
  },
  merchants,
};

const serialized = JSON.stringify(pack, null, 2) + "\n";

if (process.argv.includes("--check")) {
  let current = "";
  try { current = readFileSync(OUT, "utf8"); } catch { /* missing counts as stale */ }
  if (current !== serialized) {
    console.error("generate-merchant-pack: contracts/merchant-pack.json is stale — re-run without --check");
    process.exit(1);
  }
  console.log(`generate-merchant-pack: current — ${merchants.length} merchants @ ${PACK_VERSION}`);
} else {
  writeFileSync(OUT, serialized);
  console.log(`generate-merchant-pack: wrote ${merchants.length} merchants @ ${PACK_VERSION}`);
}
