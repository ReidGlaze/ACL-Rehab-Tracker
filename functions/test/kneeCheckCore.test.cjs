const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateKneeCheckRequest, parseKneeCheckText, buildKneeCheckPrompt, shortenMessage } = require('../lib/kneeCheckCore');
const imageBase64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64');

test('rejects missing photos, non-JPEGs, oversized photos and unknown measurement types', () => {
  for (const value of [null, {}, { imageBase64: 'not base64', measurementType: 'flexion' },
    { imageBase64: 'YWJjZA==', measurementType: 'flexion' },
    { imageBase64: 'A'.repeat(8_400_000), measurementType: 'flexion' },
    { imageBase64 }, { imageBase64, measurementType: 'abduction' }]) {
    assert.throws(() => validateKneeCheckRequest(value));
  }
});

test('accepts the request the iOS app sends', () => {
  const value = validateKneeCheckRequest({ imageBase64, measurementType: 'extension' });
  assert.equal(value.measurementType, 'extension');
  assert.match(buildKneeCheckPrompt(value), /straightening one leg/);
  assert.match(buildKneeCheckPrompt({ measurementType: 'flexion' }), /bending one knee/);
});

test('the prompt asks for a verdict only, never an angle or coordinates', () => {
  const prompt = buildKneeCheckPrompt({ measurementType: 'flexion' });
  assert.match(prompt, /"ok": true/);
  assert.doesNotMatch(prompt, /"angle"/);
});

test('a passing photo carries no problem or message', () => {
  assert.deepEqual(parseKneeCheckText('{"ok": true, "problem": "none", "message": null}'), { ok: true, problem: 'none' });
  assert.deepEqual(parseKneeCheckText('```json\n{"ok": true, "problem": "framing", "message": "ignored"}\n```'), { ok: true, problem: 'none' });
});

test('a failing photo keeps its problem and message, and unknown problems fall back to framing', () => {
  assert.deepEqual(
    parseKneeCheckText('{"ok": false, "problem": "leg_cropped", "message": "Your foot is cut off. Step back a little."}'),
    { ok: false, problem: 'leg_cropped', message: 'Your foot is cut off. Step back a little.' });
  assert.equal(parseKneeCheckText('{"ok": false, "problem": "something_else"}').problem, 'framing');
  assert.equal(parseKneeCheckText('{"ok": false, "problem": "none", "message": "  "}').message, undefined);
});

test('malformed output throws so the app treats it as "could not check"', () => {
  for (const value of [undefined, '', 'not json', '{}', '{"ok": "yes"}']) assert.throws(() => parseKneeCheckText(value));
});

test('long messages are cut at a sentence boundary', () => {
  const long = 'Step back so your whole body is in the photo. ' + 'Then turn so the camera sees the side of your leg and keep still. '.repeat(3);
  const short = shortenMessage(long);
  assert.ok(short.length <= 140);
  assert.match(short, /\.$/);
});
