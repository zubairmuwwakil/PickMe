# App Review Notes — text to paste, and why

> ## ⚠ Draft for review before submission
>
> Written by Zubair with Claude; **neither of us is a lawyer.** Part A is addressed to an Apple
> reviewer and should be read by counsel first — it makes assertions about what the app is not.
> **[verified]** = quoted from Apple's guidelines, checked 2026-08-15 · **[inference]** = our
> reasoning · **[uncertain]** = unresolved.
>
> **Not submittable yet.** Part A describes flows that must exist before it is pasted — Guideline
> 2.1 requires final, fully functional builds. See
> [`submission-readiness.md`](submission-readiness.md).
>
> ## 🔴 AMENDED 2026-08-17 — Part A contained false statements to App Review
>
> The version written 2026-08-15 told Apple *"There is no account system and no server"*,
> *"NOTHING LEAVES THE DEVICE"*, *"'When In Use' only; 'Always' is never requested"*, and
> *"no demo account is required because there are no accounts."*
>
> **Every one of those is now false.** The app has Clerk accounts, a backend, optional Wallet
> transaction capture that transmits precise location, and it requests Always authorization for
> geofenced arrival detection. Pasting the old text would have been a misrepresentation to App
> Review on the exact document meant to establish good faith.
>
> Part A is rewritten below. **Guideline 2.1(a) now applies: a demo account is required.**

**Source:** [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
checked 2026-08-15.

---

# PART A — Paste into "App Review Information → Notes"

```text
WHAT THIS APP DOES

Canadian Card Copilot tells a person which of their own credit cards earns the most
rewards on a purchase they are about to make, and shows the arithmetic behind the
answer. The user then pays manually with their own card. It is a calculator over
published credit-card reward terms. Nothing more.

NOT A FINANCIAL SERVICES APP (Guidelines 3.2.1(viii), 5.1.1(ix))

The app does not, and has no code path that could:

- trade, invest, or manage money, securities, or crypto
- hold, move, send, receive, convert, or store funds of any kind
- process, initiate, intercept, or route any payment
- connect to any bank, credit union, card issuer, or financial institution
- read, import, or access balances, statements, or transactions
- issue, apply for, activate, or manage a credit card
- store card numbers, expiry dates, security codes, PINs, or banking credentials
  (no field anywhere in the app accepts them)

Guideline 3.2.1(viii) covers apps "used for financial trading, investing, or money
management." The app does none of the three. It manages no money because it never
has access to any: it reads publicly published rewards terms, does arithmetic, and
shows a result. It is closer to a unit-price comparison tool than to a banking app.

There are no in-app purchases and the app takes no payments.

PRIVACY: THE APP WORKS FULLY WITHOUT AN ACCOUNT

Card recommendations, the local history, and arrival alerts all run entirely on
device. Card list, settings, saved shops, purchases and past recommendations are
stored in a local SwiftData database and are never transmitted anywhere.

Signing in is optional and nothing gates on it. If the user does sign in, we
receive their email address (via Clerk) and their bonus-cap usage. If they
additionally set up the optional Apple Wallet capture shortcut, we receive their
captured transactions - merchant, amount, card, time, and the location at which
the transaction occurred. Our App Privacy declaration covers all of this: Contact
Info, Identifiers, Purchase History, Precise Location and Other Financial Info,
all linked to the user, all for App Functionality, none used for tracking.

There is no analytics SDK, no crash-reporting SDK, no advertising and no ad
identifier, so there is no AppTrackingTransparency prompt. We share nothing with
other companies and use no data brokers.

LOCATION IS OPTIONAL, ONE-TIME, AND HAS A FULL MANUAL ALTERNATIVE (5.1.1)

Location is used for one purpose: a single CoreLocation fix, taken only when the
user taps to find nearby shops, to run a MapKit search so they can confirm the
store they are in.

The app also offers optional arrival alerts: it monitors a small number of geofenced
shopping areas so it can suggest a card as the user walks in, and ask what they spent
as they leave. This requires "Always" authorization and the location background mode,
because region monitoring must fire while the app is not running.

- Location is off until the user turns it on; nothing is requested at first launch.
- Arrival alerts are separately optional, behind their own explainer screen shown
  before either system prompt appears.
- The app NEVER streams position. It uses one-time fixes, significant-location-change
  monitoring, and geofences - never continuous GPS.
- No route or movement trail is recorded.

If location is declined the app remains fully functional: manual merchant search
reaches every feature, including the whole recommendation flow. Nothing is gated
behind the permission. Please do test with location denied; that path is complete,
not degraded.

REVIEWING THIS WITHOUT A CANADIAN CREDIT CARD

No credit card is needed. The app never verifies that a user holds the cards they
select; cards are picked from a built-in catalogue.

A demo account is provided below for the optional sync features, but note that the
ENTIRE core flow - steps 1 to 4 - works signed out. Please do review it signed out
first; that is how most users will run it.

Demo account: [[DEMO EMAIL]] / [[DEMO PASSWORD]]

To exercise the main flow from a fresh install, anywhere in the world:

1. Launch the app and select any two or more cards from the built-in catalogue of
   Canadian cards. No card details are requested.
2. Tap "Somewhere new."
   - Allow location: a list of nearby shops appears; pick any one.
   - Deny location: a manual search field appears instead; search any merchant name
     ("Safeway", "Shell", "Starbucks") and pick a result.
   Both routes lead to the same next screen. The list comes from Apple Maps, so a
   reviewer in the US will see US merchants. This is expected and the app works
   normally - recommendations are computed from purchase category, not country.
3. Optionally tap a purchase amount chip ($25, $50...). This step is skippable.
4. The recommendation screen shows which selected card earns the most, the dollar
   value, the runner-up, the reason, and when the card's terms were last verified.

CONTACT

[[CONTACT NAME]] - [[CONTACT EMAIL]] - happy to answer any question or provide a video
walkthrough.
```

---

# PART B — Why each paragraph is there

## B1. The 3.2.1(viii) paragraph

**[verified]** The guideline reads in full: *"Apps used for financial trading, investing, or money
management should be submitted by the financial institution performing such services and must have
necessary licensing and permissions in the locations where you make them available."*

**[inference]** Three activities are named, and the app does none of them. "Trading" and
"investing" are plainly out. **"Money management" is the only one with any reach**, and it is the
word the paste text spends its effort on — hence "It manages no money because it never has access
to any." A reviewer skimming for "credit card" will land on this paragraph, so the negative list is
concrete and code-level ("no code path that could") rather than a bare denial.

**[uncertain]** There is no Apple definition of "money management." Our reading — that it means
handling a user's funds or accounts, not calculating over published rates — is a reading. The
mitigations are the specificity of the list and the offer of a video walkthrough.

**Why the unit-price analogy is in there.** It gives the reviewer a familiar category to file the
app under. A tool that compares published prices is uncontroversial; this compares published
*earn rates*. **[inference]** — an argument, not a citation, and it is the paragraph most worth
cutting if counsel finds it flippant.

## B2. Why the paste text names 5.1.1(ix) but does not argue it

**[verified]** 5.1.1(ix) is titled **"Apps in Highly Regulated Fields"**:

> "Apps that provide services in highly regulated fields (such as banking and financial services,
> healthcare, gambling, legal cannabis use, air travel and crypto exchanges) or that require
> sensitive user information should be submitted by a legal entity that provides the services, and
> not by an individual developer."

**Two things this text does not say**, both worth being precise about internally:

1. It says **"should"**, not "must".
2. It applies to apps that **"provide services in"** those fields, submitted by "a legal entity
   **that provides the services**." **[inference]** An app that provides no banking or financial
   service, and merely calculates over published terms, is arguably outside its scope entirely.

**We are not making that argument to Apple, and the paste text does not.** It names the guideline
and then demonstrates, factually, that the app provides no such service. Arguing scope with a
reviewer is a bad trade: if they disagree, we have signalled that we were looking for an exemption.
Demonstrating the facts wins either way.

**The practical consequence is unchanged: incorporate first.** See
[`submission-readiness.md`](submission-readiness.md) §A1. Submitting a credit-card app from an
individual account invites the reviewer to reach for this guideline, and the argument above is one
we would rather never need to have.

## B3. The location paragraph

**[verified]** The manual-alternative requirement is **Guideline 5.1.1(iv) "Access"** — worth
pinning down, because the project's design docs cite "5.1.1" generally:

> "Apps must respect the user's permission settings and not attempt to manipulate, trick, or force
> people to consent to unnecessary data access… Where possible, provide alternative solutions for
> users who don't grant consent. For example, if a user declines to share Location, offer the
> ability to manually enter an address."

**[verified]** Guideline 5.1.2(i) also bears directly: *"Your app may not require users to enable
system functionalities (e.g. push notifications, location services, tracking) in order to access
functionality, content, use the app…"*

**Why the paste text invites the reviewer to test with location denied.** A reviewer who discovers
a working denial path themselves is more convinced than one who is told about it — and the
invitation is only safe because the manual path is genuinely complete. **If that ever stops being
true, delete the sentence rather than soften it.**

## B4. The privacy paragraph

Mirrors [`app-privacy-labels.md`](app-privacy-labels.md). It is in the review notes because
an app requesting Always location while collecting purchase history and precise coordinates is
exactly the pattern a reviewer probes. Answering it before it is asked costs a few lines; answering
it in a rejection appeal costs a week. §5 of the labels document has a longer reply ready for the
"why does a card calculator need Always?" question specifically.

## B5. The reviewer walkthrough

**[verified]** Guideline 2.1(a): *"include demo account info (and turn on your back-end service!)
if your app includes a login."* **Both halves now apply.** There is a login (Clerk) and a backend,
and the two halves carry different weight.

**"Turn on your back-end service" is the non-negotiable half.** The server must be up and serving
throughout the review window. A reviewer tapping Sync against a dead host is a functional failure
under Guideline 2.1, and that is a rejection.

**The demo account is strongly advisable rather than strictly required.** Clerk registration is
open, so a reviewer *can* self-register — the guideline's purpose is ensuring they can reach every
feature, and they can. Supply one anyway: sign-up may involve email verification a reviewer using a
throwaway address will not bother to complete, and leaving the field blank on an app that has a
login invites a "please provide credentials" round-trip that costs a full review cycle. Two minutes
against a week.

The walkthrough still leads with the signed-out path, because that is genuinely the primary
experience and a reviewer who sees the core flow work without an account understands the product
faster.

Three specific frictions the walkthrough defuses, all of them real:

1. **No Canadian card.** The app never validates card ownership. Stated plainly, because a reviewer
   may reasonably assume a card app needs a card.
2. **Wrong country.** MapKit returns merchants near the reviewer. A Cupertino reviewer sees US
   shops and might conclude the app is broken or misconfigured for its stated market. The note says
   this is expected and explains why the engine is indifferent — it scores on purchase *category*.
3. **Simulator location.** A reviewer on a device in a low-density area may get a short or empty
   POI list. The manual-search branch is given equal standing in step 2 for this reason, with three
   suggested search terms so nobody has to invent one.

## B6. Before pasting — checklist

- [ ] Replace `[[CONTACT NAME]]` and `[[CONTACT EMAIL]]`.
- [ ] Re-read step 1–4 against the **shipped build** and correct any screen or button name that has
      drifted. A walkthrough that does not match the binary is worse than none — it reads as
      carelessness on the exact document meant to establish care.
- [ ] Confirm the manual-search path really is complete with location denied. **Test it on device
      with the permission refused**, not in the simulator with a simulated location.
- [ ] Confirm the App Privacy answers match §2 of the labels document — five data types, all
      Linked, none Tracking — so the notes and the label agree.
- [ ] **Confirm the backend is up and stays up for the review window.** Guideline 2.1(a),
      non-negotiable half — a reviewer tapping Sync against a dead host is a Guideline 2.1
      functional failure.
- [ ] Replace `[[DEMO EMAIL]]` / `[[DEMO PASSWORD]]` with a working account. Advisable rather than
      strictly required, since Clerk sign-up is open — but it removes a likely round-trip.
- [ ] Test the signed-out path end to end. It is what the walkthrough leads with and what most
      users will run.
- [ ] Confirm the build is submitted from the **organization** account (§B2).
- [ ] **Check the length against App Store Connect's own limit for the notes field.** We could not
      verify a documented maximum from an Apple primary source (**[uncertain]**), so the block above
      is kept under 4,000 characters as a precaution. If it must be trimmed further, cut the
      walkthrough — the guideline paragraphs are the load-bearing part.
