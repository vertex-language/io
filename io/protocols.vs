package io

/// Reader is a source of bytes that answers without waiting: a file, an
/// array in memory, a decompressor over one of those.
public protocol Reader {
    /// Fills the start of `buffer` and returns how many bytes it filled.
    /// 0 is the end of the stream (or an empty buffer); it is never
    /// returned while there is more to come.
    mutating func Read(into buffer: inout [uint8]) throws -> int
}

/// Writer is a sink of bytes that answers without waiting.
public protocol Writer {
    /// Writes all of `bytes`, or throws: there is no partial write.
    mutating func Write(_ bytes: borrowing [uint8]) throws

    /// Sends on whatever is buffered. A writer that buffers nothing does
    /// nothing.
    mutating func Flush() throws
}

/// AsyncReader is a source of bytes whose reads may have to wait -- a
/// socket, a pipe -- and park the task while they do.
public protocol AsyncReader {
    /// As `Reader.Read`: 0 is the end of the stream.
    mutating func Read(into buffer: inout [uint8]) async throws -> int
}

/// AsyncWriter is a sink of bytes whose writes may have to wait.
public protocol AsyncWriter {
    /// Writes all of `bytes`, or throws.
    mutating func Write(_ bytes: borrowing [uint8]) async throws

    /// Sends on whatever is buffered.
    mutating func Flush() async throws
}

/// Closer is something holding a handle to release.
public protocol Closer {
    /// Releases the handle. Closing twice is not an error.
    mutating func Close() throws
}

/// Seeker is a stream with a position that can be moved.
public protocol Seeker {
    /// Moves the position, and returns where it now is from the start.
    mutating func Seek(_ to: SeekFrom) throws -> int64
}

/// Where a seek is measured from.
public enum SeekFrom: Equatable {
    /// This many bytes from the start.
    case start(int64)
    /// This many bytes from where the position is now; negative goes back.
    case current(int64)
    /// This many bytes from the end; negative is before it.
    case end(int64)
}
