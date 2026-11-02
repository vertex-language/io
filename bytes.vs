package io

// The byte-array helpers every function here needs.

/// The UTF-8 bytes of `text`.
public func Bytes(text: string) -> [uint8] {
    return [uint8](text.utf8)
}

/// `bytes` as UTF-8 text.
public func Text(bytes: [uint8]) -> string {
    return string(decoding: bytes, as: UTF8.self)
}

// prefix is the first n bytes of buf, as their own array.
func prefix(buf: [uint8], n: int) -> [uint8] {
    return Array(buf[0..<n])
}

// appendPrefix appends the first n bytes of buf to out.
func appendPrefix(out: inout [uint8], buf: [uint8], n: int) {
    out.append(contentsOf: buf[0..<n])
}

// copyInto writes count bytes of src into dst starting at offset at.
func copyInto(dst: inout [uint8], at: int, from src: [uint8], count: int) {
    var i = 0
    while i < count {
        dst[at + i] = src[i]
        i += 1
    }
}
