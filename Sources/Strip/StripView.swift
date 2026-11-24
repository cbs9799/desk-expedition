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
        ZStack(alignment: .topLeading) {
            StripSpriteView(store: store, onOpenHQ: onOpenHQ)
                .frame(width: StripLayout.width, height: StripLayout.height)
            StripHUD(progress: store.progress, banner: store.banner)
                .frame(width: StripLayout.width - StripLayout.battleWidth - 6, height: StripLayout.height)
                .offset(x: StripLayout.battleWidth + 6)
                .onTapGesture(count: 2) { onOpenHQ() }
        }
        .frame(width: StripLayout.width, height: StripLayout.height)
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

/// Floating HUD: no panel — every readout hangs in the air on its own soft shadow.
struct StripHUD: View {
    let progress: Progress
    let banner: String?

    var body: some View {
        Canvas { ctx, size in draw(ctx, size: size) }
    }

    private func floating(_ ctx: GraphicsContext) -> GraphicsContext {
        var c = ctx
        c.addFilter(.shadow(color: .black.opacity(0.85), radius: 1.2, x: 0, y: 1))
        c.addFilter(.shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2))
        return c
    }

    private func draw(_ base: GraphicsContext, size: CGSize) {
        let ctx = floating(base)
        let x0: CGFloat = 14
        if let banner {
            let text = Text(banner).font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: 0xFFE27A))
            ctx.draw(text, in: CGRect(x: x0, y: 18, width: size.width - 24, height: size.height - 24))
            return
        }

        let p = progress
        let waveText = p.isBossWave ? (p.isEndless ? "\(p.wave)층 보스!" : "보스전!") : p.stageText
        ctx.draw(Text(p.region.name).font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(.white),
                 at: CGPoint(x: x0, y: 22), anchor: .leading)
        ctx.draw(Text(waveText).font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundColor(p.isBossWave ? Color(hex: 0xFF8A8A) : Color(hex: 0xE8ECFF)),
                 at: CGPoint(x: size.width - 14, y: 23), anchor: .trailing)

        // Wave gems: little floating diamonds instead of a bar.
        let n = Region.wavesPerRegion
        let gap = (size.width - 28) / CGFloat(n)
        for w in 1...n {
            let c = CGPoint(x: x0 + gap * (CGFloat(w) - 0.5), y: 42)
            let boss = w == n
            let r: CGFloat = w == p.pipWave ? 5.5 : boss ? 5 : 4
            var gem = Path()
            gem.move(to: CGPoint(x: c.x, y: c.y - r)); gem.addLine(to: CGPoint(x: c.x + r, y: c.y))
            gem.addLine(to: CGPoint(x: c.x, y: c.y + r)); gem.addLine(to: CGPoint(x: c.x - r, y: c.y)); gem.closeSubpath()
            let color: Color = w < p.pipWave ? Color(hex: 0x6BE36F)
                : w == p.pipWave ? Color(hex: 0xFFD45A)
                : boss ? Color(hex: 0xFF7A7A, opacity: 0.55) : .white.opacity(0.28)
            ctx.fill(gem, with: .color(color))
            if w == p.pipWave {
                base.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                          with: .color(Color(hex: 0xFFD45A, opacity: 0.25)))
            }
        }

        let bagColor: Color = p.bagIsFull ? Color(hex: 0xFF8A8A) : .white
        ctx.draw(Text("🪙 \(p.gold.formatted())").font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundColor(Color(hex: 0xFFD45A)), at: CGPoint(x: x0, y: 66), anchor: .leading)
        ctx.draw(Text("🎒 \(p.bag.count)/\(Progress.bagCapacity)").font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(bagColor), at: CGPoint(x: x0 + 128, y: 66), anchor: .leading)
        ctx.draw(Text("⚔️ \(p.totalKills.formatted())").font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.85)), at: CGPoint(x: size.width - 14, y: 66), anchor: .trailing)
        let names = p.heroes.map(\.displayName).joined(separator: " · ")
        ctx.draw(Text(names).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8)),
                 at: CGPoint(x: x0, y: 87), anchor: .leading)
        ctx.draw(Text("📖 \(p.journal.count)  도감 \(p.dex.count)/\(Species.slotCount)")
            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(Color(hex: 0x9CF4FF)),
                 at: CGPoint(x: size.width - 14, y: 87), anchor: .trailing)
    }
}
