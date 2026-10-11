import Foundation
import Observation

/// A local history of holds, releases, and every change HODL makes. Stored as JSON lines; never leaves the Mac.
@MainActor @Observable
final class Ledger {
    static let shared = Ledger()

    private(set) var entries: [LedgerEntry] = []

    nonisolated private static var fileURL: URL { Recovery.folder.appending(path: "ledger.jsonl") }

    private init() {
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        entries = text.split(separator: "\n").suffix(200).compactMap {
            try? decoder.decode(LedgerEntry.self, from: Data($0.utf8))
        }.reversed()
    }

    func add(_ event: String, _ detail: String, reason: ReleaseReason? = nil) {
        let entry = LedgerEntry(event: event, detail: detail, reason: reason)
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        Self.write(entry)
    }

    nonisolated static func appendFromBackstop(_ detail: String) {
        write(LedgerEntry(event: "backstop", detail: detail, reason: .recovered))
    }

    nonisolated private static func write(_ entry: LedgerEntry) {
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: fileURL)
        }
    }
}
