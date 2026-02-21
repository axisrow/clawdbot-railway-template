import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("gateway host candidates include loopback fallbacks", () => {
  const src = fs.readFileSync(new URL("../src/server.js", import.meta.url), "utf8");
  assert.match(src, /INTERNAL_GATEWAY_HOST_RAW.*\|\| "localhost"/);
  assert.match(src, /const defaults = \["localhost", "127\.0\.0\.1", "::1"\]/);
});
