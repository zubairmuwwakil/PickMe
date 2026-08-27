# Privacy Policy — PickMe

> ## ⚠ Draft for legal review — do not publish as-is
>
> This was written by Zubair with Claude. **Neither of us is a lawyer.** It must be reviewed by
> Canadian privacy counsel (PIPEDA + Quebec Law 25 competence) before it is published, linked from
> App Store Connect, or relied on by anyone.
>
> Claims in the **Notes for counsel** appendix are labelled:
> **[verified]** — quoted from a primary source, URL and date-checked inline ·
> **[inference]** — reasoning from verified sources that counsel should confirm ·
> **[uncertain]** — genuinely unresolved; flagged rather than papered over.

> ## 🔴 REWRITTEN 2026-08-17 — v1's central claim is no longer true
>
> Draft v1 said: *"None of that record is sent to us. We do not operate a server that receives it,
> we have no account system that could identify you."* **All three clauses are now false.** PickMe
> has accounts (Clerk), a server, and an optional Apple Wallet capture path that sends transaction
> data — including precise coordinates — to that server, where it is retained.
>
> The app also now detects arrival at shops in the background, and looks up nearby merchants as you
> move rather than only when you ask.
>
> v1 must not be published. This version splits the policy around the distinction that actually
> matters to a reader: **what the app does on its own, and what changes if you sign in.**

**Status:** draft v2, 2026-08-17
**Applies to:** PickMe for iPhone
**Placeholders to fill before publication:** `[[LEGAL ENTITY NAME]]`, `[[CONTACT EMAIL]]`,
`[[PRIVACY OFFICER NAME AND TITLE]]`, `[[EFFECTIVE DATE]]`, `[[POLICY URL]]`

---

# PART A — The policy (publishable text)

## Privacy Policy

**Effective date:** `[[EFFECTIVE DATE]]`
**App:** PickMe for iPhone
**Published by:** `[[LEGAL ENTITY NAME]]`

### The short version

PickMe tells you which credit card in your wallet earns the most on the purchase you are about to
make. To do that it keeps a record on your iPhone of your cards, the shops you buy at, what you
spent, and the advice it gave you.

**PickMe works in two modes, and the difference matters.**

**Without an account** — the default, and the whole app works this way — everything above stays on
your iPhone. We receive nothing. There is no data for us to read, sell, or hand over, because we
never get it. The only thing that leaves your phone is a Maps lookup, which goes to Apple, not to
us.

**If you sign in** — optional, and nothing pushes you toward it — you get an account with us, and
some data does reach our server: your email address; your wallet and reward settings; how much you
have spent toward each card's bonus limits; and, if you set up the Apple Wallet capture shortcut,
your card transactions **including where you were when you made them.**

The app never asks for and never stores card numbers, PINs, or banking credentials, in either mode.
It has no access to your bank and cannot move money.

### 1. Who is responsible

`[[LEGAL ENTITY NAME]]` publishes this app and is responsible for the personal information
practices described here.

**Person in charge of the protection of personal information:**
`[[PRIVACY OFFICER NAME AND TITLE]]` — `[[CONTACT EMAIL]]`

### 2. What the app stores on your iPhone

Everything in this section is stored in the app's own storage on your device in both modes. If you
sign in, the wallet configuration in 2(a) through 2(c) is also copied to your account so the server
can evaluate Wallet Shortcut captures. The merchant history, recommendations, purchase entries,
statement checks, and location/discovery/patronage history in 2(d) through 2(i) are never
uploaded.

**a. Your cards.** Which *card products* you selected from the catalogue built into the app — for
example "American Express Cobalt Card."

> **The app never asks for and never stores card numbers, expiry dates, security codes (CVV/CVC),
> PINs, cardholder names, or online banking credentials.** There is no field anywhere in the app
> that accepts them. If any screen ever appears to ask you for a card number, it is not this app.

**b. Your card settings.** Which card is your everyday default; which cards you keep at home; bonus
categories you have selected with your issuer; whether a paid tier is active; the month your account
was opened; and your own estimates of spending toward each card's bonus caps.

**c. What you believe your points are worth.** The cents-per-point figures used to convert points
into dollars, including any you edit.

**d. Shops you confirm.** For each one: the name, the Apple Maps place identifier, **the shop's
latitude and longitude**, the purchase category you confirmed, how many times you have confirmed
it, and when it was last used.

**e. Every recommendation the app has made.** The date and time, the shop, the category it
predicted and how confident it was, the card it recommended and the dollar value it calculated, the
runner-up, the point valuation in force at that moment, the explanation you were shown, and the
amount you told it you expected to spend, if you said.

**f. Each purchase you record.** Separately from the advice: **which card you actually used**,
**what the purchase actually cost**, and whether each of those was entered at the time or recalled
later.

**g. Your statement checks.** When you later reconcile against a statement: the category the
purchase actually coded as, the points or cash back that actually posted, a classification of what
went wrong if anything, and any note you write.

**h. A record of where the app has looked for shops.** To avoid searching the same place twice, the
app remembers which roughly one-kilometre squares it has already looked in, and the shops it found
there. **This is a coarse record of areas you have passed through, not only places you shopped.**
It exists purely to save battery and network use. Squares you have not returned to are deleted
automatically after about 90 days, and the whole record is erased by "delete all data."

**i. Which shops you keep going back to.** For every merchant the app recognises, it keeps the
calendar days you paid there, captured from the Apple Wallet automation if you use it. **Not the
amount, not the card, not the time of day — just the date, and only for shops the app already
knows by name.** A shop you visit three separate days within a rolling 90-day window is treated as
one you frequent, which lets an arrival notification there use your own switch threshold instead of
the higher bar applied to a place you rarely visit. Days age out of the 90-day window on their own,
so a shop you stop going to stops counting without you doing anything. You can see this list, and
remove or block any merchant from it, from within the app; "delete all data" clears it entirely.

### 3. What this adds up to — stated plainly

Sections 2(d) through 2(i) together build a partial record of **where you go, where you shop, how
often, when, what you spent, and which cards you carry.** Section 2(b) includes approximate figures
for your annual spending in certain categories. That is genuinely personal information and we treat
it as such.

**In the default mode, that record never leaves your device.** The design decision is upstream of
this policy, not a promise layered on top of it.

### 4. If you create an account (optional)

Signing in is not required. Card recommendations, the prediction log, arrival alerts, and everything
in section 2 work fully without one.

**If you do sign in, we receive:**

- **Your email address**, through our sign-in provider, Clerk.
- **A user identifier** we use to associate your data with your account.
- **Your wallet and reward settings** — selected card products; default and drawer cards;
  card-specific reward conditions and categories; account-anniversary or cap-reset settings;
  cap-progress estimates; switching thresholds; and point or reward valuations.
- **Your bonus-cap usage** — how much you have spent toward each card's limits.
- **Card-catalogue requests you submit** — the issuer, product name, and optional note you entered.

**If you additionally set up the Apple Wallet capture shortcut, we also receive, for each
transaction it captures:**

- the merchant name as your bank reported it, and the raw transaction description
- **the amount and currency**
- the card description as Apple Wallet reported it
- the date and time, and your device's time zone
- **your location at the moment of the transaction — precise latitude, longitude and accuracy**

**We keep that location.** We do not blur it or delete it after identifying the shop. Over time this
builds a record on our server of where you shopped, when, on which card, and for how much. We are
telling you this plainly because it is the most sensitive thing we hold and you should decide about
it deliberately.

If you would rather we did not, you have three options, all of which leave the rest of the app
working: do not set up the Wallet shortcut; revoke its access token in Settings; or do not create an
account at all.

### 5. What we never do, in either mode

- **No advertising**, no ad identifiers, no ad networks.
- **No tracking** of you across other companies' apps or websites, and **no data brokers.**
- **No analytics or crash-reporting SDK** of any kind.
- **No selling or renting** of your personal information, ever.
- **No connection to your bank** or card issuer, and no access to your statements.
- **No payment processing.** The app never moves, holds, or touches money.

### 6. Location

**On your device, PickMe uses location three ways:**

1. **A one-time reading** when you tap to find nearby shops, so you can pick where you are instead
   of typing.
2. **Arrival detection**, if you turn it on. The app watches a small number of shopping areas near
   you and can suggest a card as you walk in, and ask what you spent as you leave. This needs
   "Always" permission because it must work while the app is closed.
3. **Finding shops near you as you move**, so arrival detection knows what is around. This asks
   Apple Maps about your surroundings when you arrive somewhere new.

**How it is limited.**

- Location is **off until you turn it on.** The app does not ask on first launch.
- **Arrival detection is separately optional** and explained on its own screen before either system
  prompt appears.
- The app **never streams your position.** It uses one-time fixes, iOS's significant-location-change
  service, and geofences — never continuous GPS tracking.
- **No route or trail is recorded.** What is saved is described in sections 2(d) and 2(h).

**If you say no.** The app remains fully usable. **Every feature is reachable by searching for a
shop by name.**

**Turning it off later.** iOS Settings → Privacy & Security → Location Services → PickMe.

### 7. Apple Maps

When you look for shops — or when the app looks around you for arrival detection — iOS sends that
request to **Apple** to answer it.

**Be aware of what this means:** because the app now looks around when you arrive somewhere new,
Apple receives an occasional signal of your movements, not only your deliberate searches. The app
deliberately keeps this rare: it skips lookups while you are travelling at driving speed, and it
never looks twice at a place it has already checked recently.

We do not receive those requests, are not told what was searched, and get no copy of the result.
Apple's handling is governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/), not
by this one.

### 8. How long data is kept

**On your iPhone:** until you delete it. Exceptions: the record of areas the app has looked in
(section 2(h)) deletes itself after about 90 days without a return visit, and each day in the
merchant-visit record (section 2(i)) ages out 90 days after that day, per merchant.

- **Delete individual records** — from within the app, including forgetting or blocking a single
  merchant's visit history (2(i)).
- **Delete everything local** — the app provides a control that erases the entire local database,
  including saved shop locations, the record of areas searched, and the merchant-visit record.
- **Delete the app** — removing PickMe deletes its local database with it.

**On our server, if you have an account:** until you delete your account. Settings → Delete Account
erases your account and everything we hold for you, including captured transactions and their
locations. You are asked separately whether to also erase your iPhone's local history, and the
default is to keep it — deleting your account does not require destroying your own records.

**One thing to be aware of:** if you back up your iPhone, that backup may include the app's data,
as it does for other apps. Those backups are controlled by your own iOS and iCloud settings and by
Apple, not by us.

### 9. Your rights

| Your right | How to use it |
|---|---|
| **Know what is held** | Sections 2 and 4 list it; local records are visible on screen in the app |
| **Access / get a copy** | Settings → Export produces a JSON or CSV file of your local data. For server-side data, write to us at `[[CONTACT EMAIL]]` |
| **Portability** | The same export; JSON and CSV are both structured, commonly used formats |
| **Correct** | Edit cards, settings, valuations, and categories in the app at any time |
| **Delete** | Delete individual records, erase all local data, delete your account, or delete the app |
| **Withdraw consent** | Turn off Location in iOS Settings; revoke the Wallet capture token in Settings; delete your account |

**One honest limitation about corrections:** the app **never rewrites a recommendation after the
fact.** If a prediction was wrong, your correction is stored *beside* it rather than overwriting it,
so the app's accuracy is measured against what it actually told you at the time. You can delete a
prediction, but you cannot silently edit one — including us.

### 10. Security

Local data is stored in the app's private storage, protected by iOS's app sandbox and file
protection, **which rely on your device having a passcode or biometric lock set.** Server data is
held on infrastructure we control, reachable only with your authenticated session.

**What we do not claim:** we have not undergone a third-party security audit or certification, we
hold no compliance certifications, and we do not describe our security as "bank-level" or
"military-grade."

### 11. Children

This app is designed for adults who hold credit cards. It is not directed at children and we do not
knowingly collect information from them.

### 12. Advice, not a guarantee

Recommendations are calculated from a catalogue of published card terms and from your own settings.
**Card terms change, and merchants code purchases in ways nobody outside the payment network can see
in advance.** The app is a calculator you can audit, not a promise about what your issuer will pay.
It is not financial advice.

### 13. Changes to this policy

Updates will be posted at `[[POLICY URL]]` with a new effective date. **If a future version collects
something new, we will say so prominently in the app before it happens and ask for your consent
separately**, rather than changing this page quietly.

### 14. Contact, and how to complain

**Questions, or to exercise a right:** `[[CONTACT EMAIL]]`
**Person in charge of the protection of personal information:** `[[PRIVACY OFFICER NAME AND TITLE]]`

If you are not satisfied with our response:

- **Anywhere in Canada** — Office of the Privacy Commissioner of Canada,
  [priv.gc.ca](https://www.priv.gc.ca/en/report-a-concern/), 1-800-282-1376
- **Quebec** — Commission d'accès à l'information du Québec,
  [cai.gouv.qc.ca](https://www.cai.gouv.qc.ca/), 1-888-528-7741

---

# PART B — Notes for counsel

## B1. What changed since v1, and why it matters legally

v1 was written for an app with no accounts, no server, and no outbound traffic except MapKit. Its
central legal argument was that **PIPEDA might not attach at all**, because the publisher did not
collect, use, or disclose anything.

**That argument is gone.** The publisher now collects personal information — email, user id,
purchase history, and precise location — in the course of a commercial activity. PIPEDA and Law 25
attach straightforwardly. Counsel should re-read v1's B2 knowing its threshold question is now moot.

Three specific facts drive the analysis:

1. **Precise location, retained.** Wallet capture sends latitude/longitude/accuracy and the server
   keeps it rather than truncating after merchant resolution
   ([wallet capture spec](../../../MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md),
   amended 2026-08-17). Purchase history joined to precise location joined to identity is close to
   the most sensitive combination a consumer app can hold short of health data.
2. **Background location.** The app requests Always authorization and declares the `location`
   background mode for geofenced arrival detection.
3. **Passive MapKit queries.** Merchant discovery queries Apple as the user moves, not only on
   demand. The publisher receives nothing, but the user's expectation changes.

## B2. Questions for counsel, in priority order

1. **Is the location retention decision defensible?** **[uncertain]** OPC guidance on mobile apps
   stresses collection limitation. Retaining precise coordinates indefinitely when they have already
   served their purpose (merchant disambiguation) is the weakest point in the current posture. The
   spec notes redaction is technically cheap. **We recommend counsel look here first.**
2. **Is consent for Wallet capture adequately separate?** **[verified]** Law 25 s. 14 requires
   consent to be "manifeste, libre, éclairé," given for each specific purpose, and "présentée
   distinctement de toute autre information." Capture setup currently lives in the Sync screen. It
   probably needs its own consent surface naming location explicitly.
3. **Does the arrival feature satisfy s. 9.1's privacy-by-default rule?** **[verified]** Law 25
   s. 9.1 requires that a technological product's confidentiality settings provide "le plus haut
   niveau de confidentialité" by default, without user intervention. Arrival detection is off until
   enabled from a dedicated screen, which we believe satisfies this — **[inference]**, confirm.
4. **Retention periods.** We now have a real retention question we did not have in v1. The local
   discovery cache self-prunes at ~90 days. Server-side captured transactions have **no stated
   retention limit**. **[verified]** PIPEDA Schedule 1, 4.5.3: information "no longer required to
   fulfil the identified purposes should be destroyed, erased, or made anonymous." A defined
   retention period is likely needed.
5. **Breach obligations.** v1 needed no incident-response posture because there was nothing to
   breach. There now is. PIPEDA's breach-of-security-safeguards reporting and Law 25's equivalent
   both apply.
6. **Language.** Must the policy be published in French for Quebec users? Carried over from v1's
   B5 and still open.
7. **Data residency — resolved 2026-08-17, and it needs counsel's attention.** **[verified]**
   `moneytalks.zubairmuwwakil.com` is a CNAME to `vercel-dns-017.com`, so the API runs on Vercel;
   `.env.example` shows the database is Neon Postgres (`/neondb`). Neither is region-pinned — the
   repo has no `vercel.json`, so functions run in Vercel's default `iad1` (Washington DC) and Neon
   defaults to US East. **[inference]** Captured transactions and their coordinates are therefore
   stored in the United States.

   **[verified]** Law 25 s. 17 requires a privacy impact assessment before communicating personal
   information outside Quebec, and that the information receive protection equivalent to that
   afforded under Quebec law. Precise location joined to purchase history joined to identity is the
   kind of payload that makes this assessment substantive rather than a formality.

   Two routes: perform the assessment, or move the workloads. Vercel offers `yyz1` (Toronto) and
   Neon offers a Montreal region, so relocation is a configuration change rather than a migration
   of architecture. **Counsel should advise which, and the policy text needs a residency paragraph
   either way — it currently has none.**

## B3. Statutory anchors carried forward from v1

Still accurate and still relied on; see v1 in git history for the full quotations.

- **[verified]** PIPEDA s. 4(1)(a) scope; Schedule 1 principles 4.5.3 (retention), 4.8.1
  (openness), 4.9 (access).
  ([Justice Laws](https://laws-lois.justice.gc.ca/eng/acts/P-8.6/page-1.html), checked 2026-08-15.)
- **[verified]** Law 25 s. 3.1 (privacy officer must be named and contactable — policy §1 and §14),
  s. 8 (information at collection), s. 9.1 (privacy by default), s. 14 (consent), s. 27 ¶3
  (portability, excluding inferred data), ss. 28/28.1 (rectification and de-indexing — note Quebec
  has **no** general GDPR-style erasure right in these sections), ss. 90.1/91 (penalties).
  ([LégisQuébec, P-39.1](https://www.legisquebec.gouv.qc.ca/fr/document/lc/P-39.1), checked
  2026-08-15.)
- **[verified]** Apple Guideline 5.1.1(i) requires the policy be linked in App Store Connect **and**
  in the app; 5.1.1(v) requires in-app account deletion — built, see Settings → Delete Account.

## B4. Sections describing controls that do not exist yet

**Policy §9 promises an export ("Settings → Export") that is not built.** It was unbuilt in v1 and
remains unbuilt. **The policy must not be published until it ships**, or it becomes a false
statement rather than a draft.

Built since v1 and safe to describe: local erase, account deletion with keep-or-erase, Wallet token
revocation, discovery-cache pruning.
