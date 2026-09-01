// Pins the exact argv probeCommand() builds, so a regression (a dropped
// property, a broken RuntimeMaxSec clamp, the Environment= conditional flipping,
// or the target guard weakening) fails CI without needing systemd or Hyprland.
import { probeCommand } from "./probe-command.js";
import assert from "node:assert/strict";
import { test } from "node:test";

const SIG = "5c9377c15f85_1700000000_1";
const base = { probeTimeoutMs: 4000, maxOutputBytes: 262144, hyprSignature: SIG };

test("full argv for the workspace probe", () => {
  assert.deepEqual(probeCommand("workspaces", base), [
    "systemd-run", "--user", "--pipe", "--quiet", "--collect",
    "-p", "RuntimeMaxSec=4",
    "-p", "KillSignal=SIGKILL",
    "-p", "LogLevelMax=notice",
    "-p", "Environment=HYPRLAND_INSTANCE_SIGNATURE=" + SIG,
    "--", "sh", "-c", "hyprctl -j workspaces | head -c 262144",
  ]);
});

test("monitors target only changes the sh -c and unit", () => {
  const c = probeCommand("monitors", base);
  assert.equal(c[c.length - 1], "hyprctl -j monitors | head -c 262144");
});

test("RuntimeMaxSec clamps to a positive whole second (never 0)", () => {
  const at = (ms) => probeCommand("workspaces", { ...base, probeTimeoutMs: ms })[6];
  assert.equal(at(4000), "RuntimeMaxSec=4");
  assert.equal(at(4500), "RuntimeMaxSec=5");   // ceil, not truncate
  assert.equal(at(0), "RuntimeMaxSec=1");       // clamp: 0 would disable the deadline
  assert.equal(at(500), "RuntimeMaxSec=1");
});

test("KillSignal and LogLevelMax are always present", () => {
  const c = probeCommand("workspaces", base);
  assert.ok(c.includes("KillSignal=SIGKILL"), "KillSignal must be set");
  assert.ok(c.includes("LogLevelMax=notice"), "LogLevelMax must be set");
});

test("Environment= is omitted for an empty or unsafe signature", () => {
  const has = (sig) => probeCommand("workspaces", { ...base, hyprSignature: sig })
    .some((a) => a.startsWith("Environment="));
  assert.equal(has(SIG), true);
  assert.equal(has(""), false);                 // empty -> manager-env fallback
  assert.equal(has("a b"), false);              // whitespace -> systemd grammar risk, dropped
  assert.equal(has('x"y'), false);              // quote, dropped
  assert.equal(has("a;b"), false);              // separator, dropped
});

test("an unknown target yields an empty command (no sh -c interpolation)", () => {
  assert.deepEqual(probeCommand("evil; rm -rf ~", base), []);
  assert.deepEqual(probeCommand("workspaces; x", base), []);
});
