# Privacy Policy — Canadian Card Copilot

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

**Status:** draft v1, 2026-08-15 — **superseded as the published artifact, retained as the working
document**
**Applies to:** Canadian Card Copilot for iPhone (renamed PickMe in `d4338e2`)
**Placeholders to fill before publication:** `[[LEGAL ENTITY NAME]]`, `[[CONTACT EMAIL]]`,
`[[PRIVACY OFFICER NAME AND TITLE]]`, `[[EFFECTIVE DATE]]`, `[[POLICY URL]]`

> ### What is actually published
>
> The live policy is the page at **https://moneytalks.zubairmuwwakil.com/privacy**, whose source is
> `MoneyTalks/src/app/privacy/content.ts` (MoneyTalks `910fc9f`). **That page, not this file, is the
> text people are shown and the URL given to App Store Connect.**
>
> The published page is corrected against [`account-deletion.md`](./account-deletion.md) §5: it
> describes the two-store split, the real outbound payload surface, the Wallet Shortcut flow
> (including retained precise coordinates), and the `gmail.readonly` scope. It scopes the export
> claim to the web hub and drops the per-record delete claim. It resolves the placeholders above as
> a named sole proprietor rather than an entity.
>
> **The counsel-review warning above still stands and was not satisfied by publishing.** The page
> went live because App Store Connect requires a reachable URL; that is a scheduling reason, not a
> legal sign-off. Review by Canadian privacy counsel remains outstanding.
>
> This file stays the long-form working document — it carries the Notes for counsel appendix, the
> PIPEDA and Law 25 analysis, and the open questions, none of which belong on a public page. **Edit
> the published page and this file together, or they drift apart again**, which is the failure that
> made `account-deletion.md` necessary in the first place. Sections 4, 6, 7 and 8 below are the
> known-wrong ones and are kept as written so the corrections stay legible.

---

# PART A — The policy (publishable text)

## Privacy Policy

**Effective date:** `[[EFFECTIVE DATE]]`
**App:** Canadian Card Copilot for iPhone
**Published by:** `[[LEGAL ENTITY NAME]]`

### The short version

Canadian Card Copilot tells you which credit card in your wallet earns the most on the purchase
you are about to make. To do that it keeps a record on your iPhone of your cards, the merchants
you shop at, and the advice it gave you.

**None of that record is sent to us. We do not operate a server that receives it, we have no
account system that could identify you, and there is no analytics or advertising code in the app.**
We cannot read your data, and we could not hand it over to anyone if asked, because we never
have it.

The app has no access to your bank, your card accounts, or your transactions. It cannot see what
you actually spent. Everything it knows, you told it or it inferred from a map search.

### 1. Who is responsible

`[[LEGAL ENTITY NAME]]` publishes this app and is responsible for the personal information
practices described here.

**Person in charge of the protection of personal information:**
`[[PRIVACY OFFICER NAME AND TITLE]]` — `[[CONTACT EMAIL]]`

### 2. What the app stores on your iPhone

Everything below is written to a database inside the app's own storage area on your device. It is
never transmitted to us.

**a. Your cards.** Which *card products* you selected from the catalogue built into the app —
for example "American Express Cobalt Card" or "Wealthsimple Visa Infinite Privilege."

> **The app never asks for and never stores card numbers, expiry dates, security codes (CVV/CVC),
> PINs, cardholder names, or online banking credentials.** There is no field anywhere in the app
> that accepts them. If any screen ever appears to ask you for a card number, it is not this app.

**b. Your card settings.** The choices you make about how your cards work:

- which card is your everyday default
- which cards you keep at home rather than in your wallet
- bonus categories you have selected with your issuer, where a card offers that choice
- whether an optional paid plan or subscription tier is active on a card
- the month your card account was opened, where a card's bonus limits reset on that anniversary
- **your own estimates of how much you have already spent toward each card's monthly or annual
  bonus cap** — these are approximate spending figures you enter yourself

**c. What you believe your points are worth.** The cents-per-point figures used to convert reward
points into dollars, including any you edit.

**d. Merchants you confirm.** For each merchant you confirm you are standing in:

- the merchant name
- the Apple Maps place identifier, where one exists
- **the merchant's latitude and longitude**
- the purchase category you confirmed for it
- how many times you have confirmed it, and when it was last used

**e. Every recommendation the app has made.** For each one:

- the date and time
- the merchant name and identifier
- the purchase category the app predicted, and how confident it was and why
- the card it recommended and the dollar value it calculated
- the runner-up card and its value
- the point valuation in force at that moment
- the explanation text you were shown
- **the purchase amount, only if you chose to enter one.** Entering an amount is always optional
  and always skippable.

**f. Your corrections.** When you later check a purchase against your statement:

- which card you actually paid with
- the category the purchase actually coded as
- a classification of what went wrong, if anything
- any free-text note you write
- the date you confirmed it

### 3. What this adds up to — stated plainly

Taken together, sections 2(d), 2(e) and 2(f) build a partial record of **where you shop, when,
roughly how much you spend there, and which cards you carry.** Section 2(b) includes approximate
figures for your annual spending in certain categories. That is genuinely personal information,
and we treat it as such.

**That is precisely why the app is built so that this record never leaves your device.** The design
decision is upstream of this policy, not a promise layered on top of it: there is no server to
send it to.

### 4. What we collect: nothing

We — `[[LEGAL ENTITY NAME]]` — do not collect, receive, store, sell, rent, share, or disclose
any personal information from this app. Specifically, the app contains:

- **no user accounts, sign-in, or registration** — you never give us an email address or a name
- **no analytics or crash-reporting SDK** of any kind, first-party or third-party
- **no advertising, no ad identifiers, no ad networks**
- **no tracking** of you across other apps, websites, or companies, and no data brokers
- **no connection to any bank, card issuer, or financial institution**
- **no payment processing** — the app never moves, holds, or touches money
- **no access to your transactions** — it cannot read your statements, and does not try to
- **no server of our own.** The app makes no network requests to us, because there is nothing to
  request from.

### 5. Location

**What we use it for.** With your permission, the app takes a **single location reading** to ask
Apple Maps which shops are near you, so you can pick the one you are standing in from a short list
instead of typing its name.

**How it is limited.**

- Location is **off until you turn it on.** The app does not ask on first launch and does not
  work its way around a refusal.
- The app requests **"While Using the App"** permission only. It never requests "Always."
- Each reading is a **one-time fix**, taken when you tap to find nearby merchants. The app does not
  monitor your location continuously and does not track you in the background. It cannot: the code
  requests single fixes and never starts continuous updates.
- Your coordinates are **not stored as a trail.** What is saved is the location of a merchant you
  confirmed, so the app can offer it to you again next time you are there (section 2(d)).

**If you say no.** The app remains fully usable. **Every feature is reachable by searching for a
merchant by name instead.** Declining location costs you the shortcut, not the product.

**Turning it off later.** iOS Settings → Privacy & Security → Location Services → Canadian Card
Copilot. You can revoke permission at any time; the app falls back to manual search.

### 6. Apple Maps

When you look for nearby merchants or search for one by name, iOS sends that request to **Apple**
to answer it. That is the app's only outbound network activity of any kind.

We do not receive that request, we are not told what you searched for, and we get no copy of the
result. Apple's handling of Maps requests is governed by
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/), not by this one.

### 7. How long your data is kept

Your data stays on your iPhone **until you delete it.** We do not set an expiry, because we hold
nothing and cannot delete anything on your behalf.

- **Deleting individual records** — you can delete merchants, predictions, and corrections from
  within the app.
- **Deleting everything** — the app provides a "delete all data" control that erases the entire
  local database.
- **Deleting the app** — removing Canadian Card Copilot from your iPhone deletes its database with
  it, in the ordinary iOS way.

**One thing to be aware of:** if you back up your iPhone to iCloud or to a computer, that backup
may include the app's data, in the same way it includes other apps' data. Those backups are
controlled by your own iOS and iCloud settings and by Apple — not by us. If you want the data gone
from your backups, manage or delete the backup itself.

### 8. Your rights, and how to use them

Canadian privacy law gives you rights over your personal information. Because your information is
on your device and not with us, **most of these rights are exercised directly in the app rather
than by writing to us** — and are satisfied immediately rather than within a statutory deadline:

| Your right | How to use it |
|---|---|
| **Know what is held** | Everything is listed in section 2 and visible on screen in the app |
| **Access / get a copy** | Settings → Export. One tap produces a **JSON or CSV file** containing all of your data, which you can save or send wherever you like |
| **Portability** (structured, commonly used format) | The same export. JSON and CSV are both structured, commonly used technological formats |
| **Correct** | Edit your cards, settings, valuations, and merchant categories in the app at any time |
| **Delete** | Delete individual records, use "delete all data," or delete the app |
| **Withdraw consent** | Turn off Location in iOS Settings (section 5). Nothing else in the app depends on a consent you gave us |

**If you write to us with a request for your data, we will have nothing to send you.** That is not
an evasion — it is the consequence of the design. We will tell you so, and point you to the export
button, which produces more than we could.

**One honest limitation about corrections:** the app deliberately **never rewrites a recommendation
after the fact.** If a prediction was wrong, your correction is stored *beside* it as a separate
record rather than overwriting it. This is so the app's accuracy is measured against what it
actually told you at the time, rather than against a tidied-up history. You can delete a
prediction, but you cannot silently edit one — including us.

### 9. Security

Your data is stored inside the app's private storage area on your iPhone. It is protected by iOS's
app sandbox and file-protection features, which rely on **your device having a passcode or
biometric lock set.** If your iPhone has no passcode, its local data is much less protected — this
is true of every app, including this one.

**What we do not claim:** we have not undergone a third-party security audit or certification, we
hold no compliance certifications, and we do not describe our security as "bank-level" or
"military-grade." We have no servers to secure. The honest description is the one above:
your data's security is iOS's local data protection, and your passcode.

### 10. Children

This app is designed for adults who hold credit cards. It is not directed at children, and we do
not knowingly collect information from anyone — of any age — because we do not collect information
at all.

### 11. Advice, not a guarantee

The app's recommendations are calculated from a catalogue of published card terms and from your own
settings. **Card terms change, and merchants code purchases in ways nobody outside the payment
network can see in advance.** Each recommendation shows the date its rules were last verified and
how confident the app is. The app is a calculator you can audit, not a promise about what your
issuer will pay you. It is not financial advice.

### 12. Changes to this policy

If this policy changes, the updated version will be posted at `[[POLICY URL]]` with a new effective
date. If a future version of the app ever collects anything — it does not today — **we will say so
prominently in the app before it happens, and ask for your consent separately**, rather than
changing this page quietly.

### 13. Contact, and how to complain

**Questions, or to exercise a right:** `[[CONTACT EMAIL]]`
**Person in charge of the protection of personal information:** `[[PRIVACY OFFICER NAME AND TITLE]]`

If you are not satisfied with our response, you can complain to a regulator:

- **Anywhere in Canada** — Office of the Privacy Commissioner of Canada,
  [priv.gc.ca](https://www.priv.gc.ca/en/report-a-concern/), 1-800-282-1376
- **Quebec** — Commission d'accès à l'information du Québec,
  [cai.gouv.qc.ca](https://www.cai.gouv.qc.ca/), 1-888-528-7741

---

# PART B — Notes for counsel

Everything below is working material, not part of the published policy.

## B1. What the app actually does — the factual basis

The policy above was written against these facts, taken from
[`docs/plans/2026-08-15-canadian-card-copilot-mvp-design.md`](../plans/2026-08-15-canadian-card-copilot-mvp-design.md)
and the shipped data model in [`Store/Sources/CardCopilotStore/Models.swift`](../../Store/Sources/CardCopilotStore/Models.swift):

- SwiftUI iPhone app; local-only SwiftData persistence; no accounts, no backend
- one-time `CLLocationManager.requestLocation()` fixes only — never `startUpdatingLocation`,
  never background location, never "Always" authorization
- MapKit POI search (`MKLocalPointsOfInterestRequest` / `MKLocalSearch`) is the *only* outbound
  network activity
- no analytics SDK, no crash SDK, no advertising, no ATT, no bank connection, no payment rail
- `StoredMerchant` persists **latitude/longitude** of confirmed merchants — this is precise
  location data at rest on device, and section 2(d) says so rather than hiding it
- `StoredPrediction.amountCad` is **optional** — section 2(e) says so
- owner state includes `capProgress` figures, i.e. **user-estimated category spend totals**
  (e.g. `momentum-4pct-accountYear: 12500`) — section 2(b) says so

**Sections 7 and 8 describe controls that do not exist in the code yet** (export, per-record
delete, delete-all). They are in the design doc's scope but unbuilt as of 2026-08-15. See
[`submission-readiness.md`](submission-readiness.md) §B. **The policy must not be published before
those ship**, or it becomes a false statement rather than a draft.

## B2. PIPEDA

**[verified]** PIPEDA applies to organizations that collect, use or disclose personal information
"in the course of commercial activities" — s. 4(1)(a); "commercial activity" is defined in s. 2(1)
as "any particular transaction, act or conduct or any regular course of conduct that is of a
commercial character…"; "personal information" is "information about an identifiable individual."
Schedule 1 obligations bind via s. 5(1).
([Justice Laws, PIPEDA](https://laws-lois.justice.gc.ca/eng/acts/P-8.6/page-1.html), checked
2026-08-15.)

**[verified]** Schedule 1 principles relied on: 4.5.3 — "Personal information that is no longer
required to fulfil the identified purposes should be destroyed, erased, or made anonymous";
4.8.1 — "Organizations shall be open about their policies and practices with respect to the
management of personal information"; 4.9 — individual access.
([Justice Laws, Schedule 1](https://laws-lois.justice.gc.ca/eng/acts/P-8.6/page-7.html), checked
2026-08-15.) The ten fair information principles are listed at
[OPC, "PIPEDA requirements in brief"](https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/pipeda_brief/)
(page last modified 2024-05-01, checked 2026-08-15).

**[uncertain] — the threshold question counsel should answer first.** PIPEDA's obligations attach
to an organization that *collects, uses or discloses* personal information. **This app's publisher
does none of the three.** The information is created and held by the user on the user's own device;
the publisher has no copy and no means of obtaining one. On a plain reading, most of Schedule 1
has nothing to attach to.

We have deliberately **not** relied on that reading. The policy is written as if the obligations
applied, because:

1. Apple requires a privacy policy regardless of whether Canadian law does — Guideline 5.1.1(i),
   below.
2. It is the honest thing to give a user who wants to know what the app does with their data.
3. It becomes true the moment any server-side feature ships (remote catalogue, crowdsourced
   merchant observations — both are Phase 2 items in the design doc's §10).

**Question for counsel:** is there any respect in which writing a fuller policy than the law
requires creates an obligation or representation we would not otherwise have? Our assumption is no,
but it is an assumption.

**[uncertain]** Whether a free app distributed by a newly incorporated entity with no revenue is
carrying on a "commercial activity" at all. Not load-bearing — see above — but worth a line in
counsel's memo.

**[verified]** OPC/Alberta/BC joint guidance *Seizing Opportunity: Good Privacy Practices for
Developing Mobile Apps* (2012-10-24) is directly on point and supports the design: "Limit the
collection of personal information to what is needed to carry out legitimate purposes"; tell users
"where it will be stored (on the device or elsewhere)"; "Location information can reveal user
activity patterns and habits"; "Give users the ability to delete the personal information your app
has collected. If they delete the app, their data should be deleted automatically."
([OPC](https://www.priv.gc.ca/en/privacy-topics/technology/mobile-and-digital-devices/mobile-apps/gd_app_201210/),
checked 2026-08-15.) Sections 5, 7 and 8 of the policy track this guidance.

## B3. Quebec — Law 25 / *Act respecting the protection of personal information in the private sector*, CQLR c. P-39.1

All section text below quoted from
[LégisQuébec, P-39.1](https://www.legisquebec.gouv.qc.ca/fr/document/lc/P-39.1), checked
2026-08-15. (LégisQuébec blocks automated fetching; text was read through a browser session.)

**[verified] Scope — s. 1.** The Act governs personal information "qu'une personne recueille,
détient, utilise ou communique à des tiers à l'occasion de l'exploitation d'une entreprise au sens
de l'article 1525 du Code civil."

**[verified] Extraterritorial reach.** The CAI states: "Une organisation située à l'extérieur du
Québec qui recueille, détient, utilise ou communique des renseignements personnels dans le cadre
des activités de son entreprise au Québec est assujettie à la Loi sur le privé."
([CAI, champ d'application](https://www.cai.gouv.qc.ca/protection-renseignements-personnels/information-entreprises-privees/champ-application-loi_entreprises),
checked 2026-08-15.) An Ontario-incorporated publisher shipping to the Canadian App Store is
therefore in scope for Quebec users. **[inference]**

**[verified] s. 3.1** — "Toute personne qui exploite une entreprise est responsable de la
protection des renseignements personnels qu'elle détient… la personne ayant la plus haute autorité
veille… Elle exerce la fonction de responsable de la protection des renseignements personnels" and
the officer's **title and contact details must be published**. → policy §1 and §13. **This is a
real obligation and the placeholder must be filled, not deleted.**

**[verified] s. 8** — at collection, the person must be informed of the purposes, the means of
collection, access and rectification rights, and the right to withdraw consent; and on request, of
the retention period and the privacy officer's contact details. → policy §§2, 5, 7, 8, 13.

**[verified] s. 8.1 — and a correction to the design doc's shorthand.** The section reads: a person
collecting personal information "en ayant recours à une technologie comprenant des fonctions
permettant de l'identifier, de la localiser ou d'effectuer un profilage" must inform the individual
beforehand of "1° du recours à une telle technologie; 2° des moyens offerts pour activer les
fonctions."

**s. 8.1 does not itself say the functions must be deactivated by default.** It requires disclosure
of the means to *activate* them — which presupposes they start deactivated, but the operative
default rule is elsewhere. The design doc's §9 line ("Law 25: location off-by-default with express
consent") reaches the right answer via a slightly wrong route.

**[verified] s. 9.1 — this is the actual "off by default" rule.** "Une personne qui exploite une
entreprise et qui recueille des renseignements personnels en offrant au public un produit ou un
service technologique disposant de paramètres de confidentialité doit s'assurer que, par défaut,
ces paramètres assurent le plus haut niveau de confidentialité, sans aucune intervention de la
personne concernée." (Cookies are carved out; nothing else is.) → policy §5, and the code
constraint that location is off until switched on.

**[verified] s. 14 — consent.** "…doit être manifeste, libre, éclairé et être donné à des fins
spécifiques. Il est demandé à chacune de ces fins, en termes simples et clairs… présentée
distinctement de toute autre information." → the location consent screen must be its own screen
with its own explanation, not a line in a wall of onboarding text.

**[verified] s. 27 ¶3 — portability, and its limit.** The right covers computerized personal
information "recueilli auprès du requérant, **et non pas créé ou inféré** à partir d'un
renseignement personnel le concernant," in "un format technologique structuré et couramment
utilisé," unless that raises "des difficultés pratiques sérieuses."

**[inference]** The app's predictions and confidence scores are *inferred* data and therefore fall
**outside** the statutory portability right. The one-tap export includes them anyway. The policy
does not draw this distinction, on the view that offering more than the law requires needs no
disclaimer — **counsel should confirm that is safe** and not read as a representation about scope.

**[verified] Portability in force since 2024-09-22.**
([CAI, principaux changements — Loi 25](https://www.cai.gouv.qc.ca/protection-renseignements-personnels/sujets-et-domaines-dinteret/principaux-changements-loi-25),
checked 2026-08-15.)

**[verified] ss. 28 / 28.1 — and a second correction.** s. 28 is a **rectification** right. s. 28.1
is a right to require an enterprise to **cease dissemination** of information or **de-index** a
hyperlink, in defined circumstances. **Quebec does not have a general GDPR-style "right to
erasure" in these sections.** Anyone drafting from a template that promises a Quebec "right to be
forgotten" is overstating the statute. The policy's §8 deletion row is framed as a product feature
we provide, not as a statutory right we are honouring — which is the accurate framing given that we
hold nothing.

**[verified] Penalties.** s. 90.1 provides administrative monetary penalties; s. 91 provides penal
fines of "15 000 $ à 25 000 000 $ ou du montant correspondant à 4% du chiffre d'affaires mondial."
Context for how seriously to take the review, not a prediction of exposure.

## B4. Apple's requirement for the policy to exist at all

**[verified] Guideline 5.1.1(i):** "All apps must include a link to their privacy policy in the
App Store Connect metadata field **and within the app in an easily accessible manner**." It must
"Identify what data, if any, the app/service collects, how it collects that data, and all uses of
that data"; confirm third-party protections; and "Explain its data retention/deletion policies and
describe how a user can revoke consent and/or request deletion of the user's data."
([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), checked
2026-08-15.)

Mapping: data identified → §2; how collected → §§2, 5, 6; uses → §§2, 5; third parties → §4 (there
are none) and §6 (Apple, as the OS vendor answering a Maps request); retention/deletion → §7;
revoke consent → §5 and §8.

**Note the "and within the app" half.** A URL in App Store Connect alone does not satisfy 5.1.1(i).
There is no in-app settings screen yet — tracked in
[`submission-readiness.md`](submission-readiness.md) §B.

## B5. Open questions for counsel

1. **Does PIPEDA attach at all** when the publisher never receives the data? (B2.) Does answering
   "we collect nothing" in a published policy create any representation risk?
2. **Language.** Must this policy be published in French for Quebec users? See the Charter analysis
   in [`submission-readiness.md`](submission-readiness.md) §A3. Charter s. 52 covers "les
   catalogues, les brochures, les dépliants, les annuaires commerciaux, les bons de commande et
   tout autre document de même nature qui sont disponibles au public" — **[uncertain]** whether a
   privacy policy is a "document de même nature." Our working assumption is that if the app is
   localized, the policy is localized with it.
3. **Terms of service.** There is none yet. If one is written, Charter s. 55 ("Les contrats
   d'adhésion ainsi que les documents qui s'y rattachent sont rédigés en français") applies to it
   directly and with much less ambiguity than s. 52 does to a privacy policy.
4. **Device backup.** §7 discloses that iOS backups may include the data. Should the app instead
   set `NSURLIsExcludedFromBackupKey` / a stricter Data Protection class on the SwiftData store?
   That is a product decision with a real cost — users would silently lose their history on device
   migration. Flagged, not decided.
5. **The advice disclaimer (§11).** Is it sufficient, given the app outputs dollar figures? It is
   deliberately not styled as a limitation-of-liability clause, because there is no contract to put
   one in.
6. **Trademarks.** The app displays issuer card product names ("American Express Cobalt Card").
   Nominative use, but confirm — and see
   [`submission-readiness.md`](submission-readiness.md) §A8.
