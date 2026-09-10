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
                </body></html>
                """, baseURL: URL(string: "https://example.com/deals/"))
            do {
                for _ in 0..<100 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    if browser.status.hasPrefix("상품 사진") { break }
                }
                let result = try await browser.webView.evaluateJavaScript(WebImages.script) as! [String: Any]
                let images = result["images"] as! [[String: Any]]
                precondition(images.count == 1)
                precondition(images[0]["url"] as? String == "https://example.com/product.jpg")
                print("Web images: rendered DOM, relative URL, background, size filter, deduplication, URL safety, selection and headers passed")
                exit(0)
            } catch { print(error); exit(1) }
        }
        app.run()
    }
}
