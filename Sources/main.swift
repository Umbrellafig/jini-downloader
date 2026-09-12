import SwiftUI
import AppKit
import ImageIO

struct Thumbnail: View {
    let url: String?
    var headers: [String: String] = [:]
    @State private var preview: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
            if let preview { Image(nsImage: preview).resizable().scaledToFit() }
            else { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.secondary) }
        }.frame(width: 138, height: 88).clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            preview = nil
            guard let url, let u = webURL(url) else { return }
            do {
                var r = URLRequest(url: u); r.timeoutInterval = 15
                headers.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
                let (stream, response) = try await URLSession.shared.bytes(for: r)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), (response.mimeType ?? "").hasPrefix("image/"), response.expectedContentLength <= 4*1024*1024 else { return }
                var data = Data()
                for try await byte in stream { if Task.isCancelled || data.count >= 4*1024*1024 { return }; data.append(byte) }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
                preview = NSImage(cgImage: image, size: .zero)
            } catch {}
        }
    }
}
struct DownloadProgress: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.progress.keys.sorted(), id: \.self) { key in
                if let p = item.progress[key] {
                    HStack {
                        Text(item.selectedFormat.streamIDs.count > 1 ? (key == item.selectedFormat.streamIDs.first ? "영상 다운로드" : "음성 다운로드") : "파일 다운로드").foregroundStyle(.secondary)
                        Spacer()
                        Text(p.fraction.map { "\(Int($0 * 100))%" } ?? "크기 미상").monospacedDigit().bold()
                        Text("\(bytes(p.downloaded)) / \(bytes(p.total))").foregroundStyle(.secondary)
                    }.font(.caption)
                    if let value = p.fraction { ProgressView(value: value).tint(.mint) }
                    else { ProgressView().progressViewStyle(.linear).tint(.mint) }
                    if !p.finished {
                        HStack { Text(p.speed.map { bytes($0) + "/s" } ?? "속도 계산 중"); Spacer(); Text(p.eta.map { "남은 시간 " + durationText($0) } ?? "남은 시간 계산 중") }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if ["연결 중","영상·음성 병합 중","저장 확인 중","다음 단계 준비 중"].contains(item.state) {
                HStack { ProgressView().controlSize(.mini); Text(item.state).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
struct MediaCard: View {
    @Binding var item: MediaItem
    let busy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Toggle("받기", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox).disabled(busy).accessibilityLabel("\(item.title) 선택")
                Thumbnail(url: item.thumbnail, headers: item.headers)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(item.subtitle + (item.duration != nil ? " · " + durationText(item.duration) : "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack {
                        Text(item.selectedFormat.ext.uppercased()).font(.caption.bold()).padding(.horizontal,7).padding(.vertical,3).background(Color.mint.opacity(0.13)).clipShape(Capsule())
                        Text(item.selectedFormat.sizeLabel).font(.callout.bold()).monospacedDigit()
                        Spacer()
                        Text(item.state).font(.caption.bold()).foregroundStyle(item.state == "완료" ? .mint : item.state == "실패" ? .orange : .secondary)
                    }
                    if item.engine == "yt-dlp" { Text(item.selectedFormat.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            if item.engine == "yt-dlp" {
                Picker("저장 품질", selection: Binding(get: { item.formatID }, set: { item.formatID = $0; item.state = "준비됨"; item.progress = [:]; item.output = nil; item.error = "" })) {
                    ForEach(item.choices) { choice in Text(choice.label).tag(choice.id) }
                }.disabled(busy)
                Text("선택 포맷: \(item.formatID) · 서버가 제공하는 스트림을 재인코딩 없이 저장").font(.caption2).foregroundStyle(.secondary)
            }
            if !item.warning.isEmpty { Text(item.warning).font(.caption).foregroundStyle(.orange).lineLimit(4).textSelection(.enabled) }
            if !item.error.isEmpty { Text(item.error).font(.caption).foregroundStyle(.orange).lineLimit(6).textSelection(.enabled) }
            DownloadProgress(item: item)
            if let output = item.output { HStack { Label("저장 완료", systemImage: "checkmark.circle.fill").foregroundStyle(.mint); Spacer(); Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }.font(.caption) }
        }.padding(16).background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(item.selected ? Color.mint.opacity(0.22) : Color.white.opacity(0.06)))
    }
}
struct ContentView: View {
    @ObservedObject var m: Model
    @ObservedObject var updates: AppUpdater
    @State var showLog = false
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
                ZStack(alignment: .topLeading) {
                    if m.input.isEmpty { Text("https://…  링크를 한 줄에 하나씩 입력하세요").foregroundStyle(.tertiary).padding(10) }
                    TextEditor(text: $m.input).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(5).accessibilityLabel("미디어 URL")
                }.frame(height: 60).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1))).disabled(m.busy)
                HStack {
                    Button("붙여넣기") { if let s = NSPasteboard.general.string(forType: .string) { m.input = s } }.disabled(m.busy)
                    Spacer()
                    Button("분석하기") { m.analyze() }.disabled(m.busy || !m.enginesReady).keyboardShortcut(.return, modifiers: .command)
                }
                HStack { Image(systemName: "folder").foregroundStyle(.mint); Text(m.folder.path).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button("변경") { m.choose() }.disabled(m.busy); Button("폴더 열기") { try? FileManager.default.createDirectory(at: m.folder, withIntermediateDirectories: true); NSWorkspace.shared.open(m.folder) } }
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if m.items.isEmpty && !m.busy {
                            VStack(spacing: 12) { Image(systemName: "rectangle.stack.badge.play").font(.system(size: 44)).foregroundStyle(.mint.opacity(0.6)); Text("다운로드 전에 이름·화질·용량을 확인하세요").font(.headline); Text("분석하기 → 이미지·동영상 확인 → 선택 또는 전체 다운로드").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 55)
                        }
                        ForEach($m.items) { $item in MediaCard(item: $item, busy: m.busy && !m.analyzing) }
                        ForEach(Array(m.previewErrors.enumerated()), id: \.offset) { _, e in Text(e).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    }.padding(.vertical, 2)
                }.frame(minHeight: 210)
                HStack {
                    if !m.items.isEmpty { Button("전체 선택") { for i in m.items.indices { m.items[i].selected = true } }.disabled(m.busy); Button("해제") { for i in m.items.indices { m.items[i].selected = false } }.disabled(m.busy) }
                    Text("\(m.selectedCount)개 · \(m.selectedSize)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("전체 다운로드") { m.downloadAll() }.disabled(m.busy || m.stale || !m.enginesReady || !m.items.contains { $0.state != "완료" })
                    Button("선택 다운로드") { m.start() }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(!m.canDownload)
                }
                DisclosureGroup("상세 로그", isExpanded: $showLog) { ScrollView { Text(m.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(height: 100).background(Color.black.opacity(0.12)) }.font(.caption)
                Text("용량은 서버 정보 기준이며 ‘약’은 추정값입니다. 병합 후 크기는 달라질 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            }.padding(24).frame(minWidth: 690).disabled(updates.sessionActive)
        }.frame(minWidth: 1000, minHeight: 770).preferredColorScheme(.dark)
        .onAppear { Installation.checkOnce() }
        .onChange(of: m.busy) { busy in if !busy { updates.workFinished() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in m.stop() }
    }

}
@main struct JiniDownloaderApp: App {
    @StateObject private var model: Model
    @StateObject private var updates: AppUpdater
    init() {
        let model = Model()
        _model = StateObject(wrappedValue: model)
        _updates = StateObject(wrappedValue: AppUpdater(isBusy: { model.busy }))
    }
    var body: some Scene {
        WindowGroup { ContentView(m: model, updates: updates) }
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .appInfo) {
                    Button("업데이트 확인…") { updates.check() }.disabled(model.busy || !updates.canCheck)
                }
            }
    }
}
