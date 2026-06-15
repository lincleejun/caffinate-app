import Foundation

/// 切换系统级「专注/勿扰」(macOS Focus) 的后端。具体如何切换（快捷指令、私有
/// 接口……）由实现决定；`FocusLinker` 只依赖这个抽象，方便替换与测试。
public protocol FocusVendor: AnyObject {
    /// 开启系统 Focus。
    func activate()
    /// 关闭系统 Focus；`then` 在系统 Focus **真正关闭后** 回调
    /// （用于「先关 Focus 再发通知」，避免通知被勿扰吞掉）。
    func deactivate(then: (() -> Void)?)
}

/// 番茄钟与系统 Focus 的联动器：把「现在该不该勿扰」翻译成对 vendor 的调用。
///
/// 只追踪自己开过的状态，对外暴露 `engage()` / `disengage()` 两个**幂等**操作：
/// 重复调用不会重复切换系统 Focus。是否启用联动由调用方（AppState）判断，
/// 这里只负责「想开就开、想关就关、且不重复」。
public final class FocusLinker {
    private let vendor: FocusVendor

    /// 我们当前是否已让系统 Focus 处于开启状态。
    public private(set) var isActive = false

    public init(vendor: FocusVendor) {
        self.vendor = vendor
    }

    /// 进入勿扰（专注且未暂停）。已开启则不重复开。
    public func engage() {
        guard !isActive else { return }
        isActive = true
        vendor.activate()
    }

    /// 退出勿扰。未开启时不触碰系统，但 `then` 仍会执行
    /// （这样「先关再发通知」的调用点无论是否真的开过都能正常发通知）。
    public func disengage(then: (() -> Void)? = nil) {
        guard isActive else { then?(); return }
        isActive = false
        vendor.deactivate(then: then)
    }
}
