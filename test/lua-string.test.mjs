// Regression coverage for the workspace-name -> Lua-string encoder.
//
// A workspace name is untrusted (any application can rename a workspace) and is
// interpolated into Lua the compositor parses. The invariant: no input may
// escape the string literal it is placed in. After removing every valid
// fixed-width \ddd escape, no raw " or \ may remain, and every escape is exactly
// three digits with a byte value <= 255 -- so a following literal digit can
// never merge into it.
import { luaString } from "./lua-string.js";
import assert from "node:assert/strict";
import { test } from "node:test";

function inert(enc) {
  assert.equal(enc[0], '"');
  assert.equal(enc[enc.length - 1], '"');
  const inner = enc.slice(1, -1);
  // Every backslash must begin exactly \ddd (three digits, <=255). Matching a
  // fixed three digits -- not \d+ -- is the point: a following literal digit
  // must stay outside the escape, which is the ambiguity this revision fixes.
  const re = /\\(\d{3})/g;
  let m;
  while ((m = re.exec(inner))) {
    assert.ok(Number(m[1]) <= 255, `byte > 255: \\${m[1]}`);
  }
  // No backslash may be followed by fewer than three digits (a short escape).
  assert.ok(!/\\(?!\d{3})/.test(inner), "found a non-\\ddd or short escape");
  const stripped = inner.replace(/\\\d{3}/g, "");
  assert.ok(!/["\\]/.test(stripped), "raw quote or backslash survived");
}

const ADVERSARIAL = [
  ["plain digit", "5"],
  ["printable ascii", "Editor-2"],
  ["spaces", "my project"],
  ["quote breakout", 'evil" }) hl.exec_cmd("touch /tmp/pwned") --'],
  ["statement inject", 'x" })); os.execute("rm -rf ~") --'],
  ["backslash", '\\" injection'],
  ["quote then digit", '"5'],
  ["backslash then digit", "\\5"],
  ["control then digit", "\n5"],
  ["nul then digit", "\u00005"],
  ["long bracket", "tail]]--"],
  ["long bracket level", "]=]"],
  ["newline", "line\nbreak"],
  ["carriage return", "a\rb"],
  ["tab", "a\tb"],
  ["nul byte", "null\u0000byte"],
  ["emoji alone", "🎉"],
  ["emoji then digits", "🎉123"],
  ["multi-codepoint emoji", "👩‍🚀🇺🇸"],
  ["cjk", "日本語"],
  ["accent", "café"],
  ["lone high surrogate", "a\uD800b"],
  ["lone low surrogate", "a\uDC00b"],
  ["max length name", "x".repeat(256)],
  ["only quotes", '""""'],
  ["only backslashes", "\\\\\\\\"],
  ["empty", ""],
];
for (const [name, input] of ADVERSARIAL) test(name, () => inert(luaString(input)));

// Exact-output regressions for the two defects this revision fixes.
test("fixed width: quote+digit is one escape then a literal digit", () => {
  assert.equal(luaString('"5'), '"\\0345"');
});
test("emoji encodes to its real utf-8 bytes", () => {
  assert.equal(luaString("🎉"), '"\\240\\159\\142\\137"');
});
test("printable ascii is preserved", () => {
  assert.equal(luaString("Editor-2"), '"Editor-2"');
});
