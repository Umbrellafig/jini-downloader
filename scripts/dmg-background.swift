import AppKit
let canvas = NSImage(size: NSSize(width: 660, height: 420))
canvas.lockFocus()
NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 660, height: 420)).fill()
func label(_ text: String, _ size: CGFloat, _ y: CGFloat, _ color: NSColor) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 20, y: y, width: 620, height: 50), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph])
}
label("지니 다운로더 설치", 28, 332, .white)
label("앱을 오른쪽 Applications 폴더로 옮겨 주세요", 15, 290, .lightGray)
label("→", 52, 188, NSColor.systemMint)
label("옮긴 뒤 응용 프로그램 폴더에서 실행하세요", 15, 62, .white)
label("다음부터는 앱 안에서 업데이트할 수 있어요", 12, 32, .lightGray)
canvas.unlockFocus()
let bitmap = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
