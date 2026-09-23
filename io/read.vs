package io

// ---- Reading exactly, and to the end -----------------------------------

/// Fills all of `buffer`, reading as many times as it takes. Throws
/// `IoError.unexpectedEnd` where the stream ends first.
public func ReadFull<R: Reader>(_ r: inout R, into buffer: inout [uint8]) throws {
    var got = 0
    var chunk = [uint8](repeating: 0, count: buffer.count)
    while got < buffer.count {
        chunk = [uint8](repeating: 0, count: buffer.count - got)
        let n = try r.Read(into: &chunk)
        if n == 0 {
            throw IoError.unexpectedEnd(got: got)
        }
        copyInto(&buffer, at: got, from: chunk, count: n)
        got += n
    }
}

/// Fills all of `buffer` from an async stream; see the sync form.
public func ReadFull<R: AsyncReader>(_ r: inout R, into buffer: inout [uint8]) async throws {
    var got = 0
    var chunk = [uint8](repeating: 0, count: buffer.count)
    while got < buffer.count {
        chunk = [uint8](repeating: 0, count: buffer.count - got)
        let n = try await r.Read(into: &chunk)
        if n == 0 {
            throw IoError.unexpectedEnd(got: got)
        }
        copyInto(&buffer, at: got, from: chunk, count: n)
        got += n
    }
}

/// Everything until the end of the stream. Throws `IoError.tooLarge` past
/// `limit` bytes (64 MiB where none is given).
public func ReadToEnd<R: Reader>(_ r: inout R, limit: int = 64 * 1024 * 1024) throws -> [uint8] {
    var out: [uint8] = []
    var buf = [uint8](repeating: 0, count: 16384)
    while true {
        let n = try r.Read(into: &buf)
        if n == 0 {
            return out
        }
        if out.count + n > limit {
            throw IoError.tooLarge(limit: limit)
        }
        appendPrefix(&out, buf, n)
    }
}

/// Everything until the end of an async stream; see the sync form.
public func ReadToEnd<R: AsyncReader>(_ r: inout R, limit: int = 64 * 1024 * 1024) async throws -> [uint8] {
    var out: [uint8] = []
    var buf = [uint8](repeating: 0, count: 16384)
    while true {
        let n = try await r.Read(into: &buf)
        if n == 0 {
            return out
        }
        if out.count + n > limit {
            throw IoError.tooLarge(limit: limit)
        }
        appendPrefix(&out, buf, n)
    }
}

/// Everything until the end of the stream, as UTF-8 text.
public func ReadText<R: Reader>(_ r: inout R, limit: int = 64 * 1024 * 1024) throws -> string {
    return Text(try ReadToEnd(&r, limit: limit))
}

/// Everything until the end of an async stream, as UTF-8 text.
public func ReadText<R: AsyncReader>(_ r: inout R, limit: int = 64 * 1024 * 1024) async throws -> string {
    return Text(try await ReadToEnd(&r, limit: limit))
}

// ---- Writing text ------------------------------------------------------

/// Writes `text` as UTF-8.
public func WriteText<W: Writer>(_ w: inout W, _ text: string) throws {
    try w.Write(Bytes(text))
}

/// Writes `text` as UTF-8 to an async stream.
public func WriteText<W: AsyncWriter>(_ w: inout W, _ text: string) async throws {
    try await w.Write(Bytes(text))
}

// ---- Copying -----------------------------------------------------------

/// Copies everything from `r` to `w` until `r` ends, a chunk at a time,
/// and returns how many bytes it copied. It does not flush `w`.
public func Copy<R: Reader, W: Writer>(from r: inout R, to w: inout W) throws -> int64 {
    var total: int64 = 0
    var buf = [uint8](repeating: 0, count: 32768)
    while true {
        let n = try r.Read(into: &buf)
        if n == 0 {
            return total
        }
        try w.Write(prefix(buf, n))
        total += int64(n)
    }
}

/// Copies an async stream to an async sink: a socket to a pipe.
public func Copy<R: AsyncReader, W: AsyncWriter>(from r: inout R, to w: inout W) async throws -> int64 {
    var total: int64 = 0
    var buf = [uint8](repeating: 0, count: 32768)
    while true {
        let n = try await r.Read(into: &buf)
        if n == 0 {
            return total
        }
        try await w.Write(prefix(buf, n))
        total += int64(n)
    }
}

/// Copies an async stream to a sync sink: hashing or saving a download.
public func Copy<R: AsyncReader, W: Writer>(from r: inout R, to w: inout W) async throws -> int64 {
    var total: int64 = 0
    var buf = [uint8](repeating: 0, count: 32768)
    while true {
        let n = try await r.Read(into: &buf)
        if n == 0 {
            return total
        }
        try w.Write(prefix(buf, n))
        total += int64(n)
    }
}

/// Copies a sync stream to an async sink: sending a file down a socket.
public func Copy<R: Reader, W: AsyncWriter>(from r: inout R, to w: inout W) async throws -> int64 {
    var total: int64 = 0
    var buf = [uint8](repeating: 0, count: 32768)
    while true {
        let n = try r.Read(into: &buf)
        if n == 0 {
            return total
        }
        try await w.Write(prefix(buf, n))
        total += int64(n)
    }
}
