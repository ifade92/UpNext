# UpNext — Walk-In Queue Manager for Barbershops

> *"Modern check-in for walk-in shops — QR code, TV display, or kiosk, your choice."*

## Project Overview
UpNext is a multi-surface walk-in management system for barbershops.

**Primary surface (the daily driver):**
- **iPhone app** — Owner dashboard runs BOTH live queue operations (who's next, assign barbers, mark complete) AND business analytics (revenue, barber performance, customer data). Also hosts the per-barber queue view. This is where shops spend their day.
  - Note: there's a web equivalent of this experience at `public/barber.html` — see "Two-surface note" under Key Screens for the full picture.

**Customer-facing check-in surfaces (shop's choice — see "Check-In System" below):**
- **Web** (`upnext-app.com`) — Hosts the actual customer check-in form (QR scan target), the Live Wait remote check-in flow, and the customer's queue tracker page
- **iPad app** — Kiosk mode for shops that want a dedicated check-in tablet
- **TV display mode** — Per-shop split-screen TV: live queue on one pane, walk-in QR + dynamic availability messaging on the other. URL-activated. See "TV Display Mode" under Key Screens for full mechanics.

QR-based check-in is the default in-person mode. The iPad kiosk is one of three QR placements (printed, TV, kiosk), not the headline product.

> Brand voice and content tone are defined in `docs/brand-voice.md`. Any content-creation work (social media, marketing copy, landing pages) reads that file first.

## CRITICAL POSITIONING: Walk-Ins Only — NOT a Booking App
UpNext does NOT replace Square, Booksy, or any booking platform. It works ALONGSIDE whatever scheduling tool a shop already uses. The pitch: "Keep your booking app. UpNext handles the walk-ins."

Key feature: "Go Live" toggle — appointment-only barbers can make themselves available for walk-ins during slow periods. They appear on the kiosk when live, disappear when toggled off. Turns dead chair time into revenue without changing anyone's booking platform.

## Business Model
- Monthly SaaS subscription for barbershop owners
- Single Location: $49.99/month — currently active and available (Stripe tier `base`)
- Multi-Location: $79.99/month — Coming Soon (marketed but not yet available; Stripe tier `multi`)
- No free trial — new signups go straight to the paywall (subscribe via RevenueCat on iOS or Stripe on web). 30-day money-back guarantee instead. Local shop owners can use the `WACO` promo code for a free first month.
- Note: `Shop.swift` retains legacy `starter`/`pro`/`enterprise` enum cases for backward compatibility with older shop docs. New shops use `base`/`multi`.

## Tech Stack
- Language: Swift 5.9+
- UI: SwiftUI (iPhone app), UIKit (iPad kiosk — for kiosk mode/Guided Access support)
- Backend: Firebase (Cloud Firestore, Firebase Auth, Cloud Functions, Firebase Hosting)
- Subscriptions: RevenueCat (App Store) + Stripe (web) — see "Payments & Subscriptions" below for the full architecture
- SMS: not currently wired up. The `twilio` package is installed in `functions/package.json` but unused — `notifications.ts` is stubbed and not exported. **Cleanup candidate** if SMS isn't on the near-term roadmap.
- Distribution: App Store Connect (iOS), Firebase Hosting (web)
- Version Control: GitHub

## Web Presence
- Official product website: **upnext-app.com** — deployed via Firebase Hosting from `public/`. Serves four distinct purposes:
  1. **Marketing** — `index.html` and supporting pages (privacy, terms, etc.)
  2. **Owner signup/login** — `signup.html`, `login.html` (Firebase Auth + Stripe Payment Links), `success.html` (post-signup landing)
  3. **Customer check-in flows** — `checkin.html` (QR scan target), `wait.html` (Live Wait remote check-in), `queue.html` (customer's own queue tracker with "I'm Here" button), plus `qrcode.html` (printable QR poster generator)
  4. **Barber/owner queue management (web alternative to the iPhone app)** — `barber.html` is a full queue-ops + analytics dashboard (Charts.js, Firestore-wired). `join.html` is the barber invitation/join-shop flow.
- The `public/` folder is **not** just marketing — it actively serves customer-facing product flows AND a complete barber/owner web surface. Point all new web work here.
- Legacy site: getupnextapp.com (Netlify) — **being decommissioned**. Should be redirected to upnext-app.com or taken down. Do not reference, link to, or deploy new work to this domain.

## Check-In System

UpNext supports **two distinct check-in entry points**. A shop can use either or both.

### 1. In-Person Check-In (QR-based)
- Generates an actual scannable QR code
- Three placement options:
  - **Printed QR** — physical sign in the shop
  - **TV QR** — shown on a lobby TV (see TV Display Mode under Key Screens for the full surface)
  - **Kiosk QR** — shown on the iPad kiosk app
- All three lead to the same customer-facing form (`public/checkin.html`)
- Customer scans → fills out the form on their phone (or directly on the kiosk) → joins the queue, physically present from the moment of check-in

### Walk-in vs appointment branch (inside the QR flow)
When a customer scans the in-person QR code (`public/checkin.html`), they're asked **"Do you have an appointment?"** before anything else:

- **No → walk-in path** — name + party size only, joins the shared pool with `barberId = "__next__"`, `noPreference = true`, `isAppointment = false`.
- **Yes → appointment path** — picks their booked barber, joins the queue with `isAppointment = true`, `barberId = <selected>`. From there:
  - Appointments surface in barber/owner UI as a separate "Appointments today" list
  - Appointments are excluded from walk-in analytics (which only measure walk-in business metrics)
  - Appointments are filtered out of the customer's "X people ahead of you" count on their queue tracker

The iPad kiosk does **not** ask this question yet — it hardcodes `isAppointment = false`. Adding the appointment option to the kiosk is a **planned addition**.

Fallback: if no barbers are currently Go Live, `checkin.html` shows a "Sorry, we're not taking walk-ins" screen and directs the customer to book online with non-live barbers.

### 2. Live Wait (remote check-in link)
- Generates a **shareable URL** (NOT a QR code) — owners paste it on their website, social media, Google Business profile, etc.
- Public-facing: anyone visiting the link sees the current wait time before deciding to come in
- Customer can check in remotely from anywhere
- Flow:
  1. Customer hits the link (`public/wait.html`), fills out the form → joins queue with `remoteStatus: "on_the_way"`
  2. Customer's queue tracker (`public/queue.html`) shows a 30-minute countdown + "I'm Here" button
  3. Tapping "I'm Here" flips `remoteStatus` to `"arrived"` and pushes a notification to the assigned barber (`functions/src/pushNotifications.ts`)
  4. If the timer expires without the customer tapping "I'm Here," a scheduled Cloud Function auto-removes the entry (`functions/src/remoteCleanup.ts`, runs every 5 minutes)

### Status data model — read this before touching queue code
The product describes the customer journey in three states ("in person waiting", "on the way", "arrived") but the code implements them with **three coordinated fields** on `QueueEntry`:

| Customer journey | `status` (`QueueStatus` enum) | `isRemoteCheckIn` | `remoteStatus` (`String?`) |
|---|---|---|---|
| In-person, waiting | `.waiting` (`"waiting"`) | `false` | `nil` |
| Remote, on the way | `.waiting` (`"waiting"`) | `true` | `"on_the_way"` |
| Remote, arrived | `.waiting` (`"waiting"`) | `true` | `"arrived"` |

Key implications:
- `status` tracks the **main queue progression** (waiting → notified → in_chair → completed → walked_out / removed)
- `isRemoteCheckIn` and `remoteStatus` are **not redundant** — see Data Models > QueueEntry for the full distinction. Short version: `isRemoteCheckIn` is a yes/no identity flag with a safe default (`nil`/missing = false = treat as in-person); `remoteStatus` tracks arrival progression once the customer is remote.
- Both `isRemoteCheckIn` and `remoteStatus` are always written together at every check-in site. Don't write one without the other.
- Do NOT add `"in_person_waiting"` to the `QueueStatus` enum — in-person is just "waiting with `isRemoteCheckIn = false`"
- The literal string is `"on_the_way"` (snake_case), not `"on their way"`

Defined in `UpNext/Shared/Models/QueueEntry.swift` (see Data Models section for field-level detail).

## Project Structure

UpNext ships as a **single universal Xcode target** (bundle ID `com.carlos.upnext.UpNext`, `TARGETED_DEVICE_FAMILY = "1,2"`). The folders below are code organization within that one target — they are NOT separate Xcode targets. iPhone and iPad surfaces share the same compiled binary, App Store listing, and version number.

```
UpNext/
├── UpNext.xcodeproj
├── Shared/                    # Code shared across all surfaces
│   ├── Models/                # Data models (AppUser, Shop, Barber, QueueEntry, Service, Customer)
│   ├── Services/              # Firebase, RevenueCat service layers
│   ├── Utilities/             # Extensions, helpers, constants
│   └── Config/                # Firebase config, API keys (gitignored)
├── UpNext-Kiosk/              # iPad kiosk surface (UIKit)
│   ├── Views/                 # UIKit view controllers
│   ├── ViewModels/            # Kiosk-specific view models
│   └── Assets.xcassets
├── UpNext-Barber/             # iPhone barber/owner surface (SwiftUI)
│   ├── Views/                 # SwiftUI views
│   ├── ViewModels/            # Barber/owner view models
│   └── Assets.xcassets
├── functions/                 # Firebase Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── pushNotifications.ts # Push triggers via FCM (APNs underneath for iOS) — two exports: notifyStaffOnCheckIn (walk-in→all staff; appointment→assigned barber) and notifyStaffOnRemoteArrival (when "I'm Here" tapped)
│   │   ├── stripeWebhook.ts   # Stripe → Firestore subscription sync (live)
│   │   ├── createBillingPortalSession.ts # HTTPS-callable: mints a Stripe Customer Portal session for the authenticated owner (cancel/manage)
│   │   ├── remoteCleanup.ts   # Scheduled queue cleanup (live)
│   │   └── notifications.ts   # SMS triggers (stub — not exported)
│   └── package.json
├── public/                    # Firebase Hosting site (upnext-app.com): marketing + owner signup/login + customer check-in flows (QR + Live Wait + TV display) + barber/owner web dashboard. See "Web Presence" for the four-purpose breakdown.
└── README.md
```

## Database Structure (Firestore)
- `shops/{shopId}` — Shop profile, embedded `settings` (incl. SMS templates, autoCloseTime, queueDisplayMode), subscription state
  - `shops/{shopId}/barbers/{barberId}` — Barber profiles, status, avg service time
  - `shops/{shopId}/services/{serviceId}` — Service menu (name, duration, price)
  - `shops/{shopId}/queue/{queueEntryId}` — Active queue entries
  - `shops/{shopId}/queueHistory/{queueEntryId}` — Completed/archived entries
  - `shops/{shopId}/settings/{docId}` — Settings subcollection. Exists per `firestore.rules` and is **separate** from the embedded `settings` field on the shop doc itself. Status of actual code usage is unverified — check the call site before assuming which one is canonical for a given setting.
- `users/{userId}` — Auth accounts (role: owner or barber)
- `customers/{phoneNumber}` — Return customer recognition data
- `pendingSubscriptions/{email}` — Stripe subscription waiting for shop creation. Stripe webhook writes here when a paid signup arrives before the iOS app first launches; should be promoted into the shop doc on first iOS auth (see "Known gap" under Payments & Subscriptions for current bug status).

## Payments & Subscriptions

UpNext runs a **hybrid subscription system** with two payment paths and one shared state store:

- **iOS App Store subscribers** → RevenueCat
- **Web subscribers** → Stripe (Payment Links from `public/signup.html`)
- **Convergence point** → Firestore `shops/{shopId}` document

### Subscription fields on `shops/{shopId}`
- `subscriptionStatus`: `active | past_due | cancelled | trial`
- `subscriptionTier`: `base` ($49.99) or `multi` ($79.99) — see Business Model for legacy enum notes
- `stripeCustomerId`, `stripeSubscriptionId`, `stripeEmail`

### How iOS checks subscription (paywall gate)
`ContentView.swift:54-56` is a 3-way OR:
```
paywallBypassed (DEBUG only)
|| subscriptionManager.isSubscribed     // RevenueCat: Purchases.shared.customerInfo()
|| authViewModel.isSubscribedViaStripe  // Firestore: shop.subscriptionStatus ∈ {active, pastDue}
```
`SubscriptionManager.swift` queries RevenueCat for entitlements `UpNext Pro` (any active sub) and `UpNext Multi` (multi-location). `AuthViewModel.swift` reads the shop doc for the Stripe path.

### How web checks subscription
Reads the Firestore shop doc directly. There is currently **no subscription enforcement on web login** — `public/login.html` only does Firebase Auth. The shop doc is kept fresh by the Stripe webhook.

### Sync between platforms
- **Web → iOS: works.** `functions/src/stripeWebhook.ts` handles `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, and `invoice.payment_failed`. It writes status/tier into the shop doc, which iOS reads on login.
- **iOS → web: does NOT sync.** RevenueCat status is never propagated back to Firestore. An App Store-only subscriber is invisible to anything web-side.

### Subscription management (cancel / resubscribe)
- **iOS:** Settings → Account → SUBSCRIPTION section. App Store subs use `Purchases.shared.showManageSubscriptions()` (Apple's native sheet, in-app). Stripe subs route to `upnext-app.com/barber.html` in Safari. Cancelled Stripe subs see "Resubscribe" → opens `signup.html`.
- **Web:** Settings → Subscription. Active / trial / past_due → retention interstitial (email support vs continue) → calls `createBillingPortalSession` Cloud Function → redirects to Stripe's hosted Customer Portal. Cancelled → "Resubscribe" → opens the Stripe Payment Link directly (the portal doesn't reliably offer "renew" once a sub is fully ended).
- **Cloud Function `createBillingPortalSession`:** auth-gated HTTPS-callable. Verifies caller is `role === "owner"`, then mints a Stripe Billing Portal session using `shops/{shopId}.stripeCustomerId`. Never accepts a customer ID from the client. Stripe Dashboard → Customer Portal must be configured for the function to succeed at runtime.

### Firestore security rules
`firestore.rules` does **not** enforce subscription state — all gating is client-side. Do not assume server-side protection of paid features.

### Known gap: pendingSubscriptions handoff
When a user signs up on web and pays via Stripe **before** opening the iOS app, the webhook can't yet find a shop matching the Stripe email, so it writes the subscription to `pendingSubscriptions/{email}` for later promotion. iOS **does not currently read this collection** — `AuthViewModel.loadShop()` only fetches the shop doc, so the user hits the paywall on first iOS launch despite having paid. Tracked separately as a bug; do not assume the web→iOS handoff works end-to-end yet.

## Data Models (Swift)

### AppUser (`Shared/Models/AppUser.swift`)
The auth account model — read on login, used to route to owner vs barber UI.
- id, phoneNumber, email, displayName
- role (UserRole enum: `owner` | `barber`)
- shopId, barberId — links to the shop and (if a barber) the barber profile
- fcmToken — for push notification routing
- notificationsEnabled — opt-out flag

### QueueEntry (`Shared/Models/QueueEntry.swift`)
- id, customerName, customerPhone, barberId, assignedBarberId, serviceId
- status: waiting | notified | in_chair | completed | walked_out | removed
- position, checkInTime, notifiedTime, startTime, endTime
- estimatedWaitMinutes, notifiedAlmostUp, notifiedYoureUp
- **Walk-in vs appointment (primary queue partition):**
  - `isAppointment: Bool?` — Set at check-in when the customer self-identifies (web `checkin.html` asks "Do you have an appointment?"; the kiosk hardcodes `false` for now — see Check-In System and Key Screens). This flag is the **primary axis splitting the queue into two parallel tracks**:
    - Barber/owner UI renders walk-ins and appointments as separate lists
    - Analytics excludes appointments (walk-in metrics only)
    - The customer's queue tracker filters appointments out of "X people ahead of you"
    - Notifications route differently: walk-in → all staff; appointment → assigned barber only
  - 📅 badge marks appointment entries in the barber app.
- **Walk-in routing (used when `isAppointment = false`):**
  - `noPreference: Bool?` — `true` when the customer didn't pick a barber (kiosk default; web walk-in default). Paired with sentinel `barberId = "__next__"` so the next available barber claims them.
- **Party / group check-in fields:**
  - `partySize: Int?` — group size at check-in
  - `groupId: String?` — UUID shared by all party members so the UI can group them
  - `partyIndex: Int?` — 1-based position within the group
  - `groupSize: Int?` — total people in the group
  - Note: each person in a party gets their **own** QueueEntry document; `groupId` is the join key
- **Remote check-in fields (read this carefully — both fields are required):**
  - `isRemoteCheckIn: Bool?` — Answers "is this customer NOT physically present yet?" `true` for Live Wait check-ins (website link), `false` for in-person check-ins (kiosk + QR scan). Defaults to `false` if missing — this is a deliberate safe default so a forgotten/legacy entry doesn't mislead a barber into thinking someone is remote when they aren't. Drives the 📍 lobby-presence badge and Firestore index filters.
  - `remoteStatus: String?` — For remote check-ins only. Tracks arrival progression: `"on_the_way"` → `"arrived"` (set when the customer taps "I'm Here" on `queue.html`). Drives the secondary "📍 On the Way" / "✅ Arrived" badge, the I'm-Here push notification, and the 30-min stale-entry cleanup sweep. Always `nil` for in-person check-ins.
  - **The two fields are not redundant.** `isRemoteCheckIn` is a yes/no identity flag with a safe default; `remoteStatus` is a 3-state arrival progression. Both are written together at every check-in site to keep them consistent.

### Barber (`Shared/Models/Barber.swift`)
- id, name, photoUrl, status (available | on_break | off)
- goLive: bool (whether barber appears on kiosk for walk-ins)
- barberType: walkin | appointment_only | hybrid (determines default Go Live behavior)
- goLiveSchedule: optional dict for auto-toggling (Phase 3)
- services (array of serviceIds), avgServiceTime, currentClient, order

### Service (`Shared/Models/Service.swift`)
- id, name, estimatedMinutes, price (optional), active, order

### Shop (`Shared/Models/Shop.swift`)
- id, name, address, logoUrl, hours, ownerId
- settings (showPricesOnKiosk, notifyWhenPositionAway, queueDisplayMode, smsTemplates, **autoCloseTime**)
  - `autoCloseTime: String?` — owner-set time-of-day in `"HH:MM"` 24hr format (e.g. `"21:00"`). At this time every night, all barbers are automatically set to `off`. `nil` = disabled (owner manages availability manually).
- subscriptionStatus, subscriptionTier

## Current Development Phase
Phase 1 — MVP: Core check-in loop (sign in → wait → queue management → push notification via APNs through `functions/src/pushNotifications.ts`)
Testing exclusively at Fademasters Barbershop in Waco, TX before public launch.

## Key Screens (iPhone — primary surface)
1. Login — Email/PIN + Face ID/Touch ID
2. Barber View: My Queue — "Go Live" toggle (available for walk-ins), current client, up next list, swipe actions (Start/Skip/Remove), Mark Done
3. Owner View: Dashboard — All barbers, all queues, live queue operations (reassign, remove, manual add)
4. Owner View: Analytics — Clients served, wait times, walk-outs, peak hours, revenue, barber performance, customer data
5. Owner View: Settings — Shop info, barber management, service menu, QR code generation, Live Wait link, notification config, billing

> **Two-surface note:** The barber/owner experience runs on **two real product surfaces**: the iPhone app (primary daily driver — screens above) AND `public/barber.html` (web alternative — a full Charts.js + Firestore dashboard with the same queue management and analytics). Use the iPhone app for live in-shop work; the web dashboard is useful for owners on a laptop or remote viewing. Both must be kept in sync when adding barber/owner features.

## Key Screens (Customer-facing check-in surfaces)

### Web (`upnext-app.com`)
- `checkin.html` — Customer check-in form (QR scan target for in-person check-ins)
- `wait.html` — Live Wait landing page (public wait time + remote check-in form)
- `queue.html` — Customer's own queue tracker (position, ETA, "I'm Here" button for Live Wait)
- `qrcode.html` — Printable QR poster generator

### iPad Kiosk App (one of three in-person QR placements)
The kiosk is a **3-step flow** — no barber or service selection. Customers join a shared pool and the next available barber claims them. Defined in `UpNext-Kiosk/Views/KioskCheckInView.swift` and `UpNext-Kiosk/ViewModels/KioskViewModel.swift`.

1. Welcome/Attract Screen (`.welcome`) — "Walk In? Sign In Here." + current wait time
2. Name & Phone + Party Size (`.namePhone`) — Customer enters name, phone, and party size on large touch targets / on-screen keyboard
3. Confirmation (`.confirmation`) — "You're on the list!" + position + estimated wait + visible barbers

Important: do NOT add barber-picker or service-picker screens to the kiosk. The product decision is that walk-in customers don't pick — they enter the shared pool with `barberId = "__next__"` and `noPreference = true`, and barbers claim from the queue. See `KioskViewModel.swift:230-249`.

**Planned addition:** the kiosk will get a "Do you have an appointment?" choice screen mirroring the web QR flow (`public/checkin.html`). Until then, the kiosk hardcodes `isAppointment = false` and only handles walk-in check-in. See "Walk-in vs appointment branch" under Check-In System.

### TV Display Mode (real-time lobby display + walk-in QR)
A real customer-facing surface — not a passive screen. Some shops run this on a lobby TV as their primary check-in setup, alongside or instead of the iPad kiosk.

**Implementation:** lives in `public/queue.html`. **Important:** that file serves THREE distinct modes off URL params, not just TV:
- `?shop={shopId}` only → TV Display Mode (this section)
- `?shop={shopId}&entry={entryId}` → mobile customer "my spot" tracker (the existing "I'm Here" view for Live Wait)
- no `?shop` → error fallback ("No shop ID provided")

URL routing logic is at `queue.html:676-689` — a single `if/else if/else` block.

**Activation — URL only, no Shop setting.** TV Mode is reached by navigating to `https://upnext-app.com/queue?shop={shopId}`. There is **no** `Shop.settings` toggle to enable/disable it; the existing `QueueDisplayMode` enum (`Shop.swift:106`) is unrelated — it controls only the kiosk confirmation screen's wait-info format (position vs wait time vs both). Owners reach TV Mode via the "View Live Queue" button in `public/barber.html:1326`, which calls `openLiveQueue()` (line 3967) and opens the URL in a new tab.

**Layout (`queue.html:441-488`):**
- **Header** — UpNext logo · shop name · stat chips ("X barbers live" / "X waiting") · clock
- **Two-pane content:**
  - **LEFT (`.checkin-panel`)** — eyebrow + headline + QR code + URL label
  - **RIGHT (`.up-next`)** — live queue list (`#tv-queue-list`)
- **Footer** — live updates banner

**Dynamic LEFT pane — messaging only, NOT destination switching:**
The left pane's *text* changes based on live count (`goLive === true && status !== 'off'`), via `setLiveMode(liveCount)` at `queue.html:944-963`:

| Barbers Go Live | Eyebrow | Headline | Footer |
|---|---|---|---|
| ≥ 1 | "No appointment needed" | "Walk in? Scan to check in" | "Live updates · Walk-ins welcome · Scan to check in" |
| 0 | "Walk-ins unavailable right now" | "Sorry, no one's taking walk-ins at the moment." | "We apologize for the inconvenience — please check with the front desk" |

**The QR code itself is STATIC.** Its target is generated once at TV init (`queue.html:923`) as `https://upnext-app.com/checkin?shop={shopId}&source=qr` and never changes. Only the *surrounding messaging text* on the TV updates when barbers go live/offline. The "no walk-ins → book an appointment with these barbers" UI a customer sees after scanning during the 0-live state is rendered by **`checkin.html`** itself (it has its own availability detection — see "Walk-in vs appointment branch" fallback under Check-In System). **Do not** try to add destination-switching logic to the QR; that would duplicate `checkin.html`'s rendering.

**`?source=qr` semantic:** the QR target carries `source=qr`, which `checkin.html` reads as `isFromQR === true`, which forces `isRemoteCheckIn = false` on the resulting QueueEntry. So a TV-QR scan is treated as a physically-present in-person check-in, consistent with the lobby-presence model documented under Data Models > QueueEntry.

**Real-time updates — three `onSnapshot` listeners:**
- `shops/{shopId}/barbers` — drives live count, left-pane mode, and header chip green/grey toggle
- `shops/{shopId}/queue` — active waiters/notified/in_chair
- `shops/{shopId}/queueHistory` — today's completed entries (so just-finished customers stay visible briefly before fading)

**Right pane queue rendering (`renderTVQueue` at `queue.html:995+`):**
- Merges active queue + today's history into one list
- Sort: active entries (waiting/notified/in_chair) float to top, oldest check-in first; completed/walked-out/removed sink to the bottom
- **Position number on display = `i + 1` from the sorted array, NOT `entry.position` from Firestore.** This is intentional — `entry.position` can drift stale in Firestore; recomputing visually guarantees #1 is always the longest-waiting active walker, and no one looks like they cut in line.
- Appointments are **filtered out** of this list — TV Mode shows the walk-in track only, consistent with `isAppointment` being a separate parallel track (see Data Models > QueueEntry).

**Header stat chip:** `#stat-live` toggles between `.green` and default classes based on whether `liveCount > 0` — visual cue mirroring the left-pane mode.

**What NOT to do:**
- Don't add a `Shop.settings.tvMode` (or similar) toggle — TV Mode is URL-only by design
- Don't make the QR target dynamic — destination-side rendering in `checkin.html` already covers the empty case
- Don't read `entry.position` for the displayed position — use the sorted-array index

## Design Guidelines

Source of truth: `upnext-brand-kit.html` v2.0 (March 2026). Defer to that file when in doubt.

### Brand identity vs marketing pitch
- **Brand kit tagline (formal identity):** "Walk-in Management"
- **Marketing pitch (top of this file, signup pages, App Store copy):** "Modern check-in for walk-in shops — QR code, TV display, or kiosk, your choice."
- The two are distinct. The tagline goes on logo lockups and brand surfaces; the pitch is for selling the product.

### Color palette
| Role | Name | Hex |
|---|---|---|
| Primary background | Deep Green | `#0D2B1A` |
| Accent (CTAs, active states) | Accent Green | `#2ECC71` |
| Hover | Green Dark | `#1BA355` |
| Secondary text / "Next" wordmark | Grey-Green | `#8BA898` |
| Alt background | Near Black | `#0D0D0D` |
| Text on dark | White | `#FFFFFF` |

`#F4C542` (yellow-gold) appears as a CSS variable in `public/queue.html` and `public/wait.html` but is **NOT** in the official palette — likely legacy from earlier Fademasters-era styling. Don't propagate it; replace with the green accents above when touching those files.

### Typography
| Element | Font | Weight | Size |
|---|---|---|---|
| Display | Outfit | 800 | 56px |
| Heading | Outfit | 600 | 32px |
| Subheading | Outfit | 400 | 20px |
| Body | DM Sans | 400 | 15px |
| Label | DM Sans | 600 | 11px |
| Printable poster (specialty only) | Gagalin | — | — |

Gagalin is a self-hosted custom font in `public/fonts/` used only for printable sign-in posters — do not use it in app or web UI.

### Logo
- **Critical rule:** Don't separate "Up" and "Next" — they are one wordmark.
- Six approved colorways exist: Deep Green primary, Ultra Dark, Near Black, Light, On Green, Stacked.

### Surface-specific UI guidance
- iPad kiosk: Large touch targets (minimum 44pt), high contrast, readable from 3+ feet.
- iPhone app: Standard iOS patterns, SwiftUI native components.
- Overall feel: clean, modern, premium — this is a paid subscription product.

## Development Workflow

All code changes go through this flow — no direct commits to main.

1. **Branch.** Create a feature branch off main (descriptive names preferred, e.g. `fix-icon-loading`, `update-pricing-tier`). Auto-generated names are fine for sprawling sessions.

2. **Work on the branch.** Make commits as needed. The standing rule still applies: never auto-commit, always show diffs first, wait for explicit approval before saving.

3. **Push the branch to origin.** This makes the work visible on GitHub but doesn't merge anything yet.

4. **Open a PR against main.** Use the GitHub web UI or `gh` CLI. Title should match the commit message convention. Description should cover what changed and why, by section if multiple things changed.

5. **Run /wrapup before merging.** This drafts the CHANGELOG.md entry, scans CLAUDE.md for staleness, and proposes the merge commit.

6. **Merge the PR.** Carlos clicks merge. Branch can be deleted after.

**Hard stops that still apply:**
- Subscription code changes (RevenueCat, Stripe, Firestore subscription state) require explicit approval before commit.
- `firestore.rules` and `storage.rules` changes require explicit approval before commit.
- Kiosk flow changes require explicit approval before commit.

**Production deploys are separate from main.** Firebase Hosting deploys happen via `firebase deploy --only hosting` and can ship before a PR is merged. Cloud Functions, Firestore rules, and Storage rules deploy separately.

## Coding Standards
- Use MVVM architecture (Model-View-ViewModel)
- All Firebase calls go through service layer classes (never directly in views)
- Use Combine for reactive data binding
- Error handling on every network call
- Comments on every major function explaining what it does and why
- Group related files in folders matching the project structure above

## When Building Features
1. Start with the data model
2. Build the Firebase service layer
3. Create the ViewModel
4. Build the View last
5. Test with hardcoded data first, then connect to Firebase

## Session Wrap-Up

At the end of every coding session, run `/wrapup` (defined in `.claude/commands/wrapup.md`). It walks the diff, drafts a CHANGELOG.md entry in the established style, scans CLAUDE.md for staleness, and commits everything together on approval.

Decision rules:
- **CHANGELOG.md** — append an entry for every user-visible or behavior-affecting change. Skip pure refactors, comment-only edits, and doc-only edits to CHANGELOG/CLAUDE itself.
- **CLAUDE.md** — update only when a documented fact is now wrong, a new architectural piece exists, or a documented gap is resolved. Implementation details belong in CHANGELOG, not CLAUDE.md.

## Important Context
- Carlos is testing this at his own barbershop (Fademasters) with ~15 barbers
- The shop runs both walk-ins and appointments (Square handles appointments)
- UpNext is WALK-IN ONLY — it does NOT replace or compete with booking platforms like Square or Booksy
- The "Go Live" toggle lets appointment-only barbers opt into walk-in traffic during slow periods
- UpNext complements existing booking tools, never replaces them — this is core to the product identity
- Carlos is learning Swift as he builds — write clean, well-commented, educational code
