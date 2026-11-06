import CryptoKit
import Foundation

struct DownloadResult {
    let fileURL: URL
    let size: Int
}

typealias ProgressCallback = (_ completed: Int, _ total: Int?) -> Void

enum Downloader {
    static func download(
        from remote: URL,
        to local: URL,
        expectedSize: Int?,
        expectedSha256: String? = nil,
        progress: ProgressCallback?
    ) async throws -> DownloadResult {
        var request = URLRequest(url: remote)
        request.httpMethod = "GET"
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdaterError.network("Download failed")
        }
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }

        var total = 0
        let responseExpected = response.expectedContentLength > 0 ? Int(min(response.expectedContentLength, Int64(Int.max))) : nil
        let expected = expectedSize ?? responseExpected
        var hasher = SHA256()
        var buffer: [UInt8] = []
        buffer.reserveCapacity(131_072)
        var iterator = bytes.makeAsyncIterator()
        while let byte = try await iterator.next() {
            buffer.append(byte)
            if buffer.count >= 131_072 {
                let chunk = Data(buffer)
                handle.write(chunk)
                hasher.update(data: chunk)
                total += buffer.count
                progress?(total, expected)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            let chunk = Data(buffer)
            handle.write(chunk)
            hasher.update(data: chunk)
            total += buffer.count
            buffer.removeAll(keepingCapacity: true)
        }
        progress?(total, expected)

        if let expectedSha256, !expectedSha256.isEmpty {
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual.lowercased() == expectedSha256.lowercased() else {
                try? FileManager.default.removeItem(at: local)
                throw UpdaterError.verification("SHA-256 mismatch")
            }
        }
        return DownloadResult(fileURL: local, size: total)
    }
}
