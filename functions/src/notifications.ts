/**
 * notifications.ts — SMS notification triggers for UpNext
 *
 * Three Cloud Functions handle customer SMS notifications:
 *
 * 1. onQueueEntryCreated
 *    Fires the moment a customer checks in via the kiosk.
 *    Sends a confirmation text so they know they're in the queue.
 *
 * 2. onQueueEntryStarted
 *    Fires when a barber taps "Start" (status → in_chair).
 *    Sends an "almost up" text to the person N spots away.
 *
 * 3. onQueueEntryCompleted
 *    Fires when an entry is deleted from the queue (barber tapped "Done").
 *    Sends a "you're up" text to whoever is now first in line.
 *
 * Twilio credentials are stored as Firebase secrets — never hardcoded.
 * Set them with:
 *   firebase functions:secrets:set TWILIO_ACCOUNT_SID
 *   firebase functions:secrets:set TWILIO_AUTH_TOKEN
 *   firebase functions:secrets:set TWILIO_FROM_NUMBER
 */

import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import twilio from "twilio";

const db = admin.firestore();

// Twilio credentials stored as Firebase secrets (encrypted, never in code)
const twilioAccountSid = defineSecret("TWILIO_ACCOUNT_SID");
const twilioAuthToken  = defineSecret("TWILIO_AUTH_TOKEN");
const twilioFromNumber = defineSecret("TWILIO_FROM_NUMBER");


// MARK: - Types

interface QueueEntry {
  id?: string;
  customerName: string;
  customerPhone: string;
  barberId: string;
  assignedBarberId?: string;
  serviceId: string;
  status: "waiting" | "in_chair" | "notified" | "completed" | "walked_out" | "removed";
  position: number;
  checkInTime: admin.firestore.Timestamp;
  startTime?: admin.firestore.Timestamp;
  estimatedWaitMinutes: number;
  notifiedAlmostUp: boolean;
  notifiedYoureUp: boolean;
}

interface ShopSettings {
  notifyWhenPositionAway: number;
  almostUpSmsTemplate: string;
  youreUpSmsTemplate: string;
}


// MARK: - Trigger 0: New entry created → send check-in confirmation SMS

export const onQueueEntryCreated = onDocumentCreated(
  {
    document: "shops/{shopId}/queue/{entryId}",
    secrets: [twilioAccountSid, twilioAuthToken, twilioFromNumber],
  },
  async (event) => {
    const entry = event.data?.data() as QueueEntry | undefined;
    if (!entry) return;

    const { shopId } = event.params;

    // Fetch the shop name dynamically so this works for any shop
    const shopDoc = await db.collection("shops").doc(shopId).get();
    const shopName = shopDoc.data()?.name ?? "the barbershop";

    const firstName = entry.customerName.split(" ")[0] ?? entry.customerName;
    const message = `Hey ${firstName}! You're checked in at ${shopName}. We'll text you when you're almost up.`;

    console.log(`[onQueueEntryCreated] Sending check-in confirmation to ${entry.customerName} (${entry.customerPhone})`);

    try {
      await sendSms(entry.customerPhone, message);
      console.log(`[onQueueEntryCreated] Confirmation sent to ${entry.customerPhone}`);
    } catch (error) {
      console.error("[onQueueEntryCreated] Error sending confirmation:", error);
    }
  }
);


// MARK: - Trigger 1: Entry moved to "in_chair" → send "almost up" to N-spots-back person

export const onQueueEntryStarted = onDocumentUpdated(
  {
    document: "shops/{shopId}/queue/{entryId}",
    secrets: [twilioAccountSid, twilioAuthToken, twilioFromNumber],
  },
  async (event) => {
    const before = event.data?.before.data() as QueueEntry | undefined;
    const after  = event.data?.after.data()  as QueueEntry | undefined;
    const { shopId } = event.params;

    if (!before || !after) return;
    if (before.status === "in_chair" || after.status !== "in_chair") return;

    console.log(`[onQueueEntryStarted] Barber started service for ${after.customerName} in shop ${shopId}`);

    try {
      const settings = await getShopSettings(shopId);
      const barberId = after.assignedBarberId ?? after.barberId;

      const waitingEntries = await getWaitingEntries(shopId, barberId);
      const targetIndex = settings.notifyWhenPositionAway - 1;

      if (waitingEntries.length > targetIndex) {
        const target = waitingEntries[targetIndex];

        if (!target.notifiedAlmostUp) {
          const message = formatMessage(settings.almostUpSmsTemplate, target.customerName);
          await sendSms(target.customerPhone, message);

          await event.data!.after.ref.firestore
            .collection("shops").doc(shopId)
            .collection("queue").doc(waitingEntries[targetIndex].id!)
            .update({ notifiedAlmostUp: true });

          console.log(`[onQueueEntryStarted] Sent "almost up" SMS to ${target.customerName} (${target.customerPhone})`);
        }
      }
    } catch (error) {
      console.error("[onQueueEntryStarted] Error:", error);
    }
  }
);


// MARK: - Trigger 2: Entry removed from queue → send "you're up" to next in line

export const onQueueEntryCompleted = onDocumentDeleted(
  {
    document: "shops/{shopId}/queue/{entryId}",
    secrets: [twilioAccountSid, twilioAuthToken, twilioFromNumber],
  },
  async (event) => {
    const deletedEntry = event.data?.data() as QueueEntry | undefined;
    const { shopId } = event.params;

    if (!deletedEntry) return;
    if (deletedEntry.status === "removed" || deletedEntry.status === "walked_out") {
      console.log(`[onQueueEntryCompleted] Entry removed by barber — skipping notifications`);
      return;
    }

    console.log(`[onQueueEntryCompleted] Service completed for ${deletedEntry.customerName} in shop ${shopId}`);

    try {
      const settings = await getShopSettings(shopId);
      const barberId = deletedEntry.assignedBarberId ?? deletedEntry.barberId;
      const waitingEntries = await getWaitingEntries(shopId, barberId);

      if (waitingEntries.length === 0) {
        console.log("[onQueueEntryCompleted] No one left waiting — no notifications needed");
        return;
      }

      // Send "you're up" to whoever is now first
      const nextUp = waitingEntries[0];
      if (!nextUp.notifiedYoureUp) {
        const message = formatMessage(settings.youreUpSmsTemplate, nextUp.customerName);
        await sendSms(nextUp.customerPhone, message);

        await db.collection("shops").doc(shopId)
          .collection("queue").doc(nextUp.id!)
          .update({
            notifiedYoureUp: true,
            status: "notified",
          });

        console.log(`[onQueueEntryCompleted] Sent "you're up" SMS to ${nextUp.customerName} (${nextUp.customerPhone})`);
      }

      // Send "almost up" to whoever is now at notifyWhenPositionAway
      const targetIndex = settings.notifyWhenPositionAway - 1;
      if (waitingEntries.length > targetIndex) {
        const almostUpTarget = waitingEntries[targetIndex];
        if (!almostUpTarget.notifiedAlmostUp) {
          const message = formatMessage(settings.almostUpSmsTemplate, almostUpTarget.customerName);
          await sendSms(almostUpTarget.customerPhone, message);

          await db.collection("shops").doc(shopId)
            .collection("queue").doc(almostUpTarget.id!)
            .update({ notifiedAlmostUp: true });

          console.log(`[onQueueEntryCompleted] Sent "almost up" SMS to ${almostUpTarget.customerName}`);
        }
      }
    } catch (error) {
      console.error("[onQueueEntryCompleted] Error:", error);
    }
  }
);


// MARK: - Helpers

async function getShopSettings(shopId: string): Promise<ShopSettings> {
  const shopDoc = await db.collection("shops").doc(shopId).get();
  const data = shopDoc.data();
  const settings = data?.settings ?? {};

  return {
    notifyWhenPositionAway: settings.notifyWhenPositionAway ?? 2,
    almostUpSmsTemplate: settings.almostUpSmsTemplate
      ?? "Hey {name}, you're almost up! Head back to the shop.",
    youreUpSmsTemplate: settings.youreUpSmsTemplate
      ?? "Hey {name}, it's your turn! Your barber is ready for you.",
  };
}

async function getWaitingEntries(shopId: string, barberId: string): Promise<(QueueEntry & { id: string })[]> {
  const snapshot = await db
    .collection("shops").doc(shopId)
    .collection("queue")
    .where("barberId", "==", barberId)
    .where("status", "in", ["waiting", "notified"])
    .orderBy("checkInTime", "asc")
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as QueueEntry),
  }));
}

function formatMessage(template: string, fullName: string): string {
  const firstName = fullName.split(" ")[0] ?? fullName;
  return template.replace(/{name}/gi, firstName);
}

async function sendSms(to: string, message: string): Promise<void> {
  const client = twilio(
    twilioAccountSid.value(),
    twilioAuthToken.value()
  );

  await client.messages.create({
    body: message,
    from: twilioFromNumber.value(),
    to: to,
  });

  console.log(`[sendSms] Sent to ${to}: "${message}"`);
}
