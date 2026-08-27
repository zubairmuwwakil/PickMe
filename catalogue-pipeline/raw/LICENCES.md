# Raw-source licence review

Status as reviewed **2026-08-27**. This is an engineering risk record, not legal
advice. It records only permissions that were actually found; public access,
`robots.txt` permission, and attribution are not treated as substitutes for a
licence.

## Stop gate

**Do not fetch the remaining 117 ClearFin pages.** No ClearFin terms or licence
authorizing reproduction or redistribution were found. The ten verbatim HTML
pages and their extracted sample were removed from the current tree after this
review. Re-source needed facts from issuers; do not restore the copies unless
ClearFin first grants written permission.

The OpenCard snapshot also had no located redistribution licence and was removed
from the current tree. Keep it out of new public distributions and app bundles
unless OpenCard grants permission or the needed facts are independently
re-sourced.

## Summary

| Source and local material | Licence / permission found | May the raw material be redistributed? | Must attribution travel with it? | Public-repository assessment | Required disposition |
|---|---|---|---|---|---|
| `us/cc-offers/cc-offers-export-2026-08-27.json` | MIT, copyright 2026 Sunny Golovine | **Yes, subject to the MIT notice.** This conclusion covers the upstream project's material; it cannot license third-party issuer expression embedded in a row. | **Yes.** The copyright and permission notice must accompany copies or substantial portions. | Permitted if the notice below travels with every substantial copy. | Keep; attach this notice to standalone exports, release assets, and any app distribution containing a substantial copy. Continue to treat issuer URLs as research leads, not issuer confirmation. |
| Historical `us/opencard/opencard-cards-2026-08-27.json` (removed from current tree) | **No copyright/data licence found.** API docs permit AI agents, personal tools, and research, say normal use is free, and say “Not for commercial scraping.” Site terms grant no redistribution right. The public GitHub repo has no `LICENSE` file or detected licence. | **Unclear; do not assume permission.** API access permission is not a grant to republish a frozen database snapshot. | No attribution condition was found, but attribution would not cure the missing permission. | **Not cleared.** A public raw snapshot, release source archive, or bundled app copy goes beyond the clearly stated research/personal-tool use. | Removed from the current tree. Ask OpenCard for a written data licence or re-source from issuer pages. Historical Git/tag remediation remains an owner/legal decision. |
| Historical `ca/clearfin/pages/*.html` and `clearfin-extracted-sample-2026-08-27.json` (removed), plus retained `clearfin_slugs.txt` | **No reuse licence or Terms of Service found.** ClearFin publishes a privacy statement and disclosures, marks the site © 2026 ClearFin Digital Inc., and exposes `robots.txt` with `Allow: /`. | **No permission established.** `robots.txt` permits crawling by robots; it does not license copying or publication. | No attribution condition was found, but attribution would not cure the missing permission. | **Verbatim HTML: not supported by any located terms and not cleared for a public repo.** Extracted wording/selection is also unclear. A bare URL list is lower risk, but it is only locator metadata and grants no rights in page content. | Pages and extraction removed from the current tree; the 127 URL/slugs remain as locator-only leads. Do not fetch the pages. Re-source facts from issuers. Historical Git/tag remediation remains an owner/legal decision. |

## Distribution exposure actually verified

The repository state was checked rather than assuming that every file under the
release tag becomes a release asset or app resource.

- The raw files are committed in `card-contracts@2.2`, `card-contracts@2.3`, and
  `card-contracts@2.4`. They therefore appear in GitHub's automatically generated
  **Source code** `.zip` and `.tar.gz` archives for those tags.
- Those three tagged source archives predate this file. Their copies of the
  cc-offers export therefore do **not** carry the full MIT copyright and
  permission notice required for a substantial copy. The snapshot's
  `_provenance.license: "MIT"` label alone is not the required notice.
- The raw files are **not** attached assets of either release. The attached
  assets are the contract JSON/schema files plus `RELEASE.json`.
- The current iOS/SwiftPM build processes
  `Engine/Sources/CardCopilotEngine/Resources`; neither the Xcode project nor
  `Engine/Package.swift` references `catalogue-pipeline/raw`. The raw snapshots
  are therefore **not shown to be vendored into the iOS app bundle** by the
  current tree. The derived card catalogue is bundled.
- This distinction does not clear the data. The public repository and tagged
  source archives are already redistribution, and a derived catalogue may still
  need an upstream notice or independently sourced facts.

Deleting files in a later commit would stop them from appearing at the current
tip, but would not remove them from `card-contracts@2.2`, `card-contracts@2.3`,
`card-contracts@2.4`, their source archives, or earlier Git history. Do not
delete/recreate a published contract release under the same release id: the
repository's immutability rule still applies. Historical remediation is an
explicit owner/legal decision.

## Source-by-source findings

### cc-offers (`sgolovine/cc-offers`)

Reviewed sources:

- [upstream repository and dataset description](https://github.com/sgolovine/cc-offers)
- [MIT licence at the reviewed upstream commit](https://github.com/sgolovine/cc-offers/blob/c125704e93cc78bab9cbd012f2e5eff01a67b125/LICENSE)

The README calls this an open dataset, provides raw SQLite/CSV/XLSX/seed data,
and says others may inspect, reuse, and build on it. The repository-wide MIT
licence permits use, copying, modification, publication, and distribution, but
requires the notice below in copies or substantial portions.

The local JSON is a 242-row export and therefore a substantial copy. Keeping
this `LICENCES.md` beside it satisfies the notice path for the repository and
tagged source archives. It does **not** automatically satisfy a standalone JSON
download, a release asset containing only the JSON, or an app bundle. Those
distributions must carry the same notice in a third-party-notices file or an
equivalent bundled location.

The export also contains per-row source URLs, evidence, and `raw_json`. MIT can
license Sunny Golovine's selection, schema, and authored material; it cannot
grant rights that belong to banks or other third-party sources. Avoid carrying
substantial verbatim third-party page text forward, and independently verify all
published card rules against issuer pages under D3.

### OpenCard AI

Reviewed sources:

- [API documentation at the reviewed upstream commit](https://github.com/opencard-ai/opencard/blob/ebdddf73d2842bdefe24a022db4a764693c5adb6/docs/API.md)
- [OpenCard Terms of Service](https://opencardai.com/en/terms) — last updated
  2026-04-15
- [OpenCard methodology](https://opencardai.com/en/methodology)
- [public repository](https://github.com/opencard-ai/opencard) — no `LICENSE`
  file or detected repository licence when checked

The API documentation is an invitation to call the public API and expressly
names AI agents, personal tools, and research as use cases. It also says not to
use it for commercial scraping. Neither that document nor the site Terms grants
a licence to reproduce, modify, sublicense, or publicly redistribute the
database or a snapshot of it. Calling the site or repository “open” is not a
substitute for licence terms.

Accordingly, internal discovery use may fit the stated research use, but the
historical public raw snapshot was not cleared and has been removed from the
current tree. The conservative paths are:

1. Obtain written permission from `support@opencardai.com` or the API contact,
   specifically covering a public Git repository, GitHub source archives,
   transformed contract data, and an iOS app; or
2. Use OpenCard only to discover candidate names, then re-source every retained
   fact from an issuer and remove the OpenCard snapshot from public
   distribution.

Attribution is still good provenance, but there is no found attribution clause
that turns redistribution into a permitted use.

### ClearFin

Reviewed sources:

- [site disclosures](https://www.clearfin.ca/disclosures)
- [privacy statement](https://www.clearfin.ca/privacy)
- [contact page](https://www.clearfin.ca/contact)
- [robots.txt](https://www.clearfin.ca/robots.txt)
- `/terms` and `/terms-of-service` returned 404 when checked

ClearFin's disclosures say that card names, images, trademarks, rates, fees,
rewards, offers, and eligibility details belong to their respective owners and
that ClearFin presents the information for educational comparison. That is a
disclaimer about ClearFin's use; it is not a downstream licence to PickMe.
ClearFin's footer claims © 2026 ClearFin Digital Inc.

The ten files formerly in `ca/clearfin/pages/` reproduced whole HTML responses,
including site copy, page structure, styling hooks, and other expressive
material. No located term authorizes publishing those copies. The `robots.txt`
file allows crawlers across the site, but crawler access controls do not address
copyright or downstream redistribution. On the evidence available, committing
the raw HTML to a public repository was **not cleared**; the copies have now been
removed from the current tree.

The extracted sample is less extensive than the HTML but retains ClearFin's
selection, labels, and some wording. Treat it as uncleared too. The slug/URL list
can remain as locator metadata if the owner chooses, but it must not be mistaken
for a licence to fetch or publish the corresponding pages.

ClearFin publishes `info@clearfin.ca` for corrections, removals, and general
questions. A permission request should ask for an explicit licence covering
automated retrieval, storage, public Git redistribution, release source
archives, transformations, commercial/non-commercial app use, attribution, and
revocation/version terms. Silence is not permission.

## Why facts and raw pages are treated differently

Canadian government copyright guidance distinguishes facts from their
expression: facts may be reused in one's own words, while website text, web
pages, software, and original data compilations can be protected. See
[ISED's copyright overview](https://ised-isde.canada.ca/site/ised/en/about-copyright)
and [CIPO's software and data guidance](https://ised-isde.canada.ca/site/canadian-intellectual-property-office/en/intellectual-property-rights-software-canada).

The Copyright Act gives the owner the exclusive right to reproduce a work or a
substantial part ([section 3](https://laws-lois.justice.gc.ca/eng/acts/C-42/section-3.html)).
Fair dealing can cover research ([section 29](https://laws-lois.justice.gc.ca/eng/acts/C-42/section-29.html)),
but this review does not assume that committing complete commercial web pages to
a public repository, release archive, or app is fair merely because the pipeline
has a research purpose.

The safe pipeline pattern is therefore: use comparison sites as discovery leads;
retain URLs and minimal internal provenance; independently read issuer material;
write facts in PickMe's own contract shape and words; and never promote a draft
until D3's per-rule issuer evidence exists.

## Required follow-up order

1. **Done for the current tree:** ClearFin HTML/extracted content and the OpenCard
   snapshot are removed; the ClearFin expansion remains blocked. A closed
   allowlist in `SOURCES.json` and `scripts/check-raw-source-policy.sh` prevents
   them from being recommitted accidentally.
2. **Owner/legal decision remains:** decide whether the existing tagged release
   source archives require takedown/history remediation, and how to cure the
   missing cc-offers MIT notice without reusing a published contract release id
   for a different byte-set.
3. **Before any new standalone data/release/app distribution:** make the
   cc-offers MIT notice travel with the substantial data copy. Do not rely on a
   notice that exists only elsewhere in the repository.
4. **Before promoting any imported draft:** re-source against the issuer under
   D3. Aggregator permission and issuer confirmation are separate gates.
5. **Recommended guardrail:** add source metadata with a closed disposition
   (`redistributable`, `internal-only`, or `blocked`) and make release/build
   scripts fail if `internal-only` or `blocked` raw material enters an artifact.

## MIT notice for cc-offers

MIT License

Copyright (c) 2026 Sunny Golovine

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
