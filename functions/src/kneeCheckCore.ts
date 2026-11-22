/**
 * Prompt and response handling for the Accurate-mode photo check. Kept apart from the Cloud
 * Function so it can be unit tested and reused by a local harness without drifting.
 */

export const KNEE_CHECK_MODEL = "gemini-3.8-flash";

export type KneeMeasurementType = "extension" | "flexion";

export const KNEE_PHOTO_PROBLEMS = ["none", "no_person", "framing", "leg_cropped", "camera_angle", "quality"] as const;
export type KneePhotoProblem = (typeof KNEE_PHOTO_PROBLEMS)[number];

export interface KneePhotoCheck {
  ok: boolean;
  problem: KneePhotoProblem;
  message?: string;
}

export interface KneeCheckRequest {
  imageBase64: string;
  measurementType: KneeMeasurementType;
}

const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

/** Throws with a user-safe message when the request is not a JPEG photo and a known measurement type. */
export function validateKneeCheckRequest(data: unknown): KneeCheckRequest {
  if (!data || typeof data !== "object") throw new Error("A photo is required.");
  const value = data as Record<string, unknown>;
  const image = value.imageBase64;
  if (typeof image !== "string" || image.length === 0 || image.length * 0.75 > MAX_IMAGE_BYTES ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(image) || image.length % 4 !== 0) {
    throw new Error("Provide a JPEG photo smaller than 6 MB.");
  }
  const bytes = Buffer.from(image.slice(0, 8), "base64");
  if (bytes.length < 3 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new Error("The photo must be a JPEG image.");
  }
  if (value.measurementType !== "extension" && value.measurementType !== "flexion") {
    throw new Error("Unknown measurement type.");
  }
  return { imageBase64: image, measurementType: value.measurementType };
}

export function buildKneeCheckPrompt(opts: { measurementType: KneeMeasurementType }): string {
  const movement =
    opts.measurementType === "flexion"
      ? "They are bending one knee as far as they can (knee flexion)."
      : "They are straightening one leg as far as they can (knee extension).";
  return `You are checking a photo a patient took to measure their knee angle during ACL rehab. The measurement itself is done by other software that finds the hip, knee and ankle. You only decide whether this photo is usable.

${movement} They may be standing, sitting, or lying on their back, front or side.

The photo is usable when ALL of these hold:
1. One person is clearly the subject.
2. Most of the body is in the frame: the head or upper body, and the measured leg all the way from the hip to the foot.
3. The hip, the knee and the ankle of the measured leg can each be seen or clearly located. Loose clothing is fine if the leg's line is still clear.
4. The camera looks at the SIDE of the leg, so the thigh and shin are both seen in profile. A view from the front, from behind, or from the foot end makes the angle unreliable.
5. The photo is bright and sharp enough to see the leg.

Be practical. Clutter, pillows, ordinary clothing, a slight tilt, or a slightly imperfect side view are fine. Only fail a photo when the problem would clearly make the measurement unreliable.

Respond with ONLY this JSON, no markdown:
{"ok": true, "problem": "none", "message": null}

"problem" is one of: "none", "no_person", "framing" (too close: only the knee or part of the leg, not the body), "leg_cropped" (hip or foot of the measured leg cut off or hidden), "camera_angle" (not a side view of the leg), "quality" (too dark or blurry).
When "ok" is false, "message" is ONE short, friendly sentence (under 120 characters) telling the patient what to change. Otherwise "message" is null.`;
}

/** Keeps the note short for the phone screen, cutting at a sentence boundary rather than mid-word. */
export function shortenMessage(text: string, max = 140): string {
  if (text.length <= max) return text;
  const sentences = text.match(/[^.!?]+[.!?]+/g) ?? [];
  let out = "";
  for (const s of sentences) {
    if ((out + s).trim().length > max) break;
    out += s;
  }
  if (out.trim()) return out.trim();
  const cut = text.slice(0, max);
  return cut.slice(0, cut.lastIndexOf(" ")).trim() + "…";
}

/** Parses the check response. Throws on malformed output so the caller can treat it as "couldn't check". */
export function parseKneeCheckText(text: string | undefined): KneePhotoCheck {
  if (!text) throw new Error("Empty response");
  const cleaned = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("No JSON in model response");
  const raw = JSON.parse(match[0]);
  if (typeof raw.ok !== "boolean") throw new Error("Missing ok");
  if (raw.ok) return { ok: true, problem: "none" };
  const problem: KneePhotoProblem =
    KNEE_PHOTO_PROBLEMS.includes(raw.problem) && raw.problem !== "none" ? raw.problem : "framing";
  const message = typeof raw.message === "string" && raw.message.trim() ? shortenMessage(raw.message.trim()) : undefined;
  return { ok: false, problem, message };
}
