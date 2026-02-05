import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import * as admin from "firebase-admin";

admin.initializeApp();

// Initialize Google GenAI with Vertex AI
// Gemini 3 models require the global endpoint
const ai = new GoogleGenAI({
  vertexai: true,
  project: process.env.GCLOUD_PROJECT || "acl-rehab-d3e88",
  location: "global",
});

interface AnalyzeKneeAngleRequest {
  imageBase64: string;
  imageBase64_2?: string; // Optional second image for better 3D accuracy
  injuredKnee?: "left" | "right"; // Which knee is injured
  injuryType?: string; // Type of injury (acl_only, acl_meniscus, etc.)
}

interface KeypointCoord {
  x: number;
  y: number;
}

interface AnalyzeKneeAngleResponse {
  angle: number;
  confidence: number;
  hip: KeypointCoord;
  knee: KeypointCoord;
  ankle: KeypointCoord;
}

/**
 * Analyze a leg image and return the knee angle using Vertex AI
 */
export const analyzeKneeAngle = onCall<AnalyzeKneeAngleRequest>(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 120, // Extended for HIGH thinking mode
  },
  async (request): Promise<AnalyzeKneeAngleResponse> => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const { imageBase64, imageBase64_2, injuredKnee, injuryType } = request.data;

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }

    // Build context about the patient's injury
    let injuryContext = "";
    if (injuredKnee || injuryType) {
      injuryContext = "\n\nPATIENT CONTEXT:";
      if (injuredKnee) {
        injuryContext += `\n- The patient's ${injuredKnee.toUpperCase()} knee is the injured one. If both legs are visible, focus on the ${injuredKnee} leg.`;
      }
      if (injuryType) {
        const injuryDescriptions: Record<string, string> = {
          "acl_only": "ACL reconstruction",
          "acl_meniscus": "ACL reconstruction with meniscus repair",
          "acl_mcl": "ACL and MCL repair",
          "acl_meniscus_mcl": "ACL, meniscus, and MCL repair",
          "other": "knee surgery"
        };
        const description = injuryDescriptions[injuryType] || injuryType;
        injuryContext += `\n- The patient had ${description}. This is for rehabilitation tracking.`;
      }
    }

    // Different prompts for single vs dual image
    const singleImagePrompt = `Measure the knee flexion angle in this photo of a leg.

Look at the angle formed at the KNEE JOINT between:
- The THIGH (femur) - from hip to knee
- The SHIN (tibia) - from knee to ankle

MEDICAL CONVENTION:
- 0° = leg is completely STRAIGHT (thigh and shin form a straight line)
- 45° = moderate bend
- 90° = right angle (L-shape)
- 135° = deeply bent (heel near buttock)

IMPORTANT: Focus on the actual bend at the knee joint. If the leg looks straight, it IS close to 0°.${injuryContext}

Return ONLY valid JSON: {"angle":N,"confidence":C}`;

    const dualImagePrompt = `Measure the knee flexion angle using these TWO photos of the same leg.

Look at the angle formed at the KNEE JOINT between:
- The THIGH (femur) - from hip to knee
- The SHIN (tibia) - from knee to ankle

Use both images to get a better understanding of the true angle.

MEDICAL CONVENTION:
- 0° = leg is completely STRAIGHT (thigh and shin form a straight line)
- 45° = moderate bend
- 90° = right angle (L-shape)
- 135° = deeply bent (heel near buttock)${injuryContext}

Return ONLY valid JSON: {"angle":N,"confidence":C}`;

    const prompt = imageBase64_2 ? dualImagePrompt : singleImagePrompt;

    // Build image parts
    const imageParts: Array<{ inlineData: { data: string; mimeType: string } } | { text: string }> = [
      {
        inlineData: {
          data: imageBase64,
          mimeType: "image/jpeg",
        },
      },
    ];

    if (imageBase64_2) {
      imageParts.push({
        inlineData: {
          data: imageBase64_2,
          mimeType: "image/jpeg",
        },
      });
    }

    imageParts.push({ text: prompt });

    try {
      const startTime = Date.now();
      console.log("Starting Gemini analysis with HIGH thinking...");

      const response = await ai.models.generateContent({
        model: "gemini-3-flash-preview",
        contents: [
          {
            role: "user",
            parts: imageParts,
          },
        ],
        config: {
          temperature: 0.1, // Low temperature for consistent output
          maxOutputTokens: 4096,
          thinkingConfig: {
            thinkingLevel: ThinkingLevel.HIGH, // High thinking for better 3D geometry reasoning
          },
        },
      });

      const elapsedMs = Date.now() - startTime;
      console.log(`Gemini response received in ${elapsedMs}ms (${(elapsedMs/1000).toFixed(1)}s)`);

      let text = response.text;
      console.log("AI Response:", text);

      if (!text) {
        throw new HttpsError("internal", "No response from Vertex AI");
      }

      // Strip markdown code blocks if present
      text = text.replace(/```json\s*/g, '').replace(/```\s*/g, '').trim();
      console.log("Cleaned response:", text);

      // Parse the JSON response
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.error("Could not find JSON in response:", text);
        throw new HttpsError("internal", "Invalid response format from AI: " + text.substring(0, 200));
      }

      // Try to parse, if truncated we'll catch the error
      let parsed;
      try {
        parsed = JSON.parse(jsonMatch[0]);
      } catch (parseError) {
        console.error("JSON parse failed, response may be truncated:", jsonMatch[0]);
        throw new HttpsError("internal", "AI response was truncated. Please try again.");
      }

      if (parsed.error) {
        throw new HttpsError("failed-precondition", parsed.error);
      }

      // Validate response structure - only angle is required now
      if (typeof parsed.angle !== "number") {
        throw new HttpsError("internal", "Invalid response structure from AI");
      }

      return {
        angle: Math.round(parsed.angle),
        confidence: parsed.confidence || 0.8,
        // Return dummy coordinates for backward compatibility with iOS app
        hip: { x: 0, y: 0 },
        knee: { x: 0, y: 0 },
        ankle: { x: 0, y: 0 },
      };
    } catch (error) {
      console.error("Vertex AI error:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      // Check for rate limit error
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.includes("429") || errorMessage.includes("RESOURCE_EXHAUSTED") || errorMessage.includes("exhausted")) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many requests. Please wait a moment and try again."
        );
      }

      throw new HttpsError(
        "internal",
        `Failed to analyze image: ${errorMessage}`
      );
    }
  }
);
