import Foundation
@main struct Tests {
    static func main() throws {
        let v: [String: Any] = ["format_id":"401", "ext":"mp4", "width":3840, "height":2160, "fps":60, "vcodec":"av01", "acodec":"none", "filesize":2000]
        let a: [String: Any] = ["format_id":"251", "ext":"webm", "vcodec":"none", "acodec":"opus", "filesize":200]
        let low: [String: Any] = ["format_id":"18", "ext":"mp4", "width":640, "height":360, "vcodec":"avc1", "acodec":"aac", "filesize":100]
        let d: [String: Any] = ["title":"한글 제목 🎬", "requested_formats":[v,a], "formats":[low,a,v], "duration":123]
        let item = try Metadata.video(JSONSerialization.data(withJSONObject:d), source:"https://example.com/video")
        precondition(item.title == "한글 제목 🎬")
        precondition(item.formatID == "401+251")
        precondition(item.selectedFormat.size == 2200 && item.selectedFormat.approximate)
        precondition(item.selectedFormat.height == 2160 && item.selectedFormat.audioCodec == "opus")
        precondition(item.choices.contains { $0.id == "18" })
        let m4a = item.choices.first { $0.id == "audio-m4a" }!, mp3 = item.choices.first { $0.id == "audio-mp3" }!
        precondition(m4a.audioFormat == "m4a" && m4a.streamIDs == ["251"] && m4a.size == 200 && mp3.ext == "mp3" && m4a.label.hasPrefix("음성만 · M4A"))
        var unknown = a; unknown.removeValue(forKey:"filesize")
        precondition(Metadata.choice([v,unknown]).size == nil, "Partial sizes must not look like full sizes")
        precondition(StreamProgress.parse("ODP\t401\t50\t100\tNA\t10\t5\tdownloading")?.fraction == 0.5)
        precondition(StreamProgress.parse("ODP\t251\t50\tNA\tNA\tNA\tNA\tdownloading")?.fraction == nil)
        precondition(StreamProgress.parse("ODP\t401\t100\t100\tNA\t10\t0\tfinished")?.fraction == 1)
        precondition(StreamProgress.parse("ODP\tpartial") == nil)
        let gallery: [[Any]] = [[2,["title":"Gallery"]],[3,"https://example.com/a.png",["filename":"a","extension":"png","width":100,"height":80]],[6,"https://example.com/page",[:]],[3,"https://example.com/a.png",["filename":"a","extension":"png"]]]
        let images = try Metadata.gallery(JSONSerialization.data(withJSONObject:gallery), source:"https://example.com/post")
        precondition(images.count == 1 && images[0].title == "a.png")
        precondition(webURL("file:///etc/passwd") == nil)
        precondition(webURL("https://user:pass@example.com") == nil)
        precondition(safeName("../../photo.jpg") == "photo.jpg")
        let list: [String: Any] = ["_type": "playlist", "title": "목록", "entries": [
            ["url": "https://www.youtube.com/watch?v=a", "title": "첫 영상", "duration": 60, "channel": "채널", "thumbnails": [["url": "https://i.ytimg.com/a.jpg"]]],
            ["url": "file:///etc/passwd", "title": "나쁜 항목"], ["title": "주소 없음"]]]
        let entries = try Metadata.playlist(JSONSerialization.data(withJSONObject: list), source: "https://www.youtube.com/playlist?list=x")!
        precondition(entries.count == 1 && entries[0].playlistEntry && !entries[0].selected && entries[0].engine == "yt-dlp")
        precondition(entries[0].subtitle == "채널 · 목록" && entries[0].duration == 60 && entries[0].thumbnail == "https://i.ytimg.com/a.jpg")
        precondition(entries[0].selectedFormat.automatic && entries[0].selectedFormat.id == "bv*+ba/b" && entries[0].choices.contains { $0.audioFormat == "mp3" })
        let single = try Metadata.playlist(JSONSerialization.data(withJSONObject: d), source: "https://example.com")
        precondition(single == nil)
        precondition(entries.instantPicks.isEmpty, "Instant download must not take a whole playlist")
        var live = d; live["is_live"] = true
        do { _ = try Metadata.video(JSONSerialization.data(withJSONObject:live),source:"https://example.com"); fatalError("Live media must be rejected") } catch {}
        func file(_ name: String, _ ext: String, _ size: Double?, video: Bool = false) -> MediaItem {
            var item = MediaItem(source: "https://example.com", url: "https://example.com/" + name, title: name, choices: [FormatChoice(id: "direct", ext: ext, size: size, streamIDs: ["direct"])], formatID: "direct")
            if video { item.kindHint = .video }
            return item
        }
        let found = [file("a", "png", 10), file("b", "?", nil, video: true), file("c", "jpg", nil), file("d", "mp4", 30), file("e", "webp", 20), file("f", "mp3", 5)]
        precondition(found.map(\.kind) == [.image, .video, .image, .video, .image, .other])
        precondition(found.arranged(kind: nil, sort: nil).map(\.title) == ["a", "b", "c", "d", "e", "f"])
        precondition(found.arranged(kind: .image, sort: ColumnSort(column: .size, ascending: false)).map(\.title) == ["e", "a", "c"])
        precondition(found.arranged(kind: nil, sort: ColumnSort(column: .size)).map(\.title) == ["f", "a", "e", "d", "b", "c"])
        precondition(found.arranged(kind: .video, sort: ColumnSort(column: .size, ascending: false)).map(\.title) == ["d", "b"])
        precondition(found.arranged(kind: nil, sort: ColumnSort(column: .format)).map(\.title) == ["c", "f", "d", "a", "e", "b"])
        let named = [file("img10", "png", 1), file("img2", "png", 1), file("Img1", "png", 1)]
        precondition(named.arranged(kind: nil, sort: ColumnSort(column: .name)).map(\.title) == ["Img1", "img2", "img10"])
        precondition(named.arranged(kind: nil, sort: ColumnSort(column: .name, ascending: false)).map(\.title) == ["img10", "img2", "Img1"])
        var cycle = ColumnSort.next(nil, clicked: .size)
        precondition(cycle == ColumnSort(column: .size, ascending: true))
        cycle = ColumnSort.next(cycle, clicked: .size); precondition(cycle == ColumnSort(column: .size, ascending: false))
        precondition(ColumnSort.next(cycle, clicked: .size) == nil && ColumnSort.next(cycle, clicked: .name) == ColumnSort(column: .name))
        precondition(MP4.arguments(input: "a.mp4", output: "b.mp4", ext: "mp4", video: "h264", audio: "aac") == nil)
        let remux = MP4.arguments(input: "a.mkv", output: "b.mp4", ext: "mkv", video: "av1", audio: "aac")!
        precondition(remux.contains("copy") && !remux.contains("h264_videotoolbox") && !remux.contains("aac_at") && remux.last == "b.mp4")
        let hevc = MP4.arguments(input: "a.mp4", output: "b.mp4", ext: "mp4", video: "hevc", audio: "aac")!
        precondition(hevc.contains("hvc1"))
        let encode = MP4.arguments(input: "a.mkv", output: "b.mp4", ext: "mkv", video: "vp9", audio: "opus")!
        precondition(encode.contains("h264_videotoolbox") && encode.contains("aac_at") && encode.contains("yuv420p"))
        let silent = MP4.arguments(input: "a.webm", output: "b.mp4", ext: "webm", video: "h264", audio: nil)!
        precondition(!silent.contains("aac_at") && silent.contains("0:a:0?"))
        let video = StreamProgress(id: "v", downloaded: 50, total: 80, speed: 10, eta: 3, finished: false)
        var one = StreamProgress.combined(["v": video], streams: ["v", "a"], estimate: 100)!
        precondition(one.total == 100 && one.downloaded == 50 && one.eta == 5 && !one.finished)
        one = StreamProgress.combined(["v": video], streams: ["v", "a"], estimate: nil)!
        precondition(one.total == nil && one.fraction == nil)
        let doneVideo = StreamProgress(id: "v", downloaded: 80, total: 80, speed: nil, eta: nil, finished: true)
        let audio = StreamProgress(id: "a", downloaded: 10, total: 30, speed: 5, eta: 4, finished: false)
        let both = StreamProgress.combined(["v": doneVideo, "a": audio], streams: ["v", "a"], estimate: 100)!
        precondition(both.total == 110 && both.downloaded == 90 && both.speed == 5 && both.eta == 4 && !both.finished)
        let finished = StreamProgress.combined(["v": doneVideo, "a": StreamProgress(id: "a", downloaded: 30, total: 30, speed: nil, eta: nil, finished: true)], streams: ["v", "a"], estimate: 100)!
        precondition(finished.finished && finished.fraction == 1)
        precondition(StreamProgress.combined([:], streams: ["v"], estimate: 1) == nil)
        precondition(webLinks(in: "보세요 https://a.com/x 그리고\nhttps://b.com/y?z=1 https://a.com/x ftp://c.com") == ["https://a.com/x", "https://b.com/y?z=1"])
        precondition(webLinks(in: "그냥 글자") == [])
        precondition(externalLinks(URL(string: "jinidownloader://open?url=https%3A%2F%2Fa.com%2Fv%3Fx%3D1&url=https%3A%2F%2Fb.com")!) == ["https://a.com/v?x=1", "https://b.com"])
        precondition(externalLinks(URL(string: "jinidownloader://https://a.com/v")!) == ["https://a.com/v"])
        precondition(externalLinks(URL(string: "jinidownloader://open?url=file%3A%2F%2F%2Fetc%2Fpasswd")!) == [])
        precondition(externalLinks(URL(string: "https://a.com/v")!) == ["https://a.com/v"])
        let webloc = FileManager.default.temporaryDirectory.appendingPathComponent("jini-test.webloc")
        try PropertyListSerialization.data(fromPropertyList: ["URL": "https://a.com/w"], format: .xml, options: 0).write(to: webloc)
        precondition(externalLinks(webloc) == ["https://a.com/w"]); try? FileManager.default.removeItem(at: webloc)
        precondition(externalLinks(URL(string: "ftp://a.com")!) == [])
        var pageImage = file("logo", "png", 10), postImage = file("toon", "png", 20); postImage.featured = true
        let clip = file("clip", "mp4", 30)
        precondition([pageImage, postImage, clip].instantPicks == [clip.id])
        precondition([pageImage, postImage].instantPicks == [postImage.id])
        precondition([pageImage].instantPicks.isEmpty)
        pageImage.state = "완료"; var doneClip = clip; doneClip.state = "완료"
        precondition([doneClip, postImage].instantPicks == [postImage.id])
        print("PASS: instant download picks: videos first, then featured media, never page decoration or started items")
        var signed = file("toon.png", "png", 1); signed.url = "https://cdn.example.com/up/toon.png?expiry_token=abc#x"
        var resigned = signed; resigned.url = "https://cdn.example.com/up/toon.png?expiry_token=zzz"
        precondition(historyKey(signed) == "https://cdn.example.com/up/toon.png" && historyKey(signed) == historyKey(resigned))
        var watch = file("v", "mkv", 1); watch.engine = "yt-dlp"; watch.url = "https://www.youtube.com/watch?v=a"
        precondition(historyKey(watch) == "https://www.youtube.com/watch?v=a")
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("jini-history-\(UUID().uuidString).json")
        MainActor.assumeIsolated {
            let history = History(url: store)
            history.add(signed, saved: URL(fileURLWithPath: "/tmp/toon.png"), size: 1)
            precondition(History(url: store).lookup(resigned)?.title == "toon.png", "History must persist and match re-signed links")
            precondition(History(url: store).lookup(watch) == nil)
            history.clear(); precondition(History(url: store).entries.isEmpty)
        }
        try? FileManager.default.removeItem(at: store)
        print("PASS: download history: key ignores link tokens, persists, matches, clears")
        print("PASS: external links: scheme query, scheme path, web link, webloc file, unsafe targets ignored")
        print("PASS: web links in pasted text: order, duplicates, non-web schemes")
        print("PASS: combined progress: estimate until all streams start, summed bytes, active speed, finish")
        let subs = MP4.arguments(input: "a.mkv", output: "b.mp4", ext: "mkv", video: "h264", audio: "aac", subtitles: true)!
        precondition(subs.contains("0:s?") && subs.contains("mov_text") && !remux.contains("0:s?"))
        let media = URL(fileURLWithPath: "/stage/Clip [x].mkv"), saved = URL(fileURLWithPath: "/dl/Clip [x] (1).mp4")
        precondition(Subtitles.target(for: URL(fileURLWithPath: "/stage/Clip [x].ko.srt"), media: media, saved: saved).path == "/dl/Clip [x] (1).ko.srt")
        precondition(Subtitles.target(for: URL(fileURLWithPath: "/stage/other.srt"), media: media, saved: saved).path == "/dl/Clip [x] (1).srt")
        precondition(Subtitles.isSubtitle(URL(fileURLWithPath: "a.en.VTT")) && !Subtitles.isSubtitle(media))
        precondition(Clip.seconds("75") == 75 && Clip.seconds("1:15") == 75 && Clip.seconds("0:01:15") == 75 && Clip.seconds("1:75") == nil && Clip.seconds("a") == nil && Clip.seconds("1:2:3:4") == nil)
        if case .success(let r) = Clip.range(start: "0:10", end: "", duration: 60) { precondition(r.start == 10 && r.end == 60) } else { fatalError() }
        if case .success(let r) = Clip.range(start: "", end: "2:00", duration: 60) { precondition(r.start == 0 && r.end == 60) } else { fatalError() }
        if case .success = Clip.range(start: "0:30", end: "0:10", duration: 60) { fatalError("End before start must fail") }
        if case .success = Clip.range(start: "1:30", end: "", duration: 60) { fatalError("Start past the end must fail") }
        if case .success = Clip.range(start: "0:10", end: "", duration: nil) { fatalError("Missing end without a known length must fail") }
        precondition(Clip.argument((5, 12.5)) == "*5.0-12.5")
        precondition(item.selectedFormat.sourceExt == "mp4")
        precondition(Clip.format(for: item.selectedFormat) == ("401+ba[ext=m4a]/401+251", false))
        var webmVideo = item.selectedFormat; webmVideo.sourceExt = "webm"
        precondition(Clip.format(for: webmVideo) == ("401+251", true))
        precondition(Clip.format(for: FormatChoice(id: "18", ext: "mp4", streamIDs: ["18"], sourceExt: "mp4")) == ("18", false))
        precondition(Clip.format(for: m4a) == ("ba[ext=m4a]/ba", false) && Clip.format(for: mp3).format == "ba[ext=m4a]/ba")
        precondition(Clip.format(for: entries[0].selectedFormat).format.hasPrefix("bv*[ext=mp4]+ba[ext=m4a]"))
        print("PASS: clip ranges: time formats, defaults, validation, yt-dlp section")
        var fromSite = file("a", "png", 1); fromSite.source = "https://www.youtube.com/watch?v=x"
        precondition(siteFolder(fromSite) == "youtube.com")
        fromSite.source = "https://padlet.com/board"; precondition(siteFolder(fromSite) == "padlet.com")
        precondition(FileNaming.allCases.allSatisfy { $0.template.hasSuffix(".%(ext)s") } && FileNaming.dateTitle.template.contains("&{} |"))
        let session = HTTPCookie(properties: [.domain: ".example.com", .path: "/", .name: "sid", .value: "abc", .secure: "TRUE"])!
        let scoped = HTTPCookie(properties: [.domain: "cdn.example.com", .path: "/private", .name: "k", .value: "1", .expires: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 86_400).rounded(.down))])!
        let other = HTTPCookie(properties: [.domain: "other.com", .path: "/", .name: "x", .value: "y"])!
        let jar = [session, scoped, other]
        precondition(Cookies.header(for: URL(string: "https://cdn.example.com/private/a.png")!, from: jar) == "sid=abc; k=1")
        precondition(Cookies.header(for: URL(string: "https://www.example.com/")!, from: jar) == "sid=abc")
        precondition(Cookies.header(for: URL(string: "http://www.example.com/")!, from: jar) == nil, "Secure cookies need https")
        precondition(Cookies.header(for: URL(string: "https://notexample.com/")!, from: jar) == nil)
        let txt = Cookies.netscape([session, scoped])
        precondition(txt.hasPrefix("# Netscape HTTP Cookie File\n") && txt.contains(".example.com\tTRUE\t/\tTRUE\t0\tsid\tabc") && txt.contains("cdn.example.com\tFALSE\t/private\tFALSE\t\(Int(scoped.expiresDate!.timeIntervalSince1970))\tk\t1"))
        print("PASS: browser cookies: domain/path/secure matching, header, cookies.txt")
        print("PASS: MP4 plan: already fine, remux, HEVC tag, VP9/Opus re-encode, no audio")
        print("PASS: media kinds, kind filter, column sorting with unknown values last, header click cycle")
        print("PASS: preview selection, exact/unknown size, Korean text, stream progress, gallery filtering, URL validation, live handling")
    }
}
