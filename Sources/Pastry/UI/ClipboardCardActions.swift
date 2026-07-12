import Cocoa
import Quartz

extension ClipboardCardView {
    /// 用默认应用打开（多文件/多链接时逐个打开所有存在的 URL）
    private func openItem() {
        if isMultiFile {
            let urls = existingFileURLs
            guard !urls.isEmpty else { return }
            OverlayPanelManager.shared.hide()
            for url in urls { NSWorkspace.shared.open(url) }
            DeveloperDiagnostics.record(DiagnosticsEvent.open)
            return
        }
        if isMultiURL {
            let urls = detectedLinks
            guard !urls.isEmpty else { return }
            OverlayPanelManager.shared.hide()
            for url in urls { NSWorkspace.shared.open(url) }
            DeveloperDiagnostics.record(DiagnosticsEvent.open)
            return
        }
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.open(url)
        DeveloperDiagnostics.record(DiagnosticsEvent.open)
    }

    /// 用指定应用打开
    private func openWithApp(_ appURL: URL) {
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// 手动选择应用打开（"其他…" fallback）
    private func openWithOther() {
        guard let url = openableURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n["panel.open_prompt"]
        panel.message = L10n["panel.open_message"]
        OverlayPanelManager.shared.hide()
        panel.begin { response in
            guard response == .OK, let appURL = panel.url else { return }
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 在访达中显示文件所在位置
    private func showInFinder() {
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        DeveloperDiagnostics.record(DiagnosticsEvent.showInFinder)
    }

    /// 复制到系统剪贴板（不隐藏面板、不触发粘贴）。
    /// 多选且右键落在选中集合内 → 复制全部选中；否则只复制本卡。
    private func copyItem() {
        let targets: [ClipboardItem]
        if selectedIds.count > 1, selectedIds.contains(item.id) {
            targets = StoreManager.shared.items.filter { selectedIds.contains($0.id) }
        } else {
            targets = [item]
        }

        if targets.count == 1 {
            Task {
                _ = await PasteboardWriter.write(targets[0], options: .storeSingle)
            }
        } else {
            let lines = targets.map { target in
                if target.sourceFormat == .fileURL || target.sourceFormat == .image {
                    return target.content
                }
                return DatabaseManager.shared.loadFullContent(id: target.id) ?? target.content
            }
            PasteboardWriter.writePlainText(lines.joined(separator: "\n"))
        }
        DeveloperDiagnostics.record(DiagnosticsEvent.copy)
    }

    /// 构建系统的"打开方式"子菜单
    private func buildOpenWithSubmenu(for handler: _MenuHandler) -> NSMenu? {
        guard let url = openableURL else { return nil }
        let submenu = NSMenu()
        var addedApp = false

        if #available(macOS 12.0, *) {
            let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
            for appURL in appURLs {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                let item = NSMenuItem(title: name, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
                item.target = handler
                item.representedObject = appURL
                item.image = NSWorkspace.shared.icon(forFile: appURL.path)
                item.image?.size = NSSize(width: 16, height: 16)
                submenu.addItem(item)
                addedApp = true
            }
        }

        if addedApp { submenu.addItem(.separator()) }
        let otherItem = NSMenuItem(title: L10n["context.open_with_other"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        otherItem.target = handler
        otherItem.representedObject = "openWithOther" as NSString
        submenu.addItem(otherItem)
        return submenu
    }

    /// 右键菜单（使用系统 NSMenu.popUpContextMenu）
    func showContextMenu(with event: NSEvent, for view: NSView) {
        let menu = NSMenu()
        menu.minimumWidth = UIConstants.ContextMenu.cardMinimumWidth
        let handler = _MenuHandler { title, object in
            // representedObject 传递的动作标识优先
            if let appURL = object as? URL {
                self.openWithApp(appURL)
                return
            }
            if let tag = object as? NSString {
                switch tag {
                case "pin":
                    onPin(item, selectedIds)
                case "edit_note":
                    beginFavoriteNoteEditing()
                case "open":       openItem()
                case "show_in_finder": showInFinder()
                case "copy":       copyItem()
                case "preview":    previewItem(from: view)
                case "share":      shareItem(from: view)
                case "delete":     onDelete(item)
                default: break
                }
                return
            }
            // fallback: title-based (用于"打开方式"子菜单项等)
            if title == L10n["context.open_with_other"] {
                self.openWithOther()
            }
        }

        let pinTitle = item.isPinned ? L10n["context.unpin"] : L10n["context.pin"]
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        pinItem.target = handler
        pinItem.representedObject = "pin" as NSString
        pinItem.image = NSImage(systemSymbolName: item.isPinned ? "pin.slash" : "pin", accessibilityDescription: pinTitle)
        menu.addItem(pinItem)

        let noteLabel = L10n["context.edit_favorite_note"]
        let noteItem = NSMenuItem(title: noteLabel, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        noteItem.target = handler
        noteItem.representedObject = "edit_note" as NSString
        noteItem.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: noteLabel)
        menu.addItem(noteItem)

        // Copy
        let copyMenuItem = NSMenuItem(title: L10n["context.copy"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        copyMenuItem.target = handler
        copyMenuItem.representedObject = "copy" as NSString
        copyMenuItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n["context.copy"])
        menu.addItem(copyMenuItem)

        let isFileBased = item.sourceFormat == .fileURL || item.sourceFormat == .image
        let hasAnyFile = isFileBased && !existingFileURLs.isEmpty

        // Open / Open With — 文件类始终显示（缺失时灰显）
        let isTextLike = item.sourceFormat == .text || item.sourceFormat == .rtf || item.sourceFormat == .html
        let showOpenSection = isFileBased || item.tags.isURL
            || (isTextLike && openableURL != nil)

        if showOpenSection {
            menu.addItem(.separator())
            let openEnabled = hasAnyFile || (!isFileBased && openableURL != nil)
            let oItem = NSMenuItem(title: L10n["context.open"], action: openEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            oItem.target = openEnabled ? handler : nil
            oItem.representedObject = openEnabled ? "open" as NSString : nil
            oItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: L10n["context.open"])
            oItem.isEnabled = openEnabled
            menu.addItem(oItem)

            let owEnabled = !isMultiFile && (hasAnyFile || (!isFileBased && openableURL != nil))
            let owItem = NSMenuItem(title: L10n["context.open_with"], action: nil, keyEquivalent: "")
            owItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: L10n["context.open_with"])
            owItem.isEnabled = owEnabled
            if owEnabled, let submenu = buildOpenWithSubmenu(for: handler) {
                menu.setSubmenu(submenu, for: owItem)
            }
            menu.addItem(owItem)

            // 在访达中显示（仅文件类有效）
            if isFileBased && hasAnyFile {
                let finderItem = NSMenuItem(title: L10n["context.show_in_finder"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
                finderItem.target = handler
                finderItem.representedObject = "show_in_finder" as NSString
                finderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: L10n["context.show_in_finder"])
                menu.addItem(finderItem)
            }
        }

        // Preview / Share — 文件/图片：按存在性；文本/RTF/HTML/链接：始终可用
        let previewEnabled: Bool = {
            if isMultiFile { return false }
            if isFileBased { return hasAnyFile }
            if case .missing = displayMode { return false }
            return true  // 文本/RTF/HTML/链接均可预览
        }()
        let shareEnabled: Bool = {
            if isFileBased { return hasAnyFile }
            if case .missing = displayMode { return false }
            return true  // 文本/RTF/HTML/链接均可分享
        }()

        menu.addItem(.separator())

            let pItem = NSMenuItem(title: L10n["context.preview"], action: previewEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            pItem.target = previewEnabled ? handler : nil
            pItem.representedObject = previewEnabled ? "preview" as NSString : nil
            pItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: L10n["context.preview"])
            pItem.isEnabled = previewEnabled
            menu.addItem(pItem)

            let sItem = NSMenuItem(title: L10n["context.share"], action: shareEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            sItem.target = shareEnabled ? handler : nil
            sItem.representedObject = shareEnabled ? "share" as NSString : nil
            sItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: L10n["context.share"])
            sItem.isEnabled = shareEnabled
            menu.addItem(sItem)

        menu.addItem(.separator())
        let deleteMenuItem = NSMenuItem(title: L10n["context.delete"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        deleteMenuItem.target = handler
        deleteMenuItem.representedObject = "delete" as NSString
        deleteMenuItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: L10n["context.delete"])
        menu.addItem(deleteMenuItem)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Quick Look 预览（popover 浮动预览，三角指向卡片，面板保持可见）
    private func previewItem(from sourceView: NSView) {
        let metadata: QLPreviewHelper.PreviewMetadata

        if let url = openableURL {
            switch item.sourceFormat {
            case .fileURL:
                let fileName = (item.content as NSString).lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.file"] : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .image:
                let fileName = url.lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                // 旧缓存 .orig 无可识别扩展名，Quick Look 需要转成临时 PNG。
                let previewURL: URL = {
                    guard url.pathExtension == "orig" else { return url }
                    guard let origPath = ImageCacheManager.shared.originalPath(forThumbnail: item.content),
                          let origData = try? Data(contentsOf: URL(fileURLWithPath: origPath)),
                          let origImage = NSImage(data: origData),
                          let tiff = origImage.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:])
                    else { return url }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).png")
                    try? png.write(to: tmp)
                    return tmp
                }()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: previewURL, displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.image"] : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .text, .rtf, .html:
                let host = url.host ?? ""
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: host,
                    fileType: L10n["filetype.link"],
                    infoText: url.absoluteString, isLocalFile: false
                )
            }
        } else if isTextType {
            // 纯文本 / RTF / HTML：写临时文件供 QLPreviewView 预览
            let ext: String
            let typeLabel: String
            switch item.sourceFormat {
            case .rtf:  ext = "rtf";  typeLabel = "RTF"
            case .html: ext = "html"; typeLabel = "HTML"
            default:    ext = "txt";  typeLabel = L10n["filetype.text"]
            }
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpFile = tmpDir.appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).\(ext)")
            let fullContent = DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content

            // RTF: 写原始二进制数据，不是纯文本
            if item.sourceFormat == .rtf, let rawData = item.rawFormatData {
                try? rawData.write(to: tmpFile)
            } else {
                try? fullContent.write(to: tmpFile, atomically: true, encoding: .utf8)
            }

            let charCount = fullContent.count
            let wordCount = fullContent.split { $0.isWhitespace || $0.isNewline }.count
            let lineCount = fullContent.split(separator: "\n", omittingEmptySubsequences: false).count

            metadata = QLPreviewHelper.PreviewMetadata(
                url: tmpFile, displayName: String(format: L10n["preview.title"], typeLabel),
                fileType: typeLabel,
                infoText: String(format: L10n["preview.info"], charCount, wordCount, lineCount),
                isLocalFile: true
            )
        } else {
            return
        }

        QLPreviewHelper.shared.showPreview(metadata: metadata, from: sourceView)
        DeveloperDiagnostics.record(DiagnosticsEvent.preview)
    }

    /// 系统分享面板
    private func shareItem(from view: NSView) {
        let items: [Any]
        if isMultiFile {
            let urls = existingFileURLs
            guard !urls.isEmpty else { return }
            items = urls
        } else if let url = openableURL {
            items = [url]
        } else if isTextType {
            items = [DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content]
        } else {
            return
        }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        DeveloperDiagnostics.record(DiagnosticsEvent.share)
    }
}
