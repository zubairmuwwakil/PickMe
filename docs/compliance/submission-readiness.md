# Submission Readiness — Canadian Card Copilot

> ## ⚠ Draft for review — not a legal opinion
>
> Written by Zubair with Claude; **neither of us is a lawyer.** Section A commits real money and
> real time (incorporation, a D-U-N-S number, counsel) on the strength of readings of Apple's
> guidelines and Quebec statutes. Have Canadian counsel review it before acting on A1, A3 or A8.
>
> **[verified]** = quoted from a primary source, URL and date checked inline ·
> **[inference]** = our reasoning from those sources · **[uncertain]** = genuinely unresolved.
> All sources checked **2026-08-15**.

**Companion documents:** [`privacy-policy.md`](privacy-policy.md) ·
[`app-privacy-labels.md`](app-privacy-labels.md) · [`app-review-notes.md`](app-review-notes.md)

---

## A0. Read this before anything else: the experiment does not need App Review

The design doc's pass/fail bar is **30 real physical checkouts** on Zubair's own wallet
([design §3](../plans/2026-08-15-canadian-card-copilot-mvp-design.md)). Everything in Section A
below is about **publishing to the public App Store.** None of it gates the experiment.

**[verified]** TestFlight internal testing covers "up to 100 App Store Connect users with access to
your content," and the review requirement attaches to external testing: "If you invite external
testers, your beta build may require review… When you add the first build of your app to a group,
the build gets sent to App Review."
([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/))

**[inference] Recommended sequencing.** Run the 30-checkout experiment on Zubair's own device —
direct Xcode install, or an individual Apple Developer Program account with internal-only
TestFlight. **Do not incorporate yet.** Incorporation, counsel, a website, French localization and
a real catalogue are all costs that should be paid *after* the engine has proven it can hit 85%
category accuracy, not before. If the experiment fails, §3 of the design doc says the architecture
changes — and every dollar spent on Section A would have been spent against a product that no
longer exists.

Section A is the gate for **public v1.** It is written now so the sequencing is deliberate rather
than discovered three weeks before a launch date.

---

# Section A — Things only Zubair can do, outside the codebase

## A1. Incorporate, then enroll as an organization — before public submission

**Status:** blocking for public release · **Lead time: weeks, not days**

### Why

**[verified]** Guideline 5.1.1(ix), titled **"Apps in Highly Regulated Fields"**:

> "Apps that provide services in highly regulated fields (such as banking and financial services,
> healthcare, gambling, legal cannabis use, air travel and crypto exchanges) or that require
> sensitive user information should be submitted by a legal entity that provides the services, and
> not by an individual developer."

([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))

**A correction to how this has been recorded so far.** The design doc's §9 renders this as
"incorporate and submit under an organization account before public release," which is the right
conclusion but overstates the rule. The text says **"should"**, not "must", and it is aimed at
apps that **"provide services in"** those fields, submitted by "a legal entity **that provides the
services**."

**[inference]** A recommendation-only calculator arguably provides no banking or financial service
at all and is outside the guideline's scope. **We are not relying on that.** The reason to
incorporate is not that the rule clearly binds — it is that:

1. A reviewer skimming a credit-card app will reach for 5.1.1(ix) whether or not it strictly
   applies, and "should" gives them full discretion to do so.
2. Losing that argument means a rejection, an appeal, and a delay measured in weeks — against a
   fixed, knowable cost paid once.
3. **[uncertain]** Migrating a published app from an individual account to an organization account
   afterwards is possible in some circumstances but adds moving parts. Getting the account right
   the first time avoids the question. Confirm current transfer rules before relying on this either
   way.

### What it actually requires

**[verified]** Apple Developer Program organization enrollment
([Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/)):

> "Your organization must be a legal entity that can enter into contracts with Apple. We do not
> accept DBAs, fictitious business names, trade names, or branches."

> "Your organization (excluding government entities) must have a D-U-N-S Number so that we can
> verify your organization's identity, legal entity status, and address."

> "Your organization's website must be publicly available and functional, and its domain name must
> be associated with your organization. Links to social media webpages or websites that contain
> minimal content or display a message from a domain registrar won't be accepted."

> "Your work email address needs to associated with your organization's domain name."

> "…you'll be the Account Holder and must have the legal authority to bind your organization to
> legal agreements."

### The dependency chain — each step blocks the next

- [ ] **Incorporate** (federal under the CBCA, or provincially). Choose the name carefully:
      **[verified]** "Your organization's name will be displayed as the seller name of your apps on
      the App Store."
- [ ] **Obtain a D-U-N-S Number** for the new entity (free from Dun & Bradstreet; allow time — it
      cannot start until the entity exists)
- [ ] **Register a domain** for the entity
- [ ] **Build a real website** on it — not a placeholder, not a linktree. **[verified]** Apple
      rejects "websites that contain minimal content." This same site hosts the privacy policy
      (A4), so the two tasks collapse into one.
- [ ] **Set up email at that domain** and use it as the enrollment work email
- [ ] **Enroll as an Organization** and wait for Apple's verification
- [ ] **[uncertain]** Confirm with counsel whether the entity needs anything else before publishing
      a consumer-facing product in Canada (business registration in the province of operation,
      etc.). Out of our depth.

**No FCAC, provincial securities, or RPAA registration is expected** — the app never initiates,
intercepts, or processes a payment. **[inference]**, carried forward from the design doc's §9;
**this specific point is a legal conclusion and should be confirmed by counsel (A7)**, not taken
from this document.

## A2. Guideline 4.2 — what a defensible public v1 needs

**Status:** blocking for public release · **This is the largest item on the list**

### Why it is a real risk

**[verified]** Guideline 4.2, Minimum Functionality:

> "Your app should include features, content, and UI that elevate it beyond a repackaged website.
> If your app is not particularly useful, unique, or 'app-like,' it doesn't belong on the App
> Store. If your App doesn't provide some sort of lasting entertainment value or adequate utility,
> it may not be accepted."

**[verified]** And Guideline 2.1(a): "Submissions to App Review… should be final versions with all
necessary metadata and fully functional URLs included; **placeholder text, empty websites, and
other temporary content should be scrubbed before submission.**"

**[inference] The specific exposure.** The current catalogue is *Zubair's ten cards*. For any other
Canadian, the app's first screen is a list that probably does not contain their wallet. A reviewer
selecting cards they do not hold, at a merchant they did not choose, will see a screen that
computes a number — and will reasonably ask what lasting utility a stranger gets. "A calculator
seeded with one person's cards" is a fair description of the MVP and a poor answer to 4.2.

The design doc already acknowledges this: onboarding and card selection are listed as "required
before any public release" in the iOS plan's follow-on section. This item states the bar.

### What public v1 needs

- [ ] **A catalogue a typical Canadian can find their own cards in.** The bar is not a number, it
      is *"a stranger opens the app and their wallet is in there."* Practically that means the
      consumer cards of the major Canadian issuers — RBC, TD, Scotiabank, BMO, CIBC, National Bank,
      Desjardins, Amex Canada, MBNA, Tangerine, Simplii, PC Financial, Rogers, Wealthsimple, Neo,
      Canadian Tire. **[inference]** That is realistically 60–150 products, not 10. Note the cost
      honestly: the research dossier took a full day for ten cards, and every rule carries a
      `lastVerifiedAt` that decays. **This is the single biggest piece of work between the MVP and
      a public release, and it is data work, not code.**
- [ ] **Onboarding that produces value in the first minute, before any checkout.** The **Wallet
      Report Card** (design §4, add-on 2) is the strongest available answer to 4.2: it delivers a
      concrete, personal, dollar-denominated result — *"defaulting to your X costs you ~$Y per
      $1,000"* — with no location, no purchase, and no waiting. **[inference]** An app that is
      useful before its main feature is ever used is not "not particularly useful."
- [ ] **The `EngineSmokeTestView` placeholder gone** (§B1) — 2.1(a) names placeholder content
      explicitly.
- [ ] **Depth beyond the core loop**: settings, export, history, the metrics view. A single-screen
      app invites 4.2; four or five real screens do not.
- [ ] **App-native features that make 4.2.2 obviously inapplicable.** **[verified]** 4.2.2 targets
      apps that are "primarily… web clippings, content aggregators, or a collection of links."
      The Action Button App Intent (design §4, add-on 4), the local engine, and one-time location
      are all things a website cannot do. Shipping the App Intent in v1 is cheap insurance.
- [ ] **[inference]** Rule-freshness display ("rules verified `<date>`", already in scope) reads to
      a reviewer as active curation rather than a static scrape. Keep it visible on the
      recommendation screen, not buried in settings.

## A3. Quebec — French-language obligations, and why "geo-limit v1" is not on the menu

**Status:** blocking for public release · **Recommendation: localize. Do not attempt to exclude Quebec.**

### The question was framed as a choice. It is not one.

**[verified]** App Store availability is selected per country or region — "All Countries or
Regions" or "Specific Countries or Regions" — across "175 countries or regions." **There is no
sub-national granularity: availability cannot be set by province or state.**
([Manage availability for your app on the App Store](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/))

Canada is **one** App Store territory. **You cannot ship to Canada while excluding Quebec.** The
options are: ship to Canada (Quebec included), or do not ship to Canada — which for a Canadian
credit-card app is not an option.

In-app geo-gating is the only remaining "exclusion" mechanism, and it fails on its own terms:
it would require knowing the user's province, which requires **location** — the one permission this
app deliberately makes optional (§A/B, 5.1.1(iv)). Gating core functionality behind a location
permission to dodge a language law would trade a language problem for a **[verified]** Guideline
5.1.2(i) problem: "Your app may not require users to enable system functionalities (e.g. push
notifications, location services, tracking) in order to access functionality, content, use the
app."

### What the Charter actually requires

All quoted from [LégisQuébec, Charter of the French Language, CQLR c. C-11](https://www.legisquebec.gouv.qc.ca/fr/document/lc/C-11),
read 2026-08-15. (LégisQuébec blocks automated fetching; text read via browser.)

**[verified] s. 52.1 — the operative provision, and it is not new:**

> "Tout logiciel, y compris tout ludiciel ou système d'exploitation, qu'il soit installé ou non,
> doit être disponible en français, à moins qu'il n'en existe aucune version française.
>
> Les logiciels peuvent être disponibles également dans d'autres langues que le français, pourvu
> que la version française soit accessible dans des conditions… au moins aussi favorables et
> possède des caractéristiques techniques au moins équivalentes."

**A second correction to the design doc's §9.** It records this as "Bill 96 likely means French UI
if serving Quebec." The software obligation is **not** a Bill 96 innovation — the section's history
line reads **"1997, c. 24, a. 3."** It has been law for nearly thirty years. Bill 96 (2022, c. 14)
amended neighbouring provisions and added enforcement; it did not create this duty. The practical
consequence is that this is settled law, not a novel risk to be gambled on.

**[verified] s. 5:** "Les consommateurs de biens ou de services ont le droit d'être informés et
servis en français." **s. 50.2** (added by Bill 96, 2022, c. 14, a. 41): "L'entreprise qui offre au
consommateur des biens ou des services doit respecter son droit d'être informé et servi en
français."

**[verified] s. 55:** "Les contrats d'adhésion ainsi que les documents qui s'y rattachent sont
rédigés en français." → **any Terms of Service or EULA is squarely caught.** Much clearer than
s. 52's application to a privacy policy.

**[verified] s. 52** covers "les catalogues, les brochures, les dépliants, les annuaires
commerciaux, les bons de commande et tout autre document de même nature qui sont disponibles au
public." **[uncertain]** whether an App Store listing or a privacy policy is a "document de même
nature." Assume yes for the listing; ask counsel about the policy.

**[verified] s. 204.17 — one narrow shield, easily over-read:**

> "En cas d'atteinte à un droit reconnu par les articles 2 à 6.2 de la présente loi, la victime a
> le droit d'obtenir la cessation de cette atteinte.
>
> Toutefois, le premier alinéa ne s'applique pas à une atteinte au droit reconnu par l'article 5
> lorsqu'elle a été commise par une entreprise visée au premier alinéa de l'article 50.2 qui
> employait, au moment de l'atteinte, moins de cinq personnes."

**[inference]** A newly incorporated company with fewer than five employees is outside this private
cessation remedy **for the s. 5 right only.** It is **not** an exemption from s. 52.1, which is a
separate obligation enforced by the OQLF on complaint. Do not read the under-five carve-out as
"small companies don't have to localize." It does not say that.

### Recommendation: ship French with public v1

1. **Exclusion is unavailable** (above). This alone decides it.
2. **The obligation is old, clear, and specific to software.** s. 52.1 is not a grey area.
3. **The market cost of not doing it is roughly a fifth of the addressable market.** *(Quebec's
   share of Canada's population — approximate, from general knowledge, **not verified for this
   document**; check before quoting it anywhere.)* For a Canada-only product, that is not a niche.
4. **The string surface is small, and shrinking it further is a design choice we already made.**
   This is a calculator with a handful of screens. Card product names are trademarks and stay in
   their registered form. The largest translation surface is the `RecommendationExplainer` output —
   which is **template-generated**, so it is a bounded set of sentence patterns rather than open
   prose.
5. **Retrofitting is the expensive path.** Adopting a SwiftUI String Catalog while there is exactly
   one view costs almost nothing (§B11). Doing it after twenty views exist is a week of tedium.

- [ ] Localize the app UI to French (fr-CA)
- [ ] Localize the App Store listing: name, subtitle, description, keywords, **and screenshots**
      (A5)
- [ ] Localize the privacy policy; App Store Connect takes a policy URL per localization
- [ ] If a Terms of Service is ever written, French is required — s. 55
- [ ] **[uncertain]** Have counsel confirm scope: does s. 52.1 reach the *card-rule content* in the
      catalogue, or only the app's own interface? The rules paraphrase issuer terms that issuers
      themselves publish bilingually.
- [ ] **[uncertain]** Check the *Regulation respecting the language of commerce and business* for
      applicable derogations. **[verified]** s. 54.1 empowers the government to make them — we did
      not check whether any apply here.

**For the personal MVP:** none of this is engaged. There is no "entreprise" offering goods or
services to the public, and the app is not distributed. This is a public-v1 gate only.

## A4. Privacy policy URL hosting

**Status:** blocking · **Depends on:** A1 (domain and website)

**[verified]** Guideline 5.1.1(i): "All apps must include a link to their privacy policy in the App
Store Connect metadata field **and within the app in an easily accessible manner.**"

Both halves are required. The App Store Connect field alone is not compliance — the in-app half is
§B3.

**[verified]** Guideline 2.1(a) requires "fully functional URLs" and that "empty websites… should
be scrubbed before submission." A policy URL that 404s at review time is a rejection.

- [ ] Publish [`privacy-policy.md`](privacy-policy.md) at a stable URL on the company domain
      (e.g. `https://[[DOMAIN]]/privacy`) — the same site A1 requires for enrollment
- [ ] Fill every placeholder: `[[LEGAL ENTITY NAME]]`, `[[CONTACT EMAIL]]`,
      `[[PRIVACY OFFICER NAME AND TITLE]]`, `[[EFFECTIVE DATE]]`, `[[POLICY URL]]`
- [ ] Publish the French version and set the fr-CA policy URL (A3)
- [ ] Keep it live for the life of the app, and keep a version history — a policy that silently
      changes is worse than one that changes visibly
- [ ] **Counsel signs off before it goes live** (A7)

## A5. Screenshots

**Status:** blocking · **[verified]** from
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)

- **6.9" display is the required iPhone size** (iPhone Air, 17 Pro Max, 16 Pro Max, 16 Plus,
  15 Pro Max, 15 Plus, 14 Pro Max): **1260 × 2736 px portrait**, 2736 × 1260 landscape. If it is
  not provided, scaled screenshots from the 6.5" size (1284 × 2778) are used.
- **1 to 10 screenshots per localization.** `.jpeg`, `.jpg`, `.png`. **No alpha channel or
  transparency.**

- [ ] Capture from the **real shipping build** — no mockups of screens that do not exist (2.1(a))
- [ ] A **separate French set** if the app is localized (A3) — screenshots are per-localization
- [ ] **[inference]** Do not put a specific dollar figure in marketing copy on a screenshot
      ("Save $340 a year!"). The app's own honesty design refuses to state values it cannot
      support; the store listing should not undercut that.
- [ ] **[inference]** Screenshots will show issuer card product names — see A8 before shipping them

## A6. Support URL, contact point, and the Law 25 privacy officer

**Status:** blocking

App Store Connect requires a support URL. Separately:

**[verified]** Quebec P-39.1 s. 3.1: "Toute personne qui exploite une entreprise est responsable de
la protection des renseignements personnels qu'elle détient… la personne ayant la plus haute
autorité veille à assurer le respect et la mise en oeuvre de la présente loi. Elle exerce la
fonction de responsable de la protection des renseignements personnels," and the officer's **title
and contact details must be published.**
([LégisQuébec, P-39.1](https://www.legisquebec.gouv.qc.ca/fr/document/lc/P-39.1))

- [ ] A support page on the company domain with a monitored contact address
- [ ] Designate the privacy officer (by default, the person with highest authority — Zubair) and
      **publish the title and contact details**, per s. 3.1. This is not optional boilerplate.
- [ ] Use the same address in [`app-review-notes.md`](app-review-notes.md) Part A

## A7. Retain Canadian counsel

**Status:** blocking · **Do this once A0's experiment has passed, before A1's spending**

Scope to give them — the genuinely open questions this package could not close:

1. Does **PIPEDA** attach at all when the publisher never receives the data?
   ([`privacy-policy.md`](privacy-policy.md) §B2, §B5.1)
2. **Law 25** scope for a local-only app; is the s. 9.1 privacy-by-default reading right; is the
   portability implementation adequate given that s. 27 ¶3 excludes inferred data?
   ([`privacy-policy.md`](privacy-policy.md) §B3)
3. **Charter s. 52.1** scope — UI only, or catalogue content too? Any applicable regulatory
   derogation? (A3)
4. Confirm **no FCAC / securities / RPAA** registration is triggered by a recommendation-only app
   (A1)
5. **Trademark** use of issuer card names, and whether a disclaimer is sufficient (A8)
6. Review [`privacy-policy.md`](privacy-policy.md) before publication, and
   [`app-review-notes.md`](app-review-notes.md) Part A before submission — it asserts to Apple what
   the app is not

## A8. Issuer trademarks and brand use

**Status:** open · **[uncertain] — outside our competence, flagged rather than answered**

The app displays third-party card product names ("American Express Cobalt Card", "Scotia Momentum
Visa Infinite +") and the store listing likely will too (A5).

**[inference]** This is ordinary nominative use — naming a product in order to talk about it — and
comparison sites like Ratehub and creditcardGenius do it routinely. But we have not verified that,
and Apple's IP guidelines give reviewers a hook.

- [ ] **[inference]** Word marks only. **Do not ship issuer logos or card art** without permission.
      This also happens to be the design's own position: decision #9 records that *"card art ≠
      reward rate."*
- [ ] **[inference]** Add a plain disclaimer in-app and in the listing: *not affiliated with,
      endorsed by, or sponsored by any card issuer* (§B14)
- [ ] Counsel confirms (A7 item 5)

## A9. App Store category and age rating

**Status:** open judgment call · **[inference] throughout**

Choosing **Finance** as the primary category is honest but signals "financial app" to the reviewer
who is deciding whether to reach for 5.1.1(ix) (A1). **Shopping** or **Utilities** is also an
accurate description of a purchase-time comparison calculator.

**Do not game this.** Pick the category that genuinely describes the app and be able to say why.
The point of raising it is that there is a real choice here, and it interacts with A1 — not that
there is a trick available.

- [ ] Decide primary and secondary category, and record the reasoning
- [ ] Age rating: expected 4+; no objectionable content, no gambling, no unrestricted web access

---

# Section B — Things that can be done in the codebase

**Baseline as of 2026-08-15:** the app target contains exactly one Swift file
([`CardCopilotApp.swift`](../../App/CardCopilot/CardCopilotApp.swift)) rendering an
`EngineSmokeTestView`. The SwiftData models exist in the `CardCopilotStore` package. **There is no
`Info.plist`, no location code, no MapKit, and no UI beyond the smoke test.** Most of Section B is
therefore "build the thing," and the compliance-specific items are called out as such.

### Blocking for any submission

- [ ] **B1. Delete `EngineSmokeTestView`.** **[verified]** 2.1(a) names placeholder content
      explicitly. Currently the entire app.
- [ ] **B2. Build the core flows** — Tasks 3–6 of the
      [iOS implementation plan](../plans/2026-08-15-ios-app-implementation-plan.md), plus the
      onboarding and card-selection work its follow-on section flags as required before public
      release (A2).
- [ ] **B3. In-app privacy policy link.** **[verified]** 5.1.1(i) requires the policy "within the
      app in an easily accessible manner." There is no settings screen yet. A URL in App Store
      Connect alone does not satisfy this.
- [ ] **B4. Create `Info.plist` with a specific `NSLocationWhenInUseUsageDescription`.**
      **[verified]** 5.1.1(ii): "Ensure your purpose strings clearly and completely describe your
      use of the data." Draft string in
      [`app-privacy-labels.md`](app-privacy-labels.md) §7.
- [ ] **B5. Confirm the absence of keys that must not be there:** no
      `NSUserTrackingUsageDescription` (no ATT — see labels §4), no
      `NSLocationAlwaysAndWhenInUseUsageDescription`, no `location` in `UIBackgroundModes`.
      **[verified]** 5.1.1(iii): "Apps should only request access to data relevant to the core
      functionality."
- [ ] **B6. Location off by default, behind its own consent screen.** **[verified]** P-39.1 s. 9.1:
      privacy settings must "par défaut… assure[r] le plus haut niveau de confidentialité, sans
      aucune intervention de la personne concernée." **[verified]** s. 14: consent must be
      "manifeste, libre, éclairé… demandé à chacune de ces fins, en termes simples et clairs…
      présentée distinctement de toute autre information" — **its own screen, not a line inside a
      wall of onboarding text.** **[verified]** s. 8.1 additionally requires telling the user
      beforehand that the app uses locating technology and how to activate it.
- [ ] **B7. Manual merchant search must reach every feature with location permanently denied.**
      **[verified]** 5.1.1(iv): "Where possible, provide alternative solutions for users who don't
      grant consent." **[verified]** 5.1.2(i): functionality may not require enabling location.
      [`app-review-notes.md`](app-review-notes.md) *invites the reviewer to test this path* — that
      invitation is only safe if it is genuinely complete.
- [ ] **B8. One-tap JSON/CSV export.** [`privacy-policy.md`](privacy-policy.md) §8 promises it in
      four separate rows. In scope in the design doc; unbuilt.
- [ ] **B9. Delete-all-data, and per-record delete.** **[verified]** 5.1.1(i) requires the policy to
      "describe how a user can revoke consent and/or request deletion." §7 of the policy promises
      both. **Neither appears anywhere in the current plans — this is a genuine gap, not just
      unbuilt work.**

> **B8 and B9 are load-bearing for the policy.** Publishing
> [`privacy-policy.md`](privacy-policy.md) before they ship turns a draft into a false statement.

- [ ] **B10. Automated guard that the app makes no network call except MapKit.** The entire
      privacy posture — the "Data Not Collected" label, the review notes, the policy — rests on
      this one claim. It is currently guaranteed only by nobody having added a dependency yet. A
      test or a CI check makes it a property of the codebase rather than of everyone's memory.

### Strongly recommended, non-blocking

- [ ] **B11. Adopt a SwiftUI String Catalog now**, before the UI exists (A3). Near-zero cost today;
      a week of tedium later.
- [ ] **B12. Decide the SwiftData store's Data Protection class, and whether to exclude it from
      device backups.** [`privacy-policy.md`](privacy-policy.md) §7 currently discloses that iOS
      backups may include the data — which is honest, and the alternative silently loses user
      history on device migration. Decide deliberately; §9 of the policy must match whatever is
      chosen. Open question in policy §B5.4.
- [ ] **B13. "Rules verified `<date>`" on the recommendation screen** — already in scope; it also
      does real work for A2.
- [ ] **B14. In-app disclaimers**: not financial advice; not affiliated with or endorsed by any
      card issuer (A8). Policy §11 covers the first in the published text.
- [ ] **B15. Ship the Action Button App Intent in v1** — cheap 4.2.2 insurance (A2).
- [ ] **B16. Re-run [`app-privacy-labels.md`](app-privacy-labels.md) §6 before any release that
      adds a network call or an SDK.** The label is a representation, and the crowdsourced-merchant
      feature on the Phase 2 roadmap would invert it.

---

## Summary — the critical path to a public v1

1. **Pass the 30-checkout experiment** (design §3). Nothing below is worth spending on first (A0).
2. **Retain counsel** (A7) — the answers shape A1 and A3.
3. **Incorporate → D-U-N-S → domain → website → org enrollment** (A1). Weeks of lead time, mostly
   waiting, all of it serialized.
4. **Build a real catalogue and real onboarding** (A2). The largest single body of work, and it is
   data work, not code.
5. **Localize to French** (A3). Cheapest if started before the UI is written (B11).
6. **Close the codebase gaps that the compliance documents already promise** — export, deletion,
   in-app policy link, network guard (B3, B8, B9, B10).
7. **Publish the policy, capture screenshots, paste the review notes, submit** (A4, A5,
   [`app-review-notes.md`](app-review-notes.md)).

**The two hard gates are A1 and A2**, and they fail differently. A1 fails *predictably* — you
either have the entity or you do not, and you find out before you submit. A2 fails on a reviewer's
judgment of whether a stranger gets lasting utility, which you find out only after you submit. That
asymmetry is the argument for over-investing in the catalogue and onboarding relative to how
optional they feel.
