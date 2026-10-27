import { onCall, HttpsError } from "firebase-functions/v2/https";
import AnthropicVertex from "@anthropic-ai/vertex-sdk";
import * as admin from "firebase-admin";

admin.initializeApp();

// Initialize Anthropic client via Vertex AI
const anthropic = new AnthropicVertex({
  projectId: process.env.GCLOUD_PROJECT || "acl-rehab-d3e88",
  region: "us-east5",
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
 * Analyze a leg image and return the knee angle using Claude Opus 4.6 via Vertex AI
 */
export const analyzeKneeAngle = onCall<AnalyzeKneeAngleRequest>(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 120,
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
    const measurementInstructions = `You are measuring knee FLEXION angle for ACL rehabilitation.

HOW TO MEASURE:
1. Find the HIP joint (or top of thigh if hip is hidden)
2. Find the KNEE joint center
3. Find the ANKLE joint
4. The geometric angle at the knee (between thigh line and shin line) is ~180° when straight, ~90° when bent to an L-shape
5. FLEXION ANGLE = 180 minus that geometric angle

FLEXION SCALE:
- 0° = fully straight (thigh and shin in a straight line)
- 45° = slightly bent
- 90° = L-shape, thigh and shin perpendicular
- 120°+ = deep bend, heel near buttock

IMPORTANT: Do NOT measure the shin's angle relative to the floor or any other reference. Measure the bend AT the knee joint between the thigh and shin segments.

Account for camera perspective and foreshortening. Be precise to the nearest degree.${injuryContext}

Return ONLY valid JSON: {"angle":N,"reasoning":"brief explanation"}`;

    const singleImagePrompt = measurementInstructions;

    const dualImagePrompt = `Use both photos of the same leg for better accuracy.\n\n${measurementInstructions}`;

    const prompt = imageBase64_2 ? dualImagePrompt : singleImagePrompt;

    // Build message content with images
    const content: Array<{ type: "image"; source: { type: "base64"; media_type: "image/jpeg"; data: string } } | { type: "text"; text: string }> = [
      {
        type: "image",
        source: {
          type: "base64",
          media_type: "image/jpeg",
          data: imageBase64,
        },
      },
    ];

    if (imageBase64_2) {
      content.push({
        type: "image",
        source: {
          type: "base64",
          media_type: "image/jpeg",
          data: imageBase64_2,
        },
      });
    }

    content.push({ type: "text", text: prompt });

    try {
      const startTime = Date.now();
      console.log("Starting Claude Opus 4.6 analysis...");

      const response = await anthropic.messages.create({
        model: "claude-opus-4-6",
        max_tokens: 16000,
        thinking: {
          type: "enabled",
          budget_tokens: 10000,
        },
        messages: [
          {
            role: "user",
            content: content,
          },
        ],
      });

      const elapsedMs = Date.now() - startTime;
      console.log(`Claude response received in ${elapsedMs}ms (${(elapsedMs / 1000).toFixed(1)}s)`);

      // Extract text from response (skip thinking blocks)
      const textBlock = response.content.find((block: { type: string }) => block.type === "text");
      let text = textBlock && "text" in textBlock ? textBlock.text : null;
      console.log("AI Response:", text);

      if (!text) {
        throw new HttpsError("internal", "No response from Claude");
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

      // Validate response structure - only angle is required
      if (typeof parsed.angle !== "number") {
        throw new HttpsError("internal", "Invalid response structure from AI");
      }

      // Log reasoning for debugging
      if (parsed.reasoning) {
        console.log("AI reasoning:", parsed.reasoning);
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
      console.error("Claude AI error:", error);
      console.error("Claude error detail:", JSON.stringify(error, Object.getOwnPropertyNames(error ?? {})));

      if (error instanceof HttpsError) {
        throw error;
      }

      // Check for rate limit error
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.includes("429") || errorMessage.includes("RESOURCE_EXHAUSTED") || errorMessage.includes("rate")) {
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
