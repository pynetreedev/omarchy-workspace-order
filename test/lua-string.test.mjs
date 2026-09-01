// Regression coverage for the workspace-name -> Lua-string encoder.
//
// A workspace name is untrusted (any application can rename a workspace), and
// it is interpolated into a Lua expression the compositor parses. These cases
// assert that no input can escape the string literal it is placed in: after
// removing every valid \ddd escape, no raw " or \ may remain, which is exactly
// the property that keeps the name from becoming syntax.
import { luaString } from "./lua-string.js";
import assert from "node:assert/strict";
import { test } from "node:test";

const ADVERSARIAL = [
  ["plain digit", "5"],
  ["spaces", "my project"],
  ["quote breakout", 'evil" }) hl.exec_cmd("touch /tmp/pwned") --'],
  ["statement inject", 'x" })); os.execute("rm -rf ~") --'],
  ["backslash", '\\" injection'],
  ["long bracket", "tail]]--"],
  ["long bracket level", "]=]"],
  ["newline", "line\nbreak"],
  ["carriage return", "a\rb"],
  ["nul byte", "null\u0000byte"],
  ["tab", "a\tb"],
  ["unicode + emoji", "café 日本語 →"],
  ["only quotes", '""""'],
  ["only backslashes", "\\\\\\\\"],
  ["empty", ""],
];

function escapesAreInert(encoded) {
  assert.equal(encoded[0], '"', "must open with a quote");
  assert.equal(encoded[encoded.length - 1], '"', "must close with a quote");
  const inner = encoded.slice(1, -1).replace(/\\\d{1,3}/g, "");
  assert.ok(!/["\\]/.test(inner), "no raw quote or backslash may survive");
}

for (const [name, input] of ADVERSARIAL) {
  test(name, () => escapesAreInert(luaString(input)));
}

// Printable ASCII passes through untouched, so ordinary names stay readable.
test("printable ascii is preserved", () => {
  assert.equal(luaString("Editor-2"), '"Editor-2"');
});
