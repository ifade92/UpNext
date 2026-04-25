/**
 * pushNotifications.ts — Staff push notification triggers for UpNext
 *
 * notifyStaffOnCheckIn:
 *   Fires whenever a new document is created in shops/{shopId}/queue/{entryId}.
 *
 *   Walk-in check-in  → notify ALL staff so any available barber can claim them.
 *   Appointment check-in → notify ONLY the specific barber the appointment is with.
 *   Remote check-in   → same routing, but message makes clear the customer isn't
 *                        physically in the shop yet (orange 📍 badge in the app).
 *
 * NOTE: admin.initializeApp() is called once in index.ts — do NOT call it here.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

// ── Helper: send a multicast push and clean up any stale FCM tokens ──────────
async function sendPush(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
  allDocs: admin.firestore.QueryDocumentSnapshot[]
) {
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: { title, body },
    apns: {
      payload: { aps: { sound: "default", badge: 1 } },
    },
    android: {
      priority: "high",
      notification: { sound: "default", channelId: "walk_ins" },
    },
    data,
  };

  const response = await admin.messaging().sendEachForMulticast(message);

  console.log(
    `[notifyStaff] title="${title}" sent=${tokens.length} ` +
    `ok=${response.successCount} fail=${response.failureCount}`
  );

  // Remove stale tokens so we stop targeting uninstalled apps
  const cleanup: Promise<void>[] = [];
  response.responses.forEach((resp, i) => {
    if (!resp.success && resp.error?.code === "messaging/registration-token-not-registered") {
      const staleDoc = allDocs.find((d) => d.data().fcmToken === tokens[i]);
      if (staleDoc) {
        cleanup.push(
          staleDoc.ref
            .update({ fcmToken: admin.firestore.FieldValue.delete() })
            .then(() => console.log(`[notifyStaff] Removed stale token for ${staleDoc.id}`))
        );
      }
    }
  });
  if (cleanup.length > 0) await Promise.all(cleanup);
}

// ── Main trigger ─────────────────────────────────────────────────────────────
export const notifyStaffOnCheckIn = onDocumentCreated(
  "shops/{shopId}/queue/{entryId}",
  async (event) => {
    // Lazy init — runs once per Cloud Functions container.
    // NOT at module top-level so the Firebase CLI can discover function
    // definitions without hanging on a credential lookup.
    if (!admin.apps.length) {
      admin.initializeApp();
    }

    const shopId  = event.params.shopId;
    const entryId = event.params.entryId;
    const data    = event.data?.data();

    if (!data) return;

    const customerName:  string  = data.customerName    ?? "Someone";
    const status:        string  = data.status          ?? "";
    const isAppointment: boolean = data.isAppointment   === true;
    const isRemote:      boolean = data.isRemoteCheckIn === true;
    const barberId:      string  = data.barberId        ?? "";

    // Only fire for entries entering the waiting state
    if (status !== "waiting") return;

    // Fetch all staff for this shop
    const usersSnap = await admin.firestore()
      .collection("users")
      .where("shopId", "==", shopId)
      .get();

    if (usersSnap.empty) {
      console.log(`[notifyStaff] No users found for shop ${shopId}`);
      return;
    }

    const pushData = {
      shopId,
      entryId,
      type: isAppointment ? "appointment" : "walk_in",
    };

    if (isAppointment) {
      // ── Appointment: only notify the assigned barber ──────────────────────
      const targetDocs = usersSnap.docs.filter((doc) => {
        const user = doc.data();
        return user.barberId === barberId &&
               user.notificationsEnabled !== false &&
               user.fcmToken;
      });

      const targetTokens = targetDocs
        .map((doc) => doc.data().fcmToken as string)
        .filter(Boolean);

      if (targetTokens.length === 0) {
        console.log(`[notifyStaff] No FCM token for barber ${barberId} — skipping`);
        return;
      }

      const title = isRemote ? "Virtual Check-In 📱" : "Appointment Check-In 📅";
      const body  = isRemote
        ? `${customerName} checked in remotely — they're on their way.`
        : `${customerName} is here for their appointment.`;

      await sendPush(targetTokens, title, body, pushData, usersSnap.docs);

    } else {
      // ── Walk-in: notify ALL staff so anyone can claim them ────────────────
      const allTokens = usersSnap.docs
        .filter((doc) => doc.data().notificationsEnabled !== false)
        .map((doc) => doc.data().fcmToken as string)
        .filter(Boolean);

      await sendPush(
        allTokens,
        "New Walk-In 💈",
        `${customerName} just checked in and is waiting.`,
        pushData,
        usersSnap.docs
      );
    }
  }
);


// ── Remote arrival trigger ──────────────────────────────────────────────────
// Fires when a remote customer taps "I'm Here" — their remoteStatus flips
// from "on_the_way" to "arrived". Notifies the assigned barber (appointment)
// or all staff (walk-in) so someone knows to look for them.

export const notifyStaffOnRemoteArrival = onDocumentUpdated(
  "shops/{shopId}/queue/{entryId}",
  async (event) => {
    if (!admin.apps.length) {
      admin.initializeApp();
    }

    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();

    if (!before || !after) return;

    // Only fire when remoteStatus flips from "on_the_way" → "arrived"
    if (before.remoteStatus !== "on_the_way" || after.remoteStatus !== "arrived") return;

    const shopId        = event.params.shopId;
    const entryId       = event.params.entryId;
    const customerName  = after.customerName ?? "Someone";
    const isAppointment = after.isAppointment === true;
    const barberId      = after.barberId ?? "";

    // Fetch all staff for this shop
    const usersSnap = await admin.firestore()
      .collection("users")
      .where("shopId", "==", shopId)
      .get();

    if (usersSnap.empty) return;

    const pushData = { shopId, entryId, type: "remote_arrived" };

    if (isAppointment && barberId && barberId !== "__next__") {
      // Appointment arrival — notify only the assigned barber
      const targetTokens = usersSnap.docs
        .filter((doc) => {
          const user = doc.data();
          return user.barberId === barberId
            && user.notificationsEnabled !== false
            && user.fcmToken;
        })
        .map((doc) => doc.data().fcmToken as string)
        .filter(Boolean);

      if (targetTokens.length > 0) {
        await sendPush(
          targetTokens,
          "Client Arrived ✅",
          `${customerName} is here for their appointment.`,
          pushData,
          usersSnap.docs
        );
      }
    } else {
      // Walk-in arrival — notify all staff
      const allTokens = usersSnap.docs
        .filter((doc) => doc.data().notificationsEnabled !== false)
        .map((doc) => doc.data().fcmToken as string)
        .filter(Boolean);

      await sendPush(
        allTokens,
        "Walk-In Arrived ✅",
        `${customerName} just arrived at the shop.`,
        pushData,
        usersSnap.docs
      );
    }
  }
);
