import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import { GEMINI_TEST_MODEL, measurementPrompt, parseTestResponse, validateTestRequest } from "./geminiTestCore";

const testerUIDs = defineString("GEMINI_TESTER_UIDS", { default: "" });

// Private test endpoint. Never route production clients here before validation.
export const analyzeKneeAngleGeminiTest = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120, maxInstances: 1, concurrency: 2 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before testing.");
    const allowed = testerUIDs.value().split(",").map((uid) => uid.trim()).filter(Boolean);
    if (!allowed.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "This account is not enabled for model testing.");
    }
    let data;
    try { data = validateTestRequest(request.data); }
    catch (error) { throw new HttpsError("invalid-argument", (error as Error).message); }

    const ai = new GoogleGenAI({ vertexai: true, project: process.env.GCLOUD_PROJECT, location: "global" });
    const started = Date.now();
    try {
      const response = await ai.models.generateContent({
        model: GEMINI_TEST_MODEL,
        contents: [{ role: "user", parts: [
          { inlineData: { mimeType: "image/jpeg", data: data.imageBase64 } },
          { text: measurementPrompt(data) },
        ] }],
        config: {
          maxOutputTokens: 8192,
          thinkingConfig: { thinkingLevel: ThinkingLevel.HIGH },
          responseMimeType: "application/json",
          responseJsonSchema: {
            type: "object", properties: {
              angle: { type: "number", minimum: 0, maximum: 180 },
              reasoning: { type: "string" }, error: { type: "string" },
            },
          },
        },
      });
      const result = parseTestResponse(response.text);
      // Log timing only; never log the photo, injury context, or model reasoning.
      console.info("Gemini test complete", { model: GEMINI_TEST_MODEL, elapsedMs: Date.now() - started });
      return { ...result, elapsedMs: Date.now() - started };
    } catch (error) {
      const status = (error as { status?: number }).status;
      console.error("Gemini test failed", { status, elapsedMs: Date.now() - started });
      if (status === 429) throw new HttpsError("resource-exhausted", "Test quota reached. Try again later.");
      throw new HttpsError("failed-precondition", "Gemini could not measure this photo. Try again; production is unaffected.");
    }
  },
);
