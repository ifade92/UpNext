# UpNext IAP — Live Walkthrough

Click-by-click guide for completing the App Store Connect + RevenueCat IAP setup, given UpNext's actual current state.

**Companion docs:**
- `docs/revenuecat-asc-setup.md` — higher-level architecture + decisions
- `docs/app-store-submission-audit.md` — full pre-submission audit

**Carlos's state when this walkthrough was written:**
- Subscription Group "UpNext Plans" (Group ID 22029013) exists
- Two products at "Missing Metadata":
  - Level 1: `upnext_multi_monthly` (UpNext Multi-Location)
  - Level 2: `upnext_base_monthly` (UpNext Base)
- Goal for v1.0: ship `upnext_base_monthly` only; sideline `upnext_multi_monthly` until Multi-Location feature is built

---

## Step 1: Sideline `upnext_multi_monthly` for v1.0

**Important:** ASC won't let you fully delete a subscription product once it's created. Product IDs are reserved forever. Real options:

- **Don't submit it with the app version** (don't attach to v1.0)
- **Set "Cleared for Sale" = No** so even if approved it wouldn't appear

Cleanest = both.

### 1a. Don't fill out its metadata

- [ ] In the subscription group, click into **UpNext Multi-Location** (`upnext_multi_monthly`).
- [ ] **Leave it at "Missing Metadata".** No price, no localization, no screenshot. As long as it's missing metadata, Apple physically cannot review or approve it.
- [ ] **Do NOT click "Submit for Review"** on this product.

That's enough on its own. But to be safe:

### 1b. Set Cleared for Sale = No (defensive)

- [ ] On the `upnext_multi_monthly` detail page, find **Availability** or **Pricing and Availability** section.
- [ ] Look for a toggle labeled **"Cleared for Sale"** or **"Available for Sale"**. Set to **No** / **Off**.
- [ ] If you don't see this toggle, it may only appear once metadata is filled. Skip — Missing Metadata is already a hard block.

### 1c. What you should NOT do

- [ ] **Do NOT delete the subscription group "UpNext Plans".** That nukes Base too.
- [ ] **Do NOT click "Remove from Submission"** if you see it — that's for products previously attached to a version. Yours hasn't been, so the option may not appear.
- [ ] **Do NOT try to rename `upnext_multi_monthly`.** Product IDs are immutable. When you're ready for Multi later, you'll reuse this exact ID.

### Result

`upnext_multi_monthly` sits in the **UpNext Plans** group at status **Missing Metadata**, untouched. v1.1 with Multi-Location → come back, fill metadata, attach to v1.1's version, ships. Zero rework.

**✅ Tick when done:** `upnext_multi_monthly` left at Missing Metadata, will not be attached to v1.0.

---

## Step 2: Complete `upnext_base_monthly` Metadata

Click into **UpNext Base** (`upnext_base_monthly`).

### 2a. Subscription Duration

- [ ] Confirm **1 Month** (already set per screenshot). Don't change.

### 2b. Subscription Price

- [ ] Click **Add Subscription Price** (or Pricing → Edit).
- [ ] **Country/Region:** **United States** as the base.
- [ ] **Price:** type **`49.99`** USD directly. (If old-style tiers UI: $49.99 = **Tier 50**.)
- [ ] When ASC asks "Apply price to other countries?" → **"Don't Apply"**. You're going US-only.

### 2c. Availability

- [ ] Find **Availability** section.
- [ ] Click **Edit** → **Deselect All** countries → check **United States** only → Save.

### 2d. App Store Localization (English U.S.) — REQUIRED

- [ ] Find **App Store Localization** section. Click **+** or **Add Localization** → **English (U.S.)**.

Fields:

- [ ] **Subscription Display Name** (max 30 chars):
  ```
  Single Location
  ```
  *(Customer sees this in iOS Settings → Apple ID → Subscriptions, already grouped under "UpNext". So they see "UpNext > Single Location". Don't prefix with "UpNext —".)*

- [ ] **Description** (max 45 chars):
  ```
  Walk-in queue for one barbershop.
  ```
  *(33 chars. 45 is a hard limit.)*

- [ ] Save.

### 2e. Promotional Image (optional)

- [ ] Skip for v1.0. Not a blocker.
- [ ] If you want to add: 1024×1024 PNG, no transparency, UpNext logo on Deep Green (`#0D2B1A`).

### 2f. Review Information → Screenshot (REQUIRED — the trap)

Apple wants a screenshot of the *paywall as the customer sees it*, separate from your app screenshots.

- [ ] **What to capture:**
  - The Single Location card visible
  - The "Subscribe" button (CTA visible)
  - The auto-renew disclosure text underneath
  - **Multi-Location card NOT visible** (correct since `showMultiLocationPlan = false`)

- [ ] **How to capture from iPhone 17 Pro:**
  1. Build & run UpNext on the iPhone (Subscribe button being greyed out is fine — Apple just wants the layout)
  2. Press **Side button + Volume Up** to screenshot
  3. AirDrop the PNG to your Mac

  *Alternative: capture from iPhone 15 Pro Max simulator with mock data if you want a non-greyed Subscribe button. Either works.*

- [ ] **Required size:** 640×920 minimum. Your iPhone 17 Pro screenshots are ~1290×2796 — Apple resizes down. Don't manually resize.

- [ ] **Upload:** Review Information → Screenshot field → drag-drop the PNG.

### 2g. Review Notes

- [ ] In **Review Information → Notes**, paste:
  ```
  This subscription appears on the paywall shown immediately after a new
  user signs up and creates their shop. Tap "Subscribe" on the Single
  Location card to start the IAP flow. The Multi-Location feature is not
  yet released and the corresponding IAP product is intentionally not
  submitted with this app version.
  ```

### 2h. Tax Category

- [ ] Choose **"Software as a Service (SaaS)"** if available, else **"Other → Subscriptions"**. Closest match for B2B software. Doesn't affect UX or block submission.

### 2i. Family Sharing

- [ ] Confirm **OFF**. UpNext is per-shop B2B; family sharing makes no sense.

### 2j. Status check

- [ ] Save everything. Refresh.
- [ ] Status should flip from **Missing Metadata** → **Ready to Submit**.
- [ ] If still Missing Metadata, scroll for red asterisks. Most common miss: forgot review screenshot.

**✅ Tick when done:** `upnext_base_monthly` shows status **Ready to Submit**.

---

## Aside: App's Apple-listing name

Your app is currently listed as **"UpNext - Walk-In Manager"** in ASC. Audit Section 3 recommended:
- **App name:** `UpNext: Walk-In Queue` (21 chars)
- **Subtitle:** `Walk-in queue for barbers` (25 chars)

If "UpNext - Walk-In Manager" is the App Name field, your **Subtitle slot is empty** — you're losing 30 chars of search real estate. Worth checking before submission. Not blocking IAP work.

---

## Step 3: RevenueCat Dashboard

Go to **app.revenuecat.com**. Mostly verifying existing config.

### 3a. Confirm the iOS app entry

- [ ] Sidebar → **Project Settings** → **Apps** tab.
- [ ] Confirm iOS app listed with bundle ID `com.carlos.upnext.UpNext`.
- [ ] Red banner about missing API key / shared secret? Tell me — separate fix.

### 3b. Verify the product exists in RC

- [ ] Sidebar → **Products**.
- [ ] Look for `upnext_base_monthly`.
- [ ] **If exists:** confirm Store=App Store, Identifier=`upnext_base_monthly` (lowercase, underscores).
- [ ] **If missing:** **+ New** → Store=App Store → Identifier=`upnext_base_monthly` → save.

> **Gotcha:** RC validates against ASC. If you JUST created the ASC product, RC may not see it for **30-60 minutes** (Apple propagation delay). Coffee, retry.

### 3c. Verify the `UpNext Pro` entitlement (CRITICAL)

`SubscriptionManager.swift` checks for entitlement string **`UpNext Pro`** exactly. Wrong name = purchases succeed but app never grants access.

- [ ] Sidebar → **Entitlements**.
- [ ] Confirm `UpNext Pro` exists. Capitalization: **U**p**N**ext space **P**ro.
- [ ] Open it → **Attached Products** → confirm `upnext_base_monthly` is attached. If not, add it.

### 3d. `UpNext Multi` entitlement — leave alone

- [ ] If exists with no products → leave it. Empty is harmless.
- [ ] If doesn't exist → don't create.

### 3e. Offerings

The greyed-out Subscribe button = SubscriptionManager fails to load products. Most likely cause: **no Offering configured**.

- [ ] Sidebar → **Offerings**.
- [ ] No "Current" Offering? Click **+ New Offering** → name `default` → save.
- [ ] Open → **Add Package** → choose **Monthly** package type → attach `upnext_base_monthly` → save.
- [ ] Mark as **Current** (star or "Set as Current" button).

### 3f. iOS API key

- [ ] RC dashboard → **Project Settings → API Keys** → **Public iOS SDK key**. Copy.
- [ ] Compare against the key hardcoded in `UpNextApp.swift` (lines 20-23 per audit Section 5). Don't share — just confirm match.
- [ ] Mismatch alone explains greyed Subscribe. Update code → rebuild → retest.
  - **This counts as subscription code change** per CLAUDE.md hard stops — flag before commit.

**✅ Tick when done:** product in RC, `UpNext Pro` entitlement has `upnext_base_monthly`, Offering configured, API key verified.

---

## Step 4: Sandbox Testing on iPhone 17 Pro

After Steps 2 + 3, products should load and Subscribe button should activate.

### 4a. Create a sandbox tester account

- [ ] ASC → top nav → **Users and Access** → **Sandbox** tab → **Test Accounts**.
- [ ] **+** → fill:
  - Name: anything (e.g., `Test One`)
  - **Email:** must NOT already be linked to an Apple ID. Use Gmail alias: **`ccanales71+upnext-sandbox1@gmail.com`** (Gmail ignores `+suffix`, emails go to your real inbox; Apple sees unique address)
  - **Password:** 8+ chars, upper/lower/number
  - **Country/Region:** **United States** (must match Step 2c)
  - DOB: 18+

- [ ] Save.

> **Trap:** if you use an email already on a real Apple ID, the tester saves but every IAP fails with "this Apple ID has not been used in the iTunes Store." No fix except creating a new tester. Use a fresh alias.

### 4b. Sign sandbox tester into iPhone 17 Pro

iOS hides this on purpose.

- [ ] On iPhone: **Settings** → scroll to **App Store** → scroll to bottom → **Sandbox Account** → **Sign In**.
- [ ] Enter sandbox email + password.
- [ ] **Do NOT sign out of your real Apple ID at the top.** Sandbox slot is parallel.
- [ ] **No "Sandbox Account" section visible?** Build & run UpNext from Xcode to the device first. After first IAP-enabled build, refresh Settings → App Store.

### 4c. Run the actual purchase

- [ ] Xcode → **Run** to install latest build.
- [ ] Sign in with a Firebase Auth account that does NOT have an active subscription. (Existing test owner has one in Firestore → paywall bypassed → won't hit IAP. Create a fresh email/password account through signup.)
- [ ] Paywall renders. **Subscribe button should be ACTIVE** = products loaded.
- [ ] Tap **Subscribe**.
- [ ] iOS IAP confirmation sheet:
  - Look for **`[Sandbox]`** prefix or "Sandbox" text — confirms test mode
  - Price: **$49.99/month**
  - Auto-renew language
- [ ] Authenticate (Face ID or sandbox password).
- [ ] Wait 5-15 seconds (sandbox is slower than production).
- [ ] App should: dismiss paywall, transition to owner dashboard.

### 4d. Four success criteria — all must pass

- [ ] **App side:** Paywall dismissed. In owner UI. No error.
- [ ] **RevenueCat side:** RC dashboard → **Customers** → search sandbox email → transaction logged with `upnext_base_monthly`, status `active`, entitlement `UpNext Pro` granted.
- [ ] **Xcode console side:** No "purchase failed" / "product not found" errors. RC log lines confirm entitlement granted.
- [ ] **Firestore side (will likely show NO change):** Per CLAUDE.md, iOS → Firestore subscription sync **doesn't exist**. RC doesn't write back to Firestore. This is expected. iOS reads RC directly via `subscriptionManager.isSubscribed`, not Firestore.

### 4e. If it fails — three usual suspects

1. **Product ID mismatch ASC ↔ RC** → re-check Step 2 vs Step 3b, character-for-character.
2. **Apple's propagation delay** → just-created ASC product, wait 30-60 min, retry.
3. **`UpNext Pro` entitlement not attached to product** → re-check Step 3c. Purchase succeeds, app sees `isSubscribed = false`, paywall doesn't dismiss.

Anything weirder → paste Xcode console output.

### 4f. Bonus — restore purchases

- [ ] After purchase, **delete app** (long-press → Remove App).
- [ ] Reinstall via Xcode.
- [ ] Sign in with same Firebase account.
- [ ] Should land past paywall — RC remembers entitlement.
- [ ] If paywall reappears: tap **Restore Purchases** (must exist per Apple 3.1.1).

**✅ Tick when done:** all four 4d criteria green.

---

## Step 5: Submission Day Checklist

### 5a. Attach IAP to app version

Most-forgotten step.

- [ ] ASC → My Apps → UpNext → **App Store** tab → version 1.0.
- [ ] Scroll to **In-App Purchases and Subscriptions**.
- [ ] **+** (or **Edit**) → select **`upnext_base_monthly`** → save.
- [ ] **Do NOT attach `upnext_multi_monthly`.** Stays unattached.

Skip this step → Apple reviews the app, paywall has no products, blank Subscribe button → rejected under 2.1 (App Completeness).

### 5b. App Review Information — sign-in credentials

- [ ] ASC → version 1.0 → **App Review Information**.
- [ ] **Sign-in required:** YES.
- [ ] **Username:** `appreview@upnext-app.com` (create Firebase Auth account + Firestore shop with `subscriptionStatus: "active"`, `subscriptionTier: "base"`, plus seed barbers per audit).
- [ ] **Password:** whatever you set.

### 5c. Notes for the reviewer

- [ ] **Notes** field, paste:

```
DEMO ACCOUNT
Email: appreview@upnext-app.com
Password: [the password you set]

This account has an active Stripe subscription (subscriptionStatus = "active",
tier = "base") so reviewers can access the full app without going through IAP.

TO TEST THE IAP FLOW DIRECTLY
1. Sign out of the demo account
2. Tap "Sign Up" on the login screen
3. Create any new account (use any sandbox tester Apple ID for the IAP)
4. The paywall will appear. Tap "Subscribe" on the Single Location card to
   trigger the standard sandbox IAP sheet.
5. The price is $49.99/month. Use any sandbox tester payment method —
   no real card needed.

KIOSK MODE (iPad only)
1. Log in as the owner (demo account works)
2. Tap the "Kiosk" tab
3. Tap "Launch Kiosk"
4. To exit: long-press the bottom-right corner for 2 seconds, enter PIN 1234

The Multi-Location subscription product visible in our subscription group is
intentionally not attached to this version. The Multi-Location feature is
planned for a future release.
```

### 5d. Other audit blockers — verify before submit

Three non-IAP items that block submission:

- [ ] **PrivacyInfo.xcprivacy in build** — verify in Xcode that file is included in UpNext target. ✅ Already done in this session.
- [ ] **Paywall has tappable Terms + Privacy links** — ✅ Already done & deployed.
- [ ] **Build number bumped** if not literal first TestFlight upload — leave at 1, this is first build.
- [ ] **`ITSAppUsesNonExemptEncryption = NO` in Info.plist** — ✅ Already done.

### 5e. Submit

- [ ] Version page fully green (no red badges) → **Add for Review** → **Submit for Review**.
- [ ] First review: 24-72 hours. Resubmissions: 12-24 hours.

---

## Quick reference — pending blockers stack-ranked

1. **Greyed-out Subscribe button.** Step 2 + Step 3 fix. Highest priority — until fixed, can't sandbox-test, can't submit.
2. **Sandbox-test full purchase flow** (Step 4). Cannot ship without this.
3. **Demo Firestore account seeded** for reviewer (Step 5b — manual Firestore add).
4. **iPad screenshots** (separate from this walkthrough — capture from iPad simulator).
5. **Submit.**

---

## Strategic note

The `pendingSubscriptions` handoff (BUG-001) is **not** a submission blocker — Apple reviewers use Apple's IAP path, never the web→iOS handoff. But once you ship and start running real signup traffic, anyone who pays via Stripe on web before opening the iOS app will be visibly broken. Plan v1.0.1 to fix within 2-4 weeks of launch, or actively route new signups through iOS-first until fixed.
