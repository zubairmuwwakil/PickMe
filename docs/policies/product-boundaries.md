# PickMe product boundaries (A5, E1)

**Read when:** changing product scope, adding analytics or dashboards, writing
ecosystem-facing copy, or deciding whether a feature belongs in PickMe.

## A5 — analytics belongs on the hub

PickMe is the card-decision control centre: wallet setup, owner valuations,
checkout recommendations, feedback/reconciliation, one value-recovered figure,
and a small monthly summary. Deep analytics and visualization live on the web hub.
Do not duplicate hub dashboards in Swift or Kotlin.

Existing code is capability, not authorization. In particular,
`Engine/PortfolioAnalyzer` does not authorize a new deep-analytics product surface.

## E1 — PickMe is one product of four

PickMe keeps its own name and identity. It is not the umbrella brand for the
ecosystem. The web unifier is **In Unity**; PickMe, Looply, and MarketLens remain
distinct products.

Write PickMe copy as a standalone card copilot that can connect to the ecosystem,
not as the name of the combined financial product.

## Authority

These are concise restatements of ratified A5 and E1, not revisions. For
cross-repo identity and ownership, read [`ECOSYSTEM.md`](../../ECOSYSTEM.md).
When documents conflict, use the precedence recorded there and stop rather than
averaging incompatible instructions.
