# PickMe (Canadian Card Copilot)

**PickMe** is a 100% offline, privacy-first native iOS / SwiftUI app that tells multi-card holders exactly which credit card in their wallet to swipe at checkout to maximize points, cashback, and rewards.

- **Stack:** Swift 6 · SwiftUI (iOS 18) · SwiftData · MapKit / CoreLocation · Apple Maps
- **Privacy by Construction:** Runs entirely on-device with zero accounts, zero analytics trackers, zero bank credential scrapers, and zero cloud dependencies.

---

## 1. Standalone Product Capabilities

PickMe functions independently as a dedicated, on-device checkout optimizer:

- **Ambient Merchant Discovery**: One-time location fix detects nearby merchants with an offline/location-free Apple Maps search fallback.
- **Deterministic Card Evaluation**: Evaluates every card in your physical/digital wallet against issuer earn rules, category bonus caps, foreign-exchange fees, network acceptance rules (e.g. Costco = Mastercard only), and personalized point valuations.
- **Smart Switch Thresholds**: Only prompts you to switch cards when the projected reward improvement exceeds a sensible threshold (e.g. ≥ C$0.25 and 0.5 percentage points).
- **Keep, Downgrade & Cancel Audits**: Evaluates each card's recurring annual fee against your actual category spending to deliver empirical keep/cancel portfolio verdicts.
- **Acquisition Analysis**: Ranks non-owned Canadian credit cards by the net value they would add to your existing wallet after fees.

---

## 2. Ecosystem Unification (Optional)

PickMe can operate completely standalone or optionally connect to **Inunity** ([`inunity.ca`](https://inunity.ca)):

- **Cross-Language Shared Twin Contract**: PickMe's pure Swift deterministic calculation engine (`Engine/`) defines the canonical card-decision standard. A synchronized TypeScript twin in Inunity (`src/engine/cards-twin/`) is gated by shared test fixtures (`engine-fixtures.json`).
- **Closed-Loop Reconciliation**: Inunity can consume PickMe predictions to compare checkout recommendations against actual settled transactions captured via Apple Pay or statement imports.

---

- Finds nearby merchants from a one-time location request, with manual Apple Maps search as a location-free fallback.
- Accepts a rough purchase amount through presets, custom entry, or a skippable category estimate.
- Compares every eligible card using earn rules, reward valuations, caps, foreign-exchange costs, network acceptance, and owner-specific conditions.
- Shows the winning card, estimated value, runner-up, warnings, and point-valuation breakevens.
- Presents both outcomes when a merchant's rewards category is genuinely ambiguous.
- Saves predictions locally and keeps the original recommendation immutable.
- Reconciles predictions against posted statements, then learns the category for that exact merchant location.
- Tracks the experiment's category accuracy, arithmetic correctness, miss classes, and confirmed value recovered.
- Offers one-tap repeats for previously used merchants.
- Audits the wallet for keep, downgrade, and cancel decisions based on each card's marginal value.
- Ranks non-owned cards by the value they add to the existing wallet after recurring fees, with welcome offers excluded and every counterfactual exposed.

## The experiment

The MVP is designed to answer two questions over **30 confirmed physical checkouts**:

1. Is rewards-category prediction at least **85% accurate**?
2. Does the catalogue's reward arithmetic match posted rewards **100% of the time** when the predicted category is correct and enough evidence was captured?

Statement observations are stored beside predictions instead of rewriting them. That preserves an honest record of what the app said at checkout and creates terminal-specific evidence for future recommendations.

## How recommendations work

For each eligible card, the engine calculates:

```text
expected value (CAD)
= reward units x the owner's declared valuation
+ conditional redemption value
- foreign-transaction cost
- reward-currency risk or usability haircut
```

The calculation accounts for effective-dated rules and prorates purchases that cross a rewards cap. It then applies two gates:

1. **Acceptance:** cards on unsupported networks are removed (for example, Mastercard-only acceptance at Costco Canada).
2. **Switch threshold:** the engine leaves the default card only when the improvement is at least C$0.25 and 0.5 percentage points.

Ranking uses the owner's declared point value, while cash floors and aspirational values are used to disclose when a different valuation would change the recommendation.

## Architecture

```text
App (SwiftUI, MapKit, CoreLocation)
  -> Store (SwiftData, merchant mapping, checkout and reconciliation)
      -> Engine (catalogue, scoring, explanations and portfolio analysis)
```

| Directory | Responsibility |
| --- | --- |
| [`App/`](App/) | iOS 18 SwiftUI app, merchant discovery, amount capture, recommendations, reconciliation, and dashboard |
| [`Store/`](Store/) | SwiftData models, prediction log, merchant-category learning, experiment metrics, and app/engine composition |
| [`Engine/`](Engine/) | Deterministic Swift package for rule matching, cap math, scoring, explanations, and portfolio analysis |
| [`docs/plans/`](docs/plans/) | Product decisions and implementation plans |
| [`docs/research/`](docs/research/) | Canadian card-market and rule research |
| [`docs/compliance/`](docs/compliance/) | Draft privacy and App Store submission material |

The engine and store are local Swift packages with no third-party dependencies. The app persists data with SwiftData; its only outbound requests are user-initiated Apple Maps lookups.

## Requirements

- macOS 14 or later for package development and tests
- Xcode 16 or later with Swift 6 support
- iOS 18 simulator or device for the app

## Run the app

1. Clone the repository.

   ```bash
   git clone https://github.com/zubairmuwwakil/PickMe.git
   cd PickMe
   ```

2. Open the Xcode project.

   ```bash
   open App/CardCopilot.xcodeproj
   ```

3. Select the `CardCopilot` scheme and an iOS 18 simulator, then run the app with **Command-R**.

For installation on a physical device, select your own development team in the CardCopilot target's Signing & Capabilities settings.

## Run the tests

The two packages can be tested independently from the repository root:

```bash
(cd Engine && swift test)
(cd Store && swift test)
```

The current suite contains **216 tests**: 156 engine tests and 60 store tests. To print an end-to-end recommendation walkthrough:

```bash
cd Engine
swift test --filter DemoWalkthroughTests
```

## Seed data and customization

The bundled data is intentionally personal rather than a public Canadian card catalogue:

- [`card-catalogue.json`](Engine/Sources/CardCopilotEngine/Resources/card-catalogue.json) defines card products, effective-dated earn and FX rules, caps, fees, sources, and verification dates.
- [`candidate-catalogue.json`](Engine/Sources/CardCopilotEngine/Resources/candidate-catalogue.json) holds a separate issuer-verified acquisition shortlist so non-owned cards can never leak into checkout recommendations.
- [`owner-state.json`](Engine/Sources/CardCopilotEngine/Resources/owner-state.json) defines the cards carried, default card, cap progress, reward valuations, and switch threshold.
- [`engine-fixtures.json`](Engine/Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json) is the executable recommendation specification for important edge cases.

Changes to the catalogue or owner state should be accompanied by focused test updates. Card reward rules change frequently, so verify product terms against primary issuer sources before relying on modified data.

## Privacy

There are no accounts, analytics SDKs, ad networks, bank connections, or project-owned servers. Merchant history, recommendations, and statement observations remain in the app's local SwiftData store. Location is requested only after the user asks to find nearby merchants and uses a single fix rather than continuous tracking.

The material in [`docs/compliance/`](docs/compliance/) is draft planning documentation, not legal advice, and includes controls planned for a public release that may not yet exist in the app.

## Current limitations

- The seed catalogue and owner state represent one person's wallet; there is no onboarding or in-app wallet editor yet.
- Keep/cancel and acquisition results still use a documented placeholder spend distribution until statement imports provide measured category totals.
- The acquisition catalogue is a researched six-card shortlist, not a claim of complete Canadian-market coverage.
- Data export, record deletion controls, rule-freshness UI, localization, and App Intent support are planned but not implemented.
- The project is an experimental decision aid, not financial advice, and is not ready for public App Store distribution.

See the [MVP design](docs/plans/2026-08-15-canadian-card-copilot-mvp-design.md) for the complete rationale, formulas, scope, and pass/fail criteria.
