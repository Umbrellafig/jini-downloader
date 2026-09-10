import SwiftUI
import Sparkle

/// Sparkle owns download validation, atomic replacement, recovery, and relaunch.
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var canCheck = false
    @Published var sessionActive = false
    @Published var automaticallyChecks = false
    @Published var status = "업데이트를 확인할 수 있습니다"
    private var controller: SPUStandardUpdaterController!
    private let isBusy: () -> Bool
    private var pendingInstall: (() -> Void)?
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 버전" }

    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.sessionInProgress).assign(to: &$sessionActive)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.startUpdater()
    }
    func check() {
        guard !isBusy(), canCheck else { return }
        status = "최신 버전 확인 중…"
        controller.checkForUpdates(nil)
    }
    func setAutomatic(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBusy() { throw NSError(domain: "JiniUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "진행 중인 작업을 마친 뒤 업데이트를 확인해 주세요."]) }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "새 버전 \(item.displayVersionString) 사용 가능"
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { status = "설치 가능한 새 버전이 없습니다" }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let code = (error as NSError).code
        // Sparkle reports “no update” and a user's cancellation through this callback too.
        if code == 1001 { status = "설치 가능한 새 버전이 없습니다" }
        else if code == 4007 || code == 4008 { status = "업데이트 설치를 미뤘습니다" }
        else { status = "업데이트 확인 실패 · 다시 시도해 주세요" }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        pendingInstall = installHandler
        status = "진행 중인 작업이 끝나면 업데이트를 설치합니다"
        return true
    }
    func workFinished() {
        guard !isBusy(), let install = pendingInstall else { return }
        pendingInstall = nil
        install()
    }
}
