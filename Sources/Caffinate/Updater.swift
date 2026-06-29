import Combine
import Sparkle
import SwiftUI

/// Sparkle 自动更新封装。
///
/// 更新包用自生成的 EdDSA 密钥签名（无需 Apple Developer 证书），公钥写在
/// Info.plist 的 `SUPublicEDKey`、appcast 地址写在 `SUFeedURL`——两者都由
/// `scripts/build-app.sh` 在打包时注入。后台自动检查由 Info.plist 的
/// `SUEnableAutomaticChecks` 控制。
///
/// 开发期 `swift run` 不在 .app bundle 里、Info.plist 没有 `SUFeedURL`，
/// 此时不启动 updater，`canCheckForUpdates` 保持 false，菜单项自动禁用，
/// 避免 Sparkle 因缺配置报错。
@MainActor
final class UpdaterModel: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    init() {
        // 仅当打进 .app 且配置了 feed 时才真正启动 updater。
        let configured = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(
            startingUpdater: configured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// 用户手动「检查更新」：弹出 Sparkle 标准 UI（有更新则下载并提示重启）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
