import SwiftUI
import XCTest
@testable import Pastry

@MainActor
final class ClipboardCardSnapshotTests: XCTestCase {
    func testTextCardSnapshot() throws {
        let item = ClipboardItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: "Hello, Pastry! 这是一条用于快照测试的剪贴板记录。",
            sourceFormat: .text,
            appName: "iTerm2"
        )

        try SnapshotTestSupport.assertSnapshot(
            named: "clipboard-card-text",
            size: CGSize(width: UIConstants.Card.size, height: UIConstants.Card.size),
            view: SnapshotCardHost(item: item)
        )
    }

    func testSelectedTextCardWithCommandBadgeSnapshot() throws {
        let item = ClipboardItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: "第二条文本 - 测试选中状态和 Command 数字角标。",
            sourceFormat: .text,
            appName: "Finder",
            isPinned: true
        )

        try SnapshotTestSupport.assertSnapshot(
            named: "clipboard-card-text-selected-command",
            size: CGSize(width: UIConstants.Card.size, height: UIConstants.Card.size),
            view: SnapshotCardHost(item: item, isSelected: true, cmdBadgeIndex: 2)
        )
    }

    func testLinkCardSnapshot() throws {
        let item = ClipboardItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: "https://github.com/nekutai/pastry",
            sourceFormat: .text,
            tags: ContentTags(isURL: true),
            appName: "Safari"
        )

        try SnapshotTestSupport.assertSnapshot(
            named: "clipboard-card-link",
            size: CGSize(width: UIConstants.Card.size, height: UIConstants.Card.size),
            view: SnapshotCardHost(item: item)
        )
    }

    func testMultiFileCardSnapshot() throws {
        let item = ClipboardItem(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: [
                "/Users/mason/.zshrc",
                "/Users/mason/.gitconfig",
                "/Users/mason/.profile",
            ].joined(separator: "\n"),
            sourceFormat: .fileURL,
            tags: ContentTags(isMultiFile: true),
            appName: "iTerm2"
        )

        try SnapshotTestSupport.assertSnapshot(
            named: "clipboard-card-multi-file",
            size: CGSize(width: UIConstants.Card.size, height: UIConstants.Card.size),
            view: SnapshotCardHost(item: item)
        )
    }

    func testHTMLCardSnapshot() throws {
        let item = ClipboardItem(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: "Pastry 发布说明\nv1.2 - 支持多选粘贴\nv1.1 - SQLCipher 全库加密",
            sourceFormat: .html,
            appName: "Brave Browser",
            segments: [
                .text("Pastry 发布说明"),
                .text("v1.2 - 支持多选粘贴"),
                .text("v1.1 - SQLCipher 全库加密"),
                .text("macOS 26+ 剪贴板管理器"),
            ]
        )

        try SnapshotTestSupport.assertSnapshot(
            named: "clipboard-card-html",
            size: CGSize(width: UIConstants.Card.size, height: UIConstants.Card.size),
            view: SnapshotCardHost(item: item)
        )
    }
}

private struct SnapshotCardHost: View {
    let item: ClipboardItem
    var isSelected = false
    var cmdBadgeIndex: Int?
    @State private var selectedIds: Set<UUID> = []

    var body: some View {
        ClipboardCardView(
            item: item,
            isSelected: isSelected,
            cmdBadgeIndex: cmdBadgeIndex,
            selectedIds: $selectedIds,
            onTap: { _ in },
            onPin: { _, _ in },
            onDelete: { _ in }
        )
    }
}
