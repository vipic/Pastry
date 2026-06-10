import Cocoa
import Quartz

// MARK: - Quick Look 预览辅助（NSPopover + QLPreviewView，带自定义控件）
final class QLPreviewHelper: NSObject {
    nonisolated(unsafe) static let shared = QLPreviewHelper()

    struct PreviewMetadata {
        let url: URL
        let displayName: String
        let fileType: String
        let infoText: String
        let isLocalFile: Bool
    }

    private var popover: NSPopover?
    private var previewView: QLPreviewView?
    private var closeObserver: NSObjectProtocol?
    private var currentMetadata: PreviewMetadata?

    /// 是否有预览 popover 正在显示
    var isShowing: Bool { popover != nil }

    /// 以 popover 形式预览文件（三角指向源卡片，不影响面板 key 状态）
    func showPreview(metadata: PreviewMetadata, from sourceView: NSView) {
        dismiss()

        self.currentMetadata = metadata

        let preview = QLPreviewView()
        preview.autostarts = true
        preview.previewItem = metadata.url as NSURL
        self.previewView = preview

        let container = PreviewContainerView(
            previewView: preview,
            metadata: metadata,
            onClose: { [weak self] in self?.dismiss() },
            onShare: { [weak self] in self?.shareFromContainer() },
            onReveal: { [weak self] in self?.revealInFinder() }
        )

        let vc = NSViewController()
        vc.view = container

        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.animates = true

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: p, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }

        self.popover = p
        p.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    func dismiss() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        popover?.close()
        popover = nil
        previewView = nil
        currentMetadata = nil
    }

    private func shareFromContainer() {
        guard let metadata = currentMetadata, let popover else { return }
        let picker = NSSharingServicePicker(items: [metadata.url as NSURL])
        if let contentView = popover.contentViewController?.view {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    private func revealInFinder() {
        guard let metadata = currentMetadata, metadata.isLocalFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([metadata.url])
    }
}

// MARK: - 预览容器视图（QLPreviewView + 浮层控件）
private final class PreviewContainerView: NSView {

    private let onClose: () -> Void
    private let onShare: () -> Void
    private let onReveal: () -> Void
    private let metadata: QLPreviewHelper.PreviewMetadata
    private weak var shareButton: NSButton?

    init(previewView: QLPreviewView, metadata: QLPreviewHelper.PreviewMetadata,
         onClose: @escaping () -> Void, onShare: @escaping () -> Void,
         onReveal: @escaping () -> Void) {
        self.metadata = metadata
        self.onClose = onClose
        self.onShare = onShare
        self.onReveal = onReveal

        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 420))

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let topBarHeight: CGFloat = 32
        let bottomBarHeight: CGFloat = 28
        let previewHeight = bounds.height - topBarHeight - bottomBarHeight
        previewView.frame = NSRect(x: 0, y: bottomBarHeight, width: bounds.width, height: previewHeight)
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        previewView.autoresizingMask = [.width, .height]
        addSubview(previewView)

        let topBar = NSVisualEffectView(frame: NSRect(x: 0, y: bounds.height - 32, width: bounds.width, height: 32))
        topBar.material = .hudWindow
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.autoresizingMask = [.width, .minYMargin]
        topBar.wantsLayer = true
        topBar.layer?.cornerRadius = 0
        addSubview(topBar)

        let closeBtn = NSButton(frame: NSRect(x: 6, y: 6, width: 20, height: 20))
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.title = ""
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n["a11y.close"])
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        topBar.addSubview(closeBtn)

        let typeLabel = NSTextField(labelWithString: metadata.fileType)
        typeLabel.frame = NSRect(x: 30, y: 8, width: 120, height: 16)
        typeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = .secondaryLabelColor
        topBar.addSubview(typeLabel)

        let shareBtn = NSButton(frame: NSRect(x: bounds.width - 32, y: 6, width: 24, height: 20))
        shareBtn.bezelStyle = .regularSquare
        shareBtn.isBordered = false
        shareBtn.title = ""
        shareBtn.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: L10n["a11y.share"])
        shareBtn.imagePosition = .imageOnly
        shareBtn.contentTintColor = .secondaryLabelColor
        shareBtn.target = self
        shareBtn.action = #selector(shareTapped)
        shareBtn.autoresizingMask = .minXMargin
        topBar.addSubview(shareBtn)
        self.shareButton = shareBtn

        let bottomBar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 28))
        bottomBar.material = .hudWindow
        bottomBar.blendingMode = .withinWindow
        bottomBar.state = .active
        bottomBar.autoresizingMask = [.width, .maxYMargin]
        addSubview(bottomBar)

        let infoLabel = NSTextField(labelWithString: metadata.infoText)
        infoLabel.frame = NSRect(x: 10, y: 5, width: bounds.width - 120, height: 18)
        infoLabel.font = .systemFont(ofSize: 10.5)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.autoresizingMask = .width
        bottomBar.addSubview(infoLabel)

        if metadata.isLocalFile {
            let revealBtn = NSButton(frame: NSRect(x: bounds.width - 130, y: 2, width: 120, height: 24))
            revealBtn.bezelStyle = .regularSquare
            revealBtn.isBordered = false
            revealBtn.font = .systemFont(ofSize: 11)

            let icon = NSTextAttachment()
            icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let iconStr = NSAttributedString(attachment: icon)
            let label = NSAttributedString(
                string: " \(L10n["preview.reveal"])",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
            )
            let title = NSMutableAttributedString()
            title.append(iconStr)
            title.append(label)
            revealBtn.attributedTitle = title
            revealBtn.target = self
            revealBtn.action = #selector(revealTapped)
            revealBtn.autoresizingMask = .minXMargin
            bottomBar.addSubview(revealBtn)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func closeTapped() { onClose() }
    @objc private func shareTapped() { onShare() }
    @objc private func revealTapped() { onReveal() }
}
