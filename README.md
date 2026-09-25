# io

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![runtime: async + sync](https://img.shields.io/badge/runtime-async%20%2B%20sync-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![status: tested](https://img.shields.io/badge/status-tested-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/io)

Streaming I/O abstractions, protocols, buffering, adapters, and cursor operations for bytes, files, sockets, and memory buffers.

> **Status.** The protocols, functions, buffering, adapters and `Cursor`
> are implemented, and `tests/check` passes (32 checks).

---

## Quick Start

Run any entry point with:

```bash
vsc run main.vs
```

Or run the test suite:

```bash
vsc run check
```

---

## Why

`fs.File`, `tcp.TcpStream`, QUIC streams, HTTP bodies and `os/process`
pipes all move bytes, but they don't share an interface, so none of them
can be passed to code written for another. Hashing a download as it
streams, gunzipping an HTTP body or copying a file to a socket each needs
code written for that pair of types. The names don't agree either:

| Type | Read | Everything | Write |
| --- | --- | --- | --- |
| `fs.File` | `Read(into:)` | `ReadToEnd(limit:)` | `Write(_:)`, `WriteText(_:)` |
| `tcp.TcpStream` | `Read(into:) async` | `ReadToEnd(limit:) async` | `Write(_:) async`, `WriteText(_:) async` |
| `quic.Stream` | `Read(maxBytes:) async -> [uint8]` | — | `Write(_:) async` |
| `process.PipeReader` | `Read(into:) async` | `ReadAll() async` | — |

`io` settles on one set of names, taken from what most of these already
use. It defines the protocols they conform to, and the functions and
adapters that work with any of them.

**`io` depends on nothing, and it has no native code.** A type conforms in
its own package (`fs.File: io.Reader`), so `fs`, `net` and `os` depend on
`io`, never the other way round. That's also why it isn't a core package:
the byte-moving is done by the packages that own the handles.

---

## Design rules

1. **A read of 0 bytes is the end of the stream.** This is Rust's rule,
   and what `fs`, `tcp` and `os` already do. There's no `EOF` error to
   catch, as in Go. `ReadFull` throws `io.UnexpectedEnd` where the stream
   ends before the buffer is full.
2. **`Write` writes everything or throws.** This is Go's rule, and what
   every Vertex `Write` already does. There's no partial-write count to
   loop on, unlike Rust's `write` vs `write_all`.
3. **The caller owns the buffer.** `Read(into: &buffer)` fills the
   caller's array and returns the count, so a loop reuses one allocation.
   Once core has `Span`, this becomes `Read(into: MutableSpan<uint8>)`
   (proposal §3.4).
4. **Sync and async are separate protocols.** `Reader` is for things that
   return without waiting (files, memory), and `AsyncReader` for things
   whose waiting parks a task (sockets, pipes). This split is tokio's
   `AsyncRead` and Rust's `Read`. Sync is not wrapped as async: that would
   hide a blocked thread.
5. **Conformance lives with the type.** `fs` declares
   `extension File: io.Reader`, and `io` has no list of the types it
   knows.
6. **Adapters are values.** `io.Limit(r, 1024)` is a `Reader` that wraps
   `r`, so adapters compose like Go's `io.LimitReader` and Rust's
   `take`/`chain`.

---

## Protocols

```swift
public protocol Reader {
    /// Fills the start of `buffer` and returns how many bytes it filled;
    /// 0 only at the end of the stream (or for an empty buffer).
    mutating func Read(into buffer: inout [uint8]) throws -> int
}

public protocol Writer {
    /// Writes all of `bytes`, or throws.
    mutating func Write(_ bytes: borrowing [uint8]) throws
    /// Sends on what is buffered. A no-op for a writer that buffers nothing.
    mutating func Flush() throws
}

public protocol AsyncReader {
    mutating func Read(into buffer: inout [uint8]) async throws -> int
}

public protocol AsyncWriter {
    mutating func Write(_ bytes: borrowing [uint8]) async throws
    mutating func Flush() async throws
}

public protocol Closer {
    /// Releases the handle. Closing twice is not an error.
    mutating func Close() throws
}

public protocol Seeker {
    /// Moves the position and returns it, from the start.
    mutating func Seek(_ to: SeekFrom) throws -> int64
}

public enum SeekFrom { case start(int64), current(int64), end(int64) }   // moved here from fs
```

| Vertex | Rust | Go | tokio | Swift (NIO / Foundation) |
| --- | --- | --- | --- | --- |
| `Reader` | `Read` | `io.Reader` | — | `FileHandle.read(upToCount:)` |
| `Writer` | `Write` | `io.Writer` | — | `FileHandle.write(contentsOf:)` |
| `AsyncReader` | — | — | `AsyncRead` | `AsyncSequence` of bytes |
| `AsyncWriter` | — | — | `AsyncWrite` | NIO `Channel.write` |
| `Seeker` / `SeekFrom` | `Seek` / `SeekFrom` | `io.Seeker` / `whence` | `AsyncSeek` | `FileHandle.seek(toOffset:)` |
| `Closer` | `Drop` | `io.Closer` | `shutdown` | `close()` |

---

## Functions

The functions that everyone ends up writing, each taking any conformer,
with sync and async overloads under the same name:

```swift
import "io"

try io.ReadFull(&r, into: &header)               // exactly header.count bytes, or io.UnexpectedEnd
let body = try io.ReadToEnd(&r, limit: 1 << 20)  // [uint8]; throws io.TooLarge past the limit
let text = try io.ReadText(&r, limit: 1 << 20)   // the same, as UTF-8
try io.WriteText(&w, "hello\n")
let n = try io.Copy(from: &file, to: &socket)    // int64 bytes copied, in 32 KiB chunks
```

| Function | Rust | Go |
| --- | --- | --- |
| `ReadFull(_:into:)` | `read_exact` | `io.ReadFull` |
| `ReadToEnd(_:limit:)` | `read_to_end` | `io.ReadAll` |
| `ReadText(_:limit:)` | `read_to_string` | `io.ReadAll` + `string(...)` |
| `WriteText(_:_:)` | `write_all(s.as_bytes())` | `io.WriteString` |
| `Copy(from:to:)` | `io::copy` | `io.Copy` |

`ReadToEnd` and `ReadText` always take a limit, with a default of 64 MiB.
A peer that never stops sending is a denial of service, and every
`ReadToEnd` in the tree already has a limit (`tcp` 8 MiB, `fs` 100 MiB).
The limit stays; only the default is shared.

These are free functions and not protocol-extension methods (Rust's
`reader.read_to_end()`), because protocol extensions don't work yet (see
below). When they do, the methods become the main API and the functions
stay as thin wrappers.

---

## Buffering

```swift
var r = io.BufferedReader(file)                  // 64 KiB by default; capacity: to change it
while let line = try r.ReadLine() { … }          // "\n" and "\r\n" both end a line; nil at the end
let upTo = try r.ReadUntil(0x00)                 // [uint8]?, through the delimiter
let peek = try r.Peek(4)                         // without consuming: magic numbers, sniffing

var w = io.BufferedWriter(file)
try w.Write(chunk)                               // many small writes, one syscall
try w.Flush()                                    // also done by Close
```

Both have async forms over `AsyncReader` and `AsyncWriter`
(`io.AsyncBufferedReader`). `os/process`'s `LineReader` becomes
`io.AsyncBufferedReader(pipe).ReadLine()`, and its line splitting moves
here. Seven files split lines by hand today: `os/process/pipe.vs`,
`net/http`'s request, response and server, `net/websocket/handshake.vs`,
`net/webrtc/sdp.vs` and `remote/rdp/rdpfile.vs`.

Rust calls these `BufReader`/`BufWriter`, and Go `bufio.Reader`/`Writer`.
The full word matches Vertex's other names.

---

## Adapters and in-memory streams

```swift
var head   = io.Limit(file, 512)                 // reads at most 512 bytes, then ends
var both   = io.Chain(prefix, body)              // one stream after the other
var logged = io.Tee(response, to: log)           // what is read is also written to logged.Output
var sink   = io.Discard                          // a Writer that drops everything, and counts it

var mem = io.Cursor([uint8]())                   // Reader + Writer + Seeker over an owned array
try io.WriteText(&mem, "abc")
let bytes = mem.Bytes                            // what was written

let (rx, tx) = io.Pipe()                         // not yet: an in-memory pair between tasks, once `sync` exists
```

| Vertex | Rust | Go |
| --- | --- | --- |
| `Limit(_:_:)` | `Read::take` | `io.LimitReader` |
| `Chain(_:_:)` | `Read::chain` | `io.MultiReader` |
| `Tee(_:to:)` | — | `io.TeeReader` |
| `Discard` | `io::sink()` | `io.Discard` |
| `Cursor` | `io::Cursor<Vec<u8>>` | `bytes.Buffer` / `bytes.Reader` |
| `Pipe()` | tokio `io::duplex` | `io.Pipe` |

`Cursor` is Rust's name. Go splits the same job across `bytes.Buffer`
(write, then read) and `bytes.Reader` (read and seek); one type with a
position covers both.

---

## Standard streams

`io` has no native code, so the process's standard streams belong to the
package that owns the process: **`process.Stdin`, `process.Stdout` and
`process.Stderr`**. Go puts them in `os`, and Rust in `std::io` over the
platform layer. They conform to `Reader`/`Writer` and to the async
protocols, and `term.IsTerminal(process.Stdout)` takes them. `print` stays
for the common case.

---

## Who conforms (in their own packages)

| Type | Conforms to | Change it needs |
| --- | --- | --- |
| `fs.File` | `Reader`, `Writer`, `Seeker`, `Closer` | `SeekFrom` moves to `io`, and `fs` re-exports it for a release |
| `tcp.TcpStream` | `AsyncReader`, `AsyncWriter` | a no-op `Flush`; not `Closer`, because its `Close` consumes the stream |
| `quic.Stream` | `AsyncReader`, `AsyncWriter` | gains `Read(into:)`; `Read(maxBytes:)` stays as a convenience |
| `process.PipeReader` / `PipeWriter` | `AsyncReader` / `AsyncWriter`, `Closer` | `ReadAll()` is renamed `ReadToEnd(limit:)`, as `fs` and `tcp` name it |
| `process.Stdin` / `Stdout` / `Stderr` | `Reader`/`Writer` and the async pair | new |
| hashes (`hash/*`, `crypto/sha256`, ...) | `Writer` | `Write` feeds the hash, so `io.Copy(from: &file, to: &hasher)` hashes a file |
| `compress/*` | wrap any `Reader`/`Writer` | the next packages, built on this one |
| `http` request and response bodies | `AsyncReader` | the body is a stream rather than a `[uint8]` |

---

## Compiler work

These were all fixed in `vsc` to build this package. Each has a program
in `vsc/tests/compiler` that is checked against `swiftc`.

| Needed for | Fixed |
| --- | --- |
| A generic function called inside `do { } catch { }` | the compiler crashed; a specialization now keeps its caller's catch targets (327) |
| `BufferedReader<R: Reader>` calling `Inner.Read` | it called itself; a requirement on a stored property is now the property's type's method (327) |
| Conforming to `AsyncReader` | witness thunks and existential calls are async and throwing where the requirement is (328) |
| A throwing generic call | its error was dropped; it's `try_apply`'d now (327, 328) |
| `ReadToEnd` over `Reader` beside `ReadToEnd` over `AsyncReader` | overloads resolve by constraint (329) |
| A sync `Flush` or non-throwing `Close` meeting the protocol, and the right one of two `Write`s | witnesses with fewer effects, matched by signature (330) |
| `io.BufferedReader(file)` in another module | a client checks and specializes an imported module's generic declarations, including initializer inference through labels, defaults, and nested generic calls |

Still open, so the API doesn't depend on them: protocol extensions (the
functions above are free functions for now), `AsyncSequence` and
`for await` (`ReadLine()` loops instead), and `String(decoding:)`
(`io.Text` stops at a NUL byte).

---

## Layout

```
io/
  package.vs         one target, "io"; no native target
  io/
    protocols.vs     Reader, Writer, AsyncReader, AsyncWriter, Closer, Seeker, SeekFrom
    read.vs          ReadFull, ReadToEnd, ReadText, Copy, WriteText (sync + async)
    buffered.vs      BufferedReader, BufferedWriter and the async forms
    adapters.vs      Limit, Chain, Tee, Discard
    cursor.vs        Cursor
    bytes.vs         Bytes, Text, and the array helpers
    error.vs         IoError: unexpectedEnd, tooLarge, invalidSeek
  tests/check/main.vs
```

## Roadmap

| Step | Work |
| --- | --- |
| 0 | ✅ the compiler fixes above |
| 1 | ✅ protocols, functions, `Cursor`, adapters, buffering; `tests/check`. `Pipe` after `sync` |
| 2 | ✅ conformances: `fs.File`, `tcp.TcpStream`, `os/process` pipes and `process.Stdin/Stdout/Stderr`; `ReadAll` renamed `ReadToEnd` |
| 3 | `quic.Stream`, and HTTP bodies as streams |
| 4 | `hash` and `compress` on top, the packages this one unblocks |

## Open questions

1. **`Flush` on `Writer`, or its own protocol?** Go has no `Flush` on
   `io.Writer` and puts it on `bufio.Writer`; Rust has `flush` on `Write`.
   Having it on `Writer`, as proposed, means a hasher implements a no-op
   `Flush`, but a function taking a `Writer` can always flush it.
2. **`Close` on consuming types.** `tcp.TcpStream.Close()` is `consuming`,
   and a protocol requirement can't be. Should `Closer` be dropped for
   move-only types in favor of their `deinit`, as with Rust's `Drop`?
3. **`Span` timing.** Designing around `inout [uint8]` now means a second
   migration when `Span` lands. Should `io` wait for `Span` (§3.4)? The
   proposal's step 1 lists it with the core work anyway.

---

## License

[MIT](LICENSE)
