const { test } = require('node:test');
const assert = require('node:assert/strict');
process.env.GEMINI_TESTER_UIDS = 'authorized-test-user';
const { analyzeKneeAngleGeminiTest } = require('../lib/geminiTest');
test('requires authentication before processing a photo', async () => {
  await assert.rejects(analyzeKneeAngleGeminiTest.run({ data: {} }), { code: 'unauthenticated' });
});
test('denies ordinary production users before processing a photo', async () => {
  await assert.rejects(analyzeKneeAngleGeminiTest.run({ auth: { uid: 'ordinary-app-user' }, data: {} }), { code: 'permission-denied' });
});
test('rejects malformed tester requests before any model call', async () => {
  await assert.rejects(analyzeKneeAngleGeminiTest.run({ auth: { uid: 'authorized-test-user' }, data: {} }), { code: 'invalid-argument' });
});
