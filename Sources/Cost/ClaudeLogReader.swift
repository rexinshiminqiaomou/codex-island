import Foundation

/// Walks the local Claude Code session JSONL files and emits TokenEvents for
/// every assistant message that recorded usage. Mirrors ccusage's data path:
///   - reads from ~/.claude/projects/**/*.jsonl AND ~/.config/claude/projects/**/*.jsonl
///   - honors CLAUDE_CONFIG_DIR (comma-separated) when set
///   - dedupes by `messageId:requestId`
///   - skips synthetic placeholder models
///
/// Per-file parse results are memoized in `~/Library/Caches/.../claude-parse-cache.v1.json`
/// keyed by (path, mtime, size). Between two 5/15/30-minute polls almost no
/// file has changed, so the steady-state refresh skips the JSONL scan entirely
/// and only walks the events list to dedup + filter by cutoff.
enum ClaudeLogReader {
    /// Walk the configured project roots and return every usage-bearing
    /// assistant turn from the last `lookbackDays` days. Pure file IO; no
    /// network. Safe to call from a background thread.
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var cache = loadCache()
        var seen = Set<String>()
        var out: [TokenEvent] = []
        var visited = Set<String>()
        var cacheChanged = false

        for root in projectRoots() {
            for entry in jsonlFiles(under: root, modifiedAfter: cutoff) {
                let path = entry.url.path
                visited.insert(path)

                let cachedEvents: [CachedEvent]
                if let hit = cache.files[path], hit.matches(mtime: entry.mtime, size: entry.size) {
                    cachedEvents = hit.events
                } else {
                    cachedEvents = parseFile(at: entry.url)
                    cache.files[path] = CachedFile(
                        mtime: entry.mtime, size: entry.size, events: cachedEvents
                    )
                    cacheChanged = true
                }

                for ev in cachedEvents {
                    guard ev.timestamp >= cutoff else { continue }
                    if !ev.dedupKey.isEmpty {
                        if seen.contains(ev.dedupKey) { continue }
                        seen.insert(ev.dedupKey)
                    }
                    out.append(TokenEvent(
                        provider: .claude,
                        timestamp: ev.timestamp,
                        model: ev.model,
                        inputTokens: ev.inputTokens,
                        outputTokens: ev.outputTokens,
                        cacheCreationTokens: ev.cacheCreationTokens,
                        cacheReadTokens: ev.cacheReadTokens
                    ))
                }
            }
        }

        // Drop cache entries for files that disappeared or rolled out of the
        // cutoff — otherwise the cache grows unbounded over months.
        let preCount = cache.files.count
        cache.files = cache.files.filter { visited.contains($0.key) }
        if cache.files.count != preCount { cacheChanged = true }

        if cacheChanged { saveCache(cache) }
        return out
    }

    private static func projectRoots() -> [URL] {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            return env.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("projects", isDirectory: true)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private struct FileEntry {
        let url: URL
        let mtime: Date
        let size: Int64
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [FileEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var hits: [FileEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  let mtime = values?.contentModificationDate,
                  let size = values?.fileSize else { continue }
            if mtime < cutoff { continue }
            hits.append(FileEntry(url: url, mtime: mtime, size: Int64(size)))
        }
        return hits
    }

    /// Parse a single file end-to-end. Caller is responsible for cutoff
    /// filtering — the cache keeps everything we found so a later scan with
    /// a wider window doesn't have to re-read.
    private static func parseFile(at url: URL) -> [CachedEvent] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        // Stream the file in fixed-size chunks and parse one line at a time.
        // Session JSONLs can reach 50+ MB and we walk 30 days of them, so
        // loading entire files via `Data(contentsOf:)` blows up peak memory.
        var buffer = Data()
        let chunkSize = 64 * 1024
        var out: [CachedEvent] = []

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Walk the buffer with a cursor and only trim the consumed
            // prefix once per chunk. The previous version called
            // `removeSubrange` per line, which is O(N) per call and made
            // a single 50MB JSONL O(N²) to parse.
            var cursor = buffer.startIndex
            while cursor < buffer.endIndex {
                guard let nl = buffer[cursor..<buffer.endIndex].firstIndex(of: 0x0A) else { break }
                if nl > cursor {
                    if let event = parseLine(
                        buffer[cursor..<nl],
                        formatter: formatter,
                        formatterNoFractional: formatterNoFractional
                    ) {
                        out.append(event)
                    }
                }
                cursor = buffer.index(after: nl)
            }
            if cursor > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<cursor)
            }
        }
        // Flush trailing line if the file did not end with a newline.
        if !buffer.isEmpty {
            if let event = parseLine(
                buffer,
                formatter: formatter,
                formatterNoFractional: formatterNoFractional
            ) {
                out.append(event)
            }
        }
        return out
    }

    /// Returns nil for non-assistant rows, synthetic placeholder models,
    /// noop usage entries, and lines that fail to parse.
    private static func parseLine(
        _ lineData: Data,
        formatter: ISO8601DateFormatter,
        formatterNoFractional: ISO8601DateFormatter
    ) -> CachedEvent? {
        guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        else { return nil }

        // Only assistant messages carry usage. The shape is consistent
        // across Claude Code versions: top-level `type == "assistant"`,
        // `message.usage`, `message.model`, `message.id`, top-level
        // `requestId`, top-level `timestamp`.
        guard (raw["type"] as? String) == "assistant",
              let message = raw["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String
        else { return nil }

        // Skip synthetic placeholder models (ccusage parity).
        if model == "<synthetic>" || model.hasPrefix("synthetic") { return nil }

        let messageId = message["id"] as? String ?? ""
        let requestId = raw["requestId"] as? String ?? ""

        // ccusage requires BOTH IDs for dedup; entries missing either
        // are processed without dedup. Match that behavior so a partial
        // log doesn't silently drop turns.
        let dedupKey = (messageId.isEmpty || requestId.isEmpty)
            ? ""
            : "\(messageId):\(requestId)"

        let timestampString = raw["timestamp"] as? String ?? ""
        let timestamp = formatter.date(from: timestampString)
            ?? formatterNoFractional.date(from: timestampString)
            ?? Date.distantPast

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        // Skip noop entries — ccusage filters these so totals match exactly.
        if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return nil }

        return CachedEvent(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            dedupKey: dedupKey
        )
    }

    // MARK: - Per-file cache

    /// Bump on any breaking change to `CachedEvent` / `CachedFile` to force
    /// a clean re-parse on next launch.
    private static let cacheVersion = 1

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let dedupKey: String
    }

    private struct CachedFile: Codable {
        let mtime: Date
        let size: Int64
        let events: [CachedEvent]

        /// Tolerate sub-millisecond drift through JSON's Double round-trip;
        /// any real edit moves mtime by far more than that or grows size.
        func matches(mtime other: Date, size otherSize: Int64) -> Bool {
            guard size == otherSize else { return false }
            return abs(mtime.timeIntervalSinceReferenceDate - other.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private struct ParseCache: Codable {
        var version: Int
        var files: [String: CachedFile]
    }

    private static func cacheURL() -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("dev.codexisland.CodexIsland", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claude-parse-cache.v1.json")
    }

    private static func loadCache() -> ParseCache {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ParseCache.self, from: data),
              cache.version == cacheVersion
        else { return ParseCache(version: cacheVersion, files: [:]) }
        return cache
    }

    private static func saveCache(_ cache: ParseCache) {
        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
