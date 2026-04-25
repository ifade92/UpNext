# Phone Auth — Manual Model Changes Required

Two model files need small updates that can't be patched automatically.
Open each file in Xcode and make the changes below — they're both quick.

---

## 1. Barber.swift

Add a `phone` field to the `Barber` struct.
Find the existing `email` property and add `phone` right next to it:

```swift
// BEFORE — find this line:
var email: String?

// AFTER — add phone below it:
var email: String?
var phone: String?
```

Also update the memberwise initializer (if your struct has one) to include:
```swift
phone: String? = nil,
```

That's it. The `phone` field stores the barber's number in E.164 format
(e.g. +12545551234) — this is what gets matched during sign-up.

---

## 2. AppUser.swift

Replace the `email` field with `phoneNumber`.
The `createBarberUser` function now stores `phoneNumber` instead of `email`.

```swift
// BEFORE:
var email: String?

// AFTER:
var phoneNumber: String?
```

If `email` is used anywhere else in your AppUser struct (computed props, etc.),
you can safely remove or leave it as optional — it won't break anything.

---

## 3. Firebase Console — Enable Phone Auth

You also need to turn on Phone Authentication in your Firebase project:

1. Go to https://console.firebase.google.com
2. Select your UpNext project
3. Authentication → Sign-in method
4. Enable **Phone**
5. Save

That's the only Firebase Console change needed — no other config required
since your GoogleService-Info.plist is already set up.

---

## 4. ShopSettingsViewModel.swift — Remove resetPasswordSent

The `resetPasswordSent` published var is no longer needed.
Find and remove this line from ShopSettingsViewModel:

```swift
@Published var resetPasswordSent: Bool = false
```

---

All other changes (AuthViewModel, LoginView, FirebaseService,
ShopSettingsView, ShopSettingsViewModel) have already been applied.
