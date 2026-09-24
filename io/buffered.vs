package io

/// BufferedReader reads the stream it wraps a large chunk at a time, and
/// hands it out in the pieces asked for: a line, up to a delimiter, a
/// peek at what comes next. Rust's `BufReader`, Go's `bufio.Reader`.
///
///     var r = io.BufferedReader(file)
///     while let line = try r.ReadLine() { … }
public struct BufferedReader<R: Reader>: Reader {
    /// The stream underneath.
    public var Inner: R
    var buf: [uint8]
    var start: int
    var end: int
    var done: bool

    /// Wraps `inner`, reading `capacity` bytes at a time (64 KiB by default).
    public init(_ inner: R, capacity: int = 65536) {
        Inner = inner
        buf = [uint8](repeating: 0, count: capacity < 16 ? 16 : capacity)
        start = 0
        end = 0
        done = false
    }

    /// How many bytes are read ahead and waiting.
    public var Buffered: int {
        return end - start
    }

    public mutating func Read(into buffer: inout [uint8]) throws -> int {
        if buffer.isEmpty {
            return 0
        }
        if start == end {
            // Nothing buffered: a read as large as the buffer skips it.
            if buffer.count >= buf.count {
                return try Inner.Read(into: &buffer)
            }
            try fill()
            if start == end {
                return 0
            }
        }
        var n = 0
        while n < buffer.count && start < end {
            buffer[n] = buf[start]
            n += 1
            start += 1
        }
        return n
    }

    /// The next `n` bytes without consuming them: fewer only at the end of
    /// the stream. `n` is at most the capacity.
    public mutating func Peek(_ n: int) throws -> [uint8] {
        while end - start < n && !done {
            try fill()
        }
        var out: [uint8] = []
        var i = start
        while i < end && out.count < n {
            out.append(buf[i])
            i += 1
        }
        return out
    }

    /// The bytes up to and including `delimiter`, or what is left where the
    /// stream ends first; nil at the end of the stream.
    public mutating func ReadUntil(_ delimiter: uint8) throws -> [uint8]? {
        var out: [uint8] = []
        while true {
            if start == end {
                try fill()
                if start == end {
                    return out.isEmpty ? nil : out
                }
            }
            while start < end {
                let b = buf[start]
                start += 1
                out.append(b)
                if b == delimiter {
                    return out
                }
            }
        }
    }

    /// The next line, without its "\n" or "\r\n"; nil at the end of the
    /// stream. A last line with no newline is still a line.
    public mutating func ReadLine() throws -> string? {
        guard let bytes = try ReadUntil(10) else {
            return nil
        }
        return lineText(bytes)
    }

    // fill moves what is left to the front and reads more after it.
    mutating func fill() throws {
        if done {
            return
        }
        if start > 0 {
            var i = 0
            while start + i < end {
                buf[i] = buf[start + i]
                i += 1
            }
            end -= start
            start = 0
        }
        if end == buf.count {
            return
        }
        var chunk = [uint8](repeating: 0, count: buf.count - end)
        let n = try Inner.Read(into: &chunk)
        if n == 0 {
            done = true
            return
        }
        copyInto(&buf, at: end, from: chunk, count: n)
        end += n
    }
}

/// BufferedWriter gathers small writes and passes them on a large chunk at
/// a time. `Flush` passes on what is gathered, and flushes the stream
/// underneath. Rust's `BufWriter`, Go's `bufio.Writer`.
public struct BufferedWriter<W: Writer>: Writer {
    /// The stream underneath.
    public var Inner: W
    var buf: [uint8]
    let capacity: int

    public init(_ inner: W, capacity: int = 65536) {
        Inner = inner
        buf = []
        self.capacity = capacity < 16 ? 16 : capacity
    }

    public mutating func Write(_ bytes: borrowing [uint8]) throws {
        if buf.count + bytes.count > capacity {
            try passOn()
        }
        if bytes.count >= capacity {
            try Inner.Write(bytes)
            return
        }
        for b in bytes {
            buf.append(b)
        }
    }

    public mutating func Flush() throws {
        try passOn()
        try Inner.Flush()
    }

    mutating func passOn() throws {
        if buf.isEmpty {
            return
        }
        try Inner.Write(buf)
        buf = []
    }
}

/// AsyncBufferedReader is `BufferedReader` over an `AsyncReader`: what
/// reads a socket or a pipe a line at a time.
public struct AsyncBufferedReader<R: AsyncReader>: AsyncReader {
    public var Inner: R
    var buf: [uint8]
    var start: int
    var end: int
    var done: bool

    public init(_ inner: R, capacity: int = 65536) {
        Inner = inner
        buf = [uint8](repeating: 0, count: capacity < 16 ? 16 : capacity)
        start = 0
        end = 0
        done = false
    }

    public var Buffered: int {
        return end - start
    }

    public mutating func Read(into buffer: inout [uint8]) async throws -> int {
        if buffer.isEmpty {
            return 0
        }
        if start == end {
            if buffer.count >= buf.count {
                return try await Inner.Read(into: &buffer)
            }
            try await fill()
            if start == end {
                return 0
            }
        }
        var n = 0
        while n < buffer.count && start < end {
            buffer[n] = buf[start]
            n += 1
            start += 1
        }
        return n
    }

    public mutating func Peek(_ n: int) async throws -> [uint8] {
        while end - start < n && !done {
            try await fill()
        }
        var out: [uint8] = []
        var i = start
        while i < end && out.count < n {
            out.append(buf[i])
            i += 1
        }
        return out
    }

    public mutating func ReadUntil(_ delimiter: uint8) async throws -> [uint8]? {
        var out: [uint8] = []
        while true {
            if start == end {
                try await fill()
                if start == end {
                    return out.isEmpty ? nil : out
                }
            }
            while start < end {
                let b = buf[start]
                start += 1
                out.append(b)
                if b == delimiter {
                    return out
                }
            }
        }
    }

    public mutating func ReadLine() async throws -> string? {
        guard let bytes = try await ReadUntil(10) else {
            return nil
        }
        return lineText(bytes)
    }

    mutating func fill() async throws {
        if done {
            return
        }
        if start > 0 {
            var i = 0
            while start + i < end {
                buf[i] = buf[start + i]
                i += 1
            }
            end -= start
            start = 0
        }
        if end == buf.count {
            return
        }
        var chunk = [uint8](repeating: 0, count: buf.count - end)
        let n = try await Inner.Read(into: &chunk)
        if n == 0 {
            done = true
            return
        }
        copyInto(&buf, at: end, from: chunk, count: n)
        end += n
    }
}

/// AsyncBufferedWriter is `BufferedWriter` over an `AsyncWriter`.
public struct AsyncBufferedWriter<W: AsyncWriter>: AsyncWriter {
    public var Inner: W
    var buf: [uint8]
    let capacity: int

    public init(_ inner: W, capacity: int = 65536) {
        Inner = inner
        buf = []
        self.capacity = capacity < 16 ? 16 : capacity
    }

    public mutating func Write(_ bytes: borrowing [uint8]) async throws {
        if buf.count + bytes.count > capacity {
            try await passOn()
        }
        if bytes.count >= capacity {
            try await Inner.Write(bytes)
            return
        }
        for b in bytes {
            buf.append(b)
        }
    }

    public mutating func Flush() async throws {
        try await passOn()
        try await Inner.Flush()
    }

    mutating func passOn() async throws {
        if buf.isEmpty {
            return
        }
        try await Inner.Write(buf)
        buf = []
    }
}

// lineText is a line's bytes as text, without the "\n" or "\r\n" ending it.
func lineText(_ bytes: [uint8]) -> string {
    var n = bytes.count
    if n > 0 && bytes[n - 1] == 10 {
        n -= 1
        if n > 0 && bytes[n - 1] == 13 {
            n -= 1
        }
    }
    return Text(prefix(bytes, n))
}

/// AsyncLines is a reader's lines, one at a time, without their line
/// endings: `for try await line in io.AsyncLines(reader) { … }`.
public struct AsyncLines<R: AsyncReader>: AsyncSequence, AsyncIteratorProtocol {
    var reader: AsyncBufferedReader<R>

    public init(_ inner: R) {
        reader = AsyncBufferedReader(inner)
    }

    /// The next line, or nil at the end of the stream.
    public mutating func next() async throws -> string? {
        return try await reader.ReadLine()
    }

    public func makeAsyncIterator() -> AsyncLines<R> {
        return self
    }
}
