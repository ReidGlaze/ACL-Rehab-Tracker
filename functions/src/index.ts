import { onCall, HttpsError } from "firebase-functions/v2/https";
import AnthropicVertex from "@anthropic-ai/vertex-sdk";
import * as admin from "firebase-admin";
import { measurementPrompt } from "./geminiTestCore";

admin.initializeApp();

// Initialize Anthropic client via Vertex AI
// "global" rather than us-east5: this is the only region Sonnet 5.5 has been verified working in
// from this project (via the test endpoint), and global is also cheaper ($2.00/$10.00 per MTok
// vs $2.20/$11.00 regional).
const anthropic = new AnthropicVertex({
  projectId: process.env.GCLOUD_PROJECT || "acl-rehab-d3e88",
  region: "global",
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
 * Analyze a leg image and return the knee angle using Claude Sonnet 5.5 via Vertex AI
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

    // Shared with the model-test endpoints so production and the comparison harness can never
    // drift apart. Includes the patient context and the revised hip-out-of-frame wording.
    const measurementInstructions = measurementPrompt({ imageBase64, injuredKnee, injuryType });

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
      console.log("Starting Claude Sonnet 5.5 analysis...");

      // Sonnet 5.5 rejects `budget_tokens` with a 400 -- every 4.6+ model uses adaptive thinking
      // with `effort` instead. Cast because the pinned SDK's types predate both fields.
      const response = await anthropic.messages.create(
        {
          model: "claude-sonnet-5-5",
          // Do NOT raise this without switching to streaming. The SDK throws
          // "Streaming is required for operations that may take longer than 10 minutes" from
          // calculateNonstreamingTimeout based on max_tokens alone -- an explicit timeout does
          // not suppress it. 32000 here took production down 100%; 16000 is verified working.
          max_tokens: 16000,
          thinking: { type: "adaptive" },
          output_config: { effort: "high" },
          messages: [
            {
              role: "user",
              content: content,
            },
          ],
        } as unknown as Parameters<typeof anthropic.messages.create>[0],
        // 60s keeps us inside the SHIPPED
        // app's callable deadline, which is Firebase's 70s default -- GeminiPoseService only
        // raises it to 120s under ACL_MODEL_TEST, so released users get 70s. Failing here first
        // returns a real error message instead of a client-side timeout.
        { timeout: 60_000 }
      );

      const elapsedMs = Date.now() - startTime;
      console.log(`Claude response received in ${elapsedMs}ms (${(elapsedMs / 1000).toFixed(1)}s)`);

      // Real token counts so cost can be measured rather than estimated. Output includes
      // thinking tokens, which dominate spend on this workload.
      const usage = (response as { usage?: { input_tokens?: number; output_tokens?: number } }).usage;
      console.log("Token usage", { input: usage?.input_tokens, output: usage?.output_tokens });

      // Extract text from response (skip thinking blocks). Cast because the params cast above
      // widens the return type to include the streaming variant, which this call never is.
      const blocks = (response as { content: Array<{ type: string; text?: string }> }).content;
      const textBlock = blocks.find((block: { type: string }) => block.type === "text");
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

export { analyzeKneeAngleGeminiTest } from "./geminiTest";
export { analyzeKneeAngleClaudeTest } from "./claudeTest";
