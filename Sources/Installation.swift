import AppKit

@MainActor enum Installation {
    static var installed: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let roots = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        return !path.contains("/AppTranslocation/") && roots.contains { path.hasPrefix($0) }
    }
    private static var shown = false
    static func checkOnce() {
        guard !shown, !installed else { return }
        shown = true
        show()
    }
    static func show() {
        let alert = NSAlert()
        alert.messageText = "응용 프로그램 폴더에 설치해 주세요"
        alert.informativeText = "지금은 설치 파일 또는 임시 위치에서 실행 중입니다. 응용 프로그램 폴더에 설치하면 앱 안에서 업데이트할 수 있어요.\n\nDMG 창에서는 앱 아이콘을 Applications 폴더로 드래그해도 됩니다."
        alert.addButton(withTitle: "응용 프로그램으로 설치")
        alert.addButton(withTitle: "나중에")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let destination = URL(fileURLWithPath: "/Applications/JiniDownloader.app")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                let existing = NSAlert()
                existing.messageText = "기존 앱이 설치되어 있어요"
                existing.informativeText = "응용 프로그램 폴더의 지니 다운로더를 실행해 주세요. 새 버전으로 직접 교체하려면 앱을 종료하고 Finder에서 옮겨 주세요."
                existing.addButton(withTitle: "설치된 앱 열기")
                existing.addButton(withTitle: "취소")
                if existing.runModal() == .alertFirstButtonReturn { launch(destination) }
                return
            }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destination)
            launch(destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Finder에서 앱을 옮겨 주세요"
            failure.informativeText = "자동 설치를 완료하지 못했습니다. DMG의 앱 아이콘을 Applications 폴더로 드래그해 주세요.\n\n" + error.localizedDescription
            failure.runModal()
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }
    private static func launch(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            Task { @MainActor in
                if error == nil { NSApplication.shared.terminate(nil) }
                else {
                    let alert = NSAlert()
                    alert.messageText = "설치는 완료됐습니다"
                    alert.informativeText = "이 앱을 종료하고 응용 프로그램 폴더의 지니 다운로더를 실행해 주세요."
                    alert.runModal()
                }
            }
        }
    }
}
