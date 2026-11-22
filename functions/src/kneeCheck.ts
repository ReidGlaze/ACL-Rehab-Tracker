import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import * as admin from "firebase-admin";
import { buildKneeCheckPrompt, KNEE_CHECK_MODEL, parseKneeCheckText, validateKneeCheckRequest } from "./kneeCheckCore";

/** Per-user daily cap. Real use is a handful of photos a day; this only stops scripted abuse. */
const DAILY_LIMIT = 60;

/** Counts today's calls for this user and rejects once over the cap. Stores no photo or health data. */
async function enforceDailyLimit(uid: string): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const ref = admin.firestore().collection("kneeCheckUsage").doc(`${uid}_${day}`);
  const count = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = (snap.exists ? (snap.get("count") as number) : 0) + 1;
    tx.set(ref, { uid, day, count: next, expiresAt: new Date(Date.now() + 3 * 86_400_000) }, { merge: true });
    return next;
  });
  if (count > DAILY_LIMIT) {
    throw new HttpsError("resource-exhausted", "Photo check limit reached for today.");
  }
}

/**
 * Accurate mode: asks Gemini whether a photo is usable (whole leg in frame, side view). The knee
 * angle itself is measured on the phone, so this returns no coordinates and no angle.
 * The photo is used only for this request. It is not stored or logged.
 *
 * The app treats any error from this function as "couldn't check" and still shows the on-device
 * measurement, so a failure here never blocks a user.
 */
export const checkKneePhoto = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 45, maxInstances: 20, concurrency: 20 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Please restart the app and try again.");
    let data;
    try {
      data = validateKneeCheckRequest(request.data);
    } catch (error) {
      throw new HttpsError("invalid-argument", (error as Error).message);
    }

    await enforceDailyLimit(request.auth.uid);

    const ai = new GoogleGenAI({ vertexai: true, project: process.env.GCLOUD_PROJECT || "acl-rehab-d3e88", location: "global" });
    const started = Date.now();
    try {
      const response = await ai.models.generateContent({
        model: KNEE_CHECK_MODEL,
        contents: [{
          role: "user",
          parts: [
            { inlineData: { mimeType: "image/jpeg", data: data.imageBase64 } },
            { text: buildKneeCheckPrompt({ measurementType: data.measurementType }) },
          ],
        }],
        config: {
          temperature: 0,
          maxOutputTokens: 2000,
          responseMimeType: "application/json",
          thinkingConfig: { thinkingLevel: ThinkingLevel.LOW },
          httpOptions: { timeout: 25_000 },
        },
      });
      const result = parseKneeCheckText(response.text);
      // Outcome and timing only; never the photo or the model's message.
      console.info("checkKneePhoto", { ms: Date.now() - started, model: KNEE_CHECK_MODEL, type: data.measurementType, ok: result.ok, problem: result.problem });
      return result;
    } catch (error) {
      const status = (error as { status?: number }).status;
      console.error("checkKneePhoto failed", { ms: Date.now() - started, status });
      throw new HttpsError("internal", "Couldn't check this photo.");
    }
  },
);
