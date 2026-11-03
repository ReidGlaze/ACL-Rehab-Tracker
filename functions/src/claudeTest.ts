import { onCall, HttpsError } from "firebase-functions/v2/https";
import AnthropicVertex from "@anthropic-ai/vertex-sdk";
import { measurementPrompt, parseTestResponse, validateTestRequest } from "./geminiTestCore";
import { testerUIDs } from "./geminiTest";

// "global" rather than production's us-east5: the newer models are not in every single region,
// and this endpoint is for comparison only. Production's region is deliberately left alone.
const anthropic = new AnthropicVertex({
  projectId: process.env.GCLOUD_PROJECT || "acl-rehab-d3e88",
  region: "global",
});

/**
 * Request shape differs by model generation and getting it wrong is a 400:
 *  - "adaptive" (every 4.6+ model, including all of 5.5) rejects `budget_tokens`.
 *  - "budget" (pre-4.6, e.g. Haiku 4.5) predates adaptive thinking and rejects `effort`.
 *
 * MODEL IDS: taken from the Vertex Model Garden naming convention, where Anthropic renders
 * dots as hyphens (Opus 4.6 -> claude-opus-4-6). If a model 404s, correct the key here only.
 */
type ThinkingStyle = "adaptive" | "budget";

/**
 * Keyed by the stable identifier the iOS client sends. `vertexModel` is what actually goes to
 * Vertex, so a model-ID correction (e.g. needing a "@default" version suffix) is a redeploy of
 * this function alone -- it never requires rebuilding and reinstalling the app.
 */
const CLAUDE_TEST_MODELS: Record<string, { vertexModel: string; thinking: ThinkingStyle; maxTokens: number; effort?: string; budgetTokens?: number }> = {
  // Newest generation. Each needs enabling in Vertex Model Garden before it will resolve.
  // xhigh so row 3 is a direct more-thinking A/B against production, which runs this same
  // model at `high`. Production stays at `high` until this shows it actually helps.
  "claude-sonnet-5-5": { vertexModel: "claude-sonnet-5-5", thinking: "adaptive", maxTokens: 16000, effort: "xhigh" },
  // Same model, deepest thinking. Note max_tokens stays 16000: the earlier instant failures
  // here were the SDK's non-streaming guard tripping on a 32000 budget, not the effort level.
  "claude-sonnet-5-5-max": { vertexModel: "claude-sonnet-5-5", thinking: "adaptive", maxTokens: 16000, effort: "max" },
  "claude-haiku-5-5": { vertexModel: "claude-haiku-5-5", thinking: "adaptive", maxTokens: 16000, effort: "high" },
  // Raised to xhigh: at `high` this thought for 11.9s vs Opus 4.6's 16.4s on the same photo,
  // so it was deliberating less, not more.
  "claude-opus-5-5": { vertexModel: "claude-opus-5-5", thinking: "adaptive", maxTokens: 16000, effort: "xhigh" },
  // Fallbacks while 5.5 access is pending, cheapest first.
  "claude-sonnet-5": { vertexModel: "claude-sonnet-5", thinking: "adaptive", maxTokens: 16000, effort: "high" },
  "claude-sonnet-4-6": { vertexModel: "claude-sonnet-4-6", thinking: "adaptive", maxTokens: 16000, effort: "high" },
  // Same model production runs, but on adaptive thinking instead of a fixed 10k budget -- lets
  // you separate "better model" from "better thinking config" instead of changing both at once.
  "claude-opus-4-6": { vertexModel: "claude-opus-4-6", thinking: "adaptive", maxTokens: 16000, effort: "high" },
  // Pre-4.6 generation, so it needs the older thinking shape and rejects `effort`.
  "claude-haiku-4-5": { vertexModel: "claude-haiku-4-5", thinking: "budget", maxTokens: 8000, budgetTokens: 4000 },
};

function validateModel(value: unknown): string {
  if (typeof value !== "string" || !Object.prototype.hasOwnProperty.call(CLAUDE_TEST_MODELS, value)) {
    throw new Error(`Unsupported test model. Choose one of: ${Object.keys(CLAUDE_TEST_MODELS).join(", ")}.`);
  }
  return value;
}

/** Claude returns prose-wrapped JSON, so strip code fences and take the first object. */
function extractJSON(text: string | undefined): string {
  if (!text) throw new Error("No measurement returned. Try a clearer side-view photo.");
  const cleaned = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("The model did not return a measurement. Try another photo.");
  return match[0];
}

// Private test endpoint. Never route production clients here before validation.
export const analyzeKneeAngleClaudeTest = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120, maxInstances: 1, concurrency: 2 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before testing.");
    const allowed = testerUIDs.value().split(",").map((uid) => uid.trim()).filter(Boolean);
    if (!allowed.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "This account is not enabled for model testing.");
    }

    let data;
    let model: string;
    try {
      data = validateTestRequest(request.data);
      model = validateModel((request.data as { model?: unknown })?.model);
    } catch (error) {
      throw new HttpsError("invalid-argument", (error as Error).message);
    }

    const config = CLAUDE_TEST_MODELS[model];
    const body: Record<string, unknown> = {
      model: config.vertexModel,
      max_tokens: config.maxTokens,
      messages: [
        {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: data.imageBase64 } },
            { type: "text", text: measurementPrompt(data) },
          ],
        },
      ],
    };

    if (config.thinking === "adaptive") {
      body.thinking = { type: "adaptive" };
      body.output_config = { effort: config.effort };
    } else {
      body.thinking = { type: "enabled", budget_tokens: config.budgetTokens };
    }

    const started = Date.now();
    try {
      // Cast: the pinned SDK's types predate `adaptive` thinking and `output_config`.
      // The timeout bounds the call under this function's 120s limit. It does NOT suppress the
      // SDK's "streaming is required" guard -- that fires on max_tokens alone, before any
      // request is sent, and the only fixes are a smaller max_tokens or switching to streaming.
      const response = await anthropic.messages.create(
        body as unknown as Parameters<typeof anthropic.messages.create>[0],
        { timeout: 110_000 }
      );

      const blocks = (response as { content: Array<{ type: string; text?: string }> }).content;
      const text = blocks.find((block) => block.type === "text")?.text;
      const result = parseTestResponse(extractJSON(text), model);

      // Log timing only; never log the photo, injury context, or model reasoning.
      console.info("Claude test complete", { model, elapsedMs: Date.now() - started });
      return { ...result, elapsedMs: Date.now() - started };
    } catch (error) {
      const status = (error as { status?: number }).status;
      // Message only -- API errors never contain the photo or the model's reasoning.
      const message = error instanceof Error ? error.message : String(error);
      console.error("Claude test failed", { model, status, elapsedMs: Date.now() - started, message });
      if (status === 429) throw new HttpsError("resource-exhausted", "Test quota reached. Try again later.");
      throw new HttpsError(
        "failed-precondition",
        `${model} could not measure this photo. Try again; production is unaffected.`
      );
    }
  },
);
