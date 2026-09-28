import SwiftUI
import AppKit
import ImageIO
import AVKit
import UniformTypeIdentifiers
import QuickLook

struct Thumbnail: View {
    let url: String?
    var headers: [String: String] = [:]
    var kind: MediaKind = .image
    var maxPixel = 160
    var maxBytes = 4*1024*1024
    @State private var preview: NSImage?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.05))
            if let preview { Image(nsImage: preview).resizable().scaledToFit() }
            else { Image(systemName: kind.symbol).foregroundStyle(.secondary) }
        }
        .task(id: url) {
            preview = nil
            guard let url, let u = webURL(url) else { return }
            do {
                var r = URLRequest(url: u); r.timeoutInterval = 15
                headers.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
                let (stream, response) = try await URLSession.shared.bytes(for: r)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), (response.mimeType ?? "").hasPrefix("image/"), response.expectedContentLength <= maxBytes else { return }
                var data = Data()
                for try await byte in stream { if Task.isCancelled || data.count >= maxBytes { return }; data.append(byte) }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
                preview = NSImage(cgImage: image, size: .zero)
            } catch {}
        }
    }
}
/// Large view of one result; opened by clicking a row's thumbnail.
struct PreviewSheet: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.kind.single, systemImage: item.kind.symbol).font(.caption.bold()).foregroundStyle(.mint)
                Text(item.title).font(.headline).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button(L("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Group {
                if item.kind == .video && item.engine == "direct", let u = webURL(item.url) { VideoPlayer(player: AVPlayer(url: u)) }
                else { Thumbnail(url: item.thumbnail, headers: item.headers, kind: item.kind, maxPixel: 2000, maxBytes: 30*1024*1024).font(.system(size: 48)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text([item.selectedFormat.ext.uppercased(), item.selectedFormat.sizeLabel, item.engine == "yt-dlp" ? item.selectedFormat.detail : item.selectedFormat.resolution, item.duration != nil ? durationText(item.duration) : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if let u = webURL(item.source) { Link(L("원본 페이지 열기", "Open Source Page"), destination: u).font(.caption) }
            }
        }.padding(18).frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680).preferredColorScheme(.dark)
    }
}
struct DownloadProgress: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Video and audio streams download one after another; show them as one bar.
            if item.state != "완료", let p = StreamProgress.combined(item.progress, streams: item.selectedFormat.streamIDs, estimate: item.selectedFormat.size) {
                HStack {
                    Text(L("다운로드", "Download")).foregroundStyle(.secondary)
                    Spacer()
                    Text(p.fraction.map { "\(Int($0 * 100))%" } ?? L("크기 미상", "Size unknown")).monospacedDigit().bold()
                    Text("\(bytes(p.downloaded)) / \(p.total.map { (item.progress.count < item.selectedFormat.streamIDs.count ? L("약 ", "~") : "") + bytes($0) } ?? bytes(nil))").foregroundStyle(.secondary)
                }.font(.caption)
                if let value = p.fraction { ProgressView(value: value).tint(.mint) }
                else { ProgressView().progressViewStyle(.linear).tint(.mint) }
                if !p.finished {
                    HStack { Text(p.speed.map { bytes($0) + "/s" } ?? L("속도 계산 중", "Measuring speed")); Spacer(); Text(p.eta.map { L("남은 시간 ", "Time left ") + durationText($0) } ?? L("남은 시간 계산 중", "Estimating time left")) }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if ["연결 중","영상·음성 병합 중","저장 확인 중","다음 단계 준비 중","MP4로 변환 중","MP4로 옮기는 중","음성 추출 중"].contains(item.state) {
                HStack { ProgressView().controlSize(.mini); Text(stateLabel(item.state)).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
/// Fixed widths shared by the header and every row so the columns line up.
enum Column {
    static let check: CGFloat = 18, thumb: CGFloat = 52, kind: CGFloat = 50, format: CGFloat = 56, quality: CGFloat = 170, size: CGFloat = 86, state: CGFloat = 62
}
struct ColumnHeader: View {
    @Binding var sort: ColumnSort?
    @Binding var allSelected: Bool
    let busy: Bool
    var body: some View {
        HStack(spacing: 10) {
            Toggle(L("보이는 항목 모두 선택", "Select all visible"), isOn: $allSelected).labelsHidden().toggleStyle(.checkbox).disabled(busy).frame(width: Column.check)
            Color.clear.frame(width: Column.thumb, height: 1)
            title(.name).frame(maxWidth: .infinity, alignment: .leading)
            title(.kind).frame(width: Column.kind, alignment: .leading)
            title(.format).frame(width: Column.format, alignment: .leading)
            title(.quality).frame(width: Column.quality, alignment: .leading)
            title(.size).frame(width: Column.size, alignment: .trailing)
            Text(L("상태", "Status")).foregroundStyle(.secondary).frame(width: Column.state, alignment: .trailing)
        }.font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    func title(_ column: SortColumn) -> some View {
        let active = sort?.column == column
        return Button { sort = ColumnSort.next(sort, clicked: column) } label: {
            HStack(spacing: 3) {
                Text(column.label)
                if active, let sort { Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(active ? Color.mint : Color.secondary)
        .help(L("눌러서 \(column.label) 오름차순 → 내림차순 → 찾은 순서", "Click to sort by \(column.label.lowercased()): ascending → descending → found order"))
    }
}
struct MediaRow: View {
    @Binding var item: MediaItem
    let busy: Bool
    let container: VideoContainer
    let onPreview: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(L("받기", "Download"), isOn: $item.selected).labelsHidden().toggleStyle(.checkbox).disabled(busy || item.state == "완료").accessibilityLabel(L("\(item.title) 선택", "Select \(item.title)")).frame(width: Column.check).opacity(item.state == "완료" ? 0 : 1)
                Button(action: onPreview) {
                    Thumbnail(url: item.thumbnail, headers: item.headers, kind: item.kind).frame(width: Column.thumb, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help(item.output == nil ? L("크게 보기", "View larger") : L("받은 파일 미리보기 · 끌어서 다른 곳에 놓기", "Preview the file · drag it elsewhere")).accessibilityLabel(L("\(item.title) 크게 보기", "View \(item.title) larger"))
                .onDrag { item.output.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.title).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        if !item.warning.isEmpty { Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary).help(item.warning) }
                        if item.engine == "yt-dlp" && !item.inDownloads { ClipButton(item: $item).disabled(busy) }
                    }
                    Text([item.subtitle, item.duration != nil ? durationText(item.duration) : "", item.clip.map { L("구간 \(durationText($0.start))–\(durationText($0.end))", "Section \(durationText($0.start))–\(durationText($0.end))") } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(item.kind.single).font(.caption).foregroundStyle(.secondary).frame(width: Column.kind, alignment: .leading)
                Text(item.selectedFormat.audioFormat?.uppercased() ?? (item.kind == .video && container == .mp4 ? "MP4" : item.selectedFormat.ext.uppercased())).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(Color.mint.opacity(0.13)).clipShape(Capsule()).frame(width: Column.format, alignment: .leading)
                Group {
                    if item.engine == "yt-dlp" {
                        Picker(L("저장 품질", "Quality"), selection: Binding(get: { item.formatID }, set: { item.formatID = $0; item.state = "준비됨"; item.progress = [:]; item.output = nil; item.error = "" })) {
                            ForEach(item.choices) { choice in Text(choice.label).tag(choice.id) }
                        }.labelsHidden().disabled(busy).help(container == .mp4 ? L("받은 뒤 MP4로 저장합니다. H.264·HEVC·AV1 영상은 재인코딩하지 않습니다", "Saved as MP4 after download. H.264, HEVC and AV1 video isn't re-encoded") : L("서버가 제공하는 스트림을 재인코딩 없이 저장합니다", "Saves the site's streams without re-encoding"))
                    } else {
                        Text(item.selectedFormat.height > 0 ? item.selectedFormat.resolution : "—").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.frame(width: Column.quality, alignment: .leading)
                Text(item.selectedFormat.sizeLabel).font(.caption.bold()).monospacedDigit().lineLimit(1).frame(width: Column.size, alignment: .trailing)
                Group {
                    if item.state == "준비됨", let at = item.downloadedAt {
                        Text(L("이전에 받음", "Downloaded before")).foregroundStyle(.mint.opacity(0.85)).help(L("\(at.formatted(date: .abbreviated, time: .shortened))에 받은 파일입니다", "Downloaded \(at.formatted(date: .abbreviated, time: .shortened))"))
                    } else {
                        Text(stateLabel(item.state)).foregroundStyle(item.state == "완료" ? .mint : item.state == "실패" ? .orange : .secondary)
                    }
                }.font(.caption2.bold()).lineLimit(1).frame(width: Column.state, alignment: .trailing)
            }
            if !item.error.isEmpty { Text(item.error).font(.caption).foregroundStyle(.orange).lineLimit(4).textSelection(.enabled) }
            DownloadProgress(item: item)
            if let output = item.output {
                HStack {
                    // Dragging the saved line hands the file to Finder or another app.
                    Label(L("저장 완료", "Saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                        .onDrag { NSItemProvider(contentsOf: output) ?? NSItemProvider() }
                    Spacer()
                    Button(L("미리보기", "Preview")) { onPreview() }.help(L("Quick Look으로 받은 파일 보기", "View the file in Quick Look"))
                    Button(L("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                }.font(.caption)
            }
        }.padding(.horizontal, 10).padding(.vertical, 5).background(item.selected ? Color.mint.opacity(0.07) : Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
struct HistoryCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button(L("다운로드 기록", "Download History")) { openWindow(id: "history") }.keyboardShortcut("y") }
}
/// Opens the Settings window. `showSettingsWindow:` no longer reaches SwiftUI's Settings scene on macOS 14+, so use SettingsLink.
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14, *) { SettingsLink { Text(L("설정…", "Settings…")) } }
        else { Button(L("설정…", "Settings…")) { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) } }
    }
}
struct HistoryView: View {
    @ObservedObject var m: Model
    @ObservedObject var history: History
    @State private var query = ""
    @State private var selection = Set<HistoryEntry.ID>()
    var shown: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? history.entries : history.entries.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.source.localizedCaseInsensitiveContains(q) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(L("제목이나 주소로 찾기", "Search titles or links"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Text(L("\(shown.count)개", "\(shown.count)")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button(L("선택 항목 지우기", "Delete Selected")) { history.remove(selection); selection = [] }.disabled(selection.isEmpty)
                Button(L("기록 모두 지우기", "Clear History"), role: .destructive) { history.clear(); selection = [] }.disabled(history.entries.isEmpty)
            }
            List(shown, selection: $selection) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).lineLimit(1).truncationMode(.middle)
                        Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.format) · \(bytes(entry.size))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    let file = URL(fileURLWithPath: entry.file)
                    Button(L("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file]) }.disabled(!FileManager.default.fileExists(atPath: entry.file)).help(FileManager.default.fileExists(atPath: entry.file) ? entry.file : L("파일이 옮겨졌거나 지워졌습니다", "The file was moved or deleted"))
                    Button(L("다시 분석", "Analyze Again")) { m.receive(links: [entry.source]) }.disabled(webURL(entry.source) == nil)
                }.font(.callout).padding(.vertical, 2)
            }
            if history.entries.isEmpty { Text(m.keepHistory ? L("아직 받은 파일이 없습니다.", "Nothing downloaded yet.") : L("설정에서 다운로드 기록이 꺼져 있습니다.", "Download history is off in Settings.")).font(.caption).foregroundStyle(.secondary) }
        }.padding(16).frame(minWidth: 640, minHeight: 420).preferredColorScheme(.dark)
    }
}
/// Picks a section of a video to download instead of the whole thing.
struct ClipButton: View {
    @Binding var item: MediaItem
    @State private var open = false
    @State private var start = ""
    @State private var end = ""
    @State private var error = ""
    var body: some View {
        Button {
            start = item.clip.map { durationText($0.start) } ?? ""; end = item.clip.map { durationText($0.end) } ?? ""; error = ""; open = true
        } label: { Image(systemName: item.clip == nil ? "scissors" : "scissors.circle.fill").font(.caption) }
        .buttonStyle(.plain).foregroundStyle(item.clip == nil ? Color.secondary : Color.mint).help(L("구간만 받기", "Download a section"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("구간만 받기", "Download a section")).font(.headline)
                HStack {
                    TextField(L("시작", "Start"), text: $start, prompt: Text("0:00")).frame(width: 90)
                    Text("–")
                    TextField(L("끝", "End"), text: $end, prompt: Text(item.duration.map { durationText($0) } ?? L("끝", "End"))).frame(width: 90)
                }.textFieldStyle(.roundedBorder).monospacedDigit()
                Text(L("비워 두면 처음 또는 끝까지 받습니다\(item.duration.map { " · 영상 길이 \(durationText($0))" } ?? ""). 대부분 다시 인코딩하지 않고 정확히 자르며, 일부 형식(VP9 등)은 자르는 지점만 다시 인코딩합니다.", "Leave blank to start at the beginning or run to the end\(item.duration.map { " · length \(durationText($0))" } ?? ""). Most cuts are exact without re-encoding; some formats (such as VP9) re-encode only at the cut points.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button(L("전체 받기", "Whole Video")) { item.clip = nil; open = false }.disabled(item.clip == nil)
                    Spacer()
                    Button(L("적용", "Apply")) {
                        switch Clip.range(start: start, end: end, duration: item.duration) {
                        case .success(let range): item.clip = range; open = false
                        case .failure(let problem): error = problem.localizedDescription
                        }
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(14).frame(width: 300)
        }
    }
}
/// The in-app browser: the user logs in or passes a site check, scrolls to the media, and collects what the screen shows.
struct BrowserSheet: View {
    @ObservedObject var m: Model
    @ObservedObject var session: WebImages
    @State private var address = ""
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }.help(L("뒤로", "Back"))
                Button { session.webView.goForward() } label: { Image(systemName: "chevron.right") }.help(L("앞으로", "Forward"))
                Button { session.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.help(L("새로고침", "Reload"))
                TextField(L("주소", "Address"), text: $address).textFieldStyle(.roundedBorder).onSubmit {
                    let text = address.trimmingCharacters(in: .whitespaces)
                    if let u = webURL(text) ?? webURL("https://" + text) { session.open(u) }
                }
            }
            WebImageView(browser: session).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(.mint)
                Text(L("로그인·사이트 확인을 마치고 사진·영상이 보이도록 스크롤한 뒤 ‘이 화면에서 찾기’를 누르세요. 여기서 한 로그인은 저장되지 않고 앱을 끄면 사라집니다.", "Log in or pass the site check, scroll until the photos or videos show, then press Find on This Screen. Logins here aren't saved and disappear when the app quits.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                Text(m.status).font(.caption).lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
                Button(L("닫기", "Close")) { m.showBrowser = false }.keyboardShortcut(.cancelAction)
                Button(L("이 화면에서 찾기", "Find on This Screen")) { m.findInBrowser() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(m.busy || !m.enginesReady)
            }
        }.padding(12).frame(minWidth: 1000, idealWidth: 1100, minHeight: 720, idealHeight: 820).preferredColorScheme(.dark)
        .onAppear { address = session.address }
        .onReceive(session.$address) { address = $0 }
    }
}
struct SettingsView: View {
    @ObservedObject var m: Model
    @ObservedObject var updates: AppUpdater
    var body: some View {
        Form {
            Section(L("다운로드 위치", "Download Location")) {
                HStack {
                    Image(systemName: "folder").foregroundStyle(.mint)
                    Text(m.folder.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button(L("변경…", "Change…")) { m.choose() }
                }
                HStack {
                    Spacer()
                    Button(L("다운로드 폴더로 되돌리기", "Use Downloads")) { m.resetFolder() }.disabled(m.usesDefaultFolder)
                    Button(L("폴더 열기", "Open Folder")) { NSWorkspace.shared.open(m.folder) }
                }
            }
            Section(L("일반", "General")) {
                Picker(L("언어", "Language"), selection: $m.language) { ForEach(AppLanguage.allCases) { Text($0.label).tag($0) } }
                Toggle(L("분석이 끝나면 바로 받기", "Download right after analysis"), isOn: $m.instantDownload)
                Toggle(L("다운로드가 끝나면 알림 보내기", "Notify when downloads finish"), isOn: $m.notifyWhenDone)
                Toggle(L("클립보드에 링크가 있으면 분석할지 물어보기", "Offer to analyze copied links"), isOn: $m.watchClipboard)
            }
            Section(L("고급", "Advanced")) {
                Picker(L("동영상 파일 이름", "Video file name"), selection: $m.naming) { ForEach(FileNaming.allCases) { Text($0.label).tag($0) } }
                Text(L("예: \(m.naming.example)", "Example: \(m.naming.example)")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("사이트별 폴더에 나눠 저장", "Save into a folder per site"), isOn: $m.folderPerSite)
                Toggle(L("동영상 자막도 받기", "Download video subtitles"), isOn: $m.subtitlesEnabled)
                if m.subtitlesEnabled {
                    TextField(L("자막 언어", "Subtitle languages"), text: $m.subtitleLanguages, prompt: Text("ko,en"))
                    Toggle(L("자동 생성 자막도 받기", "Include auto-generated subtitles"), isOn: $m.autoSubtitles)
                    Picker(L("저장 방식", "Save as"), selection: $m.embedSubtitles) { Text(L("별도 파일(.srt)", "Separate file (.srt)")).tag(false); Text(L("영상에 넣기", "Inside the video")).tag(true) }.pickerStyle(.segmented)
                    Text(L("쉼표로 구분 · 모든 언어는 all", "Comma-separated · all for every language")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("다운로드 기록 남기기", "Keep download history"), isOn: $m.keepHistory)
                HStack { Spacer(); Button(L("기록 지우기", "Clear History")) { m.history.clear() }.disabled(m.history.entries.isEmpty) }
                Toggle(L("동영상을 원본 형식(MKV)으로 저장", "Save videos in the original format (MKV)"), isOn: $m.keepOriginalVideo)
                Text(L("일부 앱에서는 열리지 않아요", "Some apps can't open it")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("다운로드 기록 파일(.download.txt)도 함께 저장", "Also save a download record (.download.txt)"), isOn: $m.writeRecord)
            }
            Section(L("업데이트", "Updates")) {
                Toggle(L("자동으로 업데이트 확인", "Check for updates automatically"), isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomatic($0) }))
                HStack {
                    Text(L("버전 \(AppUpdater.version)", "Version \(AppUpdater.version)")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("업데이트 확인…", "Check for Updates…")) { updates.check() }.disabled(!updates.canCheck)
                }
                Link(L("도구·라이선스 안내", "Tools and licenses"), destination: URL(string: "https://github.com/Umbrellafig/jini-downloader/blob/main/docs/ENGINES.md")!).font(.caption)
            }
        }.formStyle(.grouped).frame(width: 520).disabled(m.busy)
    }
}
struct ContentView: View {
    @ObservedObject var m: Model
    @ObservedObject var updates: AppUpdater
    @Environment(\.openWindow) private var openWindow
    @State var showLog = false
    @State var kindFilter: MediaKind?
    @State var sort: ColumnSort?
    @State var previewing: MediaItem?
    @State var quickLook: URL?
    @State var dropping = false
    var found: [MediaItem] { m.items.filter { !$0.inDownloads } }
    var shown: [MediaItem] { found.arranged(kind: kindFilter, sort: sort) }
    var downloads: [MediaItem] { m.items.filter(\.inDownloads).sorted { ($0.queue ?? .max) < ($1.queue ?? .max) } }
    /// A saved file opens in Quick Look; anything not downloaded yet shows the web preview.
    func preview(_ item: MediaItem) {
        if let output = item.output, FileManager.default.fileExists(atPath: output.path) { quickLook = output } else { previewing = item }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if m.clipboardOffer && !m.busy {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(.mint)
                        Text(L("클립보드에 링크가 있어요", "A link is on the clipboard")).font(.callout)
                        Spacer()
                        Button(L("붙여넣고 분석", "Paste and Analyze")) { m.acceptClipboard() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(!m.enginesReady)
                        Button(L("닫기", "Close")) { m.clipboardOffer = false }
                    }.padding(.horizontal, 12).padding(.vertical, 8).background(Color.mint.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                ZStack(alignment: .topLeading) {
                    if m.input.isEmpty { Text(L("링크를 붙여넣으세요", "Paste links")).foregroundStyle(.tertiary).padding(10) }
                    TextEditor(text: $m.input).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(5).accessibilityLabel(L("미디어 URL", "Media URLs"))
                }.frame(height: 60).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1))).disabled(m.busy)
                HStack {
                    Button(L("붙여넣기", "Paste")) { m.paste() }.disabled(m.busy)
                    Spacer()
                    Button(L("직접 열기", "Open in Browser")) { m.openBrowser() }.disabled(m.busy).help(L("로그인이나 사이트 확인이 필요한 페이지를 앱 안에서 열고, 보이는 사진·영상을 찾습니다", "Open a page that needs a login or site check inside the app, and find the photos and videos it shows"))
                    Button(m.instantDownload ? L("분석하고 받기", "Analyze and Download") : L("분석하기", "Analyze")) { m.analyze() }.disabled(m.busy || !m.enginesReady).keyboardShortcut(.return, modifiers: .command)
                }
                HStack { Image(systemName: "folder").foregroundStyle(.mint); Text(m.folder.path).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button(L("기록", "History")) { openWindow(id: "history") }.help(L("다운로드 기록 (⌘Y)", "Download history (⌘Y)")); SettingsButton(); Button(L("폴더 열기", "Open Folder")) { try? FileManager.default.createDirectory(at: m.folder, withIntermediateDirectories: true); NSWorkspace.shared.open(m.folder) } }
                Divider()
                if !m.enginesReady {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("처음 한 번 필요한 도구를 설치해요 · 약 \(m.engineDownloadSize)", "Install the required tools once · about \(m.engineDownloadSize)")).font(.callout)
                            Spacer()
                            Button(m.installing ? L("설치 중…", "Installing…") : L("필수 도구 설치", "Install Required Tools")) { m.installEngines() }.disabled(m.busy).buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                        }
                        if m.installing { ProgressView(value: m.installProgress).tint(.mint) }
                    }.padding(14).background(Color.mint.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack { if m.busy { ProgressView().controlSize(.small) }; Text(m.status).font(.callout).lineLimit(1); Spacer(); if m.busy { Button(L("취소", "Cancel"), role: .cancel) { m.stop() } } }
                if m.stale { Text(L("링크가 변경되었습니다. 분석하기를 다시 눌러 주세요.", "The links changed. Press Analyze again.")).font(.caption).foregroundStyle(.orange) }
                if !m.items.isEmpty {
                    HStack {
                        Picker(L("종류", "Kind"), selection: $kindFilter) {
                            Text(L("전체 \(found.count)", "All \(found.count)")).tag(MediaKind?.none)
                            ForEach(MediaKind.allCases) { kind in
                                let n = found.filter { $0.kind == kind }.count
                                if n > 0 || kind != .other { Text("\(kind.label) \(n)").tag(MediaKind?.some(kind)) }
                            }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    }
                    ColumnHeader(sort: $sort, allSelected: Binding(
                        get: { !shown.isEmpty && shown.allSatisfy(\.selected) },
                        set: { value in let ids = Set(shown.map(\.id)); for i in m.items.indices where ids.contains(m.items[i].id) { m.items[i].selected = value } }
                    ), busy: m.busy)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if m.items.isEmpty && !m.busy {
                            VStack(spacing: 12) { Image(systemName: "rectangle.stack.badge.play").font(.system(size: 44)).foregroundStyle(.mint.opacity(0.6)); Text(L("링크를 붙여넣거나 끌어다 놓으세요", "Paste or drop a link")).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 55)
                        }
                        ForEach(shown) { row in
                            if let i = m.items.firstIndex(where: { $0.id == row.id }) {
                                MediaRow(item: $m.items[i], busy: m.busy && !m.analyzing, container: m.videoContainer) { preview(m.items[i]) }
                            }
                        }
                        if !m.items.isEmpty && shown.isEmpty { Text(found.isEmpty ? L("남은 파일이 없습니다. 아래 다운로드 목록을 확인하세요.", "Nothing left. See the downloads below.") : L("이 종류의 파일은 없습니다.", "No files of this kind.")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30) }
                        ForEach(Array(m.previewErrors.enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .top) {
                                Text(e).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                                Spacer()
                                Button(L("직접 열어서 찾기", "Open and Find")) { m.openBrowser() }.font(.caption).disabled(m.busy)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.vertical, 2)
                }.frame(minHeight: 160)
                HStack {
                    if !m.items.isEmpty || !m.previewErrors.isEmpty {
                        Button(L("목록 지우기", "Clear List")) { m.clearList(); kindFilter = nil; sort = nil }.disabled(m.busy).help(L("받은 파일은 그대로 둬요", "Saved files stay"))
                    }
                    Text(L("\(m.selectedCount)개 · \(m.selectedSize)", "\(m.selectedCount) · \(m.selectedSize)")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("전체 다운로드", "Download All")) { m.downloadAll() }.disabled(m.busy || m.stale || !m.enginesReady || !m.items.contains { $0.state != "완료" })
                    Button(L("선택 다운로드", "Download Selected")) { m.start() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(!m.canDownload)
                }
                if !downloads.isEmpty {
                    // Started items live here in queue order, so the found list above never reshuffles during a download.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(L("다운로드", "Download"), systemImage: "arrow.down.circle").font(.headline)
                            let done = downloads.filter { $0.state == "완료" }.count, failed = downloads.filter { $0.state == "실패" }.count
                            Text(L("완료 \(done) · 실패 \(failed) · 진행·대기 \(downloads.count - done - failed)", "Done \(done) · failed \(failed) · active or waiting \(downloads.count - done - failed)")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button(L("완료 항목 정리", "Clear Finished")) { m.clearFinished() }.disabled(m.busy || !downloads.contains { $0.state == "완료" }).help(L("저장된 파일은 그대로 두고 목록에서만 지웁니다", "Removes them from the list; saved files stay"))
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(downloads) { row in
                                    if let i = m.items.firstIndex(where: { $0.id == row.id }) {
                                        MediaRow(item: $m.items[i], busy: m.busy, container: m.videoContainer) { preview(m.items[i]) }
                                    }
                                }
                            }
                        }.frame(minHeight: 80, maxHeight: 220)
                    }.padding(10).background(Color.black.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                DisclosureGroup(L("상세 로그", "Details"), isExpanded: $showLog) { ScrollView { Text(m.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(height: 100).background(Color.black.opacity(0.12)) }.font(.caption)
            }.padding(24).frame(minWidth: 760).disabled(updates.sessionActive)
        }.frame(minWidth: 800, minHeight: 640).preferredColorScheme(.dark)
        .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $dropping) { providers in
            dropped(providers) { m.receive(links: $0) }; return true
        }
        .overlay {
            if dropping {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55))
                    RoundedRectangle(cornerRadius: 16).stroke(Color.mint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    Label(L("놓으면 링크를 분석합니다", "Drop to analyze the links"), systemImage: "arrow.down.doc").font(.title2.bold()).foregroundStyle(.mint)
                }.padding(12).allowsHitTesting(false)
            }
        }
        .sheet(item: $previewing) { PreviewSheet(item: $0) }
        .sheet(isPresented: $m.showBrowser) { if let session = m.browser { BrowserSheet(m: m, session: session) } }
        .quickLookPreview($quickLook)
        .onAppear { Installation.checkOnce(); Task { await m.checkClipboard() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await m.checkClipboard() } }
        .onChange(of: m.busy) { busy in if !busy { updates.workFinished() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in m.stop(); Model.clearCookieFiles() }
    }

}
/// Receives links from outside the window: web links or shortcut files dropped on the Dock icon, jinidownloader:// requests,
/// and the "지니 다운로더로 분석" Services menu item. Links that arrive before the model connects are kept until it does.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var handler: (([String]) -> Void)?
    private static var pending: [String] = []
    static func connect(_ handle: @escaping ([String]) -> Void) { handler = handle; if !pending.isEmpty { handle(pending); pending = [] } }
    static func deliver(_ links: [String]) {
        var seen = Set<String>(); let links = links.filter { seen.insert($0).inserted }
        guard !links.isEmpty else { return }
        if let handler { handler(links) } else { pending += links }
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.servicesProvider = self; NSUpdateDynamicServices() }
    func application(_ application: NSApplication, open urls: [URL]) { Self.deliver(urls.flatMap(externalLinks)) }
    @objc func analyzeLinks(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []).map(\.absoluteString).filter { webURL($0) != nil }
        Self.deliver(urls + webLinks(in: pasteboard.string(forType: .string) ?? ""))
    }
}
/// Collects links from items dropped on the window: web links, shortcut files, or text containing links.
func dropped(_ providers: [NSItemProvider], then deliver: @escaping @MainActor ([String]) -> Void) {
    let group = DispatchGroup(), lock = NSLock()
    var links: [String] = []
    func add(_ found: [String]) { lock.lock(); links += found; lock.unlock() }
    for provider in providers {
        group.enter()
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in add(url.map(externalLinks) ?? []); group.leave() }
        } else {
            _ = provider.loadObject(ofClass: String.self) { text, _ in add(webLinks(in: text ?? "")); group.leave() }
        }
    }
    group.notify(queue: .main) { MainActor.assumeIsolated { deliver(links) } }
}
@main struct JiniDownloaderApp: App {
    @StateObject private var model: Model
    @StateObject private var updates: AppUpdater
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        let model = Model()
        AppDelegate.connect { model.receive(links: $0) }
        _model = StateObject(wrappedValue: model)
        _updates = StateObject(wrappedValue: AppUpdater(isBusy: { model.busy }))
    }
    var body: some Scene {
        // Links from the Dock, the URL scheme or Services go to AppDelegate and the existing window, never a new one.
        WindowGroup { ContentView(m: model, updates: updates) }
            .handlesExternalEvents(matching: [])
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .appInfo) {
                    Button(L("업데이트 확인…", "Check for Updates…")) { updates.check() }.disabled(model.busy || !updates.canCheck)
                }
                CommandGroup(before: .windowList) { HistoryCommand() }
            }
        Window(L("다운로드 기록", "Download History"), id: "history") { HistoryView(m: model, history: model.history) }
        Settings { SettingsView(m: model, updates: updates) }
    }
}
