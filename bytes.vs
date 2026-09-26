package io

// The byte-array helpers every function here needs.

/// The UTF-8 bytes of `text`.
public func Bytes(_ text: string) -> [uint8] {
    return [uint8](text.utf8)
}

/// `bytes` as UTF-8 text.
public func Text(_ bytes: [uint8]) -> string {
    return string(decoding: bytes, as: UTF8.self)
}

// prefix is the first n bytes of buf, as their own array.
func prefix(_ buf: [uint8], _ n: int) -> [uint8] {
    return Array(buf[0..<n])
}

// appendPrefix appends the first n bytes of buf to out.
func appendPrefix(_ out: inout [uint8], _ buf: [uint8], _ n: int) {
    out.append(contentsOf: buf[0..<n])
}

// copyInto writes count bytes of src into dst starting at offset at.
func copyInto(_ dst: inout [uint8], at: int, from src: [uint8], count: int) {
    var i = 0
    while i < count {
        dst[at + i] = src[i]
        i += 1
    }
}
