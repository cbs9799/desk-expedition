import AppKit
import SpriteKit

/// Procedural high-resolution VFX (deliberately NOT pixel art) layered over the pixel sprites.
/// Everything glows with additive blending; colors come from each hero's palette.
@MainActor
enum FX {
    // MARK: Palette

    static let steel = NSColor(hex: 0xBFE6FF)
    static let gold = NSColor(hex: 0xFFD45A)
    static let leaf = NSColor(hex: 0x9CFF7A)
    static let fire = NSColor(hex: 0xFF8A2A)
    static let ember = NSColor(hex: 0xFFC14D)
    static let arcane = NSColor(hex: 0xB78CFF)
    static let blood = NSColor(hex: 0xFF5A5A)

    // MARK: Textures (drawn once with Core Graphics)

    private static func make(_ size: CGSize, _ draw: @escaping (CGContext) -> Void) -> SKTexture {
        let img = NSImage(size: size, flipped: false) { _ in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(ctx) }
            return true
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }

    static let softDot: SKTexture = make(CGSize(width: 64, height: 64)) { ctx in
        let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.clear.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                               endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    /// Thin bright streak for directional sparks.
    static let streak: SKTexture = make(CGSize(width: 64, height: 8)) { ctx in
        let colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1])!
        ctx.addEllipse(in: CGRect(x: 0, y: 1, width: 64, height: 6))
        ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 4), end: CGPoint(x: 64, y: 4), options: [])
    }

    /// Crescent sword arc: bright leading edge fading into a soft tail.
    static let crescent: SKTexture = make(CGSize(width: 128, height: 128)) { ctx in
        let c = CGPoint(x: 64, y: 64)
        for i in 0..<28 {
            let f = CGFloat(i) / 27
            let path = CGMutablePath()
            path.addArc(center: c, radius: 54 - f * 10, startAngle: .pi * (0.62 - f * 0.08),
                        endAngle: -.pi * (0.62 - f * 0.08), clockwise: true)
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.05 + 0.12 * (1 - f)).cgColor)
            ctx.setLineWidth(14 * (1 - f) + 2)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
        let edge = CGMutablePath()
        edge.addArc(center: c, radius: 55, startAngle: .pi * 0.6, endAngle: -.pi * 0.6, clockwise: true)
        ctx.addPath(edge)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(4)
        ctx.strokePath()
    }

    static let ring: SKTexture = make(CGSize(width: 128, height: 128)) { ctx in
        for (w, a) in [(14.0, 0.18), (8.0, 0.35), (3.0, 1.0)] {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(a).cgColor)
            ctx.setLineWidth(w)
            ctx.strokeEllipse(in: CGRect(x: 10, y: 10, width: 108, height: 108))
        }
    }

    /// 4-point glint star.
    static let flare: SKTexture = make(CGSize(width: 64, height: 64)) { ctx in
        let colors = [NSColor.white.cgColor, NSColor.clear.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        for (w, h) in [(64.0, 5.0), (5.0, 64.0)] {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: 32 - w / 2, y: 32 - h / 2, width: w, height: h))
            ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                   endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            ctx.restoreGState()
        }
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                               endCenter: CGPoint(x: 32, y: 32), endRadius: 10, options: [])
    }

    /// Vertical beam for legendary drops.
    static let beam: SKTexture = make(CGSize(width: 32, height: 128)) { ctx in
        let colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 32, y: 0), options: [])
    }

    /// Small pixel heart (drawn as pixels on purpose — it belongs to the characters, not the VFX).
    static let heart: SKTexture = {
        let rows = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
        let t = make(CGSize(width: 7, height: 6)) { ctx in
            ctx.setFillColor(NSColor(hex: 0xFF5E8A).cgColor)
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    ctx.fill(CGRect(x: x, y: 5 - y, width: 1, height: 1))
                }
            }
        }
        t.filteringMode = .nearest
        return t
    }()

    /// Toothpick arrow, pixel style to match the archer.
    static let arrow: SKTexture = {
        let t = make(CGSize(width: 12, height: 3)) { ctx in
            ctx.setFillColor(NSColor(hex: 0xE9CF98).cgColor); ctx.fill(CGRect(x: 2, y: 1, width: 8, height: 1))
            ctx.setFillColor(NSColor(hex: 0xFFFFFF).cgColor); ctx.fill(CGRect(x: 10, y: 1, width: 2, height: 1))
            ctx.setFillColor(NSColor(hex: 0x7BD86A).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1)); ctx.fill(CGRect(x: 0, y: 2, width: 2, height: 1))
        }
        t.filteringMode = .nearest
        return t
    }()

    // MARK: Building blocks

    static func glow(_ color: NSColor, size: CGFloat, alpha: CGFloat = 1) -> SKSpriteNode {
        let n = SKSpriteNode(texture: softDot, size: CGSize(width: size, height: size))
        n.color = color
        n.colorBlendFactor = 1
        n.blendMode = .add
        n.alpha = alpha
        return n
    }

    /// One-shot burst of particles that removes itself.
    static func burst(_ layer: SKNode, at p: CGPoint, color: NSColor, count: Int, speed: CGFloat,
                      life: CGFloat = 0.45, size: CGFloat = 0.18, angle: CGFloat = 0, spread: CGFloat = .pi * 2,
                      texture: SKTexture = softDot, gravity: CGFloat = 0, rotateToVelocity: Bool = false) {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = CGFloat(count) * 60
        e.numParticlesToEmit = count
        e.particleLifetime = life
        e.particleLifetimeRange = life * 0.5
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.7
        e.emissionAngle = angle
        e.emissionAngleRange = spread
        e.particleScale = size
        e.particleScaleRange = size * 0.6
        e.particleScaleSpeed = -size / life
        e.particleAlphaSpeed = -1 / life
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.yAcceleration = gravity
        if rotateToVelocity {
            e.particleRotation = angle
            e.particleRotationRange = 0
        }
        e.position = p
        layer.addChild(e)
        e.run(.sequence([.wait(forDuration: Double(life) * 2 + 0.2), .removeFromParent()]))
    }

    /// Directional sparks: streak particles flying along `angle`.
    static func sparks(_ layer: SKNode, at p: CGPoint, color: NSColor, count: Int, angle: CGFloat, spread: CGFloat,
                       speed: CGFloat = 260) {
        for _ in 0..<count {
            let a = angle + CGFloat.random(in: -spread / 2...spread / 2)
            let s = speed * CGFloat.random(in: 0.5...1.2)
            let n = SKSpriteNode(texture: streak, size: CGSize(width: CGFloat.random(in: 10...20), height: 2.5))
            n.color = color; n.colorBlendFactor = 1; n.blendMode = .add
            n.position = p
            n.zRotation = a
            layer.addChild(n)
            let d = CGVector(dx: cos(a) * s * 0.25, dy: sin(a) * s * 0.25)
            n.run(.sequence([.group([.move(by: d, duration: 0.25), .fadeOut(withDuration: 0.25),
                                     .scaleX(to: 0.2, duration: 0.25)]), .removeFromParent()]))
        }
    }

    static func flash(_ layer: SKNode, at p: CGPoint, color: NSColor, size: CGFloat, duration: Double = 0.16) {
        let g = glow(color, size: size)
        g.position = p
        g.setScale(0.5)
        layer.addChild(g)
        g.run(.sequence([.group([.scale(to: 1.2, duration: duration), .fadeOut(withDuration: duration)]), .removeFromParent()]))
        let core = glow(.white, size: size * 0.4)
        core.position = p
        layer.addChild(core)
        core.run(.sequence([.fadeOut(withDuration: duration * 0.7), .removeFromParent()]))
    }

    static func shockwave(_ layer: SKNode, at p: CGPoint, color: NSColor, radius: CGFloat, duration: Double = 0.3,
                          squash: CGFloat = 0.45) {
        let r = SKSpriteNode(texture: ring, size: CGSize(width: 20, height: 20))
        r.color = color; r.colorBlendFactor = 1; r.blendMode = .add
        r.position = p
        r.yScale = squash
        layer.addChild(r)
        let grow = SKAction.customAction(withDuration: duration) { node, t in
            let f = t / CGFloat(duration)
            let s = (20 + (radius * 2 - 20) * (1 - pow(1 - f, 3))) / 20
            node.xScale = s; node.yScale = s * squash
            node.alpha = 1 - f
        }
        r.run(.sequence([grow, .removeFromParent()]))
    }

    // MARK: Attacks

    /// Warrior sword arc + impact. `big` for the shield-bash skill.
    static func slash(_ layer: SKNode, at p: CGPoint, big: Bool) {
        let arc = SKSpriteNode(texture: crescent, size: CGSize(width: big ? 86 : 58, height: big ? 86 : 58))
        arc.color = steel; arc.colorBlendFactor = 0.6; arc.blendMode = .add
        arc.position = CGPoint(x: p.x - 6, y: p.y + 4)
        arc.zRotation = 0.9
        arc.alpha = 0
        layer.addChild(arc)
        arc.run(.sequence([
            .group([.fadeIn(withDuration: 0.03), .rotate(byAngle: -1.6, duration: 0.12)]),
            .group([.fadeOut(withDuration: 0.12), .scale(to: 1.15, duration: 0.12)]),
            .removeFromParent(),
        ]))
        impact(layer, at: p, color: big ? gold : steel, power: big ? 1.6 : 1)
    }

    /// Generic hit: white-hot flash, ring, sparks flying away from the party.
    static func impact(_ layer: SKNode, at p: CGPoint, color: NSColor, power: CGFloat) {
        flash(layer, at: p, color: color, size: 44 * power)
        shockwave(layer, at: p, color: color, radius: 18 * power, duration: 0.22, squash: 0.8)
        sparks(layer, at: p, color: color, count: Int(7 * power), angle: 0, spread: .pi * 1.3, speed: 300 * power)
        burst(layer, at: p, color: .white, count: Int(6 * power), speed: 90, life: 0.25, size: 0.08)
    }

    /// Archer arrow with a glowing trail; calls `hit` on arrival.
    static func arrowShot(_ layer: SKNode, from a: CGPoint, to b: CGPoint, color: NSColor = leaf,
                          duration: Double = 0.16, hit: @escaping () -> Void) {
        let node = SKNode()
        node.position = a
        let shaft = SKSpriteNode(texture: arrow)
        shaft.setScale(PixelArt.scale)
        node.addChild(shaft)
        let head = glow(color, size: 14, alpha: 0.9)
        head.position = CGPoint(x: 8, y: 0)
        node.addChild(head)
        let trail = SKEmitterNode()
        trail.particleTexture = streak
        trail.particleBirthRate = 220
        trail.particleLifetime = 0.16
        trail.particleSize = CGSize(width: 16, height: 3)
        trail.particleAlphaSpeed = -6
        trail.particleScaleSpeed = -2
        trail.particleColor = color
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        trail.targetNode = layer
        node.addChild(trail)
        layer.addChild(node)
        let arcUp = SKAction.customAction(withDuration: duration) { n, t in
            let f = t / CGFloat(duration)
            n.position = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f + sin(f * .pi) * 10)
            n.zRotation = cos(f * .pi) * 0.35
        }
        node.run(.sequence([arcUp, .run {
            hit()
            trail.particleBirthRate = 0
            shaft.removeFromParent(); head.removeFromParent()
        }, .wait(forDuration: 0.3), .removeFromParent()]))
    }

    /// Mage fireball: charge glint at the staff, glowing orb with an ember trail, explosion on arrival.
    static func fireball(_ layer: SKNode, from a: CGPoint, to b: CGPoint, duration: Double = 0.24, hit: @escaping () -> Void) {
        chargeUp(layer, at: a, color: fire, time: 0.1)
        let node = SKNode()
        node.position = a
        node.alpha = 0
        let outer = glow(fire, size: 30, alpha: 0.85)
        let core = glow(NSColor(hex: 0xFFF2C0), size: 12)
        node.addChild(outer); node.addChild(core)
        outer.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.05), .scale(to: 0.9, duration: 0.05)])))
        let trail = SKEmitterNode()
        trail.particleTexture = softDot
        trail.particleBirthRate = 260
        trail.particleLifetime = 0.3
        trail.particleLifetimeRange = 0.15
        trail.particleSpeed = 20
        trail.particleSpeedRange = 20
        trail.emissionAngle = .pi
        trail.emissionAngleRange = 1.2
        trail.particleScale = 0.22
        trail.particleScaleSpeed = -0.6
        trail.particleAlphaSpeed = -3
        trail.particleColorSequence = SKKeyframeSequence(keyframeValues: [NSColor(hex: 0xFFF2C0), fire, NSColor(hex: 0x802010)],
                                                         times: [0, 0.4, 1])
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        trail.targetNode = layer
        node.addChild(trail)
        layer.addChild(node)
        node.run(.sequence([
            .wait(forDuration: 0.1), .fadeIn(withDuration: 0.02),
            .move(to: b, duration: duration),
            .run {
                hit()
                explosion(layer, at: b, power: 0.8)
                trail.particleBirthRate = 0
                outer.removeFromParent(); core.removeFromParent()
            },
            .wait(forDuration: 0.4), .removeFromParent(),
        ]))
    }

    /// Glints rushing into a point (power gathering).
    static func chargeUp(_ layer: SKNode, at p: CGPoint, color: NSColor, time: Double, count: Int = 8, radius: CGFloat = 22) {
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: 0...0.5)
            let n = glow(color, size: 8)
            n.position = CGPoint(x: p.x + cos(a) * radius, y: p.y + sin(a) * radius)
            n.alpha = 0
            layer.addChild(n)
            n.run(.sequence([.group([.fadeIn(withDuration: time * 0.3), .move(to: p, duration: time)]), .removeFromParent()]))
        }
        let g = glow(color, size: 26)
        g.position = p
        g.setScale(0.2)
        layer.addChild(g)
        g.run(.sequence([.scale(to: 1, duration: time), .fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    /// Fire explosion: flash, double ring, embers with gravity, lingering smoke.
    static func explosion(_ layer: SKNode, at p: CGPoint, power: CGFloat) {
        flash(layer, at: p, color: fire, size: 70 * power, duration: 0.22)
        shockwave(layer, at: p, color: ember, radius: 34 * power, duration: 0.3, squash: 0.55)
        shockwave(layer, at: p, color: fire, radius: 22 * power, duration: 0.22, squash: 1)
        burst(layer, at: p, color: ember, count: Int(22 * power), speed: 160 * power, life: 0.5, size: 0.14, gravity: -260)
        burst(layer, at: p, color: fire, count: Int(10 * power), speed: 60, life: 0.35, size: 0.4)
        let smoke = SKEmitterNode()
        smoke.particleTexture = softDot
        smoke.particleBirthRate = 400
        smoke.numParticlesToEmit = 8
        smoke.particleLifetime = 0.7
        smoke.particleSpeed = 22
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = 1.4
        smoke.particleScale = 0.35 * power
        smoke.particleScaleSpeed = 0.5
        smoke.particleAlpha = 0.35
        smoke.particleAlphaSpeed = -0.5
        smoke.particleColor = NSColor(hex: 0x3A2E36)
        smoke.particleColorBlendFactor = 1
        smoke.particleBlendMode = .alpha
        smoke.position = p
        layer.addChild(smoke)
        smoke.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    // MARK: Celebrations

    static func hearts(_ layer: SKNode, at p: CGPoint) {
        for i in 0..<3 {
            let h = SKSpriteNode(texture: heart)
            h.setScale(PixelArt.scale)
            h.position = CGPoint(x: p.x + CGFloat(i - 1) * 8, y: p.y)
            h.alpha = 0
            layer.addChild(h)
            h.run(.sequence([.wait(forDuration: Double(i) * 0.12),
                             .group([.fadeIn(withDuration: 0.08),
                                     .moveBy(x: CGFloat.random(in: -6...6), y: 22, duration: 0.8),
                                     .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3)])]),
                             .removeFromParent()]))
        }
    }

    static func levelUp(_ layer: SKNode, at p: CGPoint) {
        let pillar = SKSpriteNode(texture: beam, size: CGSize(width: 26, height: 90))
        pillar.color = gold; pillar.colorBlendFactor = 1; pillar.blendMode = .add
        pillar.anchorPoint = CGPoint(x: 0.5, y: 0)
        pillar.position = p
        pillar.yScale = 0.1
        layer.addChild(pillar)
        pillar.run(.sequence([.scaleY(to: 1, duration: 0.15), .group([.fadeOut(withDuration: 0.5), .scaleX(to: 0.2, duration: 0.5)]),
                              .removeFromParent()]))
        burst(layer, at: CGPoint(x: p.x, y: p.y + 10), color: gold, count: 24, speed: 70, life: 0.9, size: 0.12,
              angle: .pi / 2, spread: 1.2, gravity: 30)
        label(layer, "LEVEL UP!", at: CGPoint(x: p.x, y: p.y + 62), color: gold, size: 11, rise: 14, life: 1.1)
    }

    /// Legendary loot: beam of light, rotating rays, golden rain.
    static func legendary(_ layer: SKNode, at p: CGPoint) {
        let pillar = SKSpriteNode(texture: beam, size: CGSize(width: 44, height: 110))
        pillar.color = gold; pillar.colorBlendFactor = 1; pillar.blendMode = .add
        pillar.anchorPoint = CGPoint(x: 0.5, y: 0)
        pillar.position = CGPoint(x: p.x, y: 0)
        pillar.xScale = 0.1
        layer.addChild(pillar)
        pillar.run(.sequence([.scaleX(to: 1, duration: 0.12), .wait(forDuration: 0.9),
                              .group([.fadeOut(withDuration: 0.6), .scaleX(to: 0.1, duration: 0.6)]), .removeFromParent()]))
        let rays = SKSpriteNode(texture: flare, size: CGSize(width: 120, height: 120))
        rays.color = gold; rays.colorBlendFactor = 1; rays.blendMode = .add
        rays.position = CGPoint(x: p.x, y: p.y + 20)
        rays.setScale(0.2)
        layer.addChild(rays)
        rays.run(.sequence([.group([.scale(to: 1.1, duration: 0.25), .rotate(byAngle: .pi / 2, duration: 1.6),
                                    .sequence([.wait(forDuration: 1.0), .fadeOut(withDuration: 0.6)])]), .removeFromParent()]))
        burst(layer, at: CGPoint(x: p.x, y: 100), color: gold, count: 40, speed: 40, life: 1.2, size: 0.1,
              angle: -.pi / 2, spread: 0.8, gravity: -60)
        label(layer, "전설!", at: CGPoint(x: p.x, y: p.y + 52), color: gold, size: 13, rise: 10, life: 1.6)
    }

    /// Gold glints arcing from a defeated monster toward the HUD.
    static func coins(_ layer: SKNode, from p: CGPoint, to target: CGPoint, count: Int) {
        for i in 0..<count {
            let c = glow(gold, size: 9)
            c.position = p
            layer.addChild(c)
            let mid = CGPoint(x: (p.x + target.x) / 2 + CGFloat.random(in: -30...30), y: 95)
            let path = CGMutablePath()
            path.move(to: p)
            path.addQuadCurve(to: target, control: mid)
            c.run(.sequence([.wait(forDuration: 0.05 * Double(i)),
                             .follow(path, asOffset: false, orientToPath: false, duration: 0.55),
                             .run { flash(layer, at: target, color: gold, size: 16, duration: 0.12) },
                             .removeFromParent()]))
        }
    }

    // MARK: Text

    static func label(_ layer: SKNode, _ text: String, at p: CGPoint, color: NSColor, size: CGFloat,
                      rise: CGFloat = 16, life: Double = 0.8, pop: CGFloat = 1.25) {
        let font = NSFont.systemFont(ofSize: size, weight: .black)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        let attr = NSAttributedString(string: text, attributes: [
            .font: rounded, .foregroundColor: color,
            .strokeColor: NSColor(hex: 0x1A1020), .strokeWidth: -5,
        ])
        let l = SKLabelNode(attributedText: attr)
        l.verticalAlignmentMode = .center
        l.position = p
        l.setScale(0.3)
        layer.addChild(l)
        l.run(.sequence([
            .scale(to: pop, duration: 0.08),
            .scale(to: 1, duration: 0.08),
            .group([.moveBy(x: 0, y: rise, duration: life), .sequence([.wait(forDuration: life * 0.6),
                                                                      .fadeOut(withDuration: life * 0.4)])]),
            .removeFromParent(),
        ]))
    }
}
