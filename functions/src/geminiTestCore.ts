export const GEMINI_TEST_MODEL = "gemini-3.8-flash";

export interface TestImageRequest {
  imageBase64: string;
  injuredKnee?: "left" | "right";
  injuryType?: string;
}

export function validateTestRequest(data: unknown): TestImageRequest {
  if (!data || typeof data !== "object") throw new Error("A photo is required.");
  const value = data as Record<string, unknown>;
  const image = value.imageBase64;
  if (typeof image !== "string" || image.length > 8_000_000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(image) || image.length % 4 !== 0) {
    throw new Error("Provide a JPEG photo smaller than 6 MB.");
  }
  const bytes = Buffer.from(image, "base64");
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new Error("The photo must be a JPEG image.");
  }
  if (value.injuredKnee !== undefined && value.injuredKnee !== "left" && value.injuredKnee !== "right") {
    throw new Error("Invalid knee side.");
  }
  const injuries = ["acl_only", "acl_meniscus", "acl_mcl", "acl_meniscus_mcl", "other"];
  if (value.injuryType !== undefined && (typeof value.injuryType !== "string" || !injuries.includes(value.injuryType))) {
    throw new Error("Invalid injury type.");
  }
  return { imageBase64: image, injuredKnee: value.injuredKnee as TestImageRequest["injuredKnee"], injuryType: value.injuryType as string | undefined };
}

export function parseTestResponse(text: string | undefined) {
  if (!text) throw new Error("No measurement returned. Try a clearer side-view photo.");
  const value = JSON.parse(text);
  if (value.error) throw new Error("The leg could not be measured. Try a clearer side-view photo.");
  if (typeof value.angle !== "number" || !Number.isFinite(value.angle) || value.angle < 0 || value.angle > 180) {
    throw new Error("The model returned an invalid angle. Try another photo.");
  }
  return {
    angle: Math.round(value.angle),
    // Compatibility field only; this is not a calibrated probability of accuracy.
    confidence: 0,
    hip: { x: 0, y: 0 }, knee: { x: 0, y: 0 }, ankle: { x: 0, y: 0 },
    model: GEMINI_TEST_MODEL,
  };
}

export function measurementPrompt(data: TestImageRequest): string {
  const injuries: Record<string, string> = {
    acl_only: "ACL reconstruction", acl_meniscus: "ACL reconstruction with meniscus repair",
    acl_mcl: "ACL and MCL repair", acl_meniscus_mcl: "ACL, meniscus, and MCL repair", other: "knee surgery",
  };
  let context = "";
  if (data.injuredKnee || data.injuryType) {
    context = "\n\nPATIENT CONTEXT:";
    if (data.injuredKnee) context += `\n- The patient's ${data.injuredKnee.toUpperCase()} knee is the injured one. If both legs are visible, focus on the ${data.injuredKnee} leg.`;
    if (data.injuryType) context += `\n- The patient had ${injuries[data.injuryType]}. This is for rehabilitation tracking.`;
  }
  // Keep the measurement instructions aligned with the production Opus prompt.
  return `You are measuring knee FLEXION angle for ACL rehabilitation.

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

Account for camera perspective and foreshortening. Be precise to the nearest degree.${context}

If no leg can be measured, return {"error":"unmeasurable"}. Otherwise return ONLY valid JSON: {"angle":N,"reasoning":"brief explanation"}`;
}
