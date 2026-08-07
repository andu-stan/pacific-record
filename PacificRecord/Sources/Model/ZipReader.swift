import Compression
import Foundation

/// A minimal, read-only ZIP extractor.
///
/// Foundation can *write* a zip (`NSFileCoordinator`'s `.forUploading`) but
/// offers nothing to read one back, and this app deliberately has no
/// third-party dependencies — so this parses the archive directly and inflates
/// entries with the system Compression framework. It handles the two methods a
/// zip actually uses in practice: stored (0) and deflate (8).
enum ZipReader {
    enum ZipError: LocalizedError {
        case notAZipArchive
        case unsupportedCompression(UInt16)
        case corruptArchive

        var errorDescription: String? {
            switch self {
            case .notAZipArchive: return "That file isn't a zip archive."
            case .unsupportedCompression: return "The archive uses an unsupported compression method."
            case .corruptArchive: return "The archive is damaged and couldn't be read."
            }
        }
    }

    /// Extracts every file into `destination`, recreating the directory
    /// structure. Returns the relative paths written.
    @discardableResult
    static func extract(_ archive: URL, into destination: URL) throws -> [String] {
        // Memory-mapped: a library backup can carry hundreds of MB of covers.
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let directory = try centralDirectory(in: data)

        var written: [String] = []
        for entry in directory {
            // Refuse absolute paths and traversal — never write outside the box.
            let components = entry.path.split(separator: "/").map(String.init)
            guard !entry.path.hasPrefix("/"), !components.contains("..") else { continue }
            guard !entry.path.hasSuffix("/") else { continue }   // directory record

            let fileURL = components.reduce(destination) { $0.appendingPathComponent($1) }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents(of: entry, in: data).write(to: fileURL)
            written.append(entry.path)
        }
        return written
    }

    // MARK: - Parsing

    private struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Walks the central directory, which the End Of Central Directory record
    /// points at. Scanning backwards finds EOCD even with a trailing comment.
    private static func centralDirectory(in data: Data) throws -> [Entry] {
        let eocdSignature: UInt32 = 0x0605_4b50
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { throw ZipError.notAZipArchive }

        var eocd = -1
        let searchLimit = max(0, data.count - minimumEOCD - 0xFFFF)
        var index = data.count - minimumEOCD
        while index >= searchLimit {
            if readUInt32(data, index) == eocdSignature { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZipArchive }

        let entryCount = Int(readUInt16(data, eocd + 10))
        var offset = Int(readUInt32(data, eocd + 16))

        var entries: [Entry] = []
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, readUInt32(data, offset) == 0x0201_4b50 else {
                throw ZipError.corruptArchive
            }
            let method = readUInt16(data, offset + 10)
            let compressed = Int(readUInt32(data, offset + 20))
            let uncompressed = Int(readUInt32(data, offset + 24))
            let nameLength = Int(readUInt16(data, offset + 28))
            let extraLength = Int(readUInt16(data, offset + 30))
            let commentLength = Int(readUInt16(data, offset + 32))
            let localOffset = Int(readUInt32(data, offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { throw ZipError.corruptArchive }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            entries.append(Entry(path: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The local header repeats the name/extra lengths, and the payload follows
    /// it — the central directory's lengths can't be used to find the data.
    private static func contents(of entry: Entry, in data: Data) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, readUInt32(data, header) == 0x0403_4b50 else {
            throw ZipError.corruptArchive
        }
        let nameLength = Int(readUInt16(data, header + 26))
        let extraLength = Int(readUInt16(data, header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corruptArchive }
        let payload = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:
            return payload
        case 8:
            return try inflate(payload, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    /// ZIP method 8 is raw DEFLATE, which is what `COMPRESSION_ZLIB` decodes.
    private static func inflate(_ source: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            source.withUnsafeBytes { input -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = input.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase, uncompressedSize,
                    inputBase, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else { throw ZipError.corruptArchive }
        return output
    }

    // MARK: - Little-endian reads

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
