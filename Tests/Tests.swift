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
        var live = d; live["is_live"] = true
        do { _ = try Metadata.video(JSONSerialization.data(withJSONObject:live),source:"https://example.com"); fatalError("Live media must be rejected") } catch {}
        print("PASS: preview selection, exact/unknown size, Korean text, stream progress, gallery filtering, URL validation, live handling")
    }
}
