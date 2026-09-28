import SwiftUI
import WebKit

// A separate, ephemeral browsing session. It never imports the user's browser cookies.
@MainActor final class WebImages: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var status = L("페이지를 여는 중…", "Opening the page…")
    @Published var scanning = false
    @Published var address = ""
    // Cross-origin iframes (video players, embeds) are invisible to the page script, and a page's declared video address
    // may never reach the DOM; the model analyzes these URLs separately.
    private(set) var embeds: [String] = []
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }
    func open(_ url: URL) { address = url.absoluteString; webView.load(URLRequest(url: url)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
        status = L("상품 사진이 보이도록 스크롤한 뒤 ‘현재 페이지 이미지 가져오기’를 누르세요.", "Page loaded.")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { status = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, webURL(url.absoluteString) != nil else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    /// Login pages often open a popup; show it in this view instead of dropping it.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, webURL(url.absoluteString) != nil { webView.load(navigationAction.request) }
        return nil
    }
    func inspect(_ url: URL) async throws -> [MediaItem] {
        open(url)
        defer { webView.stopLoading() }
        var latest: [MediaItem] = []
        var signature: [String]?
        var stable = 0
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 500_000_000)
            try Task.checkCancellation()
            guard !webView.isLoading else { continue }
            // An opened post may hold only an embedded player, so an empty image list still counts as a result.
            if let result = try? await scan() {
                let current = result.map(\.url) + embeds
                stable = current == signature ? stable + 1 : 0
                signature = current; latest = result
                if stable >= 3 { return latest }
            }
        }
        return latest
    }
    static let script = #"""
    (() => {
      const out = [], seen = new Set();
      // A link to one post (e.g. Padlet /wish/…) opens it in a dialog over the whole board. When that dialog
      // holds real media, collect only from it; a cookie banner with a small logo does not qualify.
      const visible = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
      const post = Array.from(document.querySelectorAll('[role=dialog], [aria-modal=true]')).find(d => visible(d) && (
        d.querySelector('video, iframe[src]') || Array.from(d.querySelectorAll('img')).some(i => i.complete && i.naturalWidth * i.naturalHeight >= 20000)));
      const scope = post || document;
      const add = (raw, title, width, height, kind = 'image') => {
        if (!raw || out.length >= 200) return;
        try {
          const u = new URL(raw, document.baseURI);
          if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || seen.has(u.href)) return;
          // Skip icons and pixels, but keep long strips such as webtoons shown 41×745.
          if (width > 0 && height > 0 && (Math.max(width, height) < 48 || width * height < 48 * 48)) return;
          seen.add(u.href); out.push({url:u.href, title:title || '', width:width || 0, height:height || 0, kind, post: !!post});
        } catch (_) {}
      };
      for (const img of scope.querySelectorAll('img')) {
        // currentSrc is the actual resource chosen by the browser, including picture/srcset.
        if (!img.complete || !img.naturalWidth) continue;
        add(img.currentSrc || img.src, img.alt || img.title, img.naturalWidth, img.naturalHeight);
      }
      // A streaming playlist (HLS/DASH) is not a file to save as is; the video engine analyzes it with the embeds.
      const declared = [], manifest = raw => /\.(m3u8|mpd)$/i.test((() => { try { return new URL(raw, document.baseURI).pathname; } catch (_) { return ''; } })());
      const addVideo = (raw, title, width, height) => manifest(raw) ? declared.push(raw) : add(raw, title, width, height, 'video');
      for (const video of scope.querySelectorAll('video')) {
        addVideo(video.currentSrc || video.src, video.title || '페이지 동영상', video.videoWidth, video.videoHeight);
        if (!video.currentSrc) for (const source of video.querySelectorAll('source[src]')) addVideo(source.src, video.title || '페이지 동영상', 0, 0);
      }
      // Some product cards display their thumbnail as a CSS background.
      for (const el of Array.from(scope.querySelectorAll('*')).slice(0, 20000)) {
        const r = el.getBoundingClientRect();
        if (r.width < 48 || r.height < 48) continue;
        const bg = getComputedStyle(el).backgroundImage;
        for (const match of bg.matchAll(/url\(["']?(.*?)["']?\)/g)) add(match[1], el.getAttribute('aria-label') || '', 0, 0);
      }
      const frames = [];
      for (const frame of scope.querySelectorAll('iframe[src]')) {
        try {
          const u = new URL(frame.src, document.baseURI), r = frame.getBoundingClientRect();
          if (['http:', 'https:'].includes(u.protocol) && !u.username && !u.password && r.width >= 120 && r.height >= 80 && !frames.includes(u.href) && frames.length < 5) frames.push(u.href);
        } catch (_) {}
      }
      // Players fed by script (HLS) leave no video address in the DOM; the page's declared video (JSON-LD, og:video)
      // still names it. Analyzed on its own, it is fetched without this page as Referer, which some hosts refuse.
      const walk = (node, depth) => {
        if (!node || typeof node !== 'object' || depth > 4) return;
        if (Array.isArray(node)) { node.forEach(n => walk(n, depth + 1)); return; }
        if (/VideoObject/.test([].concat(node['@type'] || []).join(' '))) declared.push(node.contentUrl, node.embedUrl);
        walk(node['@graph'], depth + 1); walk(node.video, depth + 1);
      };
      if (!post) {
        for (const s of document.querySelectorAll('script[type="application/ld+json"]')) { try { walk(JSON.parse(s.textContent), 0); } catch (_) {} }
        for (const m of document.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"]')) declared.push(m.content);
      }
      for (const raw of declared) {
        try {
          const u = new URL(raw, document.baseURI);
          if (['http:', 'https:'].includes(u.protocol) && !u.username && !u.password && u.href !== location.href && !frames.includes(u.href) && frames.length < 8) frames.push(u.href);
        } catch (_) {}
      }
      return {source:location.href, images:out, frames};
    })()
    """#
    func scan() async throws -> [MediaItem] {
        scanning = true
        defer { scanning = false }
        let raw = try await webView.evaluateJavaScript(Self.script)
        guard let result = raw as? [String: Any], let source = result["source"] as? String,
              webURL(source) != nil, let rows = result["images"] as? [[String: Any]] else { throw failure(L("페이지 이미지 정보를 읽지 못했습니다.", "Couldn't read the page's images.")) }
        embeds = (result["frames"] as? [String] ?? []).filter { webURL($0) != nil && $0 != source }
        return Self.items(rows, source: source)
    }
    /// Image proxies and resizers (padlet.pics, Next.js /_next/image, wsrv.nl, …) carry the original in a `url` parameter.
    static func original(_ url: URL) -> URL? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
              let inner = webURL(value), inner.host != url.host || inner.path != url.path else { return nil }
        return inner
    }
    static func items(_ rows: [[String: Any]], source: String) -> [MediaItem] {
        var seen = Set<String>()
        return rows.prefix(200).compactMap { row in
            guard let shown = row["url"] as? String, let shownURL = webURL(shown) else { return nil }
            let isVideo = row["kind"] as? String == "video"
            // Save the original behind a proxy; the proxy's small copy stays as the preview. Its pixel size is the copy's, so drop it.
            let inner = isVideo ? nil : original(shownURL)
            let url = inner ?? shownURL, value = url.absoluteString
            guard seen.insert(value).inserted else { return nil }
            let ext = url.pathExtension.lowercased()
            let known = ["mp4", "webm", "mov", "m4v", "jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "tiff", "bmp", "svg"].contains(ext)
            let name = safeName(url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent)
            let choice = FormatChoice(id: "direct", ext: known ? ext : "?", width: inner == nil ? Int(number(row, "width") ?? 0) : 0, height: inner == nil ? Int(number(row, "height") ?? 0) : 0, streamIDs: ["direct"])
            let subtitle = row["post"] as? Bool == true ? L("열린 게시물", "Opened post") : (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L("웹페이지 이미지", "Page image")
            var item = MediaItem(source: source, url: value, title: name, subtitle: subtitle, thumbnail: isVideo ? nil : shown, choices: [choice], formatID: "direct")
            item.selected = false
            item.featured = row["post"] as? Bool == true
            if row["kind"] as? String == "video" { item.kindHint = .video }
            item.headers = ["Referer": source]
            item.warning = L("페이지에 로드된 파일입니다. 상품 원본보다 작은 썸네일일 수 있습니다. 로그인이나 사이트 보호가 필요한 파일은 저장되지 않을 수 있습니다.", "A file loaded by the page. It may be a thumbnail smaller than the original, and files behind a login or site protection may not save.")
            return item
        }
    }
}

struct WebImageView: NSViewRepresentable {
    let browser: WebImages
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
