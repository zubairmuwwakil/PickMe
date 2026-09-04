# PickMe — agent router

PickMe is the ecosystem's canonical owner of card-decision semantics: checkout
selection, keep/cancel, benefits, and valuation. Released bytes live in
`contracts/`; Swift defines behavior; every twin must pass the shared fixtures.
Uncatalogued cards follow D3's issuer-sourced request/research path, never an open editor.

## One command

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

This is the cross-language card-semantics gate already run by CI on every push.

## Read when you are…

| File | …doing this |
|---|---|
| [`REPO_MAP.md`](REPO_MAP.md) | deciding where a new artifact belongs |
| [`Engine/AGENTS.md`](Engine/AGENTS.md) | changing Swift semantics or contract bytes |
| [`android/AGENTS.md`](android/AGENTS.md) | changing the Kotlin twin or Android resources |
| [`catalogue-pipeline/AGENTS.md`](catalogue-pipeline/AGENTS.md) | researching, importing, or promoting card data |
| [`merchant MCC production architecture`](docs/superpowers/specs/2026-09-04-merchant-mcc-production-architecture-design.md) · [`issuer MCC local join`](docs/superpowers/specs/2026-09-04-issuer-mcc-local-join-design.md) | changing merchant identity, MCC seeds/learning/import joins/community evidence, providers, or Purchase Route MCC semantics |
| [`free-production MCC constraint`](docs/research/2026-09-04-free-production-mcc-sources.md) · [`exact-MCC provider research`](docs/research/2026-09-04-merchant-mcc-provider-evaluation.md) | evaluating external MCC APIs, account-link providers, public research sources, or proposing paid merchant data; $0 recurring production cost is the active default unless the owner explicitly revisits it |
| [`purchase decision architecture`](docs/superpowers/specs/2026-09-04-purchase-decision-architecture-design.md) | changing how rewards, benefits/protection, or alternate routes combine into the final checkout decision |
| [`product-boundaries.md`](docs/policies/product-boundaries.md) | changing scope, analytics, dashboards, or ecosystem copy |
| [`ECOSYSTEM.md`](ECOSYSTEM.md) | doing cross-repo work or checking ownership |

For model and effort routing, read [`FLEET.md`](FLEET.md).

## Freedom

Anything not named here and not caught by the command above is yours to decide.
Prefer acting and letting the check fail over asking. Work directly on `main`.
Do not create branches or pull requests; make a change smaller if it feels too large.
