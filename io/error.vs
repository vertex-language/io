package io

/// IoError is how the functions and adapters in this package fail. The
/// streams underneath fail their own way (fs.FsError, tcp.TcpError), and
/// those errors pass through unchanged.
public enum IoError: Error, Equatable, CustomStringConvertible {
    /// The stream ended before as many bytes as were asked for arrived:
    /// `ReadFull`'s error. `got` is how many did.
    case unexpectedEnd(got: int)
    /// More than `limit` bytes: `ReadToEnd` and `ReadText` stop there.
    case tooLarge(limit: int)
    /// A seek to before the start.
    case invalidSeek(int64)

    public var description: string {
        switch self {
        case .unexpectedEnd(let got):
            return "unexpected end of stream after \(got) bytes"
        case .tooLarge(let limit):
            return "stream longer than the limit of \(limit) bytes"
        case .invalidSeek(let to):
            return "seek to \(to), before the start"
        }
    }
}

/// The limit `ReadToEnd` and `ReadText` use when none is given: 64 MiB.
/// A peer that never stops sending is a denial of service, so reading to
/// the end always has one.
public let DefaultLimit: int = 64 * 1024 * 1024

/// The chunk `Copy` moves at a time.
let copyChunk: int = 32 * 1024
