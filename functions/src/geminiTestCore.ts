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

export function parseTestResponse(text: string | undefined, modelName: string = GEMINI_TEST_MODEL) {
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
    model: modelName,
    // Returned to the test device so a wrong angle can be diagnosed. Still never logged here.
    reasoning: typeof value.reasoning === "string" ? value.reasoning : undefined,
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

WHAT TO MEASURE
The angle where the thigh meets the shin, at the knee.
- THIGH segment: the long axis of the upper leg. The hip is usually outside the frame in these
  photos. That is normal and expected. Read the thigh's direction from whatever portion of it is
  visible and extend that line to the knee. Do not search for the hip, do not guess a hip
  position off-frame, and do not decline to measure because the hip is not visible.
- SHIN segment: the long axis of the lower leg, running from the knee toward the ankle.
- The geometric angle is the angle between those two lines where they meet at the knee.

CONVERTING TO FLEXION
FLEXION = 180 minus the geometric angle.
- Thigh and shin forming one straight line (geometric 180°) = 0° flexion, leg fully straight
- Geometric 135° = 45° flexion
- Geometric 90°, an L-shape = 90° flexion
- Geometric 45° = 135° flexion, heel near buttock

REPORTING FULL EXTENSION
0 is a normal, expected answer, not an edge case. Full extension is the goal of this measurement
and many people reach it. If the thigh and shin form a straight line, report 0. Do not round away
from 0 to a small positive number out of caution. Report a few degrees of flexion only when you
can actually see a bend at the knee.

TWO MISTAKES THAT PRODUCE LARGE ERRORS
1. Measuring a segment against an external reference. The floor, a wall, a bed, the horizon, and
   the edges of the image are all irrelevant. A shin angled steeply away from the floor can still
   belong to an almost straight leg. Only the angle between thigh and shin counts.
2. Treating camera perspective as bend. Foreshortening makes a segment pointed toward or away
   from the camera look shorter than it is, which reads as more bend than is really present.
   Judge the joint itself.

Be precise to the nearest degree.${context}

If no leg can be measured, return {"error":"unmeasurable"}. Otherwise return ONLY valid JSON: {"angle":N,"reasoning":"brief explanation"}`;
}
