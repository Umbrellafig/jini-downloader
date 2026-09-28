import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var key: String
    var title: String
    var source: String
    var file: String
    var format: String
    var size: Double?
    var date: Date
}

/// Downloads the user completed, newest first, kept in Application Support so repeated links can be recognized.
@MainActor final class History: ObservableObject {
    static let limit = 2000
    @Published private(set) var entries: [HistoryEntry] = []
    private let url: URL
    private var index: [String: HistoryEntry] = [:]
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JiniDownloader/history.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) { entries = saved }
        reindex()
    }
    func lookup(_ item: MediaItem) -> HistoryEntry? { index[historyKey(item)] }
    func add(_ item: MediaItem, saved file: URL, size: Double?) {
        let entry = HistoryEntry(key: historyKey(item), title: item.title, source: item.source, file: file.path, format: file.pathExtension.uppercased() + (item.engine == "yt-dlp" && item.selectedFormat.height > 0 ? " · \(item.selectedFormat.height)p" : ""), size: size, date: Date())
        entries = Array(([entry] + entries).prefix(Self.limit))
        save()
    }
    func remove(_ ids: Set<HistoryEntry.ID>) { entries.removeAll { ids.contains($0.id) }; save() }
    func clear() { entries = []; save() }
    private func reindex() {
        index = [:]
        for entry in entries.reversed() { index[entry.key] = entry }
    }
    private func save() {
        reindex()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
