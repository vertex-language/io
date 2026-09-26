// io test suite.
package main

import "io"

var failures: int32 = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

// Trickle is a Reader that hands out one byte a read, which is what makes
// a short read real rather than hypothetical.
struct Trickle: io.Reader {
    var data: [uint8]
    var at: int

    mutating func Read(into buffer: inout [uint8]) throws -> int {
        if at >= data.count || buffer.isEmpty {
            return 0
        }
        buffer[0] = data[at]
        at += 1
        return 1
    }
}

// AsyncTrickle is the same, but has to be awaited: a socket's shape.
struct AsyncTrickle: io.AsyncReader {
    var data: [uint8]
    var at: int

    mutating func Read(into buffer: inout [uint8]) async throws -> int {
        if at >= data.count || buffer.isEmpty {
            return 0
        }
        buffer[0] = data[at]
        at += 1
        return 1
    }
}

// Collect is an AsyncWriter into memory.
struct Collect: io.AsyncWriter {
    var got: [uint8]
    var flushes: int

    mutating func Write(_ bytes: borrowing [uint8]) async throws {
        for b in bytes {
            got.append(b)
        }
    }

    mutating func Flush() async throws {
        flushes += 1
    }
}

func testCursor() {
    do {
        var c = io.Cursor()
        try io.WriteText(&c, "hello world")
        check(c.Position == 11 && c.Bytes.count == 11, "Cursor Write moves the position")
        _ = try c.Seek(.start(6))
        try io.WriteText(&c, "WORLD")
        check(io.Text(c.Bytes) == "hello WORLD", "Cursor Write overwrites at the position")
        _ = try c.Seek(.start(0))
        check(try io.ReadText(&c) == "hello WORLD", "Cursor ReadText")
        let at = try c.Seek(.end(-5))
        check(at == 6, "Cursor Seek from the end")
        _ = try c.Seek(.current(2))
        var two = [uint8](repeating: 0, count: 2)
        try io.ReadFull(&c, into: &two)
        check(two[0] == 82 && two[1] == 76, "Cursor Seek from current")
        do {
            _ = try c.Seek(.current(-100))
            check(false, "Cursor Seek before the start throws")
        } catch let e as io.IoError {
            check(e == .invalidSeek(-90), "Cursor Seek before the start throws")
        }
    } catch {
        check(false, "Cursor: \(error)")
    }
}

func testReadFull() {
    do {
        var t = Trickle(data: io.Bytes("abcdef"), at: 0)
        var four = [uint8](repeating: 0, count: 4)
        try io.ReadFull(&t, into: &four)
        check(io.Text(four) == "abcd", "ReadFull gathers short reads")
        var three = [uint8](repeating: 0, count: 3)
        try io.ReadFull(&t, into: &three)
        check(false, "ReadFull throws at an early end")
    } catch let e as io.IoError {
        check(e == .unexpectedEnd(got: 2), "ReadFull throws unexpectedEnd with what it got")
    } catch {
        check(false, "ReadFull: \(error)")
    }
}

func testReadToEnd() {
    do {
        var t = Trickle(data: io.Bytes("0123456789"), at: 0)
        let all = try io.ReadToEnd(&t)
        check(all.count == 10, "ReadToEnd reads everything")
        var t2 = Trickle(data: io.Bytes("0123456789"), at: 0)
        _ = try io.ReadToEnd(&t2, limit: 5)
        check(false, "ReadToEnd stops at the limit")
    } catch let e as io.IoError {
        check(e == .tooLarge(limit: 5), "ReadToEnd throws tooLarge past the limit")
    } catch {
        check(false, "ReadToEnd: \(error)")
    }
}

func testAdapters() {
    do {
        var l = io.Limit(Trickle(data: io.Bytes("abcdefgh"), at: 0), 3)
        check(try io.ReadText(&l) == "abc", "Limit ends after its limit")

        var big = io.Limit(io.Cursor(io.Bytes("abcdefgh")), 5)
        var buf = [uint8](repeating: 0, count: 64)
        check(try big.Read(into: &buf) == 5, "Limit caps a large read")

        var ch = io.Chain(io.Cursor(io.Bytes("head-")), Trickle(data: io.Bytes("tail"), at: 0))
        check(try io.ReadText(&ch) == "head-tail", "Chain reads one then the other")

        var tee = io.Tee(io.Cursor(io.Bytes("copied")), to: io.Cursor())
        check(try io.ReadText(&tee) == "copied", "Tee reads through")
        check(io.Text(tee.Output.Bytes) == "copied", "Tee writes what it reads")

        var from = io.Cursor(io.Bytes("move me"))
        var to = io.Discard
        let n = try io.Copy(from: &from, to: &to)
        check(n == 7 && to.Count == 7, "Copy into Discard counts")

        var src = Trickle(data: io.Bytes("slowly"), at: 0)
        var dst = io.Cursor()
        _ = try io.Copy(from: &src, to: &dst)
        check(io.Text(dst.Bytes) == "slowly", "Copy gathers every short read")
    } catch {
        check(false, "adapters: \(error)")
    }
}

func testBuffered() {
    do {
        var r = io.BufferedReader(Trickle(data: io.Bytes("one\ntwo\r\n\nlast"), at: 0), capacity: 16)
        check(try r.Peek(3) == io.Bytes("one"), "BufferedReader Peek")
        var lines: [string] = []
        while let line = try r.ReadLine() {
            lines.append(line)
        }
        check(lines.count == 4 && lines[0] == "one" && lines[1] == "two" && lines[2] == "" && lines[3] == "last",
              "BufferedReader ReadLine: \\n, \\r\\n, empty, and an unterminated last line")

        var u = io.BufferedReader(io.Cursor(io.Bytes("key=value;rest")))
        check(try u.ReadUntil(61) == io.Bytes("key="), "BufferedReader ReadUntil includes the delimiter")
        var rest = [uint8](repeating: 0, count: 64)
        let n = try u.Read(into: &rest)
        check(n == 10, "BufferedReader Read after ReadUntil")

        var w = io.BufferedWriter(io.Cursor(), capacity: 16)
        try io.WriteText(&w, "abc")
        check(w.Inner.Bytes.isEmpty, "BufferedWriter holds small writes")
        try w.Flush()
        check(io.Text(w.Inner.Bytes) == "abc", "BufferedWriter Flush passes them on")
        try io.WriteText(&w, "0123456789abcdefXYZ")
        check(w.Inner.Bytes.count == 22, "BufferedWriter passes on a write larger than itself")
    } catch {
        check(false, "buffered: \(error)")
    }
}

func testAsync() async {
    do {
        var t = AsyncTrickle(data: io.Bytes("async body"), at: 0)
        check(try await io.ReadText(&t) == "async body", "async ReadText")

        var br = io.AsyncBufferedReader(AsyncTrickle(data: io.Bytes("GET / HTTP/1.1\r\nHost: x\r\n\r\n"), at: 0))
        var lines: [string] = []
        while let line = try await br.ReadLine() {
            lines.append(line)
        }
        check(lines.count == 3 && lines[0] == "GET / HTTP/1.1" && lines[1] == "Host: x" && lines[2] == "",
              "AsyncBufferedReader ReadLine over a request")

        var src = AsyncTrickle(data: io.Bytes("download"), at: 0)
        var hash = io.Cursor()
        let n = try await io.Copy(from: &src, to: &hash)
        check(n == 8 && io.Text(hash.Bytes) == "download", "Copy from async to sync")

        var file = io.Cursor(io.Bytes("upload"))
        var sock = Collect(got: [], flushes: 0)
        _ = try await io.Copy(from: &file, to: &sock)
        check(io.Text(sock.got) == "upload", "Copy from sync to async")

        var bw = io.AsyncBufferedWriter(Collect(got: [], flushes: 0), capacity: 16)
        try await io.WriteText(&bw, "hi")
        check(bw.Inner.got.isEmpty, "AsyncBufferedWriter holds small writes")
        try await bw.Flush()
        check(io.Text(bw.Inner.got) == "hi" && bw.Inner.flushes == 1, "AsyncBufferedWriter Flush")

        var short = AsyncTrickle(data: io.Bytes("ab"), at: 0)
        var three = [uint8](repeating: 0, count: 3)
        do {
            try await io.ReadFull(&short, into: &three)
            check(false, "async ReadFull throws at an early end")
        } catch let e as io.IoError {
            check(e == .unexpectedEnd(got: 2), "async ReadFull throws unexpectedEnd")
        }
    } catch {
        check(false, "async: \(error)")
    }
}

// Existentials: code written against the protocol, handed whatever conforms.
func countAny(_ r: inout any io.Reader) throws -> int {
    var buf = [uint8](repeating: 0, count: 4)
    var total = 0
    while true {
        let n = try r.Read(into: &buf)
        if n == 0 {
            return total
        }
        total += n
    }
}

func testExistential() {
    do {
        var a: any io.Reader = io.Cursor(io.Bytes("12345"))
        var b: any io.Reader = Trickle(data: io.Bytes("123"), at: 0)
        check(try countAny(&a) == 5 && try countAny(&b) == 3, "any io.Reader")
    } catch {
        check(false, "existential: \(error)")
    }
}

func main() async -> int32 {
    testCursor()
    testReadFull()
    testReadToEnd()
    testAdapters()
    testBuffered()
    await testAsync()
    testExistential()
    if failures > 0 {
        print("\(failures) failed")
        return 1
    }
    print("all passed")
    return 0
}
