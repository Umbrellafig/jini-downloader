import AppKit
import WebKit

@main struct WebImageTests {
    @MainActor static func main() {
            let rows: [[String: Any]] = [
                ["url": "https://example.com/a.png", "title": "상품", "width": 640, "height": 480],
                ["url": "https://example.com/a.png"], ["url": "file:///private/secret"],
                ["url": "https://name:password@example.com/private.png"]
            ]
            let items = WebImages.items(rows, source: "https://example.com/deal")
            precondition(items.count == 1 && !items[0].selected)
            precondition(items[0].selectedFormat.width == 640 && items[0].selectedFormat.size == nil)
            precondition(items[0].headers["Referer"] == "https://example.com/deal")
            let proxied = WebImages.items([
                ["url": "https://v1.padlet.pics/3/image.webp?t=w_41&url=https%3A%2F%2Fu1.example.com%2Fup%2Ftoon.png%3Fexpiry_token%3Dabc", "width": 41, "height": 745, "post": true],
                ["url": "https://v1.padlet.pics/3/image.webp?t=w_240&url=https%3A%2F%2Fu1.example.com%2Fup%2Ftoon.png%3Fexpiry_token%3Dabc", "width": 240, "height": 4000],
                ["url": "https://cdn.example.com/a.jpg?url=file%3A%2F%2F%2Fetc%2Fpasswd", "width": 300, "height": 200]
            ], source: "https://padlet.com/board/wish/1")
            precondition(proxied.count == 2)
            precondition(proxied[0].url == "https://u1.example.com/up/toon.png?expiry_token=abc" && proxied[0].title == "toon.png" && proxied[0].subtitle == "열린 게시물")
            precondition(proxied[0].thumbnail?.hasPrefix("https://v1.padlet.pics/") == true && proxied[0].selectedFormat.height == 0)
            precondition(proxied[1].url == "https://cdn.example.com/a.jpg?url=file%3A%2F%2F%2Fetc%2Fpasswd")
            print("Web image proxies: original behind url= parameter, deduplication across sizes, preview kept, non-web targets ignored")
            print("Web image metadata: URL safety, deduplication, dimensions, unknown size, selection and headers passed")
            guard CommandLine.arguments.contains("--browser") else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { print("WebKit integration test timed out"); exit(1) }
        Task { @MainActor in
            let browser = WebImages()
            browser.webView.loadHTMLString("""
                <html><head><base href="https://example.com/deals/"></head><body>
                <div style="width:100px;height:100px;background-image:url('../product.jpg')"></div>
                <div style="width:100px;height:100px;background-image:url('../product.jpg')"></div>
                <div style="width:10px;height:10px;background-image:url('../tracking.gif')"></div>
                <img src="data:image/svg+xml,invalid">
                <video src="https://example.com/movie.mp4" preload="none"></video>
                <iframe src="https://player.example.com/embed/1" width="640" height="360"></iframe>
                <iframe src="https://ads.example.com/pixel" width="1" height="1"></iframe>
                <div role="dialog" style="width:300px;height:60px">Cookies</div>
                </body></html>
                """, baseURL: URL(string: "https://example.com/deals/"))
            do {
                for _ in 0..<100 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    if browser.status.hasPrefix("상품 사진") { break }
                }
                let result = try await browser.webView.evaluateJavaScript(WebImages.script) as! [String: Any]
                let images = result["images"] as! [[String: Any]]
                precondition(images.count == 2)
                precondition(images.contains { $0["url"] as? String == "https://example.com/product.jpg" })
                precondition(images.contains { $0["url"] as? String == "https://example.com/movie.mp4" && $0["kind"] as? String == "video" })
                precondition(result["frames"] as? [String] == ["https://player.example.com/embed/1"])
                // An opened post (dialog with media) limits the scan to that post.
                _ = try await browser.webView.evaluateJavaScript("""
                    document.body.insertAdjacentHTML('beforeend', '<div role="dialog" style="width:700px;height:500px"><video src="https://example.com/post.mp4" preload="none"></video><iframe src="https://player.example.com/embed/post" width="640" height="360"></iframe></div>'); true
                    """)
                let scoped = try await browser.webView.evaluateJavaScript(WebImages.script) as! [String: Any]
                let posted = scoped["images"] as! [[String: Any]]
                precondition(posted.map { $0["url"] as? String } == ["https://example.com/post.mp4"] && posted[0]["post"] as? Bool == true)
                precondition(scoped["frames"] as? [String] == ["https://player.example.com/embed/post"])
                print("Web images: rendered DOM, relative URL, background, size filter, deduplication, URL safety, embedded players, opened-post scope, selection and headers passed")
                exit(0)
            } catch { print(error); exit(1) }
        }
        app.run()
    }
}
