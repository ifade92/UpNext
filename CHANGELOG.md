# UpNext Changelog

All notable changes to the UpNext project are logged here.

---

## [2026-04-26] — New-Account UX Fixes + Stripe Flow Cleanup

### Fixed — Web dashboard icons missing for new accounts (Critical UX)
- **Root cause:** `loadOwnerView` and `loadBarberView` in `public/barber.html` called `showView(...)` but never `lucide.createIcons()` afterward. Static `<i data-lucide="...">` chrome icons (topnav avatar/gear/analytics, bottom-nav tabs, settings rows, shop action tiles) only got rendered as a side effect when one of the `render*()` functions called `lucide.createIcons()` (which sweeps the whole DOM). For accounts with ≥1 barber, `renderSettingsBarbers()` triggered the global sweep. For brand-new accounts with `allBarbers = []`, the empty-state branch returned early before that call. Net: chrome icons stayed as raw `<i>` tags until the user happened to add a barber or service.
- **Fix:** added `lucide.createIcons()` immediately after `showView(...)` in both `loadOwnerView` and `loadBarberView`. Chrome renders on first paint regardless of dataset state.

### Fixed — iPhone "Not found: shop {shopId}" popup for new web signups (Critical)
- **Root cause:** `public/signup.html` wrote shop docs with only `name`, `ownerName`, `ownerEmail`, `ownerId`, `selectedPlan`, `subscriptionTier`, `subscriptionStatus`, `createdAt`, `createdVia`. But `Shop.swift` requires `address`, `hours`, and `settings` as non-optional. iOS Shop decode failed in `try? doc.data(as: Shop.self)`. `FirebaseService.fetchShop` then threw `documentNotFound("Shop \(shopId) not found")` — the misleading popup. Dashboard otherwise loaded because barber/queue/service listeners are independent of the Shop struct.
- **Compounded by:** `AuthViewModel.loadShop()` silently swallowed the same decode failure and left `self.shop = nil`, making `isSubscribedViaStripe` always return false for affected accounts — meaning Stripe-paid users could fail the iOS paywall gate after successful payment.
- **Fix:** `signup.html` now writes `address: ''`, a default 7-day `hours` map (Mon–Sat open, Sun closed), and a default `settings` object — all matching `FirebaseService.createShop()` on iOS. Web and iOS signups now produce structurally identical shop docs.
- **Note:** existing test accounts created before this fix still have incomplete shop docs and will still throw the popup until deleted/re-signed-up or backfilled in Firestore.

### Changed — Post-payment flow now routes entirely through upnext-app.com
- Stripe Payment Link "After payment" redirect updated in the Stripe dashboard from `getupnextapp.com/success` to `https://upnext-app.com/success`. `public/success.html` was already self-contained with relative URLs (`/barber`, `/login`) and needed no code changes.
- "Allow promotion codes" enabled on the same Payment Link in the Stripe dashboard so the WACO promo code field appears at checkout. End-to-end verified: WACO applies 100% off the first month, $49.99 recurring after; webhook flips Firestore `subscriptionStatus` to `active`; iOS paywall unlocks.
- Cosmetic: `functions/src/stripeWebhook.ts` header comment updated `getupnextapp.com` → `upnext-app.com` (no behavior change, no redeploy needed).

### Changed — CLAUDE.md trial section corrected
- The Business Model section still said "14-day free trial, no credit card required" — but the trial system was removed in the 2026-04-21 release. Updated to reflect reality: no trial, 30-day money-back guarantee, WACO promo code for local owners.

### Added — `/wrapup` slash command for ongoing doc hygiene
- New `.claude/commands/wrapup.md` formalizes the end-of-session checklist: gather diff, draft CHANGELOG entry in the established style, scan CLAUDE.md for staleness, show diffs, commit on approval. Decision rules baked in: CHANGELOG = every user-visible / behavior-affecting change; CLAUDE.md = only when documented facts become wrong or new architectural pieces exist.
- Background: a full month of changes had accumulated without doc updates, requiring a weekend of catch-up work. The wrap-up command is the prevention.

### Deployed
- Firebase Hosting redeployed with `barber.html` + `signup.html` fixes. Cloud Functions and Firestore rules unchanged.

### Files touched
- `public/barber.html` — `lucide.createIcons()` after `showView` in `loadOwnerView` + `loadBarberView`
- `public/signup.html` — shop doc now writes `address`, `hours`, `settings` matching iOS defaults
- `functions/src/stripeWebhook.ts` — cosmetic comment update
- `CLAUDE.md` — Business Model trial line corrected; new "Session Wrap-Up" section
- `.claude/commands/wrapup.md` — new end-of-session slash command

---

## [2026-04-24] — Web Signup, Sign-In & Home Page Fixes

### Fixed — Web signups couldn't sign back in (Critical)
- **Root cause:** `public/signup.html` created the Firebase Auth account and a `shops/{uid}` doc, but never created `users/{uid}`. After Stripe checkout, when the owner went to `/login` and got redirected to `/barber`, the `onAuthStateChanged` handler (`barber.html` line 1617) failed the `users/{uid}` existence check and immediately called `signOut(auth)` — bouncing every web-signup owner back to the login screen.
- **Fix:** `signup.html` now also writes `users/{uid}` with `email`, `displayName`, `role: 'owner'`, `shopId: user.uid`, and `createdAt`. Mirrors `FirebaseService.createOwnerUser` in the iOS app so iOS and web signups produce identical user docs.
- **Note:** existing test accounts created before this fix have no `users` doc — they need to be deleted in Firebase Auth and re-signed-up, OR a `users/{uid}` doc added manually in Firestore.

### Changed — Post-signup flow now sends owners to the dashboard, not the App Store
- **Old flow:** signup → Stripe checkout → `success.html` told the user to download the App Store app and sign in with their new credentials.
- **New flow:** Firebase persists the auth session through the Stripe round-trip, so users land on `success.html` already signed in. The page now uses `onAuthStateChanged` to detect that and shows a primary "Go to your dashboard →" CTA pointing to `/barber`. App Store download is demoted to a secondary link. If an unauthenticated user lands on `/success` directly, the CTA falls back to "Sign in to your dashboard →" pointing to `/login`.
- Step copy on `success.html` updated: "Open your dashboard" / "Get the iPad kiosk + iPhone app" / "Add your team and go live".

### Added — Top nav with Sign In + Get Started CTA on the home page
- The home page (`public/index.html`) had no nav at all — return visitors had no way to reach `/login` from the homepage. Added a sticky, blurred top nav with the UpNext logo on the left and "Sign In" + "Get Started" actions on the right. Mobile-responsive.

### Files touched
- `public/signup.html` + `upnextwebsite/signup.html` — added `users/{uid}` write after `shops/{uid}` creation
- `public/success.html` + `upnextwebsite/success.html` — Firebase SDK + auth-aware primary CTA, copy refresh, App Store demoted to secondary link
- `public/index.html` + `upnextwebsite/index.html` — sticky top nav (logo + Sign In + Get Started)

---

## [2026-04-22] — Web Go Live Toggle Fix

### Fixed — Barbers couldn't toggle Go Live from the web app
- **Root cause:** `public/join.html` (web barber signup) creates the user doc with `role`, `email`, and `shopId` but NOT `barberId`. The iOS flow (`FirebaseService.createBarberUser`) writes all three. The Firestore rule `isOwnBarberDoc` requires both `barberId` AND `shopId` on the user doc, so every web-signup barber failed that rule on Go Live writes.
- **Compounded by:**
  - The self-heal in `barber.html` `loadBarberView` used a strict case-sensitive `where('email', '==', appUser.email)` query. Any casing or whitespace mismatch between the email on the barber doc (owner-entered) and the auth email meant the self-heal silently missed and the barber got kicked to login — or worse, landed on the dashboard with a broken toggle.
  - The self-heal only ran when `barberDoc` was null. Stale `appUser.barberId` values (barber re-added by owner, etc.) never triggered a re-link.
  - `toggleGoLive` had no try/catch — a permission-denied write rejected the promise silently and the button appeared to do nothing.
- **Fix:**
  - `public/barber.html` `loadBarberView`: email fallback now does a case-insensitive local scan across all shop barbers. Self-heal runs every sign-in, re-linking the user doc whenever `appUser.barberId` or `appUser.shopId` don't match the resolved `barberDoc`. If the patch write fails, a toast tells the barber to sign out + back in.
  - `public/barber.html` `toggleGoLive`: wrapped in try/catch with a user-facing toast; permission-denied errors get a specific "your account link is off" message.
  - `public/join.html` `createAccount`: email normalized to lowercase at signup. After auth succeeds, we search the shop's barbers for a matching email and attach `barberId` to the user doc right there so the first Go Live toggle works immediately.

### Files touched
- `public/barber.html` — hardened `loadBarberView`; added error handling + toast to `toggleGoLive`
- `public/join.html` — lowercased email; pre-link `barberId` on the user doc at signup

---

## [2026-04-22] — Barber Booking Link Save Fix

### Fixed — Owners couldn't save barbers' booking links from the iOS Settings
- **Root cause:** the booking URL `TextField` in `EditBarberSheet` was wired through a hand-rolled `Binding(get:set:)` computed property whose closures captured a snapshot of the View — edits weren't reliably propagating into the saved `barber` struct, so the field looked blank or unchanged after save.
- **Compounded by:** the Save button was fire-and-forget (`viewModel.saveBarber(barber)` then `dismiss()` immediately). If the write threw, the error landed in the parent view's `errorMessage` after the sheet had already closed — to the user it just looked like nothing happened.
- **Fix:**
  - Added `@State var bookingUrlField: String` to the sheet, seeded from `barber.bookingUrl` in `.onAppear`, and bound the `TextField` directly to `$bookingUrlField`. Removed the `bookingUrlBinding` computed property.
  - Added `updateBarber(_:) async throws` to `ShopSettingsViewModel` (awaitable variant of `saveBarber`).
  - New `saveTapped()` helper trims whitespace, writes back into `barber`, awaits the save, and only dismisses on success. On failure it shows an inline alert ("Couldn't save barber").
  - Save button now shows a spinner + "Saving…" label while in flight and disables itself + the Cancel button to prevent double-taps.

### Files touched
- `UpNext/UpNext-Barber/Views/ShopSettingsView.swift` — `EditBarberSheet` rewrite (bookingUrl binding, save flow, error alert)
- `UpNext/UpNext-Barber/ViewModels/ShopSettingsViewModel.swift` — added `updateBarber(_:) async throws`

---

## [2026-04-21] — App Store Launch Prep

### Fixed — Stripe Subscription Gate (Critical)
- **Stripe web subscribers were locked out of the iOS app.** ContentView only checked RevenueCat for subscription status, but Stripe subscribers have their status in Firestore (set by the webhook). Now ContentView checks RevenueCat OR Firestore `subscriptionStatus` — both payment paths unlock the app correctly.
- Added `isSubscribedViaStripe` computed property to `AuthViewModel` — returns true if shop's Firestore subscription status is `active` or `past_due` (grace period).

### Fixed — Cloud Functions Out of Sync
- **Two Cloud Functions directories existed** (`functions/` and `CloudFunctions/`) with different code. Merged everything into `functions/` (the deployed directory):
  - Added `notifyStaffOnRemoteArrival` to `pushNotifications.ts` — fires when a remote customer taps "I'm Here" and notifies the right staff.
  - Added `remoteCleanup.ts` — scheduled function (every 5 min) that auto-removes remote check-ins that never arrived after 30 minutes.
  - Updated `index.ts` to export all functions.

### Removed — Free Trial System
- **Removed the 14-day free trial.** New shop owners now go straight to the paywall after signup. They subscribe via RevenueCat (App Store) or Stripe (website). Local shop owners can use the WACO promo code for a free first month.
- Removed `trialStartDate`, `trialEndDate`, `isTrialActive`, and `trialDaysRemaining` from Shop model.
- Removed trial countdown banner from OwnerDashboardView.
- Removed trial-expired messaging from PaywallView.
- `FirebaseService.createShop()` now sets `subscriptionStatus: .cancelled` (was `.trial`).
- ContentView owner gate no longer checks trial status — only RevenueCat and Stripe.
- `.trial` kept in `SubscriptionStatus` enum as legacy case for backward compat with existing Firestore docs.

### Changed
- Cleaned up stale `⚠️ REPLACE` warning comments from `UpNextApp.swift` — production RevenueCat key is already set.
- Simplified RevenueCat key comments to just explain DEBUG vs RELEASE.

### Files touched
- `UpNext/Shared/Models/Shop.swift` — removed trial fields, kept `.trial` as legacy enum case
- `UpNext/UpNext-Barber/ViewModels/AuthViewModel.swift` — removed trial helpers, added `isSubscribedViaStripe`
- `UpNext/ContentView.swift` — removed trial check, added Stripe subscription check
- `UpNext/Shared/Views/PaywallView.swift` — removed trial-expired messaging
- `UpNext/Shared/Services/FirebaseService.swift` — createShop now sets status to .cancelled
- `UpNext/UpNext-Barber/Views/OwnerDashboardView.swift` — removed trial banner
- `functions/src/pushNotifications.ts` — added `notifyStaffOnRemoteArrival`
- `functions/src/remoteCleanup.ts` — new (scheduled stale remote cleanup)
- `functions/src/index.ts` — exports all functions
- `UpNext/UpNextApp.swift` — cleaned up comments

---

## [2026-04-20] — Stripe Integration + Website Redesign

### Added — Stripe Web Subscriptions
- **Stripe as second payment path** alongside RevenueCat (App Store). Web visitors can now subscribe through Stripe Checkout.
- Two Stripe products: **Base** ($49.99/mo) and **Multi-Location** ($79.99/mo).
- **Stripe webhook Cloud Function** (`functions/src/stripeWebhook.ts`) — handles `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, and `invoice.payment_failed`.
- Webhook matches Stripe customers to shops by email (via Firebase Auth) or `stripeCustomerId`.
- `pendingSubscriptions` Firestore collection for users who pay before creating an app account.
- `stripeCustomerId`, `stripeSubscriptionId`, and `stripeEmail` fields added to `Shop.swift`.

### Added — Website Redesign
- **New homepage design** with iPhone 17 device frames, scroll-reveal animations, floating effects, and interactive app UI previews.
- Sections: Hero, Owner Dashboard, Analytics, iPad Kiosk flow, Appointments, Real-Time Sync, Feature Cards, CTA with pricing.
- Both sites updated: **upnext-app.com** (Firebase Hosting) and **getupnextapp.com** (Netlify).

### Added — Signup Flow (Account First, Payment Last)
- New `signup.html` with full account creation form: shop name, owner name, email, password, plan picker.
- Flow: create Firebase Auth account + Firestore shop doc → redirect to Stripe Checkout (email pre-filled) → success page.
- Replaces old flow that asked for payment before account creation.

### Added — Stripe Coupon for Local Signups
- **"Local Shop — Free First Month"** coupon — 100% off first month, one-time.
- Promo code: **WACO** — for in-person signups at the shop.

### Changed
- All "Download on the App Store" CTAs → **"Sign Up — Get Started"**.
- Hero badge: "Now accepting new shops — 30-day money-back guarantee".
- CTA subtext: "30-day money-back guarantee. Cancel anytime."
- `success.html` updated — tells user to sign in with their new account (not "sign up with the same email").
- `signup.html` replaced — was a meta-refresh redirect to Stripe, now a full signup form.
- Footer: added Privacy and Terms links.
- Added `/success` and `/signup` rewrites to `firebase.json`.

### Files touched
- `functions/src/stripeWebhook.ts` — new (webhook handler)
- `functions/src/index.ts` — added stripeWebhook export
- `functions/package.json` — added `stripe` dependency
- `functions/tsconfig.json` — added stripeWebhook to includes
- `UpNext/Shared/Models/Shop.swift` — added Stripe fields
- `public/index.html` — replaced with new design
- `public/signup.html` — replaced with account creation form
- `public/success.html` — updated copy for new flow
- `firebase.json` — added success rewrite
- `upnextwebsite/index.html` — synced with public/
- `upnextwebsite/signup.html` — synced with public/
- `upnextwebsite/success.html` — synced with public/

---

## [2026-04-17] — 14-Day Free Trial

### Added
- **Free trial system** — New shop owners now get 14 days of full access with no credit card required. After the trial expires, they hit the paywall and must subscribe.
- `trialStartDate` and `trialEndDate` fields on the `Shop` model, with computed helpers `isTrialActive` and `trialDaysRemaining`.
- `AuthViewModel` now loads the shop document on owner login so trial status is available app-wide.
- **Trial countdown banner** on the owner dashboard — shows "X days left in your free trial" in an accent-colored bar at the top.
- **Trial-expired paywall messaging** — when the trial ends, PaywallView shows "Your free trial has ended. Subscribe to keep your queue running." instead of the generic pitch.

### Changed
- `FirebaseService.createShop()` now sets `subscriptionStatus: .trial` (was `.active`) with trial dates calculated at signup.
- `ContentView` owner gating now checks `isTrialActive` OR `isSubscribed` (was subscription-only).

### Files touched
- `Shop.swift` — trial fields + computed properties
- `FirebaseService.swift` — trial dates on shop creation
- `AuthViewModel.swift` — shop loading, trial helpers, cleanup on sign out
- `ContentView.swift` — trial-aware access gating
- `OwnerDashboardView.swift` — trial countdown banner
- `PaywallView.swift` — trial-expired messaging
