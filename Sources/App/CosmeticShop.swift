import Foundation
import Observation
import StoreKit

/// Cosmetic-only in-app purchases (StoreKit 2). Nothing here affects combat or progression —
/// that promise is the product's selling point (see docs/APPSTORE.md).
/// In the Developer ID build products don't load (StoreKit needs an App Store build or a .storekit test
/// configuration), so the shop shows an explanation instead of buttons.
@MainActor
@Observable
final class CosmeticShop {
    static let shared = CosmeticShop()

    enum ID: String, CaseIterable {
        case themes = "club.lemongrove.deskexpedition.themes"
        case supporter = "club.lemongrove.deskexpedition.supporter"

        var title: String { L10n.t(self == .themes ? "책상 테마 팩" : "후원 팩") }
        var blurb: String {
            L10n.t(self == .themes ? "밤샘·카페·새벽 책상 테마를 언제든 골라 쓰기" : "영웅 이름이 금빛으로 · 본부에 후원 배지 · 개발 응원")
        }
    }

    private(set) var products: [ID: Product] = [:]
    private(set) var owned: Set<ID> = []
    private(set) var loading = false
    private(set) var message: String?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var purchasedThisSession: Set<ID> = []

    private init() {
        // Cache of entitlements so cosmetics show instantly at launch (re-verified by refresh()).
        owned = Set((UserDefaults.standard.stringArray(forKey: "shop.owned") ?? []).compactMap(ID.init))
    }

    var available: Bool { !products.isEmpty }
    func owns(_ id: ID) -> Bool { owned.contains(id) }

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        if let list = try? await Product.products(for: ID.allCases.map(\.rawValue)) {
            products = Dictionary(uniqueKeysWithValues: list.compactMap { p in ID(rawValue: p.id).map { ($0, p) } })
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var now: Set<ID> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, let id = ID(rawValue: t.productID) { now.insert(id) }
        }
        now.formUnion(purchasedThisSession)
        // Keep cached ownership when StoreKit is unavailable (e.g. offline) rather than revoking it.
        if available || !now.isEmpty { owned = now }
        UserDefaults.standard.set(owned.map(\.rawValue), forKey: "shop.owned")
    }

    func buy(_ id: ID) async {
        guard let product = products[id] else { return }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    purchasedThisSession.insert(id)   // currentEntitlements can lag right after a purchase
                    await refreshEntitlements()
                    message = L10n.t("고마워요! 꾸미기가 열렸어요")
                }
            case .pending: message = L10n.t("승인 대기 중이에요")
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
        message = L10n.t(owned.isEmpty ? "복원할 구매가 없어요" : "구매를 복원했어요")
    }
}
