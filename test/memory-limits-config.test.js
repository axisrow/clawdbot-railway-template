import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("server configures explicit child memory limits and diagnostics", () => {
  const src = fs.readFileSync(new URL("../src/server.js", import.meta.url), "utf8");

  assert.match(src, /OPENCLAW_GATEWAY_MAX_OLD_SPACE_MB/);
  assert.match(src, /OPENCLAW_CLI_MAX_OLD_SPACE_MB/);
  assert.match(src, /process\.constrainedMemory/);
  assert.match(src, /function availableMemoryMb\(/);
  assert.match(src, /defaultGatewayMaxOldSpaceMb/);
  assert.match(src, /defaultCliMaxOldSpaceMb/);
  assert.match(src, /if \(!\/\^\\d\+\$\/\.test\(raw\)\)/);
  assert.match(src, /function buildOpenClawChildEnv\(/);
  assert.match(src, /\[gateway\] spawning with NODE_OPTIONS=/);
  assert.match(src, /lastGatewayLaunch/);
  assert.match(src, /memory: openClawMemoryConfig\(\)/);
  assert.match(src, /memory: publicOpenClawMemoryConfig\(\)/);
  assert.match(src, /publicGatewayError\(\)/);
});

test("dockerfile hardens OpenClaw build and runtime memory defaults", () => {
  const dockerfile = fs.readFileSync(new URL("../Dockerfile", import.meta.url), "utf8");

  assert.match(dockerfile, /ARG OPENCLAW_BUILD_MAX_OLD_SPACE_MB=1536/);
  assert.match(dockerfile, /NODE_OPTIONS="--max-old-space-size=\$\{OPENCLAW_BUILD_MAX_OLD_SPACE_MB\}" pnpm install/);
  assert.match(dockerfile, /NODE_OPTIONS="--max-old-space-size=\$\{OPENCLAW_BUILD_MAX_OLD_SPACE_MB\}" pnpm build/);
  assert.doesNotMatch(dockerfile, /OPENCLAW_GATEWAY_MAX_OLD_SPACE_MB=1536/);
  assert.doesNotMatch(dockerfile, /OPENCLAW_CLI_MAX_OLD_SPACE_MB=768/);
});
