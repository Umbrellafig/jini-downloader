import Foundation

enum Mode: String, CaseIterable { case auto = "자동", video = "동영상", gallery = "사진 · 갤러리", direct = "파일 직접 링크" }
func failure(_ message: String) -> NSError { NSError(domain: "JiniDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func bytes(_ value: Double?) -> String { guard let value, value.isFinite, value > 0 else { return "용량 정보 없음" }; return ByteCountFormatter.string(fromByteCount: Int64(min(value, Double(Int64.max / 2))), countStyle: .file) }
func number(_ dict: [String: Any], _ key: String) -> Double? { if let n = dict[key] as? NSNumber { return n.doubleValue }; if let s = dict[key] as? String { return Double(s) }; return nil }
func durationText(_ seconds: Double?) -> String { guard let seconds, seconds.isFinite, seconds >= 0 else { return "시간 정보 없음" }; let n = Int(seconds); return n >= 3600 ? String(format: "%d:%02d:%02d", n/3600, n/60%60, n%60) : String(format: "%d:%02d", n/60, n%60) }
func safeName(_ value: String) -> String { let s = (value as NSString).lastPathComponent.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\n", with: " "); return s.isEmpty || s == "." || s == ".." ? "download" : String(s.prefix(180)) }
func webURL(_ value: String) -> URL? { guard let u = URL(string: value), let host = u.host, !host.isEmpty, ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.user == nil, u.password == nil else { return nil }; return u }
/// Web links in pasted or dropped text, in order and without duplicates; plain text without links yields none.
func webLinks(in text: String) -> [String] {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    var seen = Set<String>()
    return matches.compactMap { $0.url?.absoluteString }.filter { webURL($0) != nil && seen.insert($0).inserted }
}
/// Links handed to the app from outside: a jinidownloader:// request (`?url=` values, or a link after the scheme),
/// a web link dropped on the Dock icon, or a .webloc/.url shortcut file.
func externalLinks(_ url: URL) -> [String] {
    switch url.scheme?.lowercased() {
    case "jinidownloader":
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "url" }.compactMap(\.value) ?? []
        if !values.isEmpty { return values.filter { webURL($0) != nil } }
        let rest = url.absoluteString.dropFirst("jinidownloader:".count).drop { $0 == "/" }
        return webLinks(in: String(rest).removingPercentEncoding ?? String(rest))
    case "http", "https":
        return webURL(url.absoluteString) != nil ? [url.absoluteString] : []
    case "file":
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count < 1_000_000 else { return [] }
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let link = plist["URL"] as? String {
            return webURL(link) != nil ? [link] : []
        }
        return webLinks(in: String(decoding: data, as: UTF8.self))
    default:
        return []
    }
}
struct FormatChoice: Identifiable {
    var id: String
    var ext: String
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    var videoCodec: String = ""
    var audioCodec: String = ""
    var dynamicRange: String = ""
    var size: Double?
    var approximate = false
    var streamIDs: [String] = []
    var recommended = false
    /// A playlist entry's "best available" choice; the actual format is decided by yt-dlp when downloading.
    var automatic = false
    /// Set for audio-only choices ("m4a" or "mp3"): yt-dlp extracts the best audio stream into this format.
    var audioFormat: String?
    var resolution: String { height > 0 ? "\(width)×\(height)" : "해상도 정보 없음" }
    var quality: String { height > 0 ? "\(height)p" + (fps > 0 ? " · \(Int(fps))fps" : "") : "해상도 정보 없음" }
    var sizeLabel: String { (approximate && size != nil ? "약 " : "") + bytes(size) }
    /// Quality menu text; the saved file type has its own column, so it is left out here.
    var label: String { automatic ? "가장 좋은 품질 · 받을 때 결정" : audioFormat.map { "음성만 · \($0.uppercased()) · \(sizeLabel)" } ?? "\(recommended ? "최고 품질 · " : "")\(quality) · \(videoCodec) · \(sizeLabel)" }
    var detail: String { [resolution, fps > 0 ? "\(Int(fps)) fps" : "", videoCodec, audioCodec, dynamicRange].filter { !$0.isEmpty && $0 != "none" && $0 != "NA" }.joined(separator: " · ") }
}
enum MediaKind: String, CaseIterable, Identifiable {
    case image = "이미지", video = "동영상", other = "기타"
    var id: String { rawValue }
    var symbol: String { switch self { case .image: "photo"; case .video: "play.rectangle"; case .other: "doc" } }
}
enum SortColumn: String, CaseIterable, Identifiable {
    case name = "파일명", kind = "종류", format = "포맷", quality = "품질", size = "용량"
    var id: String { rawValue }
}
enum VideoContainer: String, CaseIterable, Identifiable {
    case mkv = "MKV", mp4 = "MP4"
    var id: String { rawValue }
}
enum MP4 {
    /// Codecs QuickTime plays from an MP4 as they are; anything else is re-encoded.
    static let copyVideo: Set<String> = ["h264", "hevc", "av1"]
    static let copyAudio: Set<String> = ["aac", "mp3", "alac"]
    static func needsVideoEncode(_ codec: String?) -> Bool { codec.map { !copyVideo.contains($0) } ?? false }
    /// ffmpeg arguments that turn a download into a QuickTime-friendly MP4, or nil when it already is one.
    static func arguments(input: String, output: String, ext: String, video: String?, audio: String?) -> [String]? {
        let encodeVideo = needsVideoEncode(video), encodeAudio = audio.map { !copyAudio.contains($0) } ?? false
        // HEVC needs the hvc1 tag for QuickTime, which an existing MP4 may lack.
        if ext.lowercased() == "mp4" && !encodeVideo && !encodeAudio && video != "hevc" { return nil }
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", input, "-map", "0:v:0?", "-map", "0:a:0?"]
        if encodeVideo { args += ["-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p"] }
        else { args += ["-c:v", "copy"] + (video == "hevc" ? ["-tag:v", "hvc1"] : []) }
        args += encodeAudio ? ["-c:a", "aac_at", "-b:a", "192k"] : ["-c:a", "copy"]
        return args + ["-movflags", "+faststart", output]
    }
}
struct ColumnSort: Equatable {
    var column: SortColumn
    var ascending = true
    /// Header click cycle: ascending → descending → found order (nil); another column starts ascending.
    static func next(_ current: ColumnSort?, clicked column: SortColumn) -> ColumnSort? {
        guard let current, current.column == column else { return ColumnSort(column: column) }
        return current.ascending ? ColumnSort(column: column, ascending: false) : nil
    }
}
struct MediaItem: Identifiable {
    let id = UUID()
    var source: String
    var url: String
    var title: String
    var subtitle = ""
    var thumbnail: String?
    var duration: Double?
    var choices: [FormatChoice]
    var formatID: String
    var engine = "direct"
    var selected = true
    var state = "준비됨"
    var error = ""
    var headers: [String: String] = [:]
    var warning = ""
    var output: URL?
    var progress: [String: StreamProgress] = [:]
    var kindHint: MediaKind?
    /// The main content of the link: media of an opened post or a photo gallery, as opposed to page decoration.
    var featured = false
    /// When this media was downloaded before, from the download history.
    var downloadedAt: Date?
    /// A video listed from a playlist, shown for picking rather than downloaded all at once.
    var playlistEntry = false
    /// Position in the download section; set when a download run queues the item.
    var queue: Int?
    var selectedFormat: FormatChoice { choices.first { $0.id == formatID } ?? choices[0] }
    /// Queued, running, finished or failed items leave the found list for the download section.
    var inDownloads: Bool { state != "준비됨" }
    var kind: MediaKind {
        if let kindHint { return kindHint }
        let ext = selectedFormat.ext.lowercased()
        if engine == "yt-dlp" || ["mp4", "webm", "mov", "m4v", "mkv"].contains(ext) { return .video }
        if ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "tiff", "bmp", "svg"].contains(ext) || thumbnail != nil { return .image }
        return .other
    }
}
enum SortKey { case number(Double), text(String) }
extension MediaItem {
    /// nil means unknown; unknown values stay at the end in either direction.
    func sortKey(_ column: SortColumn) -> SortKey? {
        switch column {
        case .name: return .text(title)
        case .kind: return .number(Double(MediaKind.allCases.firstIndex(of: kind) ?? 0))
        case .format: let ext = selectedFormat.ext.lowercased(); return ext == "?" || ext.isEmpty ? nil : .text(ext)
        case .quality: return selectedFormat.height > 0 ? .number(Double(selectedFormat.height)) : nil
        case .size: return selectedFormat.size.map { .number($0) }
        }
    }
}
/// Identifies the same media across analyses: a video page as it is, a file link without its query or fragment,
/// because signed file links change their tokens every time.
func historyKey(_ item: MediaItem) -> String {
    guard item.engine == "direct", var parts = URLComponents(string: item.url) else { return item.url }
    parts.query = nil; parts.fragment = nil
    return parts.string ?? item.url
}
extension Array where Element == MediaItem {
    /// What instant download takes: every video if any were found, otherwise the featured media; nothing for a plain page.
    var instantPicks: [MediaItem.ID] {
        let ready = filter { !$0.inDownloads }
        let videos = ready.filter { $0.kind == .video && !$0.playlistEntry }
        return (videos.isEmpty ? ready.filter(\.featured) : videos).map(\.id)
    }
    /// Items of one kind (nil: all), sorted by a column (nil: found order). Ties keep the found order.
    func arranged(kind: MediaKind?, sort: ColumnSort?) -> [MediaItem] {
        let shown = filter { kind == nil || $0.kind == kind }
        guard let sort else { return shown }
        return shown.enumerated().sorted { a, b in
            let result: ComparisonResult
            switch (a.element.sortKey(sort.column), b.element.sortKey(sort.column)) {
            case (nil, nil): result = .orderedSame
            case (_?, nil): return true
            case (nil, _?): return false
            case let (.number(x)?, .number(y)?): result = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            case let (.text(x)?, .text(y)?): result = x.localizedStandardCompare(y)
            default: result = .orderedSame
            }
            if result != .orderedSame { return (result == .orderedAscending) == sort.ascending }
            return a.offset < b.offset
        }.map(\.element)
    }
}
struct StreamProgress {
    var id: String
    var downloaded: Double
    var total: Double?
    var speed: Double?
    var eta: Double?
    var finished: Bool
    var fraction: Double? { if finished { return 1 }; guard let total, total > 0 else { return nil }; return max(0, min(0.999, downloaded / total)) }
    /// One bar for a download made of several streams (video + audio) that yt-dlp fetches one after another.
    /// Until every stream has started, the total falls back to the preview's size estimate.
    static func combined(_ parts: [String: StreamProgress], streams: [String], estimate: Double?) -> StreamProgress? {
        guard !parts.isEmpty else { return nil }
        let downloaded = parts.values.map(\.downloaded).reduce(0, +)
        let allStarted = parts.count >= max(streams.count, 1)
        var total: Double?
        if parts.values.allSatisfy({ $0.total != nil }) {
            let known = parts.values.compactMap(\.total).reduce(0, +)
            total = allStarted ? known : estimate.map { max($0, known) }
        }
        let speed = parts.values.first { !$0.finished }?.speed
        let eta = total.flatMap { t in speed.map { max(0, t - downloaded) / max(1, $0) } }
        return StreamProgress(id: "all", downloaded: downloaded, total: total, speed: speed, eta: eta, finished: allStarted && parts.values.allSatisfy(\.finished))
    }
    static func parse(_ line: String) -> StreamProgress? {
        guard line.hasPrefix("ODP\t") else { return nil }
        let f = line.components(separatedBy: "\t")
        guard f.count >= 8 else { return nil }
        let total = Double(f[3]).flatMap { $0 > 0 ? $0 : nil } ?? Double(f[4]).flatMap { $0 > 0 ? $0 : nil }
        return StreamProgress(id: f[1], downloaded: Double(f[2]) ?? 0, total: total, speed: Double(f[5]), eta: Double(f[6]), finished: f[7] == "finished")
    }
}
enum Metadata {
    static func choice(_ streams: [[String: Any]], recommended: Bool = false) -> FormatChoice {
        let v = streams.first { ($0["vcodec"] as? String ?? "none") != "none" } ?? streams[0]
        let a = streams.first { ($0["acodec"] as? String ?? "none") != "none" }
        let ids = streams.compactMap { $0["format_id"] as? String }
        let sizes = streams.map { number($0, "filesize") ?? number($0, "filesize_approx") }
        let complete = sizes.allSatisfy { ($0 ?? 0) > 0 }
        return FormatChoice(id: ids.joined(separator: "+"), ext: streams.count > 1 ? "mkv" : (v["ext"] as? String ?? "?"), width: Int(number(v, "width") ?? 0), height: Int(number(v, "height") ?? 0), fps: number(v, "fps") ?? 0, videoCodec: v["vcodec"] as? String ?? "", audioCodec: a?["acodec"] as? String ?? "", dynamicRange: v["dynamic_range"] as? String ?? "", size: complete ? sizes.compactMap { $0 }.reduce(0,+) : nil, approximate: streams.count > 1 || streams.contains { number($0, "filesize") == nil }, streamIDs: ids, recommended: recommended)
    }
    static func video(_ data: Data, source: String) throws -> MediaItem {
        guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("동영상 정보를 읽지 못했습니다.") }
        if d["_type"] as? String == "playlist" { throw failure("개별 동영상 링크를 입력해 주세요. 재생목록 미리보기는 지원하지 않습니다.") }
        if d["is_live"] as? Bool == true { throw failure("진행 중인 라이브 방송은 크기와 완료 시점을 확정할 수 없습니다. 종료된 영상 링크를 사용해 주세요.") }
        let formats = (d["formats"] as? [[String: Any]] ?? []).filter { ($0["has_drm"] as? Bool) != true }
        let requested = d["requested_formats"] as? [[String: Any]] ?? [d]
        var best = choice(requested, recommended: true)
        if best.id.isEmpty { best.id = d["format_id"] as? String ?? ""; best.streamIDs = [best.id] }
        guard !best.id.isEmpty else { throw failure("저장할 수 있는 포맷을 찾지 못했습니다.") }
        let audio = requested.first { ($0["vcodec"] as? String) == "none" && ($0["acodec"] as? String ?? "none") != "none" } ?? formats.last { ($0["vcodec"] as? String) == "none" && ($0["acodec"] as? String ?? "none") != "none" }
        var choices = [best]; var seen = Set([best.id])
        for f in formats.reversed() where (f["vcodec"] as? String ?? "none") != "none" && (number(f, "height") ?? 0) > 0 {
            if f["has_drm"] as? Bool == true { continue }
            let streams: [[String: Any]]
            if f["acodec"] as? String == "none" { guard let audio else { continue }; streams = [f, audio] } else { streams = [f] }
            let c = choice(streams)
            if !c.id.isEmpty && seen.insert(c.id).inserted { choices.append(c) }
        }
        // Audio-only choices take the best audio stream; the size is that stream's (MP3 re-encoding changes it a little).
        if let audio, let id = audio["format_id"] as? String {
            let size = number(audio, "filesize") ?? number(audio, "filesize_approx")
            for format in ["m4a", "mp3"] {
                choices.append(FormatChoice(id: "audio-" + format, ext: format, audioCodec: format == "mp3" ? "mp3" : "aac", size: size, approximate: true, streamIDs: [id], audioFormat: format))
            }
        }
        return MediaItem(source: source, url: source, title: d["title"] as? String ?? source, subtitle: d["uploader"] as? String ?? URL(string: source)?.host ?? "", thumbnail: d["thumbnail"] as? String, duration: number(d, "duration"), choices: choices, formatID: best.id, engine: "yt-dlp")
    }
    /// Videos of a playlist (from yt-dlp --flat-playlist), up to 200; nil when the JSON is a single video.
    static func playlist(_ data: Data, source: String) throws -> [MediaItem]? {
        guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any], d["_type"] as? String == "playlist" else { return nil }
        let name = d["title"] as? String ?? ""
        return (d["entries"] as? [[String: Any]] ?? []).prefix(200).compactMap { e in
            guard let url = (e["url"] as? String) ?? (e["webpage_url"] as? String), webURL(url) != nil else { return nil }
            let best = FormatChoice(id: "bv*+ba/b", ext: "mkv", streamIDs: [], recommended: true, automatic: true)
            let audio = ["m4a", "mp3"].map { FormatChoice(id: "audio-" + $0, ext: $0, audioCodec: $0 == "mp3" ? "mp3" : "aac", streamIDs: [], audioFormat: $0) }
            let thumbnail = (e["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            var item = MediaItem(source: source, url: url, title: e["title"] as? String ?? url, subtitle: [e["channel"] as? String ?? e["uploader"] as? String ?? "", name].filter { !$0.isEmpty }.joined(separator: " · "), thumbnail: thumbnail.flatMap { webURL($0) != nil ? $0 : nil }, duration: number(e, "duration"), choices: [best] + audio, formatID: best.id, engine: "yt-dlp")
            item.selected = false; item.playlistEntry = true
            return item
        }
    }
    static func gallery(_ data: Data, source: String) throws -> [MediaItem] {
        guard let messages = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw failure("갤러리 정보를 읽지 못했습니다.") }
        var items: [MediaItem] = []; var seen = Set<String>()
        for m in messages {
            guard m.count >= 3, m[0] as? Int == 3, let url = m[1] as? String, let u = webURL(url), seen.insert(url).inserted, let d = m[2] as? [String: Any] else { continue }
            let ext = d["extension"] as? String ?? u.pathExtension
            let name = d["filename"] as? String ?? u.deletingPathExtension().lastPathComponent
            let c = FormatChoice(id: "direct", ext: ext, width: Int(number(d, "width") ?? 0), height: Int(number(d, "height") ?? 0), size: number(d, "filesize"), streamIDs: ["direct"])
            var item = MediaItem(source: source, url: url, title: name + (ext.isEmpty ? "" : "." + ext), subtitle: d["title"] as? String ?? "갤러리 파일", thumbnail: d["thumbnail"] as? String, choices: [c], formatID: c.id)
            if item.thumbnail == nil && ["jpg","jpeg","png","webp","gif","avif"].contains(ext.lowercased()) { item.thumbnail = url }
            item.headers = d["_http_headers"] as? [String: String] ?? [:]
            if item.headers["Referer"] == nil { item.headers["Referer"] = source }
            items.append(item)
        }
        guard !items.isEmpty else { throw failure("미리보기 가능한 갤러리 파일이 없습니다. 개별 게시물 링크를 사용해 주세요.") }
        return Array(items.prefix(200))
    }
}
