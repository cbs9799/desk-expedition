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

struct StripHUD: View {
    let progress: Progress
    let banner: String?

    var body: some View {
        Canvas { ctx, size in draw(ctx, size: size) }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let panel = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
        ctx.fill(panel, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x1A1424, opacity: 0.82), Color(hex: 0x120E1A, opacity: 0.9)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(panel, with: .color(Color(hex: 0xFFD45A, opacity: 0.18)), lineWidth: 1)

        let x0: CGFloat = 12
        if let banner {
            let text = Text(banner).font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: 0xFFE27A))
            ctx.draw(text, in: CGRect(x: x0, y: 14, width: size.width - 24, height: size.height - 20))
            return
        }

        let p = progress
        let waveText = p.isBossWave ? (p.isEndless ? "\(p.wave)층 보스!" : "보스전!") : p.stageText
        ctx.draw(Text(p.region.name).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white),
                 at: CGPoint(x: x0, y: 22), anchor: .leading)
        ctx.draw(Text(waveText).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(p.isBossWave ? Color(hex: 0xFF7A7A) : .white.opacity(0.7)),
                 at: CGPoint(x: size.width - 12, y: 22), anchor: .trailing)

        let pipW = (size.width - 24 - 9 * 4) / 10
        for w in 1...Region.wavesPerRegion {
            let rect = CGRect(x: x0 + CGFloat(w - 1) * (pipW + 4), y: 36, width: pipW, height: 5)
            let boss = w == Region.wavesPerRegion
            let color: Color = w < p.pipWave ? Color(hex: 0x6BE36F)
                : w == p.pipWave ? Color(hex: 0xFFD45A)
                : boss ? Color(hex: 0xFF7A7A, opacity: 0.4) : .white.opacity(0.15)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(color))
        }

        let bagColor: Color = p.bagIsFull ? Color(hex: 0xFF7A7A) : .white.opacity(0.85)
        ctx.draw(Text("🪙 \(p.gold.formatted())").font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(Color(hex: 0xFFD45A)), at: CGPoint(x: x0, y: 66), anchor: .leading)
        ctx.draw(Text("🎒 \(p.bag.count)/\(Progress.bagCapacity)").font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(bagColor), at: CGPoint(x: x0 + 124, y: 66), anchor: .leading)
        ctx.draw(Text("⚔️ \(p.totalKills.formatted())").font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.6)), at: CGPoint(x: size.width - 12, y: 66), anchor: .trailing)
        let names = p.heroes.map(\.displayName).joined(separator: " · ") + "   📖 \(p.journal.count) · 도감 \(p.dex.count)/\(Species.slotCount)"
        ctx.draw(Text(names).font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.45)), at: CGPoint(x: x0, y: 86), anchor: .leading)
    }
}
