import SwiftUI

/// "일괄 판매" menu: one click sells everything at or below a rarity (upgrades are always kept).
/// Rare/legendary sales ask once for confirmation.
struct BulkSellMenu<Label: View>: View {
    @Environment(GameStore.self) private var store
    @Environment(\.staticRendering) private var staticRendering
    /// In the floating strip panel alerts can't take focus, so rare/legendary sales use "click again to confirm".
    var inPanel = false
    @ViewBuilder let label: () -> Label
    @State private var confirm: Rarity?
    @State private var armed: (Rarity, Date)?

    private let tiers: [(Rarity, String)] = [(.common, "일반만"), (.uncommon, "고급 이하"), (.rare, "희귀 이하"), (.legendary, "전부 (전설 포함)")]

    var body: some View {
        if staticRendering {
            label()
        } else {
            Menu {
                Section(L10n.t("일괄 판매 — 업그레이드 장비는 남겨요")) {
                    ForEach(tiers, id: \.0) { rarity, title in
                        let preview = store.sellPreview(upTo: rarity)
                        Button("\(L10n.t(title)) · \(preview.count)개 · 🪙 \(preview.gold.formatted())") {
                            if rarity < .rare {
                                store.bulkSell(upTo: rarity)
                            } else if inPanel {
                                if let a = armed, a.0 == rarity, Date().timeIntervalSince(a.1) < 6 {
                                    armed = nil
                                    store.bulkSell(upTo: rarity)
                                } else {
                                    armed = (rarity, Date())
                                    store.showBanner(L10n.t("희귀·전설도 팔려면 같은 항목을 한 번 더 누르세요") + " (\(preview.count)개 · 🪙 \(preview.gold.formatted()))", seconds: 6)
                                }
                            } else {
                                confirm = rarity
                            }
                        }
                        .disabled(preview.count == 0)
                    }
                }
            } label: { label() }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.white)
            .fixedSize()
            .alert(L10n.t("희귀·전설 장비도 팔까요?"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
                Button(L10n.t("판매"), role: .destructive) { if let r = confirm { store.bulkSell(upTo: r) }; confirm = nil }
                Button(L10n.t("취소"), role: .cancel) { confirm = nil }
            } message: {
                let p = store.sellPreview(upTo: confirm ?? .rare)
                Text("\(p.count)개 · 🪙 \(p.gold.formatted())")
            }
        }
    }
}
