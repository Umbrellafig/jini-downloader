import Foundation

enum Mode: String, CaseIterable { case auto = "자동", video = "동영상", gallery = "사진 · 갤러리", direct = "파일 직접 링크" }
func failure(_ message: String) -> NSError { NSError(domain: "JiniDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func bytes(_ value: Double?) -> String { guard let value, value.isFinite, value > 0 else { return "용량 정보 없음" }; return ByteCountFormatter.string(fromByteCount: Int64(min(value, Double(Int64.max / 2))), countStyle: .file) }
func number(_ dict: [String: Any], _ key: String) -> Double? { if let n = dict[key] as? NSNumber { return n.doubleValue }; if let s = dict[key] as? String { return Double(s) }; return nil }
func durationText(_ seconds: Double?) -> String { guard let seconds, seconds.isFinite, seconds >= 0 else { return "시간 정보 없음" }; let n = Int(seconds); return n >= 3600 ? String(format: "%d:%02d:%02d", n/3600, n/60%60, n%60) : String(format: "%d:%02d", n/60, n%60) }
func safeName(_ value: String) -> String { let s = (value as NSString).lastPathComponent.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\n", with: " "); return s.isEmpty || s == "." || s == ".." ? "download" : String(s.prefix(180)) }
func webURL(_ value: String) -> URL? { guard let u = URL(string: value), let host = u.host, !host.isEmpty, ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.user == nil, u.password == nil else { return nil }; return u }
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
    var resolution: String { height > 0 ? "\(width)×\(height)" : "해상도 정보 없음" }
    var quality: String { height > 0 ? "\(height)p" + (fps > 0 ? " · \(Int(fps))fps" : "") : "해상도 정보 없음" }
    var sizeLabel: String { (approximate && size != nil ? "약 " : "") + bytes(size) }
    var label: String { "\(recommended ? "최고 품질 · " : "")\(quality) · \(ext.uppercased()) · \(videoCodec) · \(sizeLabel)" }
    var detail: String { [resolution, fps > 0 ? "\(Int(fps)) fps" : "", videoCodec, audioCodec, dynamicRange].filter { !$0.isEmpty && $0 != "none" && $0 != "NA" }.joined(separator: " · ") }
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
    var selectedFormat: FormatChoice { choices.first { $0.id == formatID } ?? choices[0] }
}
struct StreamProgress {
    var id: String
    var downloaded: Double
    var total: Double?
    var speed: Double?
    var eta: Double?
    var finished: Bool
    var fraction: Double? { if finished { return 1 }; guard let total, total > 0 else { return nil }; return max(0, min(0.999, downloaded / total)) }
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
        return MediaItem(source: source, url: source, title: d["title"] as? String ?? source, subtitle: d["uploader"] as? String ?? URL(string: source)?.host ?? "", thumbnail: d["thumbnail"] as? String, duration: number(d, "duration"), choices: choices, formatID: best.id, engine: "yt-dlp")
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
