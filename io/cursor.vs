package io

/// Cursor is an array of bytes with a position: a Reader, Writer and
/// Seeker over memory. Reading takes from the position on; writing
/// overwrites from the position and grows the array past its end.
///
///     var mem = io.Cursor()
///     try io.WriteText(&mem, "hello")
///     mem.Position = 0
///     let back = try io.ReadText(&mem)
///
/// Rust's `io::Cursor<Vec<u8>>`; Go splits it into `bytes.Buffer` and
/// `bytes.Reader`.
public struct Cursor: Reader, Writer, Seeker {
    /// The bytes.
    public var Bytes: [uint8]
    /// Where the next read or write starts.
    public var Position: int

    /// An empty cursor, to write into.
    public init() {
        Bytes = []
        Position = 0
    }

    /// A cursor over `bytes`, at their start: to read them.
    public init(_ bytes: [uint8]) {
        Bytes = bytes
        Position = 0
    }

    public mutating func Read(into buffer: inout [uint8]) throws -> int {
        var n = 0
        while n < buffer.count && Position < Bytes.count {
            buffer[n] = Bytes[Position]
            n += 1
            Position += 1
        }
        return n
    }

    public mutating func Write(_ bytes: borrowing [uint8]) throws {
        for b in bytes {
            if Position < Bytes.count {
                Bytes[Position] = b
            } else {
                Bytes.append(b)
            }
            Position += 1
        }
    }

    public mutating func Flush() throws {}

    public mutating func Seek(_ to: SeekFrom) throws -> int64 {
        var at: int64 = 0
        switch to {
        case .start(let n):
            at = n
        case .current(let n):
            at = int64(Position) + n
        case .end(let n):
            at = int64(Bytes.count) + n
        }
        if at < 0 {
            throw IoError.invalidSeek(at)
        }
        // Past the end is allowed; a write there fills the gap with zeros.
        while int64(Bytes.count) < at {
            Bytes.append(0)
        }
        Position = int(at)
        return at
    }
}
