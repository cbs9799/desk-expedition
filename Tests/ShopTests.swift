import StoreKitTest
import XCTest
@testable import DeskExpedition

final class ShopTests: XCTestCase {
    @MainActor
    func testCosmeticPurchaseUnlocksThemeOverride() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        let shop = CosmeticShop.shared
        await shop.refresh()
        XCTAssertTrue(shop.available, "products load from the StoreKit test configuration")
        XCTAssertEqual(shop.products[.themes]?.type, .nonConsumable)
        XCTAssertFalse(shop.owns(.themes))

        let store = GameStore(progress: Progress(), persist: false)
        store.settings.themeOverride = 2
        XCTAssertEqual(store.effectiveTheme, 0, "override ignored until the pack is owned")

        await shop.buy(.themes)
        XCTAssertTrue(shop.owns(.themes), "message: \(shop.message ?? "nil")")
        XCTAssertEqual(store.effectiveTheme, 2)
        XCTAssertFalse(shop.owns(.supporter))
        session.clearTransactions()
    }
}
