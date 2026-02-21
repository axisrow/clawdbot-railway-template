import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("gateway start timeout default is 120000ms", () => {
  const src = fs.readFileSync(new URL("../src/server.js", import.meta.url), "utf8");
  assert.match(src, /GATEWAY_START_TIMEOUT_MS .*\"120000\"/);
});

test("gateway warmup tracking uses gatewayStartedAt", () => {
  const src = fs.readFileSync(new URL("../src/server.js", import.meta.url), "utf8");
  assert.match(src, /let gatewayStartedAt = null/);
  assert.match(src, /const ageMs = gatewayStartedAt \? Date\.now\(\) - gatewayStartedAt/);
});
