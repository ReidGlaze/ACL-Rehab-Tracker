const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateTestRequest, parseTestResponse, measurementPrompt } = require('../lib/geminiTestCore');
const imageBase64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64');
test('rejects missing images, invalid JPEGs, oversized images and invalid context', () => {
  for (const value of [null, {}, { imageBase64: 'not base64' }, { imageBase64: 'YWJjZA==' },
    { imageBase64: 'A'.repeat(8_000_004) }, { imageBase64, injuredKnee: 'both' },
    { imageBase64, injuryType: 'injected instructions' }]) assert.throws(() => validateTestRequest(value));
});
test('accepts existing client request shape and preserves context', () => {
  const value = validateTestRequest({ imageBase64, injuredKnee: 'left', injuryType: 'acl_meniscus' });
  assert.match(measurementPrompt(value), /LEFT knee/);
  assert.match(measurementPrompt(value), /ACL reconstruction with meniscus repair/);
});
test('preserves zero degrees and compatibility fields without fabricated confidence', () => {
  const result = parseTestResponse('{"angle":0}');
  assert.equal(result.angle, 0); assert.equal(result.confidence, 0);
  assert.deepEqual(result.hip, { x: 0, y: 0 });
  assert.equal(parseTestResponse('{"angle":134.7}').angle, 135);
});
test('rejects unmeasurable, missing, nonnumeric and out-of-range results', () => {
  for (const value of [undefined, '{}', '{"angle":"90"}', '{"angle":-1}', '{"angle":181}',
    '{"angle":1e999}', '{"error":"unmeasurable"}', 'not json']) assert.throws(() => parseTestResponse(value));
});
