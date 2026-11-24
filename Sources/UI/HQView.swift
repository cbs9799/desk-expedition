import SwiftUI

/// 원정 본부: heroes, equipment, bag, region selection.
struct HQView: View {
    @Environment(GameStore.self) private var store
    @State private var selectedID: UUID?
    @State private var tab = 0
    @State private var showOnboarding = OnboardingView.needed
    @Environment(\.staticRendering) private var hqStatic
    var initialTab: Int? = nil

    var body: some View {
        let p = store.progress
        VStack(alignment: .leading, spacing: 14) {
            header(p)
            if let report = store.lastOffline {
                offlineBanner(report)
            }
            if !store.unseenDiary.isEmpty { captainBanner(store.unseenDiary) }
            SegmentRow(options: [0, 1, 2, 3], selected: initialTab ?? tab,
                       label: { [String(localized: "원정대"), String(localized: "도감 \(p.dex.count)/\(Species.slotCount)"),
                                 String(localized: "일지 \(p.journal.count)장"), String(localized: "기록")][$0] },
                       onSelect: { tab = $0 })
            switch initialTab ?? tab {
            case 1: DexView()
            case 2: JournalView()
            case 3: MaybeScroll { RecordsView() }
            default:
                MaybeScroll {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(p.heroes.enumerated()), id: \.offset) { i, hero in
                                HeroCard(index: i, hero: hero, hp: store.battle.heroes[safe: i]?.hp ?? hero.maxHP)
                            }
                        }
                        bag(p)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .frame(minWidth: HQLayout.min.width, idealWidth: HQLayout.ideal.width, maxWidth: .infinity,
               minHeight: HQLayout.min.height, idealHeight: HQLayout.ideal.height, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .overlay {
            if showOnboarding && !hqStatic {
                ZStack {
                    Color.black.opacity(0.55)
                    OnboardingView { OnboardingView.finish(); showOnboarding = false }
                }
            }
        }
    }

    private func header(_ p: Progress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("원정 본부").font(.system(size: 22, weight: .heavy, design: .rounded))
                Text(p.isBossWave ? "\(p.region.name) · \(p.isEndless ? "\(p.wave)층 " : "")보스전" : "\(p.region.name) · \(p.stageText)")
                Text("\(p.tactic.icon) \(p.tactic.name) · 📅 \(WeeklyRule.current().name)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                Spacer()
                Label("\(p.totalKills.formatted())", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.dim)
                Text("🪙 \(p.gold.formatted())")
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
            }
            SegmentRow(options: Array(Region.all.indices), selected: p.regionIndex,
                       label: { i in i <= p.unlockedRegion ? (Region.all[i].endless ? "∞ \(L10n.t(Region.all[i].name))" : "\(i + 1). \(L10n.t(Region.all[i].name))") : "🔒 \(Region.all[i].endless ? "∞" : "\(i + 1)")" },
                       enabled: { $0 <= p.unlockedRegion },
                       onSelect: { store.selectRegion($0) })
        }
    }

    /// "밤사이 대장이 한 일": what the connected AI did since HQ was last opened.
    private func captainBanner(_ entries: [DiaryEntry]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🤖").font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 원정대장이 한 일 \(entries.count)개").font(.system(size: 12, weight: .heavy, design: .rounded))
                ForEach(entries.suffix(3)) { e in
                    Text("· \(e.text)").font(.system(size: 11, design: .rounded)).foregroundStyle(Color(hex: 0x9CF4FF)).lineLimit(1)
                }
            }
            Spacer()
            Button("확인") { store.markDiarySeen() }.buttonStyle(GameButtonStyle(compact: true))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1F3340)))
    }

    private func offlineBanner(_ r: OfflineReport) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.gold)
            Text("자리를 비운 \(r.durationText) 동안: \(r.kills.formatted())마리 처치 · 골드 +\(r.gold.formatted()) · 전리품 \(r.items)개\(r.bosses > 0 ? " · 보스 \(r.bosses)회" : "")\(r.newDex > 0 ? " · 새 도감 \(r.newDex)" : "")\(r.pages > 0 ? " · 일지 \(r.pages)장" : "")\(r.autoSold > 0 ? " · 자동 판매 \(r.autoSold)개" : "")")
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
                        Text("꾸미기: \(L10n.t(Accessory.all[hero.accessory ?? 0]))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    } else {
                    Picker("꾸미기", selection: Binding(
                        get: { hero.accessory ?? 0 },
                        set: { store.setAccessory(index, $0) })) {
                        ForEach(Accessory.all.indices, id: \.self) { i in Text(L10n.t(Accessory.all[i])).tag(i) }
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
            TraitRow(index: index, hero: hero)
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
                    Text(store.progress.memories > 0 ? "\(Int(hero.attack * Move.bonus(store.progress))) (추억 +\(store.progress.memories * 5)%)" : "\(Int(hero.attack))")
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


/// True while rendering with ImageRenderer (AppKit-backed controls can't be drawn there).
private struct StaticRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

/// 영웅 특성: chosen traits, and the two options when a tier is unlocked.
private struct TraitRow: View {
    @Environment(GameStore.self) private var store
    let index: Int
    let hero: HeroProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tier = hero.pendingTraitTier {
                let (a, b) = Traits.options(hero.heroClass, tier: tier)
                Text("★ Lv.\(Traits.tiers[tier]) 특성을 골라 주세요").font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                HStack(spacing: 4) {
                    ForEach([(0, a), (1, b)], id: \.0) { opt, t in
                        Button { store.chooseTrait(index, tier: tier, option: opt) } label: {
                            VStack(spacing: 1) {
                                Text(t.name).font(.system(size: 10, weight: .heavy, design: .rounded))
                                Text(t.desc).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.dim)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                    }
                }
            } else {
                let names = hero.chosenTraitNames
                Text(names.isEmpty ? "특성: Lv.10에 열려요" : "특성: " + names.joined(separator: " · "))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
    }
}

/// HQ window sizes: resizable down to `min`, opens at `ideal` the first time.
enum HQLayout {
    static let min = CGSize(width: 860, height: 520)
    static let ideal = CGSize(width: 960, height: 680)
}

/// Scrolls in the live window; renders flat for ImageRenderer snapshots (which can't draw ScrollView content).
struct MaybeScroll<Content: View>: View {
    @Environment(\.staticRendering) private var staticRendering
    @ViewBuilder let content: () -> Content

    var body: some View {
        if staticRendering { content() } else { ScrollView { content() }.scrollIndicators(.automatic) }
    }
}
