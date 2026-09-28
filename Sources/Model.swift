import SwiftUI
import AppKit
import UserNotifications

@MainActor final class Model: ObservableObject {
    @Published var input = ""
    @Published var mode: Mode = .auto
    @Published var folder: URL
    /// Videos are saved as MP4 (remuxed, or re-encoded only for QuickTime-incompatible codecs). The advanced option
    /// keeps the site's streams untouched in MKV instead.
    @Published var keepOriginalVideo = UserDefaults.standard.bool(forKey: "keepOriginalVideo") { didSet { UserDefaults.standard.set(keepOriginalVideo, forKey: "keepOriginalVideo") } }
    var videoContainer: VideoContainer { keepOriginalVideo ? .mkv : .mp4 }
    @Published var notifyWhenDone = UserDefaults.standard.object(forKey: "notifyWhenDone") as? Bool ?? true { didSet { UserDefaults.standard.set(notifyWhenDone, forKey: "notifyWhenDone") } }
    /// After analysis, download the main content right away (see `instantPicks`).
    @Published var instantDownload = UserDefaults.standard.bool(forKey: "instantDownload") { didSet { UserDefaults.standard.set(instantDownload, forKey: "instantDownload") } }
    @Published var subtitlesEnabled = UserDefaults.standard.bool(forKey: "subtitlesEnabled") { didSet { UserDefaults.standard.set(subtitlesEnabled, forKey: "subtitlesEnabled") } }
    @Published var subtitleLanguages = UserDefaults.standard.string(forKey: "subtitleLanguages") ?? "ko,en" { didSet { UserDefaults.standard.set(subtitleLanguages, forKey: "subtitleLanguages") } }
    @Published var autoSubtitles = UserDefaults.standard.bool(forKey: "autoSubtitles") { didSet { UserDefaults.standard.set(autoSubtitles, forKey: "autoSubtitles") } }
    @Published var embedSubtitles = UserDefaults.standard.bool(forKey: "embedSubtitles") { didSet { UserDefaults.standard.set(embedSubtitles, forKey: "embedSubtitles") } }
    @Published var naming = FileNaming(rawValue: UserDefaults.standard.string(forKey: "fileNaming") ?? "") ?? .titleID { didSet { UserDefaults.standard.set(naming.rawValue, forKey: "fileNaming") } }
    @Published var folderPerSite = UserDefaults.standard.bool(forKey: "folderPerSite") { didSet { UserDefaults.standard.set(folderPerSite, forKey: "folderPerSite") } }
    let history = History()
    /// Record finished downloads so later analyses can mark files received before.
    @Published var keepHistory = UserDefaults.standard.object(forKey: "keepHistory") as? Bool ?? true { didSet { UserDefaults.standard.set(keepHistory, forKey: "keepHistory") } }
    /// Offer to analyze a link found on the clipboard when the app comes forward.
    @Published var watchClipboard = UserDefaults.standard.object(forKey: "watchClipboard") as? Bool ?? true { didSet { UserDefaults.standard.set(watchClipboard, forKey: "watchClipboard"); if !watchClipboard { clipboardOffer = false } } }
    @Published var clipboardOffer = false
    private var offeredChange = -1
    /// Advanced option: write a `.download.txt` record (source page, format, size, time) next to each saved file.
    @Published var writeRecord = UserDefaults.standard.bool(forKey: "writeDownloadRecord") { didSet { UserDefaults.standard.set(writeRecord, forKey: "writeDownloadRecord") } }
    @Published var items: [MediaItem] = []
    @Published var log = L("링크를 넣고 미리보기를 분석하세요.", "Enter links and analyze them.")
    @Published var busy = false
    @Published var analyzing = false
    @Published var status = L("다운로드 전에 받을 파일을 확인하세요", "Check the files before downloading")
    @Published var previewErrors: [String] = []
    @Published var enginesReady = false
    @Published var installing = false
    @Published var installProgress = 0.0
    private let installer: EngineInstaller?
    var engineDownloadSize: String { bytes(installer.map { Double($0.manifest.tools.map(\.bytes).reduce(0,+)) }) }
    private var runner: EngineRunner?
    private var transfer: FileTransfer?
    private var task: Task<Void, Never>?
    private var cancelled = false
    private var snapshot = ""
    private var activeID: UUID?
    var bin: URL { installer?.bin ?? FileManager.default.temporaryDirectory.appendingPathComponent("jini-engines-unavailable") }
    var signature: String { mode.rawValue + "\n" + input.trimmingCharacters(in: .whitespacesAndNewlines) }
    var stale: Bool { !items.isEmpty && snapshot != signature }
    var selectedCount: Int { items.filter { $0.selected && $0.state != "완료" }.count }
    var canDownload: Bool { enginesReady && !busy && !stale && selectedCount > 0 }
    var selectedSize: String {
        let selected = items.filter { $0.selected && $0.state != "완료" }
        let known = selected.compactMap { $0.selectedFormat.size }.reduce(0,+)
        if known == 0 { return L("총 용량 정보 없음", "Total size unknown") }
        return L("약 \(bytes(known))", "~\(bytes(known))") + (selected.contains { $0.selectedFormat.size == nil } ? L(" + 용량 미상 파일", " + files of unknown size") : "")
    }
    init() {
        installer = (try? EngineManifest.bundled()).map { EngineInstaller(manifest: $0) }
        enginesReady = installer?.ready ?? false
        if let path = UserDefaults.standard.string(forKey: "saveFolder") { folder = URL(fileURLWithPath: path) }
        else { folder = Self.defaultFolder }
        Self.clearCookieFiles()
        // A new tool revision after an app update: the user already agreed to the tools, so upgrade in place.
        if !enginesReady, installer?.hasPreviousInstall == true { installEngines() }
    }
    static var defaultFolder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
    var usesDefaultFolder: Bool { folder.standardizedFileURL == Self.defaultFolder.standardizedFileURL }
    func resetFolder() { folder = Self.defaultFolder; UserDefaults.standard.removeObject(forKey: "saveFolder") }
    func installEngines() {
        guard !busy, let installer else { status = L("앱의 설치 정보를 읽을 수 없습니다.", "Couldn't read the app's install information."); return }
        busy = true; installing = true; cancelled = false; installProgress = 0
        task = Task {
            defer { busy = false; installing = false; task = nil }
            do {
                try await installer.install { [weak self] message, fraction in
                    Task { @MainActor [weak self] in self?.status = message; self?.installProgress = fraction }
                }
                enginesReady = installer.ready; status = L("설치 완료 · 미리보기를 분석할 수 있습니다", "Installed · ready to analyze")
            } catch { status = Task.isCancelled ? L("설치를 취소했습니다", "Installation cancelled") : L("설치 실패 · 상세 로그를 확인하고 다시 시도해 주세요", "Installation failed · check the log and try again"); note(error.localizedDescription) }
        }
    }
    /// Checks only whether the clipboard holds a link, which macOS allows without a paste alert; the contents are read
    /// when the user accepts the offer. Each clipboard change is offered once.
    func checkClipboard() async {
        let pasteboard = NSPasteboard.general
        guard watchClipboard, !busy, pasteboard.changeCount != offeredChange else { return }
        offeredChange = pasteboard.changeCount
        if #available(macOS 15.4, *) {
            clipboardOffer = (try? await pasteboard.detectedPatterns(for: [\.probableWebURL]))?.contains(\.probableWebURL) ?? false
        } else {
            clipboardOffer = !webLinks(in: pasteboard.string(forType: .string) ?? "").isEmpty
        }
    }
    /// Links from a drop, the URL scheme or the Services menu. They are analyzed right away, or added to the input while busy.
    func receive(links: [String]) {
        guard !links.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        if busy {
            let existing = input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            input = (existing.filter { !$0.isEmpty } + links.filter { !existing.contains($0) }).joined(separator: "\n")
            status = L("링크를 추가했습니다 · 지금 작업이 끝나면 분석하기를 눌러 주세요", "Link added · press Analyze when the current job finishes")
        } else {
            input = links.joined(separator: "\n")
            if enginesReady { analyze() }
        }
    }
    /// The in-app browser for pages that need a login or a site check. Its session lives in memory only.
    @Published var browser: WebImages?
    @Published var showBrowser = false
    static let cookieFolder = FileManager.default.temporaryDirectory.appendingPathComponent("JiniDownloader-cookies", isDirectory: true)
    func openBrowser() {
        let session = browser ?? WebImages()
        browser = session
        if session.webView.url == nil, let first = input.components(separatedBy: .newlines).lazy.compactMap({ webURL($0.trimmingCharacters(in: .whitespaces)) }).first { session.open(first) }
        showBrowser = true
    }
    /// Collects the media on the browser's current screen, with the session's cookies attached so logged-in files download.
    func findInBrowser() {
        guard !busy, let session = browser, let page = session.webView.url, webURL(page.absoluteString) != nil else { return }
        busy = true; analyzing = true; cancelled = false; snapshot = signature
        status = L("지금 화면에서 이미지와 동영상 찾는 중", "Finding images and videos on this screen")
        task = Task {
            defer { busy = false; analyzing = false; task = nil; runner = nil }
            let before = items.count
            let cookies = await session.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let jar = cookies.isEmpty ? nil : try? writeCookies(cookies)
            var found = (try? await session.scan()) ?? []
            for i in found.indices { if let u = webURL(found[i].url), let header = Cookies.header(for: u, from: cookies) { found[i].headers["Cookie"] = header } }
            appendResults(found)
            let pages = [page.absoluteString] + session.embeds
            let videos = await withTaskGroup(of: [MediaItem].self) { group in
                for link in pages { group.addTask { await self.attempt("동영상") { try await self.inspectVideo(link, cookies: jar) } } }
                var all: [MediaItem] = []
                for await result in group { all += result }
                return all
            }
            appendResults(videos)
            let added = items.suffix(items.count - before)
            await probeDirect(added.filter { $0.engine == "direct" }.map(\.id))
            status = added.isEmpty ? L("이 화면에서 받을 파일을 찾지 못했어요. 사진·영상이 보이도록 스크롤한 뒤 다시 찾아 주세요", "Nothing to download on this screen. Scroll until the photos or videos show, then find again") : L("\(added.count)개 추가 · 목록에서 골라 받으세요", "\(added.count) added · choose from the list")
        }
    }
    private func writeCookies(_ cookies: [HTTPCookie]) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.cookieFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = Self.cookieFolder.appendingPathComponent(UUID().uuidString + ".txt")
        guard fm.createFile(atPath: file.path, contents: Data(Cookies.netscape(cookies).utf8), attributes: [.posixPermissions: 0o600]) else { throw failure(L("로그인 정보를 임시로 저장하지 못했습니다.", "Couldn't keep the login temporarily.")) }
        return file
    }
    /// Browser cookies are never kept: drop the session's temporary cookie files.
    static func clearCookieFiles() { try? FileManager.default.removeItem(at: cookieFolder) }
    func acceptClipboard() {
        clipboardOffer = false
        paste()
        if !input.isEmpty && enginesReady { analyze() }
    }
    /// Pastes the clipboard's links, one per line; text without links is pasted as it is.
    func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let links = webLinks(in: text)
        input = links.isEmpty ? text : links.joined(separator: "\n")
        offeredChange = NSPasteboard.general.changeCount; clipboardOffer = false
    }
    func note(_ s: String) { guard !s.isEmpty else { return }; log += "\n" + s; if log.count > 36000 { log = String(log.suffix(28000)) } }
    func choose() { let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.directoryURL = folder; if p.runModal() == .OK, let u = p.url { folder = u; UserDefaults.standard.set(u.path, forKey: "saveFolder") } }
    func stop() { cancelled = true; task?.cancel(); runner?.cancel(); transfer?.cancel(); status = L("취소 중…", "Cancelling…") }
    func invalidateSelection(_ id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = "준비됨"; items[i].error = ""; items[i].progress = [:]; items[i].output = nil; items[i].queue = nil } }
    func clearFinished() { items.removeAll { $0.state == "완료" } }
    func appendResults(_ found: [MediaItem]) {
        var seen = Set(items.map(\.url))
        for var item in found where seen.insert(item.url).inserted {
            item.selected = false
            item.downloadedAt = history.lookup(item)?.date
            items.append(item)
        }
    }
    func downloadAll() {
        guard !busy, !stale else { return }
        for i in items.indices { items[i].selected = items[i].state != "완료" }
        start()
    }
    func analyze() {
        guard !busy, enginesReady else { status = L("먼저 필수 도구를 설치해 주세요", "Install the required tools first"); return }
        let values = input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !values.isEmpty, values.allSatisfy({ webURL($0) != nil }) else { status = L("http 또는 https 링크를 한 줄에 하나씩 입력해 주세요", "Enter http or https links, one per line"); return }
        var seen = Set<String>(); let urls = values.filter { seen.insert($0).inserted }
        let sig = signature
        busy = true; analyzing = true; cancelled = false; items = []; previewErrors = []; snapshot = sig
        log = L("페이지의 이미지와 동영상을 함께 찾습니다. 미리보기 이미지는 불러오지만 선택 전에는 파일을 저장하지 않습니다.", "Finding images and videos on the page. Previews load, but nothing is saved until you choose.")
        task = Task {
            defer { busy = false; analyzing = false; task = nil; runner = nil }
            for (n, value) in urls.enumerated() {
                if Task.isCancelled { break }
                let before = items.count
                let url = webURL(value)!
                do {
                    status = L("링크 \(n+1)/\(urls.count) · 이미지와 동영상 찾는 중", "Link \(n+1)/\(urls.count) · finding images and videos")
                    let directExtensions = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "tiff", "bmp", "svg", "mp4", "webm", "mov", "m4v", "mp3", "wav"]
                    if directExtensions.contains(url.pathExtension.lowercased()) {
                        appendResults([try await inspectDirect(url)])
                    } else {
                        // The page scan, yt-dlp and gallery-dl are independent, so they run at the same time.
                        async let video = attempt("동영상") { try await self.inspectVideo(value) }
                        async let gallery = attempt("사진 게시물") { try await self.inspectGallery(value) }
                        let browser = WebImages()
                        appendResults(await attempt("웹페이지") { try await browser.inspect(url) })
                        try Task.checkCancellation()
                        status = L("\(items.count)개 찾음 · 동영상 품질과 사진 게시물 확인 중", "\(items.count) found · checking video qualities and photo posts")
                        let embeds = await withTaskGroup(of: [MediaItem].self) { group in
                            for embed in browser.embeds { group.addTask { await self.attempt("삽입된 동영상") { try await self.inspectVideo(embed) } } }
                            var found: [MediaItem] = []
                            for await result in group { found += result }
                            return found
                        }
                        appendResults(await video)
                        appendResults(embeds)
                        appendResults(await gallery)
                    }
                    try Task.checkCancellation()
                    if items.count == before {
                        previewErrors.append(L("\(value)\n확인 가능한 파일을 찾지 못했습니다. 로그인·사이트 확인이 필요한 페이지이거나 지원하지 않는 콘텐츠일 수 있습니다.", "\(value)\nNo files found. The page may need a login or a site check, or the content isn't supported."))
                    }
                } catch {
                    if !Task.isCancelled { previewErrors.append("\(value)\n\(error.localizedDescription)") }
                }
            }
            await probeDirect(items.filter { $0.engine == "direct" }.map(\.id))
            snapshot = sig
            status = cancelled ? L("분석 중단 · 찾은 파일은 선택해서 받을 수 있습니다", "Analysis stopped · you can still download what was found") : L("\(items.count)개 파일 · 원하는 항목을 선택하거나 전체 다운로드하세요", "\(items.count) files · choose items or download all")
            // Runs after this task's cleanup has cleared busy, so the download can start.
            if instantDownload && !cancelled { Task { @MainActor in self.startInstant() } }
        }
    }
    /// Tells the user a download run finished when they are working in another app.
    private func notifyFinished(saved: [MediaItem], failed: Int) {
        guard notifyWhenDone, !NSApp.isActive, !saved.isEmpty || failed > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = failed == 0 ? L("다운로드 완료", "Download complete") : L("다운로드 끝남 · 실패 \(failed)개", "Downloads finished · \(failed) failed")
        content.body = saved.count == 1 ? L("\(saved[0].output?.lastPathComponent ?? saved[0].title) 저장", "Saved \(saved[0].output?.lastPathComponent ?? saved[0].title)") : L("\(saved.count)개 파일을 저장했습니다", "Saved \(saved.count) files")
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    private func startInstant() {
        let picks = Set(items.instantPicks)
        guard !picks.isEmpty else {
            status = items.contains(where: \.playlistEntry) ? L("재생목록 영상 \(items.filter(\.playlistEntry).count)개 · 받을 영상을 골라 주세요", "\(items.filter(\.playlistEntry).count) playlist videos · choose the ones to download") : L("\(items.count)개 파일 · 바로 받을 동영상이나 게시물이 없어요. 받을 파일을 골라 주세요", "\(items.count) files · no video or post to download right away. Choose the files to download")
            return
        }
        for i in items.indices where !items[i].inDownloads { items[i].selected = picks.contains(items[i].id) }
        start()
    }
    /// Name and size checks for direct files are small HEAD requests; run up to eight at once within a time limit.
    private func probeDirect(_ ids: [UUID]) async {
        let deadline = Date().addingTimeInterval(12)
        var pending = items.filter { ids.contains($0.id) }.compactMap { item in webURL(item.url).map { (item.id, $0, item.headers) } }[...]
        if !pending.isEmpty && !Task.isCancelled { status = L("\(items.count)개 찾음 · 파일 이름과 용량 확인 중", "\(items.count) found · checking names and sizes") }
        await withTaskGroup(of: (UUID, MediaItem?).self) { group in
            func probe(_ job: (UUID, URL, [String: String])) { group.addTask { (job.0, try? await self.inspectDirect(job.1, headers: job.2, timeout: 2)) } }
            for _ in 0..<8 { if let job = pending.popFirst() { probe(job) } }
            for await (id, info) in group {
                if let info, let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].choices[0].size = info.selectedFormat.size
                    if info.selectedFormat.ext != "?" { items[i].choices[0].ext = info.selectedFormat.ext }
                    items[i].title = info.title
                }
                if !Task.isCancelled, Date() < deadline, let job = pending.popFirst() { probe(job) }
            }
        }
    }
    /// Runs one finder; a failure goes to the log so the other finders' results still count.
    private func attempt(_ label: String, _ work: () async throws -> [MediaItem]) async -> [MediaItem] {
        do { return try await work() }
        catch { if !Task.isCancelled { note("\(label): \(error.localizedDescription)") }; return [] }
    }
    private func execute(_ name: String, _ args: [String], id: UUID? = nil, metadata: Bool = false) async throws -> EngineResult {
        try Task.checkCancellation()
        let r = EngineRunner(); runner = r
        let result = try await r.run(bin.appendingPathComponent(name), args) { [weak self] line in
            // Metadata stdout may contain temporary signed URLs; keep it out of the UI log.
            if metadata && (line.hasPrefix("{") || line.hasPrefix("[") && !line.hasPrefix("[youtube") && !line.hasPrefix("[generic")) { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let id { self.receive(line, id: id) }
                else if line.contains("WARNING:") || line.contains("ERROR:") { self.note(line) }
            }
        }
        runner = nil
        try Task.checkCancellation()
        if result.code != 0 { throw failure(String(result.errors.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("\(name) 처리 실패 (\(result.code))", "\(name) failed (\(result.code))") : String(result.errors.suffix(2000))) }
        return result
    }
    private var videoBase: [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-colors", "--socket-timeout", "25", "--retries", "2", "--ffmpeg-location", bin.path, "--js-runtimes", "deno:" + bin.appendingPathComponent("deno").path]
    }
    /// One video with its formats, or the videos of a playlist link (listed without per-video analysis).
    private func inspectVideo(_ value: String, cookies: URL? = nil) async throws -> [MediaItem] {
        let login = cookies.map { ["--cookies", $0.path] } ?? []
        let r = try await execute("yt-dlp", videoBase + login + ["--skip-download", "--flat-playlist", "-I", "1:200", "--dump-single-json", "-f", "bv*+ba/b", "--", value], metadata: true)
        if let entries = try Metadata.playlist(r.output, source: value) {
            guard !entries.isEmpty else { throw failure(L("재생목록에서 받을 수 있는 영상을 찾지 못했습니다.", "No downloadable videos in this playlist.")) }
            return entries
        }
        var item = try Metadata.video(r.output, source: value)
        item.cookieFile = cookies?.path
        if item.choices.count == 1 && item.selectedFormat.size == nil, let u = webURL(value), !u.pathExtension.isEmpty, let direct = try? await inspectDirect(u) { item.choices[0].size = direct.selectedFormat.size }
        if r.errors.contains("WARNING:") { item.warning = r.errors.components(separatedBy: .newlines).filter { $0.contains("WARNING:") }.joined(separator: "\n") }
        return [item]
    }
    private func inspectGallery(_ value: String) async throws -> [MediaItem] {
        let r = try await execute("gallery-dl", ["--config-ignore", "--no-input", "--http-timeout", "25", "--retries", "2", "--range", "1-200", "--resolve-json", "--", value], metadata: true)
        var found = try Metadata.gallery(r.output, source: value)
        for i in found.indices {
            found[i].warning = L("사진·갤러리 파일은 최대 200개까지 표시합니다. 선택한 URL을 그대로 저장합니다.", "Up to 200 gallery files are shown. The chosen URLs are saved as they are.")
            found[i].featured = true
        }
        return found
    }
    private func inspectDirect(_ u: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> MediaItem {
        var request = URLRequest(url: u); request.httpMethod = "HEAD"; request.timeoutInterval = timeout
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        var size: Double?; var title = u.lastPathComponent; var ext = u.pathExtension; var mime = ""; var warning = ""
        do {
            let (_, r) = try await URLSession.shared.data(for: request)
            if let http = r as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                mime = r.mimeType ?? ""; title = r.suggestedFilename ?? title
                if r.expectedContentLength > 0 { size = Double(r.expectedContentLength) }
                let returnedExtension = (title as NSString).pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "tiff", "bmp", "svg"].contains(returnedExtension) || ext.isEmpty { ext = returnedExtension }
                if mime.contains("text/html") { throw failure(L("파일 대신 웹페이지가 응답했습니다. 자동 또는 동영상 모드로 분석해 주세요.", "A web page came back instead of a file.")) }
            } else { warning = L("서버가 사전 용량 조회를 지원하지 않습니다. 다운로드 시 파일 종류를 확인합니다.", "The server doesn't report the size in advance. The file type is checked when downloading.") }
        } catch {
            try Task.checkCancellation()
            if (error as NSError).domain == "JiniDownloader" { throw error }
            warning = L("사전 정보를 가져오지 못했습니다. 파일 이름은 URL 기준이며 용량은 다운로드 시작 후 표시됩니다.", "Couldn't get details in advance. The name comes from the URL and the size shows once the download starts.")
        }
        let c = FormatChoice(id: "direct", ext: ext.isEmpty ? (mime.isEmpty ? "?" : mime) : ext, size: size, streamIDs: ["direct"])
        let image = mime.hasPrefix("image/") || ["png","jpg","jpeg","gif","webp","avif"].contains(ext.lowercased())
        return MediaItem(source: u.absoluteString, url: u.absoluteString, title: safeName(title), subtitle: u.host ?? L("직접 파일", "Direct file"), thumbnail: image ? u.absoluteString : nil, choices: [c], formatID: c.id, headers: headers, warning: warning)
    }
    func start() {
        guard canDownload else { return }
        let ids = items.filter { $0.selected && $0.state != "완료" }.map(\.id); let dest = folder
        busy = true; cancelled = false; log = L("선택한 포맷으로 저장합니다. 재인코딩하지 않습니다.", "Saving in the chosen format without re-encoding.")
        task = Task {
            defer {
                // Items a cancelled run never reached go back to the found list.
                for i in items.indices where items[i].state == "대기 중" { items[i].state = "준비됨"; items[i].queue = nil }
                busy = false; activeID = nil; runner = nil; transfer = nil; task = nil
            }
            do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true) } catch { status = error.localizedDescription; return }
            var next = (items.compactMap(\.queue).max() ?? 0) + 1
            for id in ids { if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = "대기 중"; items[i].error = ""; items[i].queue = next; next += 1 } }
            for (n,id) in ids.enumerated() {
                if Task.isCancelled { break }
                NSApp.dockTile.badgeLabel = "\(ids.count - n)"
                guard let i = items.firstIndex(where: { $0.id == id }) else { continue }
                items[i].progress = [:]; items[i].error = ""; items[i].state = "연결 중"; activeID = id
                status = "\(n+1)/\(ids.count) · \(items[i].title)"
                let item = items[i]
                let target = folderPerSite ? dest.appendingPathComponent(siteFolder(item), isDirectory: true) : dest
                do {
                    let stage = dest.appendingPathComponent(".JiniDownloader-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: stage) }
                    let saved: URL
                    if item.engine == "yt-dlp" {
                        _ = try await execute("yt-dlp", videoBase + ["--newline", "--progress", "--progress-delta", "0.2", "--progress-template", "download:ODP\t%(info.format_id)s\t%(progress.downloaded_bytes)s\t%(progress.total_bytes)s\t%(progress.total_bytes_estimate)s\t%(progress.speed)s\t%(progress.eta)s\t%(progress.status)s", "--progress-template", "postprocess:ODPOST\t%(progress.status)s", "--no-simulate"] + selection(item) + (item.cookieFile.map { ["--cookies", $0] } ?? []) + ["-P", stage.path, "-o", naming.template, "--", item.url], id: id)
                        items[i].state = "저장 확인 중"
                        let written = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).filter { !["part","ytdl","json"].contains($0.pathExtension) && !$0.lastPathComponent.hasPrefix(".") }
                        let files = written.filter { !Subtitles.isSubtitle($0) }, subtitleFiles = written.filter(Subtitles.isSubtitle)
                        guard files.count == 1 else { throw failure(L("완성 파일을 확인하지 못했습니다. \(files.count)개 결과가 있습니다.", "Couldn't identify the finished file. There are \(files.count) results.")) }
                        let streams = try await probeStreams(files[0])
                        if let v = streams.first(where: { $0["codec_type"] as? String == "video" }) {
                            let height = Int(number(v,"height") ?? 0)
                            if item.selectedFormat.height > 0 && height != item.selectedFormat.height { throw failure(L("선택한 해상도와 결과가 다릅니다 (선택 \(item.selectedFormat.height)p / 결과 \(height)p). 미리보기를 다시 분석해 주세요.", "The result doesn't match the chosen resolution (chose \(item.selectedFormat.height)p, got \(height)p). Analyze the link again.")) }
                            if let f = items[i].choices.firstIndex(where: { $0.id == item.formatID }) {
                                items[i].choices[f].width = Int(number(v,"width") ?? 0); items[i].choices[f].height = height
                                items[i].choices[f].videoCodec = v["codec_name"] as? String ?? items[i].choices[f].videoCodec
                            }
                            note("확인: \(Int(number(v,"width") ?? 0))×\(height) · \(v["codec_name"] as? String ?? "") · \(v["r_frame_rate"] as? String ?? "") fps")
                        }
                        let cut = item.clip != nil && item.selectedFormat.audioFormat == nil && videoContainer == .mp4 ? try await trimSection(files[0], streams: streams, in: stage) : files[0]
                        let finished = item.selectedFormat.audioFormat == nil ? try await finishVideo(cut, streams: streams, in: stage, id: id) : cut
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        saved = try moveUnique(finished, to: target)
                        // Separate subtitle files follow the saved video's final name, keeping their language code. When they were
                        // embedded, the files are only kept as a fallback if the video ended up without a subtitle track.
                        let embedded = embedSubtitles && streams.contains { $0["codec_type"] as? String == "subtitle" }
                        for subtitle in subtitleFiles where !embedded { try? FileManager.default.moveItem(at: subtitle, to: Subtitles.target(for: subtitle, media: files[0], saved: saved)) }
                        if !subtitleFiles.isEmpty { note(embedded ? "자막을 영상에 넣었습니다." : "자막 \(subtitleFiles.count)개를 함께 저장했습니다.") }
                    } else {
                        let t = FileTransfer(); transfer = t
                        t.progress = { [weak self] p in Task { @MainActor [weak self] in self?.update(p, id: id) } }
                        var r = URLRequest(url: webURL(item.url)!); item.headers.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
                        let downloaded = try await t.download(r, to: stage.appendingPathComponent(safeName(item.title)))
                        try Task.checkCancellation()
                        let file = item.kind == .video && videoContainer == .mp4 ? try await finishVideo(downloaded, streams: try await probeStreams(downloaded), in: stage, id: id) : downloaded
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        saved = try moveUnique(file, to: target)
                    }
                    items[i].output = saved; items[i].state = "완료"
                    let size = (try? FileManager.default.attributesOfItem(atPath: saved.path)[.size] as? NSNumber)?.doubleValue
                    for key in items[i].progress.keys { items[i].progress[key]?.finished = true }
                    if item.engine == "direct" { items[i].progress["direct"] = StreamProgress(id: "direct", downloaded: size ?? 0, total: size, speed: nil, eta: nil, finished: true) }
                    if let f = items[i].choices.firstIndex(where: { $0.id == item.formatID }) { items[i].choices[f].size = size; items[i].choices[f].approximate = false }
                    if writeRecord {
                        let receipt = "Jini Downloader \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")\n이름: \(item.title)\n원본 페이지: \(item.source)\n선택 포맷 ID: \(item.formatID)\n선택 정보: \(item.selectedFormat.detail)\n저장 파일: \(saved.lastPathComponent)\n실제 용량: \(bytes(size))\n저장 시각: \(Date())\n사이트 제공 스트림을 재인코딩 없이 저장했습니다. 업로드 원본 파일과 동일함을 보장하지 않습니다.\n"
                        try? receipt.write(to: saved.appendingPathExtension("download.txt"), atomically: true, encoding: .utf8)
                    }
                    if keepHistory { history.add(items[i], saved: saved, size: size) }
                    note("저장 완료: \(saved.lastPathComponent) · \(bytes(size))")
                } catch { items[i].state = Task.isCancelled ? "취소됨" : "실패"; items[i].error = Task.isCancelled ? "" : error.localizedDescription; note(error.localizedDescription) }
                activeID = nil
            }
            let saved = ids.compactMap { id in items.first { $0.id == id && $0.state == "완료" } }
            let failed = ids.filter { id in items.contains { $0.id == id && $0.state == "실패" } }.count
            status = cancelled ? L("다운로드 취소됨", "Download cancelled") : L("완료 \(saved.count) · 실패 \(failed)", "Done \(saved.count) · failed \(failed)")
            NSApp.dockTile.badgeLabel = nil
            if !cancelled { notifyFinished(saved: saved, failed: failed) }
        }
    }
    /// yt-dlp format arguments: merged video+audio into MKV, or the best audio extracted into M4A/MP3.
    private func selection(_ item: MediaItem) -> [String] {
        let format = item.selectedFormat
        var picked = format.audioFormat.map { $0 == "m4a" ? "ba[ext=m4a]/ba" : "ba" } ?? format.id
        var section: [String] = []
        if let clip = item.clip {
            let plan = Clip.format(for: format)
            picked = plan.format
            // MKV has no edit list to hide a keyframe lead-in, so the original-format option cuts precisely instead.
            let precise = plan.forceKeyframes || keepOriginalVideo && format.audioFormat == nil
            section = ["--download-sections", Clip.argument(clip)] + (precise ? ["--force-keyframes-at-cuts"] : [])
        }
        guard let audio = format.audioFormat else { return ["--merge-output-format", "mkv", "-f", picked] + section + subtitleArguments }
        return ["-f", picked, "-x", "--audio-format", audio, "--audio-quality", "0"] + section
    }
    /// Subtitle options for video downloads: chosen languages as SRT, as files beside the video or embedded in it.
    private var subtitleArguments: [String] {
        guard subtitlesEnabled else { return [] }
        let languages = subtitleLanguages.filter { $0.isLetter || $0.isNumber || ",-_.*".contains($0) }
        return ["--write-subs"] + (autoSubtitles ? ["--write-auto-subs"] : []) + ["--sub-langs", languages.isEmpty ? "ko,en" : languages, "--convert-subs", "srt"] + (embedSubtitles ? ["--embed-subs"] : [])
    }
    private func probeStreams(_ file: URL) async throws -> [[String: Any]] {
        let probe = try await execute("ffprobe", ["-v","error","-show_entries","stream=codec_type,codec_name,width,height,r_frame_rate,start_time","-of","json",file.path], metadata: true)
        return (try JSONSerialization.jsonObject(with: probe.output) as? [String: Any])?["streams"] as? [[String: Any]] ?? []
    }
    /// A section cut without re-encoding keeps its video from the keyframe before the start, while the audio starts exactly
    /// there. A standalone MP4 hides that lead-in with an edit list, but the merged file loses it, so the clip plays from
    /// the keyframe. Rebuild it as an MP4 starting at the audio: streams are copied and the new edit list trims the lead-in.
    private func trimSection(_ file: URL, streams: [[String: Any]], in stage: URL) async throws -> URL {
        func start(_ type: String) -> Double? { streams.first { $0["codec_type"] as? String == type }.flatMap { number($0, "start_time") } }
        guard let video = start("video"), let audio = start("audio"), audio - video > 0.05 else { return file }
        let folder = stage.appendingPathComponent("trimmed", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".mp4")
        let subtitles = streams.contains { $0["codec_type"] as? String == "subtitle" } ? ["-map", "0:s?", "-c:s", "mov_text"] : []
        _ = try await execute("ffmpeg", ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-ss", String(format: "%.3f", audio - video), "-i", file.path, "-map", "0:v:0", "-map", "0:a:0"] + subtitles + ["-c:v", "copy", "-c:a", "copy", "-movflags", "+faststart", output.path], metadata: true)
        note("구간: 키프레임 앞부분 \(String(format: "%.1f", audio - video))초를 재생 목록에서 잘라냈습니다(재인코딩 없음).")
        return output
    }
    /// With the MP4 option, turns a finished video into an MP4 QuickTime plays; otherwise returns it unchanged.
    private func finishVideo(_ file: URL, streams: [[String: Any]], in stage: URL, id: UUID) async throws -> URL {
        guard videoContainer == .mp4 else { return file }
        let video = streams.first { $0["codec_type"] as? String == "video" }?["codec_name"] as? String
        let audio = streams.first { $0["codec_type"] as? String == "audio" }?["codec_name"] as? String
        let folder = stage.appendingPathComponent("mp4", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".mp4")
        let hasSubtitles = streams.contains { $0["codec_type"] as? String == "subtitle" }
        guard let args = MP4.arguments(input: file.path, output: output.path, ext: file.pathExtension, video: video, audio: audio, subtitles: hasSubtitles) else { return file }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = MP4.needsVideoEncode(video) ? "MP4로 변환 중" : "MP4로 옮기는 중" }
        _ = try await execute("ffmpeg", args, metadata: true)
        note(MP4.needsVideoEncode(video) ? "MP4 변환: \(video ?? "") 영상을 H.264로 인코딩했습니다." : "MP4 변환: 영상은 재인코딩 없이 옮겼습니다.")
        return output
    }
    private func moveUnique(_ source: URL, to dest: URL) throws -> URL {
        let name = source.lastPathComponent as NSString; var target = dest.appendingPathComponent(name as String); var n = 1
        while FileManager.default.fileExists(atPath: target.path) { target = dest.appendingPathComponent("\(name.deletingPathExtension) (\(n)).\(name.pathExtension)"); n += 1 }
        try FileManager.default.moveItem(at: source, to: target); return target
    }
    private func receive(_ line: String, id: UUID) {
        guard activeID == id, let i = items.firstIndex(where: { $0.id == id }), !["완료","실패","취소됨"].contains(items[i].state) else { return }
        if let p = StreamProgress.parse(line) { update(p, id: id) }
        else if line.hasPrefix("ODPOST") || line.contains("[Merger]") || line.contains("[ExtractAudio]") { items[i].state = items[i].selectedFormat.audioFormat == nil ? "영상·음성 병합 중" : "음성 추출 중" }
        else { note(line) }
    }
    private func update(_ p: StreamProgress, id: UUID) {
        guard activeID == id, let i = items.firstIndex(where: { $0.id == id }), !["완료","실패","취소됨","저장 확인 중","영상·음성 병합 중","MP4로 변환 중","MP4로 옮기는 중","음성 추출 중"].contains(items[i].state) else { return }
        items[i].progress[p.id] = p; items[i].state = p.finished ? "다음 단계 준비 중" : "다운로드 중"
    }
}
