package io

/// LimitReader reads at most `Remaining` more bytes of the stream it
/// wraps, and then reports the end: Go's `io.LimitReader`, Rust's `take`.
public struct LimitReader<R: Reader>: Reader {
    /// The stream underneath.
    public var Inner: R
    /// How many bytes may still be read.
    public var Remaining: int

    public init(_ inner: R, _ limit: int) {
        Inner = inner
        Remaining = limit
    }

    public mutating func Read(into buffer: inout [uint8]) throws -> int {
        if Remaining <= 0 || buffer.isEmpty {
            return 0
        }
        if buffer.count <= Remaining {
            let n = try Inner.Read(into: &buffer)
            Remaining -= n
            return n
        }
        var part = [uint8](repeating: 0, count: Remaining)
        let n = try Inner.Read(into: &part)
        copyInto(&buffer, at: 0, from: part, count: n)
        Remaining -= n
        return n
    }
}

/// A reader of at most `limit` bytes of `r`.
public func Limit<R: Reader>(_ r: R, _ limit: int) -> LimitReader<R> {
    return LimitReader(r, limit)
}

/// ChainReader reads one stream to its end and then the other: Go's
/// `io.MultiReader` for two, Rust's `chain`.
public struct ChainReader<A: Reader, B: Reader>: Reader {
    public var First: A
    public var Second: B
    var firstDone: bool

    public init(_ first: A, _ second: B) {
        First = first
        Second = second
        firstDone = false
    }

    public mutating func Read(into buffer: inout [uint8]) throws -> int {
        if !firstDone {
            let n = try First.Read(into: &buffer)
            if n > 0 || buffer.isEmpty {
                return n
            }
            firstDone = true
        }
        return try Second.Read(into: &buffer)
    }
}

/// A reader of `first` and then `second`.
public func Chain<A: Reader, B: Reader>(_ first: A, _ second: B) -> ChainReader<A, B> {
    return ChainReader(first, second)
}

/// TeeReader writes everything it reads from one stream to a writer as
/// well: Go's `io.TeeReader`. The writer is its own, and read back from
/// `Output` once reading is done.
public struct TeeReader<R: Reader, W: Writer>: Reader {
    public var Inner: R
    public var Output: W

    public init(_ inner: R, to writer: W) {
        Inner = inner
        Output = writer
    }

    public mutating func Read(into buffer: inout [uint8]) throws -> int {
        let n = try Inner.Read(into: &buffer)
        if n > 0 {
            try Output.Write(prefix(buffer, n))
        }
        return n
    }
}

/// A reader of `r` that also writes what it reads to `w`.
public func Tee<R: Reader, W: Writer>(_ r: R, to w: W) -> TeeReader<R, W> {
    return TeeReader(r, to: w)
}

/// DiscardWriter accepts everything and keeps nothing, counting as it
/// goes: Go's `io.Discard`, Rust's `io::sink()`.
public struct DiscardWriter: Writer {
    /// How many bytes it has been given.
    public var Count: int64

    public init() {
        Count = 0
    }

    public mutating func Write(_ bytes: borrowing [uint8]) throws {
        Count += int64(bytes.count)
    }

    public mutating func Flush() throws {}
}

/// A writer that drops what it is given.
public var Discard: DiscardWriter {
    return DiscardWriter()
}
