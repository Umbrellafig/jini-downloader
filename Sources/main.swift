import SwiftUI
import AppKit
import ImageIO
import AVKit
import UniformTypeIdentifiers

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
                Label(item.kind.rawValue, systemImage: item.kind.symbol).font(.caption.bold()).foregroundStyle(.mint)
                Text(item.title).font(.headline).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Group {
                if item.kind == .video && item.engine == "direct", let u = webURL(item.url) { VideoPlayer(player: AVPlayer(url: u)) }
                else { Thumbnail(url: item.thumbnail, headers: item.headers, kind: item.kind, maxPixel: 2000, maxBytes: 30*1024*1024).font(.system(size: 48)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text([item.selectedFormat.ext.uppercased(), item.selectedFormat.sizeLabel, item.engine == "yt-dlp" ? item.selectedFormat.detail : item.selectedFormat.resolution, item.duration != nil ? durationText(item.duration) : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if let u = webURL(item.source) { Link("원본 페이지 열기", destination: u).font(.caption) }
            }
        }.padding(18).frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680).preferredColorScheme(.dark)
    }
}
struct DownloadProgress: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Video and audio streams download one after another; show them as one bar.
            if let p = StreamProgress.combined(item.progress, streams: item.selectedFormat.streamIDs, estimate: item.selectedFormat.size) {
                HStack {
                    Text("다운로드").foregroundStyle(.secondary)
                    Spacer()
                    Text(p.fraction.map { "\(Int($0 * 100))%" } ?? "크기 미상").monospacedDigit().bold()
                    Text("\(bytes(p.downloaded)) / \(p.total.map { (item.progress.count < item.selectedFormat.streamIDs.count ? "약 " : "") + bytes($0) } ?? bytes(nil))").foregroundStyle(.secondary)
                }.font(.caption)
                if let value = p.fraction { ProgressView(value: value).tint(.mint) }
                else { ProgressView().progressViewStyle(.linear).tint(.mint) }
                if !p.finished {
                    HStack { Text(p.speed.map { bytes($0) + "/s" } ?? "속도 계산 중"); Spacer(); Text(p.eta.map { "남은 시간 " + durationText($0) } ?? "남은 시간 계산 중") }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if ["연결 중","영상·음성 병합 중","저장 확인 중","다음 단계 준비 중","MP4로 변환 중","MP4로 옮기는 중"].contains(item.state) {
                HStack { ProgressView().controlSize(.mini); Text(item.state).font(.caption).foregroundStyle(.secondary) }
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
            Toggle("보이는 항목 모두 선택", isOn: $allSelected).labelsHidden().toggleStyle(.checkbox).disabled(busy).frame(width: Column.check)
            Color.clear.frame(width: Column.thumb, height: 1)
            title(.name).frame(maxWidth: .infinity, alignment: .leading)
            title(.kind).frame(width: Column.kind, alignment: .leading)
            title(.format).frame(width: Column.format, alignment: .leading)
            title(.quality).frame(width: Column.quality, alignment: .leading)
            title(.size).frame(width: Column.size, alignment: .trailing)
            Text("상태").foregroundStyle(.secondary).frame(width: Column.state, alignment: .trailing)
        }.font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    func title(_ column: SortColumn) -> some View {
        let active = sort?.column == column
        return Button { sort = ColumnSort.next(sort, clicked: column) } label: {
            HStack(spacing: 3) {
                Text(column.rawValue)
                if active, let sort { Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(active ? Color.mint : Color.secondary)
        .help("눌러서 \(column.rawValue) 오름차순 → 내림차순 → 찾은 순서")
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
                Toggle("받기", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox).disabled(busy || item.state == "완료").accessibilityLabel("\(item.title) 선택").frame(width: Column.check).opacity(item.state == "완료" ? 0 : 1)
                Button(action: onPreview) {
                    Thumbnail(url: item.thumbnail, headers: item.headers, kind: item.kind).frame(width: Column.thumb, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help("크게 보기").accessibilityLabel("\(item.title) 크게 보기")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.title).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        if !item.warning.isEmpty { Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary).help(item.warning) }
                    }
                    Text([item.subtitle, item.duration != nil ? durationText(item.duration) : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary).frame(width: Column.kind, alignment: .leading)
                Text(item.kind == .video && container == .mp4 ? "MP4" : item.selectedFormat.ext.uppercased()).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(Color.mint.opacity(0.13)).clipShape(Capsule()).frame(width: Column.format, alignment: .leading)
                Group {
                    if item.engine == "yt-dlp" {
                        Picker("저장 품질", selection: Binding(get: { item.formatID }, set: { item.formatID = $0; item.state = "준비됨"; item.progress = [:]; item.output = nil; item.error = "" })) {
                            ForEach(item.choices) { choice in Text(choice.label).tag(choice.id) }
                        }.labelsHidden().disabled(busy).help(container == .mp4 ? "받은 뒤 MP4로 저장합니다. H.264·HEVC·AV1 영상은 재인코딩하지 않습니다" : "서버가 제공하는 스트림을 재인코딩 없이 저장합니다")
                    } else {
                        Text(item.selectedFormat.height > 0 ? item.selectedFormat.resolution : "—").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.frame(width: Column.quality, alignment: .leading)
                Text(item.selectedFormat.sizeLabel).font(.caption.bold()).monospacedDigit().lineLimit(1).frame(width: Column.size, alignment: .trailing)
                Text(item.state).font(.caption2.bold()).foregroundStyle(item.state == "완료" ? .mint : item.state == "실패" ? .orange : .secondary).lineLimit(1).frame(width: Column.state, alignment: .trailing)
            }
            if !item.error.isEmpty { Text(item.error).font(.caption).foregroundStyle(.orange).lineLimit(4).textSelection(.enabled) }
            DownloadProgress(item: item)
            if let output = item.output { HStack { Label("저장 완료", systemImage: "checkmark.circle.fill").foregroundStyle(.mint); Spacer(); Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }.font(.caption) }
        }.padding(.horizontal, 10).padding(.vertical, 5).background(item.selected ? Color.mint.opacity(0.07) : Color.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
/// Opens the Settings window. `showSettingsWindow:` no longer reaches SwiftUI's Settings scene on macOS 14+, so use SettingsLink.
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14, *) { SettingsLink { Text("설정…") } }
        else { Button("설정…") { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) } }
    }
}
struct SettingsView: View {
    @ObservedObject var m: Model
    var body: some View {
        Form {
            Section("다운로드 위치") {
                HStack {
                    Image(systemName: "folder").foregroundStyle(.mint)
                    Text(m.folder.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("변경…") { m.choose() }
                }
                HStack {
                    Text(m.usesDefaultFolder ? "기본 위치(다운로드 폴더)에 저장합니다." : "지정한 폴더에 저장합니다.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("다운로드 폴더로 되돌리기") { m.resetFolder() }.disabled(m.usesDefaultFolder)
                    Button("폴더 열기") { NSWorkspace.shared.open(m.folder) }
                }
            }
            Section("일반") {
                Toggle("분석이 끝나면 바로 받기", isOn: $m.instantDownload)
                Text("동영상이 있으면 모든 동영상을 가장 좋은 품질로, 없으면 열린 게시물이나 사진 모음의 파일을 바로 받습니다. 페이지 장식 이미지는 받지 않습니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("클립보드에 링크가 있으면 분석할지 물어보기", isOn: $m.watchClipboard)
                Text("앱으로 돌아올 때 링크가 복사되어 있으면 알려 줍니다. 링크가 있는지만 확인하고, 내용은 ‘붙여넣고 분석’을 누를 때만 읽습니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("고급") {
                Toggle("동영상을 원본 형식(MKV)으로 저장", isOn: $m.keepOriginalVideo)
                Text("기본은 QuickTime·사진 앱·아이폰에서 바로 열리는 MP4입니다. H.264·HEVC·AV1 영상은 재인코딩 없이 옮기고, VP9 등만 H.264로 변환합니다. 켜면 사이트가 주는 영상·음성을 변환 없이 MKV에 담습니다. 화질 손실이 전혀 없지만 일부 앱에서는 열리지 않습니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("다운로드 기록 파일(.download.txt)도 함께 저장", isOn: $m.writeRecord)
                Text("켜면 받은 파일 옆에 원본 페이지·선택 포맷·용량·저장 시각을 적은 텍스트 파일을 만듭니다. 출처를 남겨야 할 때만 켜세요.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 520).disabled(m.busy)
    }
}
struct ContentView: View {
    @ObservedObject var m: Model
    @ObservedObject var updates: AppUpdater
    @State var showLog = false
    @State var kindFilter: MediaKind?
    @State var sort: ColumnSort?
    @State var previewing: MediaItem?
    @State var dropping = false
    var found: [MediaItem] { m.items.filter { !$0.inDownloads } }
    var shown: [MediaItem] { found.arranged(kind: kindFilter, sort: sort) }
    var downloads: [MediaItem] { m.items.filter(\.inDownloads).sorted { ($0.queue ?? .max) < ($1.queue ?? .max) } }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "arrow.down.to.line.circle.fill").font(.system(size: 42)).foregroundStyle(.mint)
                Text("지니 다운로더").font(.system(size: 22, weight: .bold))
                Text("확인하고,\n원하는 품질로.").font(.title2).foregroundStyle(.secondary)
                Divider()
                Label("1  링크 분석", systemImage: "link")
                Label("2  파일·품질 선택", systemImage: "checklist")
                Label("3  다운로드", systemImage: "arrow.down")
                Spacer()
                Text("원본에 대한 안내").font(.caption.bold())
                Text("유튜브 업로드 원본과\n서비스가 제공하는 영상은\n다릅니다. 앱은 제공되는\n스트림을 추가 압축 없이\n저장합니다.").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                Text("VERSION \(AppUpdater.version)").font(.caption2).foregroundStyle(.tertiary)
                Button("업데이트 확인…") { updates.check() }.disabled(m.busy || !updates.canCheck)
                Toggle("자동으로 업데이트 확인", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomatic($0) })).font(.caption).toggleStyle(.checkbox)
                Text(m.busy ? "작업 완료 후 업데이트할 수 있습니다" : updates.status).font(.caption2).foregroundStyle(.secondary)
            }.padding(24).frame(width: 192).frame(maxHeight: .infinity).background(Color.black.opacity(0.18))
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("받을 파일을 먼저 확인하세요").font(.title.bold()); Spacer(); Text("PREVIEW & DOWNLOAD").font(.system(size: 10, weight: .semibold)).foregroundStyle(.mint) }
                if m.clipboardOffer && !m.busy {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(.mint)
                        Text("클립보드에 링크가 있어요").font(.callout)
                        Spacer()
                        Button("붙여넣고 분석") { m.acceptClipboard() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(!m.enginesReady)
                        Button("닫기") { m.clipboardOffer = false }
                    }.padding(.horizontal, 12).padding(.vertical, 8).background(Color.mint.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                ZStack(alignment: .topLeading) {
                    if m.input.isEmpty { Text("https://…  링크를 한 줄에 하나씩 입력하세요").foregroundStyle(.tertiary).padding(10) }
                    TextEditor(text: $m.input).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(5).accessibilityLabel("미디어 URL")
                }.frame(height: 60).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1))).disabled(m.busy)
                HStack {
                    Button("붙여넣기") { m.paste() }.disabled(m.busy)
                    Spacer()
                    Button(m.instantDownload ? "분석하고 받기" : "분석하기") { m.analyze() }.disabled(m.busy || !m.enginesReady).keyboardShortcut(.return, modifiers: .command)
                }
                HStack { Image(systemName: "folder").foregroundStyle(.mint); Text(m.folder.path).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); SettingsButton(); Button("폴더 열기") { try? FileManager.default.createDirectory(at: m.folder, withIntermediateDirectories: true); NSWorkspace.shared.open(m.folder) } }
                Divider()
                if !m.enginesReady {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("첫 실행 준비").font(.headline)
                        Text("다운로드와 영상 병합에 필요한 도구를 한 번 설치합니다 (약 \(m.engineDownloadSize)). 관리자 암호는 필요하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                        Text("yt-dlp·gallery-dl·Deno: 각 GitHub 배포처 / FFmpeg·FFprobe: Martin Riedl의 macOS 빌드. 버전과 SHA-256을 확인한 뒤 설치합니다.").font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Link("도구·라이선스 안내", destination: URL(string: "https://github.com/Umbrellafig/jini-downloader/blob/main/docs/ENGINES.md")!).font(.caption)
                            Spacer()
                            Button(m.installing ? "설치 중…" : "필수 도구 설치") { m.installEngines() }.disabled(m.busy).buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                        }
                        if m.installing { ProgressView(value: m.installProgress).tint(.mint); Text("설치 단계 진행").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(14).background(Color.mint.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack { if m.busy { ProgressView().controlSize(.small) }; Text(m.status).font(.callout).lineLimit(1); Spacer(); if m.busy { Button("취소", role: .cancel) { m.stop() } } }
                if m.stale { Text("링크가 변경되었습니다. 분석하기를 다시 눌러 주세요.").font(.caption).foregroundStyle(.orange) }
                if !m.items.isEmpty {
                    HStack {
                        Picker("종류", selection: $kindFilter) {
                            Text("전체 \(found.count)").tag(MediaKind?.none)
                            ForEach(MediaKind.allCases) { kind in
                                let n = found.filter { $0.kind == kind }.count
                                if n > 0 || kind != .other { Text("\(kind.rawValue) \(n)").tag(MediaKind?.some(kind)) }
                            }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                        Spacer()
                        Text("열 이름을 눌러 정렬").font(.caption2).foregroundStyle(.tertiary)
                    }
                    ColumnHeader(sort: $sort, allSelected: Binding(
                        get: { !shown.isEmpty && shown.allSatisfy(\.selected) },
                        set: { value in let ids = Set(shown.map(\.id)); for i in m.items.indices where ids.contains(m.items[i].id) { m.items[i].selected = value } }
                    ), busy: m.busy)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if m.items.isEmpty && !m.busy {
                            VStack(spacing: 12) { Image(systemName: "rectangle.stack.badge.play").font(.system(size: 44)).foregroundStyle(.mint.opacity(0.6)); Text("다운로드 전에 이름·화질·용량을 확인하세요").font(.headline); Text("분석하기 → 이미지·동영상 확인 → 선택 또는 전체 다운로드").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 55)
                        }
                        ForEach(shown) { row in
                            if let i = m.items.firstIndex(where: { $0.id == row.id }) {
                                MediaRow(item: $m.items[i], busy: m.busy && !m.analyzing, container: m.videoContainer) { previewing = m.items[i] }
                            }
                        }
                        if !m.items.isEmpty && shown.isEmpty { Text(found.isEmpty ? "남은 파일이 없습니다. 아래 다운로드 목록을 확인하세요." : "이 종류의 파일은 없습니다.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30) }
                        ForEach(Array(m.previewErrors.enumerated()), id: \.offset) { _, e in Text(e).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    }.padding(.vertical, 2)
                }.frame(minHeight: 160)
                HStack {
                    if !m.items.isEmpty {
                        // Selection follows the visible list, so a filtered kind can be picked in one step.
                        let ids = Set(shown.map(\.id))
                        Button(kindFilter.map { "\($0.rawValue) 모두 선택" } ?? "전체 선택") { for i in m.items.indices where ids.contains(m.items[i].id) { m.items[i].selected = true } }.disabled(m.busy)
                        Button("해제") { for i in m.items.indices where ids.contains(m.items[i].id) { m.items[i].selected = false } }.disabled(m.busy)
                    }
                    Text("\(m.selectedCount)개 · \(m.selectedSize)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("전체 다운로드") { m.downloadAll() }.disabled(m.busy || m.stale || !m.enginesReady || !m.items.contains { $0.state != "완료" })
                    Button("선택 다운로드") { m.start() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(!m.canDownload)
                }
                if !downloads.isEmpty {
                    // Started items live here in queue order, so the found list above never reshuffles during a download.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("다운로드", systemImage: "arrow.down.circle").font(.headline)
                            let done = downloads.filter { $0.state == "완료" }.count, failed = downloads.filter { $0.state == "실패" }.count
                            Text("완료 \(done) · 실패 \(failed) · 진행·대기 \(downloads.count - done - failed)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button("완료 항목 정리") { m.clearFinished() }.disabled(m.busy || !downloads.contains { $0.state == "완료" }).help("저장된 파일은 그대로 두고 목록에서만 지웁니다")
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(downloads) { row in
                                    if let i = m.items.firstIndex(where: { $0.id == row.id }) {
                                        MediaRow(item: $m.items[i], busy: m.busy, container: m.videoContainer) { previewing = m.items[i] }
                                    }
                                }
                            }
                        }.frame(minHeight: 80, maxHeight: 220)
                    }.padding(10).background(Color.black.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                DisclosureGroup("상세 로그", isExpanded: $showLog) { ScrollView { Text(m.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(height: 100).background(Color.black.opacity(0.12)) }.font(.caption)
                Text("용량은 서버 정보 기준이며 ‘약’은 추정값입니다. 병합 후 크기는 달라질 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            }.padding(24).frame(minWidth: 690).disabled(updates.sessionActive)
        }.frame(minWidth: 1000, minHeight: 770).preferredColorScheme(.dark)
        .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $dropping) { providers in
            dropped(providers) { m.receive(links: $0) }; return true
        }
        .overlay {
            if dropping {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55))
                    RoundedRectangle(cornerRadius: 16).stroke(Color.mint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    Label("놓으면 링크를 분석합니다", systemImage: "arrow.down.doc").font(.title2.bold()).foregroundStyle(.mint)
                }.padding(12).allowsHitTesting(false)
            }
        }
        .sheet(item: $previewing) { PreviewSheet(item: $0) }
        .onAppear { Installation.checkOnce(); Task { await m.checkClipboard() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await m.checkClipboard() } }
        .onChange(of: m.busy) { busy in if !busy { updates.workFinished() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in m.stop() }
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
                    Button("업데이트 확인…") { updates.check() }.disabled(model.busy || !updates.canCheck)
                }
            }
        Settings { SettingsView(m: model) }
    }
}
