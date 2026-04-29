# RevenueCat + App Store Connect IAP Setup

**Audience:** Carlos, solo founder, never shipped IAP before.
**Goal:** Get UpNext's Single Location subscription working through Apple IAP, end-to-end, before first App Store submission.
**Time estimate:** 2-4 hours (most of that is waiting for ASC records to propagate and capturing the review screenshot).
**Source documents:** [docs/app-store-submission-audit.md](app-store-submission-audit.md) Sections 1 and 4. [CLAUDE.md](../CLAUDE.md) Payments & Subscriptions section.

Work top to bottom. Do not skip steps. Check items off as you go.

---

## Step 1: Decide what to ship

### The question
Should the **Multi-Location $79.99/mo** IAP exist in App Store Connect at first submission?

### Recommendation: NO. Ship Single Location only.

**Reasoning:**
- Multi-Location is marketed as "Coming Soon" in CLAUDE.md. The feature is not built. The Stripe `multi` tier exists, but no shop can actually USE multi-location functionality yet.
- Apple guideline **2.3.1 (Accurate Metadata)** rejects apps that list features, products, or IAPs that aren't usable. If Multi-Location appears as a buyable IAP and a reviewer purchases it, they will look for the multi-location feature, not find it, and reject.
- The audit (Section 4) already confirmed the paywall hides Multi-Location correctly: [`PaywallView.swift:153`](../UpNext/Shared/Views/PaywallView.swift) sets `private let showMultiLocationPlan = false`. Good — leave that flag alone.
- Adding Multi-Location later is a routine app update. You add the IAP in ASC, attach it to the next version, flip `showMultiLocationPlan = true` in the paywall, and resubmit. Nothing about shipping Single Location now blocks shipping Multi later.

**Trade-off you're accepting:** If a Fademasters-adjacent shop owner with two locations downloads v1.0, they only see Single Location pricing. They either subscribe at $49.99/mo for one shop, or they wait. That's fine. You're not losing meaningful revenue at this stage; you're losing rejection risk.

### Marketing surface — what must NOT mention Multi-Location

If you ship Single Location only, every customer-facing surface in the iOS submission must be consistent. Cross-check:

- [ ] **Paywall** — already correct. `showMultiLocationPlan = false` in [`PaywallView.swift:153`](../UpNext/Shared/Views/PaywallView.swift). **Do not flip this flag for v1.0.** If you (or anyone else) edits this file before submission, that change requires explicit approval per CLAUDE.md hard stops.
- [ ] **App Store description** — the audit's draft description (Section 3) already omits Multi-Location. Use that draft. Do not add multi-location language.
- [ ] **App Store keywords** — no "multi-location", "multi-shop", "chain" terms.
- [ ] **App Store screenshots** — if any screenshot shows the paywall, confirm Multi-Location card is not visible. (It won't be, because the flag is off, but verify when capturing the IAP review screenshot in Step 2.)
- [ ] **Promotional text** — the audit's draft promo text doesn't mention it. Keep it that way.
- [ ] **Web (`upnext-app.com`)** — out of scope for App Review, but inconsistency between web ("Multi-Location coming soon") and iOS (silent on it) is fine. Web can keep marketing it as Coming Soon.

> If you decide later you want Multi in v1.0 anyway, stop and re-read this section. The audit explicitly flags 2.3.1 risk. Don't ship a buyable IAP for an unbuilt feature.

---

## Step 2: App Store Connect — create the subscription

You'll be on **appstoreconnect.apple.com** for this step. Sign in with the Apple ID that owns the UpNext app record.

### 2.1 Confirm the app record exists

- [ ] Go to **My Apps**. Confirm UpNext appears.
- [ ] Click into UpNext. Confirm Bundle ID is `com.carlos.upnext.UpNext` (audit Section 1 already verified this matches the Xcode project).
- [ ] If the app record doesn't exist yet: **My Apps → "+" → New App**, fill in name, bundle ID, primary language (English U.S.), SKU (any unique string, e.g. `upnext-ios-001`), full access. Then come back here.

### 2.2 Navigate to Subscriptions

- [ ] In the left sidebar of the app page, find **Monetization → Subscriptions**.
- [ ] If you see "Create your first Subscription Group", that's expected for a brand-new app.

> Apple's exact left-sidebar label has changed over the years. As of this writing (April 2026) the section may be labeled **"Subscriptions"** or **"In-App Purchases and Subscriptions"** under Monetization. If you can't find it, use ASC's search (Cmd+K) for "Subscriptions". I can't guarantee the exact UI label.

### 2.3 Create the Subscription Group

A Subscription Group is the container that lets users upgrade/downgrade between tiers. Even if you only ship one tier today, create a group — you'll add Multi-Location into the same group later.

- [ ] Click **Create Subscription Group** (or **+** next to Subscription Groups).
- [ ] **Reference Name:** `UpNext Subscriptions` (this is internal — only you and Apple's reviewers see it).
- [ ] Save. The group page opens.

> The Subscription Group itself has a **localized display name** that customers DO see in the App Store ("Manage Subscription" UI). Recommend `UpNext`. Set this on the group's localization tab.

### 2.4 Create the Single Location subscription product

Inside the group:

- [ ] Click **Create Subscription** (or **+**).
- [ ] **Reference Name (internal, you'll see this in ASC + RevenueCat):** `Single Location Monthly`
- [ ] **Product ID (this is the canonical string — it must match RevenueCat exactly):** `upnext_base_monthly`
  - **Why this string:** Audit Section 1 inferred `upnext_base_monthly` from RevenueCat's existing config. Use the exact string already in your RevenueCat dashboard. **If RevenueCat has a different string, use that one and update the rest of this doc accordingly.** The two systems must agree on this string or purchases fail silently.
  - **Product IDs are immutable.** Once you save, you cannot rename it. Triple-check spelling, lowercase, underscores not hyphens, before saving.
- [ ] Save the product. ASC opens the product detail page.

### 2.5 Set duration, price, availability

On the product detail page:

- [ ] **Subscription Duration:** `1 Month`.
- [ ] **Subscription Price:**
  - Click **Add Price** or the price field.
  - Select country: **United States** (your primary market).
  - Choose price tier: **USD 49.99** (Apple calls this Tier 50 in the legacy tier system, but the modern UI lets you type the price directly — type `49.99`).
  - Apple will auto-suggest equivalent prices in other currencies. For first launch you can either accept the auto-conversion (ship globally) OR limit availability to US only.
    - **Recommendation:** US-only for v1.0. Path: **Pricing and Availability → Availability → Edit → United States only.** Reduces tax/VAT complexity and matches your testing-at-Fademasters reality.
- [ ] **Family Sharing:** **OFF.** Recommend: leave family sharing disabled. UpNext is a per-shop business subscription. Family Sharing makes sense for media/games where one purchase legitimately benefits a household — not for B2B SaaS where a shared subscription would create multi-account auth chaos.

### 2.6 Localization (Display Name + Description)

Apple requires at least one localization. ASC will reject a subscription with empty localization fields.

- [ ] **English (U.S.) Display Name:** `Single Location` (this is what appears in the iOS Settings → Apple ID → Subscriptions screen)
- [ ] **English (U.S.) Description:** Recommended copy:

  > `Real-time walk-in queue management for one barbershop. Includes live queue, Go Live toggle for barbers, customer check-in via QR/TV/kiosk, and analytics. Renews monthly. Cancel anytime.`

  (231 chars — Apple's limit is 4000 but keep it tight; this is what reviewers and your customers see in subscription management.)

- [ ] Save the localization.

### 2.7 Tax category

- [ ] **Tax Category:** Apple will prompt for one. Pick **"Software as a Service (SaaS)"** if available, otherwise **"Other → Subscriptions"**. UpNext is a recurring SaaS tool, not a media app or game.
  - I don't know exactly which label Apple uses today (the tax category UI changed in 2024 and may have changed again). Pick the closest match for "B2B subscription software". If unsure, contact ASC support — getting tax category wrong only affects how Apple reports your revenue to tax authorities, not the user experience.

### 2.8 Review Screenshot (REQUIRED — this trips up first-time submitters)

Apple requires a screenshot of the IAP itself, separate from the app's screenshots. **Without this, the IAP gets rejected and your app submission gets stuck in "Waiting for Review".**

- [ ] **What to capture:** [`PaywallView.swift`](../UpNext/Shared/Views/PaywallView.swift) rendered on iPhone, showing the Single Location card and the Subscribe button.
- [ ] **Required size:** 640×920 minimum (per Apple's docs). 1290×2796 (your existing iPhone 6.7" screenshot size) is acceptable — Apple resizes down.
- [ ] **How to capture:**
  1. Run the app in iOS Simulator on iPhone 15 Pro Max (or any 6.7" simulator).
  2. Sign in with a fresh test account so the paywall is the first thing you see (or temporarily set `paywallBypassed = false` in DEBUG to force it).
  3. **Cmd+S** in the simulator → screenshot saves to your Desktop.
- [ ] **Upload:** ASC product page → Review Information → Screenshot → drag-drop the file.
- [ ] **Review Notes (optional but useful):** "Paywall appears immediately after sign-in for non-subscribed accounts. Tap Subscribe to start the IAP flow." Helps reviewers find it.

### 2.9 Subscription status

- [ ] **Status starts as "Missing Metadata"** until everything above is complete. Once you've filled in price, localization, tax category, and screenshot, it should flip to **"Ready to Submit"**.
- [ ] Do NOT click "Submit for Review" on the IAP standalone. The IAP gets reviewed alongside the app version — see Step 6.

---

## Step 3: RevenueCat dashboard

You'll be on **app.revenuecat.com** for this step.

### 3.1 Confirm the app project exists

- [ ] Sign in to RevenueCat. Confirm there's a project for UpNext (likely just called "UpNext").
- [ ] Confirm the iOS app is listed under **Project Settings → Apps**. Bundle ID should be `com.carlos.upnext.UpNext`.

### 3.2 Add the Apple App Store product

- [ ] Sidebar → **Products** (under "Product Catalog" or similar).
- [ ] Click **+ New** or **Add Product**.
- [ ] **Store:** `App Store`.
- [ ] **App Store product identifier:** `upnext_base_monthly` — **must match the Product ID you set in ASC step 2.4 exactly.** Lowercase, underscores. Copy-paste from ASC to be safe.
- [ ] **Display name (RC internal):** `Single Location Monthly`
- [ ] Save. RevenueCat will validate the product against ASC. If validation fails, the product ID doesn't match — go back to ASC and confirm the spelling.

> **Common gotcha:** RevenueCat won't successfully validate a brand-new ASC product for up to a few hours after you create it in ASC. If you get a "product not found" error, wait 30-60 minutes and retry. This delay is on Apple's side, not RevenueCat's.

### 3.3 Verify the `UpNext Pro` entitlement

[`SubscriptionManager.swift:18-21`](../UpNext/Shared/Services/SubscriptionManager.swift) expects two entitlement names: `UpNext Pro` (any active subscription) and `UpNext Multi` (multi-location only).

- [ ] Sidebar → **Entitlements**.
- [ ] If `UpNext Pro` doesn't exist, click **+ New Entitlement**, name it exactly `UpNext Pro` (capitalization matters — Swift code uses this exact string), and save.
- [ ] Open the `UpNext Pro` entitlement → **Attached Products** → add the `upnext_base_monthly` product you just created.
- [ ] Confirm: when a customer buys Single Location, RevenueCat will grant the `UpNext Pro` entitlement. iOS will read `customerInfo.entitlements["UpNext Pro"]?.isActive == true` and `isSubscribed` will be `true`.

### 3.4 `UpNext Multi` entitlement — leave alone for now

Since you're NOT shipping Multi-Location at v1.0:

- [ ] If `UpNext Multi` already exists with no products attached: leave it. Empty entitlement is harmless.
- [ ] If it doesn't exist: don't create it. You'll create it the day you ship Multi-Location.
- [ ] Either way: the Swift code referencing `UpNext Multi` will simply return `false` on `isSubscribedToMulti`, which is the correct behavior pre-launch.

### 3.5 Offerings (optional but recommended)

RevenueCat's "Offerings" feature lets you group products into named bundles for the paywall. The current paywall code may or may not use Offerings — check [`SubscriptionManager.swift`](../UpNext/Shared/Services/SubscriptionManager.swift) for `Offerings.current` references.

- [ ] If the code uses Offerings: in RC dashboard, **Offerings → Current Offering → Packages → add the `upnext_base_monthly` product as the "Monthly" package.**
- [ ] If the code uses raw product fetching (no Offerings): skip this step.

> I don't have the exact contents of SubscriptionManager.swift loaded. Check the file before this step — if you see `Purchases.shared.offerings()` anywhere, you need an Offering configured. If you only see direct product purchases by ID, you don't.

### 3.6 API key — verify, don't change

- [ ] In RC dashboard, **Project Settings → API Keys → Public iOS SDK key.** Copy it.
- [ ] Open [`UpNextApp.swift`](../UpNext/UpNextApp.swift) (audit Section 5 noted hardcoded keys around lines 20-23).
- [ ] Confirm the key in code matches the RC dashboard.
- [ ] **If they don't match:** the iOS app cannot communicate with RevenueCat at all. Purchases will fail before they even reach Apple. Update the key in code (this is a code change — flag it before commit, but it's not subscription-logic-changing so the hard-stop concern is lighter).
- [ ] **If they match:** good. Move on.

> **Note:** Public SDK keys are public-by-design — fine in source. Don't confuse them with the **Secret API key** in RC dashboard, which must NEVER appear in client code.

---

## Step 4: Sandbox testing — before you submit anything

You will not catch IAP problems in the iOS Simulator. **IAP only works on a real device with a sandbox tester Apple ID.** This is the single most common reason first-time submitters waste a TestFlight cycle.

### 4.1 Create a sandbox tester

- [ ] ASC → **Users and Access** (top nav) → **Sandbox** tab → **Testers** subsection.
- [ ] Click **+** → fill in:
  - **First name / last name:** anything (e.g. `Test User`)
  - **Email:** **must be an email address NOT already linked to any Apple ID.** Use a `+sandbox` alias if your domain supports it (e.g. `ccanales71+sandbox1@gmail.com` — Gmail aliases work).
  - **Password:** anything you'll remember.
  - **Country / Region:** United States (matches your IAP availability).
  - **Date of birth:** anything 18+.
- [ ] Save. The tester is now usable.

> **Critical gotcha:** If you accidentally type an email that already has an Apple ID, the tester creation appears to succeed but the IAP flow on device will fail with "this Apple ID has not yet been used in the iTunes Store". Use a brand-new alias.

### 4.2 Sign the sandbox tester into your iPhone

iOS's sandbox login is hidden specifically to keep regular users from finding it.

- [ ] On your iPhone: **Settings → App Store** → scroll to bottom → **Sandbox Account** section → **Sign In** → use the sandbox tester email + password.
- [ ] **Do NOT sign out of your real Apple ID at the top of Settings.** The sandbox account ONLY needs to be active in the Sandbox Account slot.
- [ ] If you don't see a "Sandbox Account" section: you've never run a development build of an IAP-enabled app on this device. Build and run UpNext from Xcode to your iPhone first (Product → Run, with the iPhone connected). After the first run, the Sandbox Account slot will appear in Settings.

### 4.3 Test the purchase

- [ ] Open the development build of UpNext on your iPhone.
- [ ] Sign in with a fresh Firebase Auth account (one that does NOT have an active subscription in Firestore — otherwise the paywall will be bypassed).
- [ ] Confirm the paywall renders. Tap **Subscribe**.
- [ ] iOS shows the IAP confirmation sheet. It will say something like **"[Sandbox] Confirm Subscription"** with the price and "Sandbox" prefix — that's how you know you're testing for free.
- [ ] Tap **Subscribe** / authenticate with Face ID.
- [ ] After a few seconds, the app should:
  1. Receive the RevenueCat callback,
  2. Update `subscriptionManager.isSubscribed = true`,
  3. Dismiss the paywall, and
  4. Land you in the main app (owner dashboard or kiosk).

### 4.4 What "successful test" looks like — verify all four

- [ ] **App-side:** Paywall dismisses. You're in the app. No error toasts.
- [ ] **RevenueCat dashboard side:** Sidebar → **Customers** → search for your sandbox email → confirm a transaction is logged with `upnext_base_monthly`, status `active`, entitlement `UpNext Pro` granted.
- [ ] **Firestore side (only if your code syncs RC → Firestore — most apps don't):** Look at the user's shop doc. If `subscriptionStatus` updates from RC, confirm it. If not (current UpNext architecture: iOS → web sync does NOT happen — see CLAUDE.md "Known gap"), this is expected and fine.
- [ ] **Logs side (Xcode console):** Look for RevenueCat log lines. No "purchase failed" errors. The `isSubscribed` value flipped from `false` to `true`.

> **If any of those four don't pass: do not submit.** Debug first. The most common failure is a product ID mismatch between ASC and RC — re-check Step 2.4 vs Step 3.2. The second most common is RevenueCat API key drift — re-check Step 3.6.

### 4.5 Test resubscription / restore

- [ ] After a successful purchase, force-quit the app and relaunch. Confirm `isSubscribed = true` persists (RevenueCat caches the entitlement).
- [ ] Sign out of the sandbox account (Settings → App Store → Sandbox Account → Sign Out). Sign back in. Open app. **Tap "Restore Purchases"** on the paywall (if visible) — confirm the entitlement comes back.
  - If there's no Restore Purchases button: that's a separate issue Apple WILL flag. Guideline 3.1.1 requires a Restore button on any IAP paywall. Check the paywall — if missing, hand to Feature Builder.

### 4.6 The 30-day money-back guarantee — clarify your messaging

This is non-obvious for first-time IAP shippers and worth stating explicitly:

- **Apple controls iOS refunds.** When an iOS subscriber asks for a refund, the path is **reportaproblem.apple.com** → Apple decides (usually approves within 48 hours for first-time refund requests). UpNext / Carlos has no role in this.
- **Stripe (web) is different.** Carlos can issue full refunds directly through the Stripe dashboard. The 30-day money-back guarantee is meaningful and Carlos-controlled on web.
- **What you're allowed to say in App Store metadata:** You can mention "30-day money-back guarantee" generally, but **do NOT** imply you'll override Apple's refund process or that customers should email you for a refund instead of using Apple's process. Apple sometimes flags this under guideline 3.1.1 ("you cannot direct users away from Apple's IAP system") if it sounds like you're substituting your own refund process for Apple's.
- **Recommended language for App Store description:** "30-day money-back guarantee — not for you? Email support@upnext-app.com." (This is what the audit's draft already uses. Acceptable because it's a support invitation, not an instruction to bypass Apple.)
- **What you must NOT say:** "Email us for a refund" without qualification, or "We refund within 30 days regardless of Apple's policy." That reads as undermining Apple's process.

---

## Step 5: Common rejection / setup pitfalls

Read each one. Confirm you're not committing it.

- [ ] **Product IDs not matching between ASC and RevenueCat → purchases fail silently.** The single most common first-submission disaster. The user taps Subscribe, the IAP sheet appears, the purchase "succeeds" at Apple's end, but RevenueCat can't find the product so the entitlement never grants. The app stays on the paywall. From the user's perspective, they paid and nothing happened. Re-check Step 2.4 ↔ Step 3.2 character-for-character.
- [ ] **Missing Review Screenshot on the IAP product → submission stuck.** No error message will tell you this clearly. The app sits in "Waiting for Review" past the typical 24-48hr window. Check ASC → IAP → status. If it says "Missing Metadata" — upload the screenshot.
- [ ] **Subscription Group Display Name vs Reference Name confusion.** The Reference Name is internal. The **Display Name on the localization tab is what users see** in iOS Settings → Subscriptions. If you leave the display name as something internal-sounding, users see "UpNext Subscriptions Group" or worse. Set it to `UpNext`.
- [ ] **Missing "Subscription Terms" disclosure on the paywall.** Audit Section 1 already verified [`PaywallView.swift:330-332`](../UpNext/Shared/Views/PaywallView.swift) has the auto-renew disclosure text. Good. **But the paywall is also missing tappable Terms of Use + Privacy Policy LINKS** (audit Section 1 BLOCKER). Carlos must either:
  - (a) hand the link addition to Feature Builder before submission, OR
  - (b) accept the rejection risk and add them post-rejection.
  - I recommend (a). It's a 5-minute code change and a near-certain rejection if skipped.
- [ ] **Required disclosure text format.** Apple's standard is along the lines of: *"Auto-renewable subscription. Cancel anytime in Settings > Apple ID > Subscriptions. Payment is charged to your Apple ID account at confirmation of purchase."* The current paywall has this — keep it. Don't paraphrase it into something cuter.
- [ ] **Don't put `WACO` (or any promo code) anywhere in App Store metadata or screenshots.** Apple guideline 3.1.1 prohibits incentives for downloads. WACO is fine to use privately for Waco-area shops via your own channels — but not visible on the App Store.
- [ ] **Don't ship a purchase flow that mentions Stripe.** iOS digital subscriptions MUST go through Apple IAP. Mentioning Stripe, web checkout, or "save 10% by signing up on our website" inside the iOS app violates 3.1.3(a) and gets rejected. Web is web; iOS is iOS. Keep them separate in messaging.

---

## Step 6: Submission day checklist

When everything above is green, you're ready. Final pre-submit pass:

- [ ] **IAP product status in ASC = "Ready to Submit"** (not "Missing Metadata", not "Developer Action Needed").
- [ ] **IAP attached to the app version being submitted.** This is a separate checkbox per ASC version. Path: ASC → app → **App Store** tab → version 1.0 → scroll to **In-App Purchases and Subscriptions** section → click **+** → select `Single Location Monthly` → save. Without this attachment, Apple reviews the app without the IAP and your paywall won't have a product to show — instant rejection.
- [ ] **Sandbox tester credentials populated in ASC App Review Information notes.** Path: ASC → app → version 1.0 → **App Review Information** section → **Notes**. Add:
  > `Demo account for App Review:`
  > `Email: appreview@upnext-app.com`
  > `Password: [your chosen password]`
  > `This account has an active subscription via Firestore (subscriptionStatus = "active") so reviewers can access the full app without going through IAP. To also test the IAP flow, use any sandbox tester Apple ID — the paywall will appear for non-subscribed accounts and Subscribe will trigger the standard sandbox IAP sheet.`
  > `Kiosk mode: log in as owner, tap Kiosk tab, tap Launch Kiosk. To exit: long-press bottom-right corner 2 seconds, enter PIN 1234.`
- [ ] **App Review Information → Sign-in required = YES**, with the demo account credentials in the username/password fields too (separate from the Notes).
- [ ] **Privacy Manifest (`PrivacyInfo.xcprivacy`)** is in the build (audit Section 1 BLOCKER — needs Feature Builder if not done yet).
- [ ] **Paywall has tappable Terms + Privacy links** (audit Section 1 BLOCKER — needs Feature Builder if not done yet).
- [ ] **Sandbox-tested the purchase flow end-to-end on a real device** (Step 4.4 all four green).
- [ ] **App version (Marketing) = 1.0**, **Build number ≥ 1** and unique (audit Section 1 — bump from previous TestFlight upload if any).
- [ ] **Export Compliance answered** (audit Section 1: HTTPS exemption applies, recommend adding `ITSAppUsesNonExemptEncryption = NO` to Info.plist).
- [ ] **Age Rating answered** → 4+ (audit Section 1).
- [ ] **App Privacy questionnaire complete** in ASC (audit Section 1).
- [ ] **Screenshots uploaded:** 5-7 iPhone (1290×2796) + 3-5 iPad (2064×2752 or 2048×2732). Audit Section 2.

When all of the above are checked, click **Submit for Review** at the top of the version page.

Expect first-review turnaround of 24-72 hours. If rejected, the rejection note will tell you which guideline; fix and resubmit (resubmissions usually review faster, 12-24hr).

---

## Items you must verify yourself — I cannot confirm these

These are documented in audit Section "Items I couldn't verify" but listed again here because they intersect IAP setup:

1. **App Store Connect record exists** for `com.carlos.upnext.UpNext` and is past the "Prepare for Submission" placeholder state.
2. **In-App Purchase capability is enabled** for the App ID in developer.apple.com → Certificates, IDs & Profiles → Identifiers → tap App ID → Capabilities tab. Without this checkbox, IAP will fail at runtime with no useful error.
3. **Banking and Tax info** is filled in ASC → Business → Agreements, Tax, and Banking. **You cannot ship a paid app or IAP until this is complete.** First-time setup takes a few days because Apple verifies banking. Start this NOW if you haven't.
4. **The exact RevenueCat product ID string** in your existing dashboard configuration. If it's not `upnext_base_monthly`, use whatever's already there — don't rename, that creates a worse mess.

---

## When this is done, what you have

- Single Location Monthly IAP live in App Store Connect, $49.99/mo, ready to submit.
- RevenueCat product mapping verified, `UpNext Pro` entitlement attached.
- Sandbox-tested purchase flow on a real device, end-to-end green.
- Reviewer can access the app via demo account; reviewer can also test the IAP via Apple's standard sandbox path.
- Multi-Location is intentionally absent — adds in v1.1 once the feature actually ships.

After approval, **monitor Carlos's first 5-10 real subscribers closely.** RevenueCat dashboard → Customers. Watch for purchases that complete on Apple's side but don't grant entitlements (sign of a config drift). Catch problems while you have small N.
