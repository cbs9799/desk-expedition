import SwiftUI

enum StripLayout {
    static let width: CGFloat = 920
    static let height: CGFloat = 80
    static let groundY: CGFloat = 74
    static let battleWidth: CGFloat = 640
}

/// The bottom-of-screen band. Redraws whenever the store's battle state changes (10 Hz, 2 Hz in low-power).
struct StripView: View {
    @Environment(GameStore.self) private var store
    var onOpenHQ: () -> Void = {}

    var body: some View {
        StripCanvas(progress: store.progress, battle: store.battle, banner: store.banner)
            .frame(width: StripLayout.width, height: StripLayout.height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onOpenHQ() }
    }
}

struct StripCanvas: View {
    let progress: Progress
    let battle: Battle
    let banner: String?

    var body: some View {
        Canvas { ctx, size in
            draw(ctx, size: size)
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize) {
        var ctx = context
        let region = progress.region
        let t = battle.time
        let groundY = StripLayout.groundY

        // Band background.
        let band = Path(roundedRect: CGRect(x: 0, y: 6, width: size.width, height: size.height - 6), cornerRadius: 12)
        ctx.fill(band, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x12141C, opacity: 0.55), Color(hex: 0x12141C, opacity: 0.78)]),
            startPoint: CGPoint(x: 0, y: 6), endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(band, with: .color(.white.opacity(0.08)), lineWidth: 1)

        // Ground.
        let ground = CGRect(x: 10, y: groundY, width: StripLayout.battleWidth - 20, height: 3)
        ctx.fill(Path(roundedRect: ground, cornerRadius: 1.5), with: .color(Color(hex: region.groundColor)))
        for i in stride(from: 24.0, to: Double(StripLayout.battleWidth - 20), by: 37) {
            ctx.fill(Path(CGRect(x: i, y: groundY - 2, width: 3, height: 2)),
                     with: .color(Color(hex: region.groundColor, opacity: 0.7)))
        }

        // Heroes.
        for (i, hero) in battle.heroes.enumerated() {
            let sprite = Sprites.heroes[i]
            var x = CGFloat(Engine.heroX[i])
            let attacking = t - hero.lastAttackAt < 0.15 || t - hero.lastSkillAt < 0.2
            if attacking { x += 4 }
            let bob: CGFloat = hero.alive ? (sin(t * 6 + Double(i)) > 0.6 ? -1 : 0) : 0
            sprite.draw(in: ctx, bottomCenter: CGPoint(x: x, y: groundY + bob), scale: 4,
                        flash: t - hero.lastHitAt < 0.1, opacity: hero.alive ? 1 : 0.25)
            if t - hero.lastSkillAt < 0.4 {
                let glow = Path(ellipseIn: CGRect(x: x - 26, y: groundY - 4, width: 52, height: 8))
                ctx.fill(glow, with: .color(Color(hex: 0xFFE27A, opacity: 0.45)))
            }
            let maxHP = progress.heroes[i].maxHP
            drawBar(ctx, x: x - 18, y: groundY - 52, width: 36, fraction: hero.hp / maxHP,
                    color: Color(hex: 0x58D26B))
        }

        // Monsters.
        for m in battle.monsters {
            let sprite = Sprites.monsters[m.kind]
            let scale: CGFloat = m.isBoss ? 5.5 : 4
            var x = CGFloat(m.x)
            if t - m.lastAttackAt < 0.15 { x -= 5 }
            let colors: [Character: UInt32] = m.isBoss
                ? ["m": region.monsterDark, "d": 0x1A1A22]
                : ["m": region.monsterColor, "d": region.monsterDark]
            let hover: CGFloat = m.kind == 1 ? CGFloat(-12 + sin(t * 5 + m.x) * 3) : 0
            sprite.draw(in: ctx, bottomCenter: CGPoint(x: x, y: groundY + hover), scale: scale, flipped: true,
                        overrides: colors, flash: t - m.lastHitAt < 0.08)
            let top = groundY + hover - CGFloat(sprite.height) * scale
            if m.isBoss {
                Sprites.crown.draw(in: ctx, bottomCenter: CGPoint(x: x, y: top), scale: 3)
            }
            drawBar(ctx, x: x - 18, y: max(4, top - (m.isBoss ? 12 : 6)), width: 36, fraction: m.hp / m.maxHP,
                    color: m.isBoss ? Color(hex: 0xFF5A5A) : Color(hex: 0xF0A040))
        }

        // Effects.
        for e in battle.effects {
            let age = t - e.born
            let fade = max(0, 1 - age / Engine.effectLifetime)
            switch e.kind {
            case .damage(let v, let crit):
                let text = Text(crit ? "\(v)!" : "\(v)")
                    .font(.system(size: crit ? 13 : 11, weight: .heavy, design: .rounded))
                    .foregroundColor(crit ? Color(hex: 0xFFD23F) : .white)
                ctx.opacity = fade
                ctx.draw(text, at: CGPoint(x: e.x + 6, y: 30 - age * 22))
                ctx.opacity = 1
            case .heroDamage(let v):
                ctx.opacity = fade
                ctx.draw(Text("-\(v)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0xFF6B6B)), at: CGPoint(x: e.x - 8, y: 24 - age * 18))
                ctx.opacity = 1
            case .text(let s):
                ctx.opacity = fade
                ctx.draw(Text(s).font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0xFFE27A)), at: CGPoint(x: e.x, y: 16 - age * 8))
                ctx.opacity = 1
            case .arrow(let from, let to):
                guard age < 0.2 else { continue }
                let px = from + (to - from) * (age / 0.2)
                ctx.fill(Path(CGRect(x: px - 6, y: Double(groundY) - 26, width: 12, height: 2)),
                         with: .color(Color(hex: 0xE8D5A8)))
            case .bolt(let from, let to):
                guard age < 0.25 else { continue }
                let px = from + (to - from) * (age / 0.25)
                ctx.fill(Path(ellipseIn: CGRect(x: px - 4, y: Double(groundY) - 32, width: 8, height: 8)),
                         with: .color(Color(hex: 0x7FE7FF)))
            case .burst:
                guard age < 0.45 else { continue }
                let r = 8 + age * 50
                ctx.stroke(Path(ellipseIn: CGRect(x: e.x - r, y: Double(groundY) - 22 - r, width: r * 2, height: r * 2)),
                           with: .color(Color(hex: 0xFF8A3D, opacity: 1 - age / 0.45)), lineWidth: 3)
            case .slash:
                guard age < 0.15 else { continue }
                var p = Path()
                p.move(to: CGPoint(x: e.x - 12, y: Double(groundY) - 40))
                p.addLine(to: CGPoint(x: e.x + 8, y: Double(groundY) - 10))
                ctx.stroke(p, with: .color(.white.opacity(0.9 - age * 5)), lineWidth: 3)
            }
        }

        // Phase overlay.
        if case .retreating = battle.phase {
            ctx.draw(Text("후퇴 중… 전열을 가다듬는 중").font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8)), at: CGPoint(x: 400, y: 44))
        }

        drawHUD(ctx, size: size)
    }

    private func drawHUD(_ ctx: GraphicsContext, size: CGSize) {
        let x0 = StripLayout.battleWidth + 4
        ctx.fill(Path(CGRect(x: x0 - 6, y: 16, width: 1, height: size.height - 26)), with: .color(.white.opacity(0.12)))

        if let banner {
            let text = Text(banner).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: 0xFFE27A))
            ctx.draw(text, in: CGRect(x: x0 + 4, y: 16, width: size.width - x0 - 16, height: size.height - 20))
            return
        }

        let p = progress
        let waveText = p.isBossWave ? "보스전!" : "웨이브 \(p.wave)/\(Region.wavesPerRegion)"
        ctx.draw(Text("\(p.region.name)").font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white), at: CGPoint(x: x0 + 4, y: 26), anchor: .leading)
        ctx.draw(Text(waveText).font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(p.isBossWave ? Color(hex: 0xFF7A7A) : .white.opacity(0.7)),
                 at: CGPoint(x: size.width - 14, y: 26), anchor: .trailing)

        // Wave progress pips.
        for w in 1...Region.wavesPerRegion {
            let rect = CGRect(x: x0 + 4 + CGFloat(w - 1) * 25, y: 38, width: 21, height: 4)
            let color: Color = w < p.wave ? Color(hex: 0x58D26B) : w == p.wave ? Color(hex: 0xFFE27A) : .white.opacity(0.15)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(w == Region.wavesPerRegion && w != p.wave && w > p.wave ? Color(hex: 0xFF7A7A, opacity: 0.35) : color))
        }

        let bagColor: Color = p.bagIsFull ? Color(hex: 0xFF7A7A) : .white.opacity(0.85)
        ctx.draw(Text("🪙 \(p.gold.formatted())").font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: 0xFFD23F)), at: CGPoint(x: x0 + 4, y: 58), anchor: .leading)
        ctx.draw(Text("🎒 \(p.bag.count)/\(Progress.bagCapacity)").font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(bagColor), at: CGPoint(x: x0 + 128, y: 58), anchor: .leading)
        ctx.draw(Text("⚔️ \(p.totalKills.formatted())").font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.6)), at: CGPoint(x: size.width - 14, y: 58), anchor: .trailing)
    }

    private func drawBar(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, width: CGFloat, fraction: Double, color: Color) {
        let f = CGFloat(min(1, max(0, fraction)))
        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: 4), cornerRadius: 2),
                 with: .color(.black.opacity(0.55)))
        if f > 0 {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: width * f, height: 4), cornerRadius: 2),
                     with: .color(color))
        }
    }
}
