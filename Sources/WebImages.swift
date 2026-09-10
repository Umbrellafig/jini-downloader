import SwiftUI
import WebKit

// A separate, ephemeral browsing session. It never imports the user's browser cookies.
@MainActor final class WebImages: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var status = "페이지를 여는 중…"
    @Published var scanning = false
    @Published var address = ""
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }
    func open(_ url: URL) { address = url.absoluteString; webView.load(URLRequest(url: url)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
        status = "상품 사진이 보이도록 스크롤한 뒤 ‘현재 페이지 이미지 가져오기’를 누르세요."
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { status = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, webURL(url.absoluteString) != nil else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    static let script = #"""
    (() => {
      const out = [], seen = new Set();
      const add = (raw, title, width, height) => {
        if (!raw || out.length >= 200) return;
        try {
          const u = new URL(raw, document.baseURI);
          if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || seen.has(u.href)) return;
          if (width > 0 && height > 0 && (width < 48 || height < 48)) return;
          seen.add(u.href); out.push({url:u.href, title:title || '', width:width || 0, height:height || 0});
        } catch (_) {}
      };
      for (const img of document.images) {
        // currentSrc is the actual resource chosen by the browser, including picture/srcset.
        if (!img.complete || !img.naturalWidth) continue;
        add(img.currentSrc || img.src, img.alt || img.title, img.naturalWidth, img.naturalHeight);
      }
      // Some product cards display their thumbnail as a CSS background.
      for (const el of Array.from(document.querySelectorAll('*')).slice(0, 20000)) {
        const r = el.getBoundingClientRect();
        if (r.width < 48 || r.height < 48) continue;
        const bg = getComputedStyle(el).backgroundImage;
        for (const match of bg.matchAll(/url\(["']?(.*?)["']?\)/g)) add(match[1], el.getAttribute('aria-label') || '', 0, 0);
      }
      return {source:location.href, images:out};
    })()
    """#
    func scan() async throws -> [MediaItem] {
        scanning = true
        defer { scanning = false }
        let raw = try await webView.evaluateJavaScript(Self.script)
        guard let result = raw as? [String: Any], let source = result["source"] as? String,
              webURL(source) != nil, let rows = result["images"] as? [[String: Any]] else { throw failure("페이지 이미지 정보를 읽지 못했습니다.") }
        let items = Self.items(rows, source: source)
        guard !items.isEmpty else { throw failure("로드된 이미지를 찾지 못했습니다. 사이트 확인 화면을 직접 완료하고, 사진이 보이도록 스크롤한 뒤 다시 시도해 주세요.") }
        return items
    }
    static func items(_ rows: [[String: Any]], source: String) -> [MediaItem] {
        var seen = Set<String>()
        return rows.prefix(200).compactMap { row in
            guard let value = row["url"] as? String, let url = webURL(value), seen.insert(value).inserted else { return nil }
            let ext = url.pathExtension.lowercased()
            let known = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "tiff", "bmp", "svg"].contains(ext)
            let name = safeName(url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent)
            let choice = FormatChoice(id: "direct", ext: known ? ext : "?", width: Int(number(row, "width") ?? 0), height: Int(number(row, "height") ?? 0), streamIDs: ["direct"])
            var item = MediaItem(source: source, url: value, title: name, subtitle: row["title"] as? String ?? "웹페이지 이미지", thumbnail: value, choices: [choice], formatID: "direct")
            item.selected = false
            item.headers = ["Referer": source]
            item.warning = "페이지에 로드된 이미지입니다. 상품 원본보다 작은 썸네일일 수 있습니다. 로그인이나 사이트 보호가 필요한 파일은 저장되지 않을 수 있습니다."
            return item
        }
    }
}

struct WebImageView: NSViewRepresentable {
    let browser: WebImages
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

struct WebImageSheet: View {
    let url: URL
    let receive: ([MediaItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebImages()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("웹페이지에서 이미지 찾기").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }.disabled(browser.scanning)
            }
            Text(browser.address).font(.caption).textSelection(.enabled).lineLimit(2)
            Text("사이트 확인 화면은 직접 진행해 주세요. 사진이 나중에 나타나면 아래로 스크롤하세요. 최대 200개의 이미지를 가져오며, 다운로드할 사진은 다음 화면에서 선택합니다.").font(.callout)
            WebImageView(browser: browser).frame(minWidth: 850, minHeight: 500)
            HStack {
                Text(browser.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if browser.scanning { ProgressView().controlSize(.small) }
                Button("현재 페이지 이미지 가져오기") {
                    Task {
                        do { let items = try await browser.scan(); receive(items); dismiss() }
                        catch { browser.status = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(browser.scanning || browser.webView.isLoading)
            }
        }.padding(20).onAppear { browser.open(url) }
    }
}
