import XCTest
@testable import Pastry

final class OverlayInteractionModelTests: XCTestCase {
    func testHasActiveFiltersIncludesUrlAndHandoffFilters() {
        XCTAssertFalse(OverlayInteractionModel.hasActiveFilters(
            searchQuery: "",
            typeFilter: nil,
            appFilter: nil,
            timeFilter: .any,
            urlFilter: false,
            handoffFilter: false
        ))

        XCTAssertTrue(OverlayInteractionModel.hasActiveFilters(
            searchQuery: "",
            typeFilter: nil,
            appFilter: nil,
            timeFilter: .any,
            urlFilter: true,
            handoffFilter: false
        ))

        XCTAssertTrue(OverlayInteractionModel.hasActiveFilters(
            searchQuery: "",
            typeFilter: nil,
            appFilter: nil,
            timeFilter: .any,
            urlFilter: false,
            handoffFilter: true
        ))
    }

    func testSelectedItemsPreservesVisibleOrder() {
        let first = makeItem(id: "11111111-1111-1111-1111-111111111111", content: "first")
        let second = makeItem(id: "22222222-2222-2222-2222-222222222222", content: "second")
        let third = makeItem(id: "33333333-3333-3333-3333-333333333333", content: "third")

        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: [first, second, third],
            selectedIds: [third.id, first.id]
        )

        XCTAssertEqual(selected.map(\.id), [first.id, third.id])
    }

    func testCommandBadgeIndexOnlyShowsFirstNineWhenCommandIsHeld() {
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: false, itemIndex: 0))
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 0), 1)
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 8), 9)
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 9))
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: -1))
    }

    private func makeItem(id: String, content: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: id)!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            content: content,
            sourceFormat: .text,
            appName: "Tests"
        )
    }
}
