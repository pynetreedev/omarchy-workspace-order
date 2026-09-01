// Extracted verbatim from Workspaces.qml (function luaString) so the test
// exercises the shipped encoder. If you change the encoder, re-extract this.

export function luaString(value) {
  var s = String(value)
  var out = '"'

  for (var i = 0; i < s.length; i++) {
    var cp = s.codePointAt(i)

    if (cp >= 32 && cp <= 126 && cp !== 34 && cp !== 92) {
      out += s.charAt(i)
      continue
    }

    if (cp > 0xFFFF) i++
    if (cp >= 0xD800 && cp <= 0xDFFF) cp = 0xFFFD

    var bytes
    if (cp <= 0x7F) bytes = [cp]
    else if (cp <= 0x7FF) bytes = [0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)]
    else if (cp <= 0xFFFF) bytes = [0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)]
    else bytes = [0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)]

    for (var b = 0; b < bytes.length; b++) out += "\\" + ("00" + bytes[b]).slice(-3)
  }

  return out + '"'
}
