import SpriteKit
import SwiftUI

enum StripLayout {
    static let width: CGFloat = 920
    static let height: CGFloat = 100
    static let battleWidth: CGFloat = 640
}

/// The bottom-of-screen band: a SpriteKit window into the desk world on the left, a compact HUD on the right.
struct StripView: View {
    @Environment(GameStore.self) private var store
    var onOpenHQ: () -> Void = {}

    var body: some View {
        let s = CGFloat(store.settings.stripScale)
        let hudW = StripLayout.width - StripLayout.battleWidth - 6
        ZStack(alignment: .topLeading) {
            // SpriteKit scales its fixed 920×100 scene to the view (scaleMode .fill).
            StripSpriteView(store: store, onOpenHQ: onOpenHQ)
                .frame(width: StripLayout.width * s, height: StripLayout.height * s)
            StripHUD(progress: store.progress, banner: store.banner)
                .frame(width: hudW, height: StripLayout.height)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: hudW * s, height: StripLayout.height * s, alignment: .topLeading)
                .offset(x: (StripLayout.battleWidth + 6) * s)
        }
        .frame(width: StripLayout.width * s, height: StripLayout.height * s, alignment: .topLeading)
    }
}

/// Hosts the scene in a transparent SKView; pauses rendering entirely in low-power mode.
struct StripSpriteView: NSViewRepresentable {
    let store: GameStore
    let onOpenHQ: () -> Void

    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: StripLayout.width, height: StripLayout.height))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        let scene = StripScene(size: CGSize(width: StripLayout.width, height: StripLayout.height))
        scene.store = store
        scene.onOpenHQ = onOpenHQ
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        view.isPaused = store.lowPower
    }
}

/// Floating HUD: no panel — every readout hangs in the air on its own soft shadow — and it is playable:
/// pick the region, jump to a wave, level heroes up, all without opening HQ.
struct StripHUD: View {
    @Environment(GameStore.self) private var store
    @Environment(\.staticRendering) private var staticRendering
    let progress: Progress
    let banner: String?

    var body: some View {
        let p = progress
        VStack(alignment: .leading, spacing: 5) {
            if let banner {
                Text(L10n.t(banner)).font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFE27A)).lineLimit(2).floating()
                    .frame(height: 34, alignment: .leading)
            } else {
                HStack {
                    regionPicker(p)
                    Spacer()
                    Text(L10n.t(p.isBossWave ? (p.isEndless ? "\(p.wave)층 보스!" : "보스전!") : p.stageText))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(p.isBossWave ? Color(hex: 0xFF8A8A) : Color(hex: 0xE8ECFF)).floating()
                }
                waveGems(p)
            }
            HStack(spacing: 12) {
                Text("🪙 \(p.gold.formatted())").font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFD45A)).floating()
                Text("🎒 \(p.bag.count)/\(Progress.bagCapacity)").font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(p.bagIsFull ? Color(hex: 0xFF8A8A) : .white).floating()
                tacticPicker(p)
                Spacer()
                Text("도감 \(p.dex.count)/\(Species.slotCount)").font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x9CF4FF)).floating()
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in levelChip(i, p) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func regionPicker(_ p: Progress) -> some View {
        let label = Text("\(L10n.t(p.region.name)) ▾").font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(.white)
        if staticRendering {
            label.floating()
        } else {
            Menu {
                ForEach(0...p.unlockedRegion, id: \.self) { i in
                    Button((i == p.regionIndex ? "✓ " : "") + (Region.all[i].endless ? "∞ " : "\(i + 1). ") + Region.all[i].name) {
                        store.selectRegion(i)
                    }
                }
            } label: { label }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .floating()
            .help("원정 지역 바꾸기")
        }
    }

    private func waveGems(_ p: Progress) -> some View {
        let selectable = store.selectableWaves
        return HStack(spacing: 0) {
            ForEach(1...Region.wavesPerRegion, id: \.self) { w in
                let boss = w == Region.wavesPerRegion
                let current = w == p.pipWave
                let color: Color = w < p.pipWave ? Color(hex: 0x6BE36F)
                    : current ? Color(hex: 0xFFD45A)
                    : boss ? Color(hex: 0xFF7A7A, opacity: 0.6) : .white.opacity(0.3)
                let canPick = selectable?.contains(w) ?? false
                Button { store.selectWave(w) } label: {
                    Image(systemName: boss ? "crown.fill" : "diamond.fill")
                        .font(.system(size: current ? 11 : boss ? 10 : 8, weight: .black))
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canPick)
                .help(canPick ? "\(w)웨이브로 이동" : "")
            }
        }
        .floating()
    }

    @ViewBuilder private func tacticPicker(_ p: Progress) -> some View {
        let label = Text(p.tactic.icon).font(.system(size: 13))
        if staticRendering {
            label.floating()
        } else {
            Menu {
                ForEach(Tactic.allCases, id: \.self) { t in
                    Button("\(t == p.tactic ? "✓ " : "")\(t.icon) \(t.name) — \(t.desc)") { store.setTactic(t) }
                }
            } label: { label }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().floating()
            .help("원정 전술: \(p.tactic.name)")
        }
    }

    @ViewBuilder private func levelChip(_ i: Int, _ p: Progress) -> some View {
        let h = p.heroes[i]
        if let tier = h.pendingTraitTier, !staticRendering {
            let (a, b) = Traits.options(h.heroClass, tier: tier)
            Menu {
                Section("★ Lv.\(Traits.tiers[tier]) 특성 고르기") {
                    Button("\(a.name) — \(a.desc)") { store.chooseTrait(i, tier: tier, option: 0) }
                    Button("\(b.name) — \(b.desc)") { store.chooseTrait(i, tier: tier, option: 1) }
                }
                Button("레벨업 (🪙 \(h.levelUpCost))") { store.levelUp(i) }.disabled(p.gold < h.levelUpCost)
            } label: { chipLabel(h, affordable: p.gold >= h.levelUpCost, star: true) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        } else {
            plainChip(i, p)
        }
    }

    private func chipLabel(_ h: HeroProgress, affordable: Bool, star: Bool) -> some View {
        HStack(spacing: 3) {
            if star { Text("★").font(.system(size: 10, weight: .black)).foregroundStyle(Color(hex: 0xFFD45A)) }
            Text(h.displayName).font(.system(size: 10, weight: .heavy, design: .rounded)).lineLimit(1)
            Text("\(h.level)").font(.system(size: 10, weight: .black, design: .rounded)).foregroundStyle(Color(hex: 0xFFE27A))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(star ? Color(hex: 0x6A4A12, opacity: 0.9) : Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Color(hex: 0xFFD45A, opacity: 0.8), lineWidth: 1))
        .foregroundStyle(.white)
    }

    private func plainChip(_ i: Int, _ p: Progress) -> some View {
        let h = p.heroes[i]
        let affordable = p.gold >= h.levelUpCost
        return Button { store.levelUp(i) } label: {
            HStack(spacing: 3) {
                Text(h.displayName).font(.system(size: 10, weight: .heavy, design: .rounded)).lineLimit(1)
                Text("\(h.level)").font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFE27A))
                Text("▲\(h.levelUpCost.formatted(.number.notation(.compactName)))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(affordable ? Color(hex: 0x9CFF9C) : .white.opacity(0.45))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(affordable ? Color(hex: 0x2E7D4A, opacity: 0.85) : Color.black.opacity(0.35)))
            .overlay(Capsule().stroke(affordable ? Color(hex: 0x9CFF9C, opacity: 0.7) : .white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
        .help(affordable ? "\(h.displayName) 레벨업 (🪙 \(h.levelUpCost))" : "골드가 모자라요")
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }
}

private extension View {
    /// Readable over any wallpaper without a panel behind it.
    func floating() -> some View {
        shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)
    }
}
