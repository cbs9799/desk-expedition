import SwiftUI

/// Crisp pixel cell from any processed sheet (monsters, trophies).
struct SheetPortrait: View {
    let key: String
    var frame: Int = 0
    var scale: CGFloat = 1.5
    var shiny = false
    var unknown = false

    var body: some View {
        if let sheet = SpriteSheet.named(key), let cg = sheet.cgImage(frame: frame) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(sheet.meta.cellW) * scale, height: CGFloat(sheet.meta.cellH) * scale)
                .hueRotation(.radians(shiny ? 2.6 : 0))
                .colorMultiply(unknown ? .black : .white)
                .opacity(unknown ? 0.35 : 1)
        } else {
            Color.clear.frame(width: 30 * scale, height: 24 * scale)
        }
    }
}

// MARK: - 책상 도감

struct DexView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        let p = store.progress
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("책상 도감").font(.system(size: 15, weight: .heavy, design: .rounded))
                Text("\(p.dex.count)/\(Species.slotCount)").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text("칸마다 골드 +1% (지금 +\(p.dex.count)%) · 반짝이 1/400 · 왕관 1/50 · 희귀 손님은 가끔 웨이브에 끼어들어요")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Species.all) { sp in
                        DexCard(species: sp, dex: p.dex)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}

private struct DexCard: View {
    let species: Species
    let dex: [String: DexEntry]

    var body: some View {
        let seenAny = species.variants.contains { dex[Dex.key(species.id, $0)] != nil }
        let shinySeen = dex[Dex.key(species.id, .shiny)] != nil
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                SheetPortrait(key: species.spriteKey, scale: species.isBoss ? 0.9 : 1.4, shiny: shinySeen && !seenNormal,
                              unknown: !seenAny)
                    .frame(height: 50)
            }
            Text(seenAny ? species.name : "???")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(species.variants, id: \.self) { v in
                    let e = dex[Dex.key(species.id, v)]
                    Text(v == .normal ? (species.isGuest ? "손님" : "일반") : v.label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(e == nil ? Color.white.opacity(0.06) : badge(v).opacity(0.85)))
                        .foregroundStyle(e == nil ? Theme.dim : .black)
                        .help(e.map { "\($0.count)번 만남" } ?? "아직 못 만났어요")
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(species.isGuest ? Color(hex: 0x1F3340) : species.isBoss ? Color(hex: 0x3A2430) : Theme.panelHi))
    }

    private var seenNormal: Bool { dex[Dex.key(species.id, .normal)] != nil }

    private func badge(_ v: MonsterVariant) -> Color {
        switch v {
        case .normal: return species.isGuest ? Color(hex: 0x9CF4FF) : Color(hex: 0xB9C0C8)
        case .shiny: return Theme.gold
        case .crowned: return Color(hex: 0xFF8A6A)
        }
    }
}

// MARK: - 원정 일지

struct JournalView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        let p = store.progress
        let names = p.heroes.map(\.displayName)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("원정 일지").font(.system(size: 15, weight: .heavy, design: .rounded))
                Text("\(p.journal.count)/\(Journal.entries.count)장").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text("보스, 새 지역, 도감, 심층 기록 같은 순간마다 한 장씩 쓰여요")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !p.aiDiary.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("🤖 대장 일지").font(.system(size: 13, weight: .heavy, design: .rounded))
                            ForEach(p.aiDiary.suffix(8).reversed()) { e in
                                HStack(alignment: .top) {
                                    Text(e.date.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                                    Text(e.text).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(hex: 0x9CF4FF))
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1F3340)))
                    }
                    ForEach(p.journal.reversed()) { page in
                        let e = Journal.text(page.id, names: names)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.title).font(.system(size: 13, weight: .heavy, design: .rounded))
                                Spacer()
                                Text(page.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                            }
                            Text(e.text).font(.system(size: 12, design: .serif))
                                .foregroundStyle(Color(hex: 0x3A2C1E))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .foregroundStyle(Color(hex: 0x3A2C1E))
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xF3E6C8)))
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}

// MARK: - 기록 (trophies, depth, moving)

struct RecordsView: View {
    @Environment(GameStore.self) private var store
    @State private var confirmMove = false

    var body: some View {
        let p = store.progress
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                stat("심층 최고층", p.bestFloor > 0 ? "\(p.bestFloor)층" : "-", "다섯 번째 보스를 잡으면 서랍 심층이 열려요")
                stat("추억 조각", "\(p.memories)", "공격력·골드 +\(p.memories * 5)%")
                stat("이사", "\(p.moves)회", "지금: \(DeskTheme.names[p.theme])")
                stat("이름 있는 전설", "\(p.uniquesFound.count)/\(Unique.names.count)", "전설 장비의 35%는 이름이 새겨져 있어요")
            }
            HStack(alignment: .top, spacing: 12) {
                let week = WeeklyRule.current()
                VStack(alignment: .leading, spacing: 4) {
                    Text("📅 이번 주: \(week.name)").font(.system(size: 13, weight: .heavy, design: .rounded))
                    Text(week.desc).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
                    let kills = p.weekKey == WeeklyRule.weekKey() ? p.weekKills : 0
                    Text(p.weekClaimed ? "주간 목표 달성 ✓ (추억 조각 +1)" : "주간 목표: \(min(kills, WeeklyRule.goalKills))/\(WeeklyRule.goalKills)마리 → 추억 조각 +1")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("🧩 도감 조각 \(p.shards)").font(.system(size: 13, weight: .heavy, design: .rounded))
                    Text("이미 만난 반짝이(3)·왕관(1)·희귀 손님(2)을 또 만나면 쌓여요. 반짝이 천장 \(p.shinyPity)/\(Pity.shinySpawns) · 전설 천장 \(p.legendaryPity)/\(Pity.legendaryDrops)")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(GearSlot.allCases, id: \.self) { slot in
                            Button("\(Pity.legendaryPrice)개 → 전설 \(slot.name)") { store.exchangeShards(slot: slot) }
                                .buttonStyle(GameButtonStyle(color: Color(hex: 0x8A6D3B), compact: true))
                                .disabled(p.shards < Pity.legendaryPrice || p.bagIsFull)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("🐾 동행").font(.system(size: 13, weight: .heavy, design: .rounded))
                    ForEach(Companion.allCases, id: \.self) { c in
                        Text(c.unlocked(p) ? "✓ \(c.name)" : "· \(c.name) — \(c.unlockText)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(c.unlocked(p) ? Color(hex: 0x9CFF9C) : Theme.dim)
                    }
                    Text(Camp.hasCart(p) ? "✓ 전리품 수레" : "· 전리품 수레 — 보스 3회")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Camp.hasCart(p) ? Color(hex: 0x9CFF9C) : Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))

            VStack(alignment: .leading, spacing: 8) {
                Text("트로피 진열장").font(.system(size: 14, weight: .heavy, design: .rounded))
                Text("모은 트로피는 원정 띠의 풍경 속에 반짝이며 지나가요.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                HStack(spacing: 10) {
                    ForEach(Trophy.names.indices, id: \.self) { i in
                        let owned = p.trophies.contains(i)
                        VStack(spacing: 4) {
                            SheetPortrait(key: "trophies", frame: i, scale: 2.4, unknown: !owned)
                                .frame(height: 56)
                            Text(owned ? Trophy.names[i] : "???")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))

            ShopSection()

            VStack(alignment: .leading, spacing: 6) {
                Text("새 책상으로 이사").font(.system(size: 14, weight: .heavy, design: .rounded))
                Text("레벨·장비·골드·지역이 처음으로 돌아가는 대신 추억 조각을 얻어요. 조각 하나당 공격력과 골드가 영구히 +5%. 도감·일지·트로피·이름·꾸미기는 그대로 가져가요.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(Move.canMove(p) ? "지금 이사하면 추억 조각 +\(Move.gain(p)) · 다음 책상: \(DeskTheme.names[(p.moves + 1) % DeskTheme.names.count])"
                                         : "서랍 심층이 열리면 이사할 수 있어요")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Move.canMove(p) ? Theme.gold : Theme.dim)
                    Spacer()
                    Button("이사하기") { confirmMove = true }
                        .buttonStyle(GameButtonStyle(color: Color(hex: 0xB0623B), compact: true))
                        .disabled(!Move.canMove(p))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            Spacer(minLength: 0)
        }
        .alert("새 책상으로 이사할까요?", isPresented: $confirmMove) {
            Button("이사하기", role: .destructive) { store.moveDesk() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("레벨·장비·골드·지역이 초기화되고 추억 조각 \(Move.gain(p))개를 얻어요.")
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
            Text(note).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }
}

/// 꾸미기 상점 (StoreKit 2, cosmetic only).
private struct ShopSection: View {
    @Environment(GameStore.self) private var store
    private var shop: CosmeticShop { CosmeticShop.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("꾸미기 상점").font(.system(size: 14, weight: .heavy, design: .rounded))
                if shop.owns(.supporter) { Text("🎖 후원자").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold) }
                Spacer()
                Text("게임 성능에 영향 없는 꾸미기만 팔아요").font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 8) {
                ForEach(CosmeticShop.ID.allCases, id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(id.title).font(.system(size: 12, weight: .heavy, design: .rounded))
                            Text(id.blurb).font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim).lineLimit(2)
                        }
                        Spacer()
                        if shop.owns(id) {
                            Text("보유 중").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0x9CFF9C))
                        } else if let p = shop.products[id] {
                            Button(p.displayPrice) { Task { await shop.buy(id) } }
                                .buttonStyle(GameButtonStyle(color: Color(hex: 0x3BA55C), compact: true))
                        } else {
                            Text("—").foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))
                }
            }
            if shop.owns(.themes) {
                SegmentRow(options: [-1] + Array(DeskTheme.names.indices), selected: store.settings.themeOverride,
                           label: { $0 < 0 ? L10n.t("이사 순서대로") : L10n.t(DeskTheme.names[$0]) },
                           onSelect: { store.settings.themeOverride = $0 })
            }
            HStack {
                Text(shop.available ? (shop.message ?? "") : "앱스토어 버전에서 구매할 수 있어요. 지금 받은 버전(직접 배포)은 모든 게임 내용이 그대로 열려 있어요.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                Spacer()
                if shop.available { Button("구매 복원") { Task { await shop.restore() } }.buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true)) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}
