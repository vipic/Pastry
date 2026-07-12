import Cocoa

/// 卡片 NSView 弱引用注册表，供键盘 Space 预览锚定 popover。
enum CardPreviewAnchorRegistry {
    private static let lock = NSLock()
    private static let anchors = NSMapTable<NSString, NSView>.weakToWeakObjects()

    static func register(_ id: UUID, view: NSView) {
        lock.lock()
        defer { lock.unlock() }
        anchors.setObject(view, forKey: id.uuidString as NSString)
    }

    static func unregister(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        anchors.removeObject(forKey: id.uuidString as NSString)
    }

    static func view(for id: UUID) -> NSView? {
        lock.lock()
        defer { lock.unlock() }
        return anchors.object(forKey: id.uuidString as NSString)
    }
}
