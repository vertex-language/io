package io

// The byte-array helpers every function here needs. Array slicing and
// String(decoding:) are not in core yet (vsc_TODO.md: Collections, Strings),
// so they are loops.

/// The UTF-8 bytes of `text`.
public func Bytes(_ text: string) -> [uint8] {
    var out: [uint8] = []
    for b in text.utf8 {
        out.append(b)
    }
    return out
}

/// `bytes` as UTF-8 text. A NUL byte ends it, until core can make a string
/// from bytes directly.
public func Text(_ bytes: [uint8]) -> string {
    var chars: [CChar] = []
    for b in bytes {
        if b == 0 {
            break
        }
        chars.append(CChar(truncatingIfNeeded: b))
    }
    chars.append(0)
    return string(cString: chars)
}

// prefix is the first n bytes of buf, as their own array.
func prefix(_ buf: [uint8], _ n: int) -> [uint8] {
    var out: [uint8] = []
    var i = 0
    while i < n {
        out.append(buf[i])
        i += 1
    }
    return out
}

// appendPrefix appends the first n bytes of buf to out.
func appendPrefix(_ out: inout [uint8], _ buf: [uint8], _ n: int) {
    var i = 0
    while i < n {
        out.append(buf[i])
        i += 1
    }
}

// copyInto writes count bytes of src into dst starting at offset at.
func copyInto(_ dst: inout [uint8], at: int, from src: [uint8], count: int) {
    var i = 0
    while i < count {
        dst[at + i] = src[i]
        i += 1
    }
}
