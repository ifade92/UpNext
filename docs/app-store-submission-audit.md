# UpNext — App Store Submission Audit

**Date:** 2026-04-27
**Audit scope:** First submission readiness — Xcode project, ASC metadata fields, screenshots, App Review risk surface.
**Source of truth verified against:** `project.pbxproj`, `Info.plist`, `UpNext.entitlements`, `ContentView.swift`, `PaywallView.swift`, `NotificationManager.swift`, `SubscriptionManager.swift`, `UpNextApp.swift`, `Assets.xcassets/AppIcon.appiconset/`.

---

## CRITICAL FINDING — Project structure is NOT what CLAUDE.md describes

CLAUDE.md says UpNext-Barber and UpNext-Kiosk are two targets. **They aren't.** [`project.pbxproj`](project.pbxproj) shows a **single target** named `UpNext` (bundle ID `com.carlos.upnext.UpNext`) with `TARGETED_DEVICE_FAMILY = "1,2"` — meaning **one universal app that runs on iPhone AND iPad**. The "kiosk" is a `fullScreenCover` mode inside the same app ([`ContentView.swift:165`](UpNext/ContentView.swift)). This is good news for submission: **one app, one listing, one set of metadata**. But it changes the screenshot story (universal app needs both iPhone and iPad screenshots) and the App Review story (the same binary must satisfy both surfaces).

CLAUDE.md should be updated, but that's not part of this audit.

---

## Section 1: Submission blockers (must fix before submitting)

### Bundle ID, version, build number
- [ ] **Confirm App Store Connect record uses bundle ID `com.carlos.upnext.UpNext`** — set in [`project.pbxproj:413`](project.pbxproj) (Debug) and [`project.pbxproj:445`](project.pbxproj) (Release). ASC: My Apps → UpNext → App Information → Bundle ID.
- [ ] **Bump build number from 1.** `CURRENT_PROJECT_VERSION = 1` in [`project.pbxproj:431`](project.pbxproj). Every TestFlight upload needs a unique build. Increment to `1` only if this is your literal first upload, otherwise `2`+. Xcode → target → General → Build.
- [ ] **Marketing version is `1.0`** ([`project.pbxproj:444`](project.pbxproj)) — fine for first submission. Match this in ASC → Version Information.

### Signing & capabilities
- [x] **Push entitlement present.** [`UpNext.entitlements`](UpNext/UpNext.entitlements) sets `aps-environment = production`. Correct for App Store submission.
- [x] **Background mode for remote notifications present.** [`Info.plist:11-14`](UpNext/Info.plist) has `UIBackgroundModes: remote-notification`.
- [ ] **Verify Push Notifications capability is enabled in Apple Developer Portal for the App ID** `com.carlos.upnext.UpNext`. Path: developer.apple.com → Certificates, IDs & Profiles → Identifiers → tap your App ID → Capabilities tab → "Push Notifications" must be checked. Apple requires both the entitlement AND the capability registered on the App ID, otherwise APNs token registration fails on the device. *(unverified — check yourself in the portal.)*
- [ ] **APNs Auth Key uploaded to Firebase.** Firebase Console → Project Settings → Cloud Messaging → Apple app configuration. NotificationManager.swift's setup checklist (lines 26-34) calls this out as a prerequisite. *(unverified — check yourself.)*
- [ ] **No IAP entitlement is required** — StoreKit/RevenueCat doesn't need one, but the **In-App Purchase capability must be enabled in Apple Developer Portal** for the App ID. Same path as Push Notifications above. *(unverified — check yourself.)*
- [ ] **Code signing is Automatic** ([`project.pbxproj:398`](project.pbxproj)) with team `3GJHYKLCPV`. Confirm in Xcode → target → Signing & Capabilities → "Automatically manage signing" checked, team selected, no red errors.

### Privacy Manifest (`PrivacyInfo.xcprivacy`) — BLOCKER
- [ ] **No `PrivacyInfo.xcprivacy` exists in the project.** I searched the entire worktree — not present. Required since May 1, 2024 for any app that links Firebase, RevenueCat, or other "commonly used" SDKs. Apple will warn or reject on submission.
  - **What to do:** Add a `PrivacyInfo.xcprivacy` file to the app target. Declare:
    - `NSPrivacyTracking` = false (UpNext does not track users across other companies' apps)
    - `NSPrivacyTrackingDomains` = empty array
    - `NSPrivacyCollectedDataTypes` = phone numbers, names, device identifiers (FCM tokens), purchase history (via RevenueCat)
    - `NSPrivacyAccessedAPITypes` = `UserDefaults` (CA92.1 — App functionality), `DiskSpace` (E174.1 if Firebase reads it), `FileTimestamp` if any caching uses it
  - Apple's template: File → New → File → Resource → "App Privacy".
  - **Hand to Feature Builder** — needs an actual file added with declared SDKs (Firebase, RevenueCat).

### App Privacy answers in App Store Connect
- [ ] **App Store Connect → App Privacy section must be filled out.** Based on UpNext's actual collection:
  - **Contact Info → Phone Number:** Yes (customers enter phone at check-in). Linked to user. Not used for tracking. Used for "App Functionality" (queue notifications) and "Customer Support".
  - **Contact Info → Name:** Yes (customer first name + last initial). Same answers as above.
  - **Contact Info → Email Address:** Yes (owner signup). Used for "App Functionality" and "Account Management".
  - **Identifiers → User ID:** Yes (Firebase UID). Linked to user, not used for tracking.
  - **Identifiers → Device ID:** Yes (FCM tokens are device-scoped push identifiers). Linked, not for tracking.
  - **Purchases → Purchase History:** Yes (via RevenueCat). Linked, not for tracking.
  - **Usage Data:** Verify — does Firebase Analytics fire? *(unverified — Carlos check `GoogleService-Info.plist` and FirebaseApp config; if Analytics is enabled by default, declare "Product Interaction" + "Other Usage Data".)*
  - **Diagnostics → Crash Data + Performance Data:** If you ship Firebase Crashlytics, declare. If you don't, skip.

### Subscription configuration (RevenueCat ↔ ASC)
- [ ] **Confirm IAP products exist in App Store Connect** matching what [`SubscriptionManager.swift:18-21`](UpNext/Shared/Services/SubscriptionManager.swift) expects:
  - Base product → linked to RevenueCat package `Monthly` (built-in) → ASC product ID likely `upnext_base_monthly` (verify in RC dashboard)
  - Multi product → linked to RevenueCat package `multi_monthly`
  - **Status of ASC IAP products: unverified — check yourself in ASC → My Apps → UpNext → Features → In-App Purchases.**
- [ ] **Subscription Group exists in ASC** — both products must live in the same Subscription Group (Apple requires this for upgrade/downgrade flow).
- [ ] **Each subscription has a localized display name + description filled in ASC.** Apple rejects subscriptions with empty localizations.
- [ ] **Each subscription has a Review Screenshot uploaded** — the IAP product itself needs a 640×920 (or larger) screenshot showing the paywall. Without this, Apple rejects the IAP, which blocks app submission.
- [ ] **Subscription pricing is set** — $49.99/mo for Base, $79.99/mo for Multi. Tier 50 / Tier 80 in Apple's price tier system. *(unverified.)*
- [x] **Paywall disclosure text is present** ([`PaywallView.swift:330-332`](UpNext/Shared/Views/PaywallView.swift)): "Subscription automatically renews. Cancel anytime in Settings > Apple ID > Subscriptions. Payment is charged to your Apple ID account at confirmation of purchase." Auto-renew + charge timing covered.
- [ ] **Paywall is missing required Terms of Use and Privacy Policy LINKS.** [`PaywallView.swift`](UpNext/Shared/Views/PaywallView.swift) shows the disclosure text but no tappable links to Terms or Privacy. **Apple guideline 3.1.2 explicitly requires functional links to both, accessible from the paywall before purchase.** This is a frequent rejection.
  - **Hand to Feature Builder:**
    - **What to build:** Add two tappable links below the auto-renew disclosure text in [`PaywallView.swift`](UpNext/Shared/Views/PaywallView.swift) `footerSection` (around line 322): "Terms of Use" → `https://upnext-app.com/terms.html` and "Privacy Policy" → `https://upnext-app.com/privacy.html`. Use `Link(destination:)`.
    - **iOS-specific considerations:** SwiftUI `Link` opens in Safari. Apple wants these visible WITHOUT scrolling on the paywall — currently they would be at the very bottom of a `ScrollView`. Consider a compact two-link row right under the Subscribe button or under the guarantee badge.
    - **Files affected:** [`PaywallView.swift`](UpNext/Shared/Views/PaywallView.swift) only.
    - **Risk surface:** Touches subscription UI. Per CLAUDE.md, subscription code changes need explicit approval before commit — flag this to Carlos.
    - **Hard stops to confirm:** Yes — subscription code change.
- [ ] **Paywall is also missing a visible price + period summary above the Subscribe button.** The card shows the price, but the call-to-action ("Subscribe to Base") doesn't restate "$49.99/month, auto-renews monthly". Apple's reviewers often flag CTAs that don't include this. Consider tightening the button label or adding a one-line summary directly above it.

### Demo account credentials for App Review — BLOCKER
- [ ] **App Review will hit the paywall and not be able to get past it.** A reviewer creating a fresh Apple ID will sign up → land on `LoginView` → if they try to create a shop they'll be hit by the paywall. Two options:
  - **Option A (preferred):** Create a permanent test account `appreview@upnext-app.com` with a password, pre-seeded with a fully working shop, an active subscription status in Firestore (`subscriptionStatus = "active"`, tier `base`), and at least 2 demo barbers + 1 demo queue entry. Provide credentials in ASC → App Review Information → Sign-in required → Username + Password.
  - **Option B (riskier):** Set the App Review tester Apple ID's RevenueCat user up as a sandbox subscriber. More fragile.
  - **Why this is a #1 rejection risk:** B2B SaaS reviewers WILL test the paid surface. Without working credentials, they'll reject under guideline 2.1 ("App Completeness") with "we couldn't access the app's features".
- [ ] **Add review notes** in ASC → App Review Information → Notes:
  - Explain the two-mode app: iPhone owner dashboard + iPad kiosk mode launched from the Kiosk tab.
  - Mention: "To enter Kiosk mode on iPad, log in as the owner, tap the 'Kiosk' tab, then 'Launch Kiosk'. To exit kiosk mode, long-press the bottom-right corner for 2 seconds and enter PIN `1234`." (See note about hardcoded PIN below — change before shipping.)

### Export compliance (encryption usage)
- [ ] **Set in ASC → App Information → Export Compliance.** UpNext uses HTTPS-only Firebase calls + standard StoreKit. Answer:
  - "Does your app use encryption?" → **Yes** (HTTPS counts)
  - "Does your app qualify for any of the exemptions?" → **Yes** — the standard exemption for apps that only use encryption for HTTPS / standard OS encryption applies.
  - You can also add `ITSAppUsesNonExemptEncryption = NO` to [`Info.plist`](UpNext/Info.plist) to skip the prompt on every TestFlight upload. Recommended.

### Age rating questionnaire
- [ ] **Fill out in ASC → App Information → Age Rating.** UpNext answers:
  - All categories (violence, sexual content, profanity, gambling, alcohol, etc.) → **None**
  - Unrestricted Web Access → **No** (the app doesn't embed a browser)
  - Result: **4+** rating. This is correct.

### App icon
- [x] **App icon present.** [`AppIcon.appiconset/Contents.json`](UpNext/Assets.xcassets/AppIcon.appiconset/Contents.json) declares one universal 1024×1024 PNG with light/dark/tinted variants. iOS 17+ generates all the smaller sizes from this single source — this is the modern, supported way. Submission-ready.
- [ ] **Verify the 1024×1024 PNG has no alpha channel and no rounded corners.** Apple rejects icons with transparency. Open `AppIcon-1024.png` in Preview → Tools → Show Inspector → confirm no alpha. *(unverified — check yourself.)*

### iOS deployment target
- [ ] **`IPHONEOS_DEPLOYMENT_TARGET = 26.2`** ([`project.pbxproj:325`](project.pbxproj)) is unusually high. iOS 26.2 was just released. This means:
  - **Anyone on iOS 25 or earlier cannot install your app at all.**
  - For first launch this is probably acceptable (early adopters) — but expect customer support requests.
  - **Recommendation:** Drop to `iOS 17.0` or `iOS 18.0` to capture the long tail. SwiftUI features used in the app (NavigationStack, `.onChange(of:_:)` two-param form) work back to iOS 17. Test before changing.
  - *(Carlos can ship at 26.2 if he wants. Just know the tradeoff.)*

---

## Section 2: Screenshot requirements + content recommendations

### iPhone screenshots — what you have works
You have 10 screenshots at **1290×2796** (iPhone 6.7"). [`AppStoreScreenshots/01_go_live.png`](AppStoreScreenshots/01_go_live.png) through `10_hero.png`.

- [x] **6.7" satisfies Apple's current iPhone screenshot requirement.** Apple still accepts 6.7" as the primary iPhone size; the 6.9" (1320×2868) tier is optional. You're fine.
- [ ] **Apple requires 3-10 iPhone screenshots.** You have 10 — ship 5-7 of the strongest. More isn't better.
- [ ] **First 3 screenshots are what most users see in search results without tapping.** Filename order suggests:
  1. `01_go_live.png` — Go Live toggle (the differentiator)
  2. `02_queue.png` — live queue
  3. `03_customer.png` — customer-facing flow
  - **My recommendation:** Lead with the **single clearest "what is this app"** image. If `10_hero.png` is your hero treatment with text overlay, consider it slot 1. Then `01_go_live.png` (the differentiator) at slot 2. Then `02_queue.png` (the daily-driver screen) at slot 3. Save analytics/team management for slots 5-7.
  - Without seeing the actual screenshots I can't confirm the order — view them in Preview and decide.
- [ ] **Add text overlays.** Apple-accepted screenshots almost universally have a 1-line headline at the top. Without overlays you're competing with apps that have them. Examples:
  - 01_go_live: "Turn dead chair time into walk-ins"
  - 02_queue: "Real-time queue, every barber in sync"
  - 03_customer: "Customers check in by QR, TV, or kiosk"
  - 06_analytics: "See your busiest hours at a glance"
- [ ] **Hand to Hormozi Marketing** — copywriting on the overlays is their lane, not iOS Advisor's. I'm flagging the *requirement*, not writing the copy.

### iPad screenshots — REQUIRED, not optional, and you have ZERO
- [ ] **Since the app target's `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad universal), Apple requires iPad screenshots.** No exceptions for universal apps.
- [ ] **Required size: iPad 13" → 2064×2752 (portrait) or 2752×2064 (landscape).** Apple also accepts 12.9" (2048×2732) as an alternative.
- [ ] **Minimum 2, maximum 10.** Recommend 3-5.
- [ ] **What to capture (kiosk-side, since iPad = kiosk):**
  1. **Welcome / Attract Screen** — `KioskCheckInView.welcome` ([`KioskCheckInView.swift:41`](UpNext/UpNext-Kiosk/Views/KioskCheckInView.swift)) with available barbers chips visible. Add overlay: "Customer kiosk on your iPad — Walk-ins handled."
  2. **Name & Phone screen** — `KioskCheckInView.namePhone`. Show large touch targets. Overlay: "Sign in with name and phone — that's it."
  3. **Confirmation screen** — `KioskCheckInView.confirmation`. Show "You're on the list!" with position + ETA. Overlay: "Customers see exactly where they stand."
  4. *(Optional)* **Owner Dashboard on iPad** — same SwiftUI dashboard rendered at iPad width. Shows the app isn't "phone app stretched" — it adapts.
  5. *(Optional)* **Owner Analytics on iPad** — charts at iPad scale.
- [ ] **Capture in landscape.** The kiosk is designed for landscape (a barbershop counter mount). [`project.pbxproj:406`](project.pbxproj) allows all four orientations on iPad — landscape will look most "shop kiosk".
- [ ] **Hand to Feature Builder OR Carlos manually** — capture screens via Xcode → Window → Devices & Simulators → run on iPad simulator → Cmd+S to save screenshot. Then resize to 2064×2752 if needed.

### Screenshot rejection traps to avoid
- [ ] **No status bar with carrier name "Carrier" or "Simulator".** Use the iOS simulator with `xcrun simctl status_bar` to clean it up, or use a real device.
- [ ] **No real customer phone numbers** in the screenshots. Use `(555) 555-0123` or similar fake test data. Apple has rejected for showing real contact info.
- [ ] **No text the reviewer might confuse for app functionality you don't have.** If a screenshot shows "SMS reminder sent", make sure SMS actually works in the build — per CLAUDE.md, SMS is currently stubbed. Don't claim it.

---

## Section 3: Metadata sanity check

### App name (30 char)
- [ ] **Recommended:** `UpNext: Walk-In Queue` (21 chars). Avoid stuffing keywords here — Apple penalizes.
- [ ] **Backup if taken:** `UpNext — Barber Walk-Ins` (24 chars).

### Subtitle (30 char)
- [ ] **Recommended:** `Walk-in queue for barbers` (25 chars) — direct, no fluff.
- [ ] **Alt:** `Modern walk-in check-in` (23 chars).

### Promotional text (170 char)
Promotional text doesn't require resubmission to update — use it for current offers/news.
- [ ] **Recommended for launch:**
  > "Built for barbershops. Keep your booking app — UpNext handles the walk-ins. QR code, TV display, or iPad kiosk — your choice. 30-day money-back guarantee."
  > (158 chars)

### Description (4000 char) — DRAFT
- [ ] **Recommended draft (paste into ASC, edit Carlos voice):**

```
Modern check-in for walk-in shops — QR code, TV display, or kiosk. Your choice.

UpNext is the walk-in queue manager built specifically for barbershops. It does NOT replace Square, Booksy, or any booking app you already use. Keep your scheduling tool. UpNext handles the walk-ins.

WHO IT'S FOR
- Barbershops with walk-in traffic
- Multi-chair shops where the front desk gets buried during peak hours
- Owners who want their appointment-only barbers to fill dead chair time without changing booking platforms

THE GO LIVE TOGGLE
The feature shops talk about most. Appointment-only barbers can flip themselves Go Live during slow periods, appear on the kiosk, take walk-ins, and toggle off when their next booking comes in. Dead chair time becomes revenue.

THREE WAYS TO CHECK IN — YOUR CHOICE
- Printed QR code at the front desk
- TV display in the lobby (live queue + walk-in QR side by side)
- iPad kiosk mode (locked to one app via iOS Guided Access)

REAL-TIME QUEUE
- Every barber sees the queue update live, on iPhone or iPad
- Push notifications when someone joins
- Customer's own queue tracker shows position and wait time
- Live Wait link lets customers join the queue from home — they tap "I'm Here" when they arrive

ANALYTICS THAT MATTER
- Daily, weekly, monthly walk-in counts
- Wait time averages
- Peak hours
- Walk-out tracking (how many leave before being served)
- Revenue and per-barber performance

BUILT BY A BARBERSHOP OWNER
UpNext is built and tested at Fademasters Barbershop in Waco, TX. Real shop, real walk-ins, real feedback.

PRICING
- Single Location: $49.99/month
- 30-day money-back guarantee — not for you? Email support@upnext-app.com for a full refund.

QUESTIONS, BUGS, OR FEATURE REQUESTS
support@upnext-app.com
```

- [ ] **Notes:** No promo code (`WACO`) is mentioned — Apple prohibits it. Multi-Location tier is omitted from the description (it's not yet purchasable — see Section 4 below).

### Keywords (100 char)
Apple counts every comma. Use single words separated by commas, no spaces.
- [ ] **Recommended:** `barbershop,salon,queue,walkin,checkin,kiosk,barber,shop,wait,SMS,QR,TV,booksy,square`
  - 86 chars. Includes competitor names (allowed) and category words.
- [ ] **Don't repeat words from your title/subtitle** — Apple already indexes those. So `walkin`, `queue`, `barber` could be dropped if you have them in the title/subtitle.

### Category
- [ ] **Primary:** **Business** — UpNext is a B2B SaaS tool for shop owners.
- [ ] **Secondary:** **Productivity** OR **Lifestyle**. Productivity ranks better for B2B; Lifestyle gets discovered by barbers browsing for tools.
- [ ] **Avoid:** "Health & Fitness" (mismatch), "Utilities" (low discoverability for paid).

### URLs
- [x] **Privacy Policy URL exists:** `https://upnext-app.com/privacy.html` ([`public/privacy.html`](public/privacy.html) confirmed). **REQUIRED in ASC.**
- [x] **Terms of Service URL exists:** `https://upnext-app.com/terms.html` ([`public/terms.html`](public/terms.html) confirmed). Required for paywall link (Section 1).
- [ ] **Support URL:** Recommend `https://upnext-app.com/` (your homepage) or create `https://upnext-app.com/support.html` if you want a dedicated page. **REQUIRED in ASC.**
- [ ] **Marketing URL (optional):** `https://upnext-app.com/`.

### Copyright
- [ ] **Recommended:** `© 2026 Carlos Canales` or `© 2026 UpNext` (whichever entity holds the copyright). One line in ASC → App Information.

### Age Rating answers (covered in Section 1) → **4+**

---

## Section 4: High-risk rejection triggers specific to UpNext

### Multi-Location "Coming Soon" — handled correctly in code
- [x] **The Multi-Location plan is hidden in the paywall.** [`PaywallView.swift:153`](UpNext/Shared/Views/PaywallView.swift): `private let showMultiLocationPlan = false`. The card never renders. **Safe.**
- [ ] **Do NOT mention Multi-Location in the App Store description for v1.0.** The draft above already omits it. Apple guideline 2.3.1 ("Accurate Metadata") rejects descriptions that promise features not in the build. Add Multi-Location to the description only when it's actually purchasable.

### DEBUG paywall bypass — gated correctly
- [x] **`paywallBypassed` is `#if DEBUG` gated.** [`ContentView.swift:26-30`](UpNext/ContentView.swift):
  ```swift
  #if DEBUG
  private let paywallBypassed = true
  #else
  private let paywallBypassed = false
  #endif
  ```
  - Release builds (the only kind that go to App Store / TestFlight) compile with `paywallBypassed = false`. Reviewers cannot bypass.
  - **`SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"`** is only set in the Debug config ([`project.pbxproj:331`](project.pbxproj)). Release config does NOT define DEBUG. Confirmed safe.
- [ ] **One thing to verify:** Run `Product → Archive` in Xcode and confirm the archived `.xcarchive` is built with the Release config (Xcode does this by default). *(unverified — Carlos confirm before submission.)*

### Kiosk Guided Access claim
- [ ] **The description draft mentions "locked to one app via iOS Guided Access".** Apple WILL test this on iPad. Confirm:
  - The kiosk view ([`KioskCheckInView.swift`](UpNext/UpNext-Kiosk/Views/KioskCheckInView.swift)) renders correctly when Guided Access is active (no system gestures, no escape route).
  - The exit PIN flow works after exiting Guided Access. ([`ContentView.swift:262`](UpNext/ContentView.swift) — `if pinInput == exitPIN { isPresented = false }`.)
- [ ] **Hardcoded PIN `1234` in [`ContentView.swift:237`](UpNext/ContentView.swift).** This is the "Owner exit PIN" for kiosk mode. **NOT a security blocker for App Review** (it's a UX convenience, not a security boundary), but:
  - Comment it out of the App Review notes if you change it before shipping.
  - **Consider:** moving to Firestore `Shop.settings.kioskExitPIN` so each shop sets their own. Not blocking — flag for v1.1.

### WACO promo code
- [x] **WACO is not mentioned anywhere I can find in the iOS codebase.** Searched paywall, ContentView, AuthViewModel — clean. Don't put it in the App Store description either. Apple guideline 3.1.1 prohibits incentives for downloads.

### `pendingSubscriptions` handoff bug — submission decision
- [ ] **[`BUGS.md`](BUGS.md) BUG-001:** When a user signs up on web → pays via Stripe → opens iOS app first time → hits paywall despite paying. Root cause: `AuthViewModel.loadShop()` doesn't check `pendingSubscriptions/{email}` collection.
- **Is this a submission blocker?**
  - **For App Review specifically: NO.** A reviewer using Apple's IAP path (your demo account or sandbox) will never hit this bug because they're not coming through the Stripe webhook flow.
  - **For real customers post-launch: YES.** Anyone who pays on the web first will be visibly broken.
  - **Recommendation:** Submit v1.0 to the App Store WITHOUT fixing the bug — but make sure your launch sequence pushes new users to subscribe **inside the iOS app first** (RevenueCat path), not on the web. Then fix BUG-001 in v1.0.1 / v1.1.
  - **Hand to Feature Builder (post-launch):** see [`BUGS.md`](BUGS.md) for the suggested fix.

### Push notification permission timing — handled correctly
- [x] **Permission is requested AFTER login**, not on cold launch. [`AuthViewModel.swift:323`](UpNext/UpNext-Barber/ViewModels/AuthViewModel.swift) calls `NotificationManager.shared.setup(userId:)` only after a successful auth load. The user has context for why notifications are useful (they're the shop owner / barber waiting on walk-in alerts). Apple HIG-friendly.
- [ ] **Consider adding a soft pre-prompt** before the system dialog — a screen that says "We'll alert you when a walk-in checks in. Tap Allow on the next screen." This dramatically improves Allow rate but isn't required for App Review.

### Other risk surfaces — verified clean
- [x] **No `NSCameraUsageDescription`, `NSContactsUsageDescription`, `NSLocationUsageDescription` are present in [`Info.plist`](UpNext/Info.plist) — none needed.** Searched the codebase: no `AVCaptureDevice`, no `CLLocationManager`, no `Contacts.framework` references in the iOS target. Clean.
- [x] **`UIBackgroundModes` is minimal** — only `remote-notification`. Apple is suspicious of unnecessary background modes; you have only what you need.
- [x] **No private API usage** (would need a deeper grep — but the codebase is small and idiomatic SwiftUI/Firebase, no obvious flags).
- [x] **No third-party paywall (Stripe IAP) mentioned in iOS app** for digital subscriptions — RevenueCat handles iOS purchases through Apple IAP. Compliant with guideline 3.1.1.

---

## Section 5: Resubmission risk reduction

### Today (small fixes — knock out before submitting)
- [ ] Bump build number in Xcode.
- [ ] Add `ITSAppUsesNonExemptEncryption = NO` to [`Info.plist`](UpNext/Info.plist).
- [ ] Verify no transparency on the 1024×1024 app icon.
- [ ] Capture and resize iPad screenshots (3-5 of the kiosk).
- [ ] Pick the strongest 5-7 iPhone screenshots and order them.
- [ ] Fill in ASC App Information: subtitle, promo text, description, keywords, category, URLs, copyright.
- [ ] Fill in ASC App Privacy questionnaire.
- [ ] Fill in ASC Age Rating → 4+.
- [ ] Add ASC App Review Notes (kiosk launch path, exit PIN `1234`, demo credentials).
- [ ] Set up the demo account in Firestore (`appreview@upnext-app.com`) and verify it bypasses the paywall via `subscriptionStatus = "active"`.

### Real work (do before submitting)
- [ ] **Add `PrivacyInfo.xcprivacy`.** Required since May 2024.
- [ ] **Add Terms of Use + Privacy Policy links to the paywall.** Code change in [`PaywallView.swift`](UpNext/Shared/Views/PaywallView.swift). Subscription code change — needs Carlos approval per CLAUDE.md.
- [ ] **Confirm RevenueCat IAP products exist in ASC** with display names, descriptions, review screenshots, and pricing. Without this, IAPs get rejected and the app submission gets stuck.
- [ ] **Test the paywall purchase flow end-to-end with a sandbox tester Apple ID.** RevenueCat → Apple IAP → entitlement → app sees `isSubscribed = true`. If this doesn't work, App Review fails immediately.

### Strategic call: ship at iOS 26.2 or drop the deployment target?
- Solo founder, first submission. Either works.
- Shipping at 26.2 is fine if your Fademasters team is on the latest iPhones — early-adopter strategy.
- Dropping to iOS 17.0 takes ~10 minutes (Xcode → target → General → Minimum Deployments) and triples your addressable market.
- Recommend: **drop to iOS 17.0 before submission**, smoke-test on iOS 17 simulator, ship.

### What is NOT a blocker (despite looking like one)
- The CLAUDE.md ↔ code mismatch (single target vs claimed two targets) — submission works fine as one universal app. Document fix is post-submission.
- The hardcoded `1234` kiosk exit PIN — UX convenience, not a security issue Apple cares about.
- Hardcoded RevenueCat keys in [`UpNextApp.swift:20-23`](UpNext/UpNextApp.swift) — these are public-by-design API keys, fine in source.
- BUG-001 (`pendingSubscriptions`) — won't trip App Review.

---

## Items I couldn't verify — Carlos must check himself

1. **App Store Connect record exists** for bundle ID `com.carlos.upnext.UpNext` and is in "Prepare for Submission" state.
2. **Apple Developer Portal capabilities** (Push Notifications, In-App Purchase) are enabled for the App ID.
3. **APNs Auth Key** is uploaded to Firebase Cloud Messaging.
4. **RevenueCat IAP products** (`upnext_base_monthly`, `upnext_multi_monthly` or whatever the actual ASC product IDs are) exist in App Store Connect with all metadata + review screenshots.
5. **Subscription Group** exists in ASC and both products are in it.
6. **Sandbox tester Apple ID** is set up and verified to be able to purchase the IAP in a development build.
7. **Firebase Analytics / Crashlytics** are enabled (changes the App Privacy answers).
8. **Archive build (Release config)** actually compiles with `paywallBypassed = false` and the production RevenueCat key.
9. **Guided Access works correctly** with the kiosk view on a real iPad.
10. **The 1024×1024 app icon has no alpha channel.**
