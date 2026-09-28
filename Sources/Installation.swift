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
        alert.messageText = L("응용 프로그램 폴더에 설치해 주세요", "Install in the Applications folder")
        alert.informativeText = L("지금은 설치 파일 또는 임시 위치에서 실행 중입니다. 응용 프로그램 폴더에 설치하면 앱 안에서 업데이트할 수 있어요.\n\nDMG 창에서는 앱 아이콘을 Applications 폴더로 드래그해도 됩니다.", "The app is running from the installer or a temporary location. Install it in Applications to get updates inside the app.\n\nIn the DMG window you can also drag the app icon onto the Applications folder.")
        alert.addButton(withTitle: L("응용 프로그램으로 설치", "Install in Applications"))
        alert.addButton(withTitle: L("나중에", "Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let destination = URL(fileURLWithPath: "/Applications/JiniDownloader.app")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                let existing = NSAlert()
                existing.messageText = L("기존 앱이 설치되어 있어요", "The app is already installed")
                existing.informativeText = L("응용 프로그램 폴더의 지니 다운로더를 실행해 주세요. 새 버전으로 직접 교체하려면 앱을 종료하고 Finder에서 옮겨 주세요.", "Open Jini Downloader from Applications. To replace it with this version yourself, quit the app and move it in Finder.")
                existing.addButton(withTitle: L("설치된 앱 열기", "Open Installed App"))
                existing.addButton(withTitle: L("취소", "Cancel"))
                if existing.runModal() == .alertFirstButtonReturn { launch(destination) }
                return
            }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destination)
            launch(destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = L("Finder에서 앱을 옮겨 주세요", "Move the app in Finder")
            failure.informativeText = L("자동 설치를 완료하지 못했습니다. DMG의 앱 아이콘을 Applications 폴더로 드래그해 주세요.\n\n", "The automatic install didn't finish. Drag the app icon in the DMG onto the Applications folder.\n\n") + error.localizedDescription
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
                    alert.messageText = L("설치는 완료됐습니다", "Installed")
                    alert.informativeText = L("이 앱을 종료하고 응용 프로그램 폴더의 지니 다운로더를 실행해 주세요.", "Quit this app and open Jini Downloader from Applications.")
                    alert.runModal()
                }
            }
        }
    }
}
