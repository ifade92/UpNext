# UpNext — Walk-In Queue Manager for Barbershops

> *"Modern check-in for walk-in shops — QR code, TV display, or kiosk, your choice."*

## Project Overview
UpNext is a multi-surface walk-in management system for barbershops.

**Primary surface (the daily driver):**
- **iPhone app** — Owner dashboard runs BOTH live queue operations (who's next, assign barbers, mark complete) AND business analytics (revenue, barber performance, customer data). Also hosts the per-barber queue view. This is where shops spend their day.

**Customer-facing check-in surfaces (shop's choice — see "Check-In System" below):**
- **Web** (`upnext-app.com`) — Hosts the actual customer check-in form (QR scan target), the Live Wait remote check-in flow, and the customer's queue tracker page
- **iPad app** — Kiosk mode for shops that want a dedicated check-in tablet
- **TV display mode** — Lobby queue visualization, also doubles as a QR placement option

QR-based check-in is the default in-person mode. The iPad kiosk is one of three QR placements (printed, TV, kiosk), not the headline product.

## CRITICAL POSITIONING: Walk-Ins Only — NOT a Booking App
UpNext does NOT replace Square, Booksy, or any booking platform. It works ALONGSIDE whatever scheduling tool a shop already uses. The pitch: "Keep your booking app. UpNext handles the walk-ins."

Key feature: "Go Live" toggle — appointment-only barbers can make themselves available for walk-ins during slow periods. They appear on the kiosk when live, disappear when toggled off. Turns dead chair time into revenue without changing anyone's booking platform.

## Business Model
- Monthly SaaS subscription for barbershop owners
- Single Location: $49.99/month — currently active and available (Stripe tier `base`)
- Multi-Location: $79.99/month — Coming Soon (marketed but not yet available; Stripe tier `multi`)
- 14-day free trial, no credit card required
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
- Official product website: **upnext-app.com** — deployed via Firebase Hosting from `public/`. Serves three distinct purposes:
  1. **Marketing** — `index.html` and supporting pages (privacy, terms, etc.)
  2. **Owner signup/login** — `signup.html`, `login.html` (Firebase Auth + Stripe Payment Links)
  3. **Customer check-in flows** — `checkin.html` (QR scan target), `wait.html` (Live Wait remote check-in), `queue.html` (customer's own queue tracker with "I'm Here" button), plus `qrcode.html`, `barber.html`, `join.html`
- The `public/` folder is **not** just marketing — it actively serves customer-facing product flows. Point all new web work here.
- Legacy site: getupnextapp.com (Netlify) — **being decommissioned**. Should be redirected to upnext-app.com or taken down. Do not reference, link to, or deploy new work to this domain.

## Check-In System

UpNext supports **two distinct check-in entry points**. A shop can use either or both.

### 1. In-Person Check-In (QR-based)
- Generates an actual scannable QR code
- Three placement options:
  - **Printed QR** — physical sign in the shop
  - **TV QR** — displayed on a lobby TV
  - **Kiosk QR** — shown on the iPad kiosk app
- All three lead to the same customer-facing form (`public/checkin.html`)
- Customer scans → fills out the form on their phone (or directly on the kiosk) → joins the queue, physically present from the moment of check-in

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
The product describes the customer journey in three states ("in person waiting", "on the way", "arrived") but the code implements them as **two parallel fields** on `QueueEntry`:

| Customer journey | `status` (`QueueStatus` enum) | `remoteStatus` (`String?`) |
|---|---|---|
| In-person, waiting | `.waiting` (`"waiting"`) | `nil` |
| Remote, on the way | `.waiting` (`"waiting"`) | `"on_the_way"` |
| Remote, arrived | `.waiting` (`"waiting"`) | `"arrived"` |

Key implications:
- `status` tracks the **main queue progression** (waiting → notified → in_chair → completed → walked_out / removed)
- `remoteStatus` is an **optional secondary state** that exists ONLY for Live Wait check-ins. In-person check-ins leave it `nil`.
- Do NOT add `"in_person_waiting"` to the `QueueStatus` enum — in-person is just "waiting with no remoteStatus"
- The literal string is `"on_the_way"` (snake_case), not `"on their way"`

Defined in `UpNext/Shared/Models/QueueEntry.swift:88-93, 118-123`.

## Project Structure
```
UpNext/
├── UpNext.xcodeproj
├── Shared/                    # Code shared between both targets
│   ├── Models/                # Data models (Shop, Barber, QueueEntry, Service, Customer)
│   ├── Services/              # Firebase, RevenueCat service layers
│   ├── Utilities/             # Extensions, helpers, constants
│   └── Config/                # Firebase config, API keys (gitignored)
├── UpNext-Kiosk/              # iPad kiosk target
│   ├── Views/                 # UIKit view controllers
│   ├── ViewModels/            # Kiosk-specific view models
│   └── Assets.xcassets
├── UpNext-Barber/             # iPhone barber/owner target
│   ├── Views/                 # SwiftUI views
│   ├── ViewModels/            # Barber/owner view models
│   └── Assets.xcassets
├── functions/                 # Firebase Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── pushNotifications.ts # APNs push triggers (live)
│   │   ├── stripeWebhook.ts   # Stripe → Firestore subscription sync (live)
│   │   ├── remoteCleanup.ts   # Scheduled queue cleanup (live)
│   │   └── notifications.ts   # SMS triggers (stub — not exported)
│   └── package.json
├── public/                    # Firebase Hosting site (upnext-app.com): marketing + signup/login + customer check-in flows (QR + Live Wait). NOT just marketing.
└── README.md
```

## Database Structure (Firestore)
- `shops/{shopId}` — Shop profile, settings, SMS templates
  - `shops/{shopId}/barbers/{barberId}` — Barber profiles, status, avg service time
  - `shops/{shopId}/services/{serviceId}` — Service menu (name, duration, price)
  - `shops/{shopId}/queue/{queueEntryId}` — Active queue entries
  - `shops/{shopId}/queueHistory/{queueEntryId}` — Completed/archived entries
- `users/{userId}` — Auth accounts (role: owner or barber)
- `customers/{phoneNumber}` — Return customer recognition data

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

### Firestore security rules
`firestore.rules` does **not** enforce subscription state — all gating is client-side. Do not assume server-side protection of paid features.

### Known gap: pendingSubscriptions handoff
When a user signs up on web and pays via Stripe **before** opening the iOS app, the webhook can't yet find a shop matching the Stripe email, so it writes the subscription to `pendingSubscriptions/{email}` for later promotion. iOS **does not currently read this collection** — `AuthViewModel.loadShop()` only fetches the shop doc, so the user hits the paywall on first iOS launch despite having paid. Tracked separately as a bug; do not assume the web→iOS handoff works end-to-end yet.

## Data Models (Swift)

### QueueEntry
- id, customerName, customerPhone, barberId, assignedBarberId, serviceId
- status: waiting | in_chair | notified | completed | walked_out | removed
- position, checkInTime, notifiedTime, startTime, endTime
- estimatedWaitMinutes, notifiedAlmostUp, notifiedYoureUp

### Barber
- id, name, photoUrl, status (available | on_break | off)
- goLive: bool (whether barber appears on kiosk for walk-ins)
- barberType: walkin | appointment_only | hybrid (determines default Go Live behavior)
- goLiveSchedule: optional dict for auto-toggling (Phase 3)
- services (array of serviceIds), avgServiceTime, currentClient, order

### Service
- id, name, estimatedMinutes, price (optional), active, order

### Shop
- id, name, address, logoUrl, hours, ownerId
- settings (showPricesOnKiosk, notifyWhenPositionAway, queueDisplayMode, smsTemplates)
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

## Key Screens (Customer-facing check-in surfaces)

### Web (`upnext-app.com`)
- `checkin.html` — Customer check-in form (QR scan target for in-person check-ins)
- `wait.html` — Live Wait landing page (public wait time + remote check-in form)
- `queue.html` — Customer's own queue tracker (position, ETA, "I'm Here" button for Live Wait)
- `qrcode.html`, `barber.html`, `join.html` — supporting flows

### iPad Kiosk App (one of three in-person QR placements)
1. Welcome/Attract Screen — "Walk In? Sign In Here." + current wait time
2. Name & Phone Input — Large touch targets, on-screen keyboard
3. Choose Your Barber — Grid of barber cards with queue count + wait estimate
4. Choose Your Service — Service cards with name + duration
5. Confirmation — "You're checked in!" + position + estimated wait
6. Live Queue Display (idle mode) — Shows current queue for the lobby

### TV Display Mode
- Lobby queue visualization (current queue + estimated waits) with the shop's check-in QR overlay

## Design Guidelines

> **TODO (audit pending):** This section may contain stale Fademasters-era branding. Verify against `upnext-brand-kit.html` and update during next CLAUDE.md audit pass.

- Dark backgrounds with gold accents (#C9A84C) — matches Fademasters branding
- Clean, modern, premium feel — this is a paid subscription product
- iPad kiosk: Large touch targets (minimum 44pt), high contrast, readable from 3+ feet
- iPhone app: Standard iOS patterns, SwiftUI native components

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

## Important Context
- Carlos is testing this at his own barbershop (Fademasters) with ~15 barbers
- The shop runs both walk-ins and appointments (Square handles appointments)
- UpNext is WALK-IN ONLY — it does NOT replace or compete with booking platforms like Square or Booksy
- The "Go Live" toggle lets appointment-only barbers opt into walk-in traffic during slow periods
- UpNext complements existing booking tools, never replaces them — this is core to the product identity
- Carlos is learning Swift as he builds — write clean, well-commented, educational code
