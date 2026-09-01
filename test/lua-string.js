// Extracted verbatim from Workspaces.qml (function luaString) so the test
// exercises the shipped encoder. If you change the encoder, copy it here.

export function luaString(value) {
    var s = String(value)
    var out = '"'

    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i)

      // Printable ASCII except the two characters that end or escape a Lua
      // string. Everything else -- quotes, backslashes, control characters,
      // and any code point above 126, including anything multi-byte -- goes
      // out as a numeric escape.
      if (c >= 32 && c <= 126 && c !== 34 && c !== 92) {
        out += s.charAt(i)
      } else if (c <= 255) {
        out += "\\" + c
      } else {
        // Emit the UTF-8 bytes of a higher code point as individual escapes,
        // so the name round-trips rather than being mangled or truncated.
        var bytes = unescape(encodeURIComponent(s.charAt(i)))
        for (var b = 0; b < bytes.length; b++) out += "\\" + bytes.charCodeAt(b)
      }
    }

    return out + '"'
  }
