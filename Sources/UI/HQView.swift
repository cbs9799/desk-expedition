import SwiftUI

/// 원정 본부: heroes, equipment, bag, region selection.
struct HQView: View {
    @Environment(GameStore.self) private var store
    @State private var selectedID: UUID?

    var body: some View {
        let p = store.progress
        VStack(alignment: .leading, spacing: 14) {
            header(p)
            if let report = store.lastOffline {
                offlineBanner(report)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(p.heroes.enumerated()), id: \.offset) { i, hero in
                    HeroCard(index: i, hero: hero, hp: store.battle.heroes[safe: i]?.hp ?? hero.maxHP)
                }
            }
            bag(p)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .frame(width: 920, height: 600, alignment: .top)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
    }

    private func header(_ p: Progress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("원정 본부").font(.system(size: 22, weight: .heavy, design: .rounded))
                Text(p.isBossWave ? "\(p.region.name) · 보스전" : "\(p.region.name) · 웨이브 \(p.wave)/\(Region.wavesPerRegion)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                Spacer()
                Label("\(p.totalKills.formatted())", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.dim)
                Text("🪙 \(p.gold.formatted())")
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
            }
            SegmentRow(options: Array(Region.all.indices), selected: p.regionIndex,
                       label: { i in i <= p.unlockedRegion ? "\(i + 1). \(Region.all[i].name)" : "🔒 \(i + 1)" },
                       enabled: { $0 <= p.unlockedRegion },
                       onSelect: { store.selectRegion($0) })
        }
    }

    private func offlineBanner(_ r: OfflineReport) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.gold)
            Text("자리를 비운 \(r.durationText) 동안: \(r.kills.formatted())마리 처치 · 골드 +\(r.gold.formatted()) · 전리품 \(r.items)개\(r.bosses > 0 ? " · 보스 \(r.bosses)회" : "")\(r.autoSold > 0 ? " · 자동 판매 \(r.autoSold)개" : "")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            Button("확인") { store.lastOffline = nil }.buttonStyle(GameButtonStyle(compact: true))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x3A3420)))
    }

    private func bag(_ p: Progress) -> some View {
        let selected = p.bag.first { $0.id == selectedID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("가방").font(.system(size: 15, weight: .heavy, design: .rounded))
                Text("\(p.bag.count)/\(Progress.bagCapacity)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(p.bagIsFull ? Color(hex: 0xFF7A7A) : Theme.dim)
                Spacer()
                Button("최적 장착") { store.autoEquip() }.buttonStyle(GameButtonStyle(color: Color(hex: 0x3BA55C), compact: true))
                Button("일반 일괄 판매") { store.sellAll(upTo: .common) }.buttonStyle(GameButtonStyle(color: Color(hex: 0x8A6D3B), compact: true))
                Button("고급 이하 판매") { store.sellAll(upTo: .uncommon) }.buttonStyle(GameButtonStyle(color: Color(hex: 0x8A6D3B), compact: true))
            }
            HStack(alignment: .top, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(46), spacing: 6), count: 8), spacing: 6) {
                    ForEach(0..<Progress.bagCapacity, id: \.self) { i in
                        let item = p.bag[safe: i]
                        ItemCell(item: item, selected: item != nil && item?.id == selectedID,
                                 upgrade: item.map { store.isUpgrade($0) } ?? false)
                            .onTapGesture { selectedID = item?.id }
                    }
                }
                .frame(width: 8 * 46 + 7 * 6)
                ItemDetail(item: selected, onDone: { selectedID = nil })
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}

private struct HeroCard: View {
    @Environment(GameStore.self) private var store
    @Environment(\.staticRendering) private var staticRendering
    let index: Int
    let hero: HeroProgress
    let hp: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                HeroPortrait(heroClass: hero.heroClass, accessory: hero.accessory, scale: 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if staticRendering {
                            Text(hero.displayName).font(.system(size: 16, weight: .heavy, design: .rounded))
                        } else {
                        TextField(hero.heroClass.defaultNickname, text: Binding(
                            get: { hero.nickname ?? "" },
                            set: { store.rename(index, to: $0) }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .frame(maxWidth: 90)
                            .help("이름을 눌러 바꿀 수 있어요")
                        }
                        Text(hero.heroClass.name).font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                    Text("Lv. \(hero.level)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
                    if staticRendering {
                        Text("꾸미기: \(Accessory.all[hero.accessory ?? 0])")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    } else {
                    Picker("꾸미기", selection: Binding(
                        get: { hero.accessory ?? 0 },
                        set: { store.setAccessory(index, $0) })) {
                        ForEach(Accessory.all.indices, id: \.self) { i in Text(Accessory.all[i]).tag(i) }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 140)
                    }
                    Text("\(hero.heroClass.skillName) — \(hero.heroClass.skillDescription)")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("체력").foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(Int(max(0, hp)))/\(Int(hero.maxHP))")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                Bar(fraction: hp / hero.maxHP)
                HStack {
                    Text("공격력").foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(Int(hero.attack))")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            HStack(spacing: 8) {
                ForEach(GearSlot.allCases, id: \.self) { slot in
                    let item = hero.item(in: slot)
                    VStack(spacing: 2) {
                        ItemCell(item: item, size: 40)
                            .onTapGesture { store.unequip(slot: slot, from: index) }
                        Text(item?.statText ?? slot.name)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(item.map { Color(hex: $0.rarity.colorHex) } ?? Theme.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button {
                store.levelUp(index)
            } label: {
                Text("레벨업  🪙 \(hero.levelUpCost.formatted())").frame(maxWidth: .infinity)
            }
            .buttonStyle(GameButtonStyle())
            .disabled(store.progress.gold < hero.levelUpCost)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}

private struct ItemDetail: View {
    @Environment(GameStore.self) private var store
    let item: Item?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item {
                HStack(spacing: 8) {
                    ItemCell(item: item, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: item.rarity.colorHex))
                        Text("\(item.rarity.name) \(item.slot.name) · \(item.statText)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    }
                }
                ForEach(Array(store.progress.heroes.enumerated()), id: \.offset) { i, hero in
                    let current = hero.item(in: item.slot)
                    let delta = item.power - (current?.power ?? 0)
                    Button {
                        store.equip(item, on: i)
                        onDone()
                    } label: {
                        HStack {
                            Text("\(hero.displayName)에게 장착")
                            Spacer()
                            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                .foregroundStyle(delta >= 0 ? Color(hex: 0x9CF0A8) : Color(hex: 0xFF9C9C))
                        }
                    }
                    .buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                }
                Button("판매  🪙 \(item.sellValue.formatted())") {
                    store.sell(item)
                    onDone()
                }
                .buttonStyle(GameButtonStyle(color: Color(hex: 0x8A6D3B), compact: true))
            } else {
                Text("전리품을 눌러 장착하거나 판매하세요.\n장착 칸을 누르면 장비를 가방으로 돌려놓아요.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(Rarity.allCases, id: \.self) { r in
                        Text(r.name).font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().stroke(Color(hex: r.colorHex)))
                            .foregroundStyle(Color(hex: r.colorHex))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// True while rendering with ImageRenderer (AppKit-backed controls can't be drawn there).
private struct StaticRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}
