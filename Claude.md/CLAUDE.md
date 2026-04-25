# UpNext — Walk-In Queue Manager for Barbershops

## Project Overview
UpNext is a two-app walk-in management system for barbershops:
- iPad Kiosk App: Customer-facing check-in experience (Swift/UIKit)
- iPhone App: Barber queue management + owner dashboard (Swift/SwiftUI)

Customers sign in at the kiosk → see their wait time → barbers manage their queue on iPhone → customers get texted when it's their turn.

## CRITICAL POSITIONING: Walk-Ins Only — NOT a Booking App
UpNext does NOT replace Square, Booksy, or any booking platform. It works ALONGSIDE whatever scheduling tool a shop already uses. The pitch: "Keep your booking app. UpNext handles the walk-ins."

Key feature: "Go Live" toggle — appointment-only barbers can make themselves available for walk-ins during slow periods. They appear on the kiosk when live, disappear when toggled off. Turns dead chair time into revenue without changing anyone's booking platform.

## Business Model
- Monthly SaaS subscription for barbershop owners
- Starter: $49/mo (1-5 barbers), Pro: $79/mo (6-15 barbers), Enterprise: $129/mo (16+)
- 14-day free trial, no credit card required

## Tech Stack
- Language: Swift 5.9+
- UI: SwiftUI (iPhone app), UIKit (iPad kiosk — for kiosk mode/Guided Access support)
- Backend: Firebase (Cloud Firestore for real-time DB, Firebase Auth, Cloud Functions)
- SMS: Twilio (customer notifications — "you're almost up" and "you're up")
- Subscriptions: RevenueCat (handles App Store subscription logic)
- Distribution: App Store Connect
- Version Control: GitHub

## Project Structure
```
UpNext/
├── UpNext.xcodeproj
├── Shared/                    # Code shared between both targets
│   ├── Models/                # Data models (Shop, Barber, QueueEntry, Service, Customer)
│   ├── Services/              # Firebase, Twilio, RevenueCat service layers
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
├── CloudFunctions/            # Firebase Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── notifications.ts   # SMS trigger logic
│   │   ├── queue.ts           # Queue management logic
│   │   └── analytics.ts      # Daily reports, stats calculation
│   └── package.json
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
Phase 1 — MVP: Core check-in loop (sign in → wait → queue management → SMS notification)
Testing exclusively at Fademasters Barbershop in Waco, TX before public launch.

## Key Screens (iPad Kiosk)
1. Welcome/Attract Screen — "Walk In? Sign In Here." + current wait time
2. Name & Phone Input — Large touch targets, on-screen keyboard
3. Choose Your Barber — Grid of barber cards with queue count + wait estimate
4. Choose Your Service — Service cards with name + duration
5. Confirmation — "You're checked in!" + position + estimated wait
6. Live Queue Display (idle mode) — Shows current queue for the lobby

## Key Screens (iPhone App)
7. Login — Email/PIN + Face ID/Touch ID
8. Barber View: My Queue — "Go Live" toggle (available for walk-ins), current client, up next list, swipe actions (Start/Skip/Remove), Mark Done
9. Owner View: Dashboard — All barbers, all queues, quick actions (reassign, remove, manual add)
10. Owner View: Analytics (Phase 2) — Clients served, wait times, walk-outs, peak hours
11. Owner View: Settings — Shop info, barber management, service menu, notification config, billing

## Design Guidelines
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
