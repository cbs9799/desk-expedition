import AppKit
import SpriteKit

/// Renders the battle as a side-scrolling march through the desk world.
/// The engine stays the source of truth (positions, HP, hits); this scene only *presents* it:
/// it scrolls the world between waves, animates every actor from sprite sheets, and turns
/// engine effects into high-resolution VFX timed to each attack's impact frame.
@MainActor
final class StripScene: SKScene {
    static let viewport = CGRect(x: 0, y: 0, width: StripLayout.battleWidth, height: StripLayout.height)
    static let groundY: CGFloat = 12
    /// Prop frames that don't read well standing on the ground.
    static let skipProps: [String: Set<Int>] = ["drawer": [5]]
    /// Where gold glints fly to (HUD gold counter, scene coordinates).
    static let goldTarget = CGPoint(x: StripLayout.battleWidth + 4, y: 34)

    weak var store: GameStore?
    var onOpenHQ: () -> Void = {}

    // Layers
    private let crop = SKCropNode()
    private let world = SKNode()
    private let farLayer = SKNode(), groundLayer = SKNode(), propLayer = SKNode()
    private let actorLayer = SKNode(), fxLayer = SKNode(), textLayer = SKNode()
    private let overlayFX = SKNode()   // not cropped (coins flying to the HUD)

    // World scroll
    private var scroll: CGFloat = 0
    private var speedNow: CGFloat = 0
    private var farTiles: [SKSpriteNode] = [], groundTiles: [SKSpriteNode] = []
    private var props: [(node: SKSpriteNode, worldX: CGFloat)] = []
    private var nextPropX: CGFloat = 300
    private var sceneKey = ""
    private var groundTop: CGFloat = 34
    private var hazeNode: SKNode?

    // Actors
    private var heroes: [HeroActor] = []
    private var monsters: [UUID: MonsterActor] = [:]

    // Timing
    private var lastUpdate: TimeInterval = 0
    private var clock: Double = 0          // animation clock (pauses during hitstop)
    private var realClock: Double = 0
    private var hitstopUntil: Double = 0
    private var shake: CGFloat = 0
    private var lastBattleTime: Double = 0
    private var lastEffectID = 0
    private var lastMonsterCount = 0
    private var numberStack = 0
    private var nextAnnounceAt = 0.0
    private var victoryUntil: Double = 0
    private var seenLegendary = 0
    private var seenLevelUps = [0, 0, 0]

    // MARK: Setup

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero

        let mask = SKShapeNode(rect: Self.viewport, cornerRadius: 12)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        addChild(crop)
        crop.addChild(world)
        for (z, layer) in [farLayer, groundLayer, propLayer, actorLayer, fxLayer, textLayer].enumerated() {
            layer.zPosition = CGFloat(z * 10)
            world.addChild(layer)
        }
        overlayFX.zPosition = 100
        addChild(overlayFX)

        heroes = HeroClass.allCases.enumerated().map { i, c in
            let a = HeroActor(heroClass: c, index: i)
            actorLayer.addChild(a.root)
            return a
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.1, max(0, currentTime - lastUpdate))
        lastUpdate = currentTime
        advance(dt: dt)
    }

    /// One presentation step (also driven manually by the offscreen snapshot renderer).
    func advance(dt: Double) {
        guard let store else { return }
        realClock += dt
        if realClock >= hitstopUntil { clock += dt }
        let p = store.progress, b = store.battle

        if b.time + 0.5 < lastBattleTime { resetForNewBattle() }
        lastBattleTime = b.time
        if sceneKey != p.region.scene { loadRegion(p.region) }

        updateScroll(dt: dt, battle: b)
        consumeEffects(b, progress: p)
        syncMonsters(b, progress: p)
        syncHeroes(b, progress: p, dt: dt)
        celebrations(store)
        cursorReactions()

        // Shake (only the world inside the band moves).
        if shake > 0.05 {
            world.position = CGPoint(x: CGFloat.random(in: -shake...shake), y: CGFloat.random(in: -shake...shake) * 0.6)
            shake *= pow(0.0005, CGFloat(dt))
        } else {
            world.position = .zero
            shake = 0
        }
    }

    private func resetForNewBattle() {
        for m in monsters.values { m.root.removeFromParent() }
        monsters.removeAll()
        lastEffectID = 0
        lastMonsterCount = 0
        for h in heroes { h.resetTrackers() }
    }

    // MARK: World

    private func loadRegion(_ region: Region) {
        sceneKey = region.scene
        for n in farTiles + groundTiles { n.removeFromParent() }
        farTiles = []; groundTiles = []
        for pr in props { pr.node.removeFromParent() }
        props = []
        nextPropX = scroll + 260

        func tiles(_ name: String, y: CGFloat, into layer: SKNode) -> [SKSpriteNode] {
            guard let t = Backdrop.texture(name) else { return [] }
            let w = t.size().width * PixelArt.scale
            let count = Int(ceil(Self.viewport.width / w)) + 1
            return (0..<count).map { _ in
                let n = SKSpriteNode(texture: t)
                n.anchorPoint = .zero
                n.setScale(PixelArt.scale)
                n.position = CGPoint(x: 0, y: y)
                layer.addChild(n)
                return n
            }
        }
        groundTiles = tiles("bg_\(region.scene)_ground", y: 0, into: groundLayer)
        let groundTop = (groundTiles.first?.size.height ?? 30) - 1
        self.groundTop = groundTop
        farTiles = tiles("bg_\(region.scene)_far", y: groundTop, into: farLayer)
        // Depth: dim the scenery a little so the characters pop.
        let haze = SKSpriteNode(color: NSColor(hex: 0x140C22, alpha: 0.28),
                                size: CGSize(width: Self.viewport.width, height: Self.viewport.height - groundTop))
        haze.anchorPoint = .zero
        haze.position = CGPoint(x: 0, y: groundTop)
        haze.zPosition = 5
        farLayer.addChild(haze)
        hazeNode?.removeFromParent()
        hazeNode = haze
        if farTiles.isEmpty {   // art missing → soft gradient fallback
            let n = SKSpriteNode(color: NSColor(hex: 0x2B3550), size: Self.viewport.size)
            n.anchorPoint = .zero
            farTiles = [n]; farLayer.addChild(n)
        }
    }

    private func updateScroll(dt: Double, battle b: Battle) {
        let target: CGFloat
        switch b.phase {
        case .spawning: target = 64
        case .retreating: target = 0
        case .fighting:
            let front = b.monsters.map(\.x).min() ?? 0
            target = front > Engine.frontSlotX + 40 ? 26 : 0
        }
        speedNow += (target - speedNow) * CGFloat(min(1, dt * 4))
        scroll += speedNow * CGFloat(dt)

        func wrap(_ tiles: [SKSpriteNode], factor: CGFloat) {
            guard let w = tiles.first.map({ $0.size.width }), w > 0, tiles.count > 1 else { return }
            let off = (scroll * factor).truncatingRemainder(dividingBy: w)
            for (i, n) in tiles.enumerated() {
                n.position.x = (CGFloat(i) * w - off).rounded(toPixel: 0.5)
            }
        }
        wrap(farTiles, factor: 0.3)
        wrap(groundTiles, factor: 1)

        // Foreground props stream past at ground speed.
        while nextPropX < scroll + Self.viewport.width + 80 {
            let owned = Array(store?.progress.trophies ?? [])
            if !owned.isEmpty, Double.random(in: 0..<1) < 0.22, let tsheet = SpriteSheet.named("trophies"),
               let t = owned.randomElement(), tsheet.frames.indices.contains(t) {
                let n = SKSpriteNode(texture: tsheet.frames[t])
                n.anchorPoint = tsheet.anchor
                n.setScale(PixelArt.scale)
                n.zPosition = 2
                let glint = SKSpriteNode(texture: FX.flare, size: CGSize(width: 14, height: 14))
                glint.color = FX.gold; glint.colorBlendFactor = 1; glint.blendMode = .add
                glint.position = CGPoint(x: 2, y: CGFloat(tsheet.meta.cellH) * 0.7)
                glint.setScale(1 / PixelArt.scale)
                glint.run(.repeatForever(.sequence([.fadeAlpha(to: 0.1, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
                n.addChild(glint)
                propLayer.addChild(n)
                props.append((n, nextPropX))
            } else if let sheet = SpriteSheet.named("props_\(sceneKey)") {
                let usable = (0..<sheet.frames.count).filter { !(Self.skipProps[sceneKey] ?? []).contains($0) }
                let n = SKSpriteNode(texture: sheet.frames[usable.randomElement() ?? 0])
                n.anchorPoint = sheet.anchor
                n.setScale(PixelArt.scale * CGFloat.random(in: 0.55...0.75))
                n.color = NSColor(hex: 0x2A2040)
                n.colorBlendFactor = 0.2
                n.zPosition = CGFloat.random(in: 0...1)
                propLayer.addChild(n)
                props.append((n, nextPropX))
            }
            nextPropX += CGFloat.random(in: 170...340)
        }
        props.removeAll { pr in
            let x = pr.worldX - scroll
            pr.node.position = CGPoint(x: x.rounded(toPixel: 0.5), y: groundTop - 3)
            if x < -120 { pr.node.removeFromParent(); return true }
            return false
        }
    }

    // MARK: Heroes

    private func syncHeroes(_ b: Battle, progress p: Progress, dt: Double) {
        let retreating: Bool
        if case .retreating = b.phase { retreating = true } else { retreating = false }
        let engaged = b.monsters.contains { $0.x <= Engine.frontSlotX + 6 }
        for (i, actor) in heroes.enumerated() where b.heroes.indices.contains(i) {
            let hero = b.heroes[i], hp = p.heroes[i]
            actor.apply(hero: hp)

            // Attack / skill started this tick → play the swing; VFX are timed off effects.
            if hero.lastAttackAt > actor.seenAttack || hero.lastSkillAt > actor.seenSkill {
                let skill = hero.lastSkillAt > actor.seenSkill
                actor.seenAttack = hero.lastAttackAt
                actor.seenSkill = hero.lastSkillAt
                actor.startAttack(at: clock, skill: skill)
                if skill { skillStart(i, actor: actor) }
            }
            if hero.lastHitAt > actor.seenHit {
                actor.seenHit = hero.lastHitAt
                actor.hurtUntil = clock + 0.25
                actor.flash(color: FX.blood, until: realClock + 0.12)
            }

            var x = CGFloat(Engine.heroX[i])
            if i == 0 && engaged { x += 26 }            // warrior steps up to meet the line
            let moving = speedNow > 6 && !retreating
            if moving { x += CGFloat(sin(clock * 2.2 + Double(i) * 1.7)) * 4 }
            actor.update(clock: clock, realClock: realClock, dt: dt, baseX: x, groundY: Self.groundY,
                         alive: hero.alive, speed: speedNow, victory: clock < victoryUntil, retreating: retreating,
                         hpFraction: hero.hp / hp.maxHP)
        }
    }

    private func skillStart(_ i: Int, actor: HeroActor) {
        let p = actor.handPoint
        switch heroes[i].heroClass {
        case .warrior:
            FX.flash(fxLayer, at: actor.chestPoint, color: FX.gold, size: 60, duration: 0.3)
            FX.shockwave(fxLayer, at: CGPoint(x: actor.root.position.x, y: Self.groundY + 2), color: FX.gold, radius: 36)
        case .archer:
            FX.chargeUp(fxLayer, at: p, color: FX.gold, time: 0.14, count: 10)
        case .mage:
            FX.chargeUp(fxLayer, at: p, color: FX.arcane, time: 0.16, count: 12, radius: 30)
            FX.shockwave(fxLayer, at: CGPoint(x: actor.root.position.x, y: Self.groundY + 1), color: FX.arcane,
                         radius: 30, duration: 0.5, squash: 0.3)
        }
    }

    // MARK: Monsters

    private func syncMonsters(_ b: Battle, progress p: Progress) {
        let region = p.region
        var alive = Set<UUID>()
        for m in b.monsters {
            alive.insert(m.id)
            let actor: MonsterActor
            if let a = monsters[m.id] {
                actor = a
            } else {
                let sp = Species.all[safe: m.species]
                let key = sp?.spriteKey ?? ("mon_" + (m.isBoss ? region.bossKey : region.monsterKeys[min(m.kind, 2)]))
                actor = MonsterActor(id: m.id, sheet: SpriteSheet.named(key), flyer: sp?.isFlyer ?? (m.kind == 1),
                                     boss: m.isBoss, startX: CGFloat(m.x), variant: m.variant, guest: sp?.isGuest ?? false)
                monsters[m.id] = actor
                actorLayer.addChild(actor.root)
                announce(actor)
            }
            if m.lastAttackAt > actor.seenAttack {
                actor.seenAttack = m.lastAttackAt
                actor.attackStart = clock
            }
            actor.update(clock: clock, realClock: realClock, engineX: CGFloat(m.x), groundY: Self.groundY,
                         hpFraction: m.hp / m.maxHP)
        }
        // Gone from the engine → killed (or swept away on retreat).
        var retreating = false
        if case .retreating = b.phase { retreating = true }
        for (id, actor) in monsters where !alive.contains(id) {
            monsters[id] = nil
            if retreating {
                actor.root.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            } else {
                killMonster(actor)
            }
        }
        if lastMonsterCount > 0 && b.monsters.isEmpty, case .spawning = b.phase {
            victoryUntil = clock + 0.9
        }
        lastMonsterCount = b.monsters.count
    }

    /// Rare spawns get called out so a glance at the strip catches them.
    private func announce(_ actor: MonsterActor) {
        let text: String
        let color: NSColor
        if actor.guest { text = "희귀 손님!"; color = NSColor(hex: 0x9CF4FF) }
        else if actor.variant == .shiny { text = "반짝이!"; color = FX.gold }
        else if actor.variant == .crowned { text = "왕관 몬스터!"; color = NSColor(hex: 0xFF8A6A) }
        else { return }
        let at = CGPoint(x: Self.viewport.width - 80, y: 78)
        // Queue callouts so simultaneous rare spawns read one at a time.
        let start = max(realClock + 0.4, nextAnnounceAt)
        nextAnnounceAt = start + 1.1
        after(start - realClock) { [weak self] in
            guard let self else { return }
            FX.label(self.textLayer, text, at: at, color: color, size: 14, rise: 6, life: 1.6)
            FX.flash(self.fxLayer, at: actor.centerPoint, color: color, size: 60, duration: 0.4)
        }
    }

    private func killMonster(_ actor: MonsterActor) {
        let delay = 0.16   // let the killing blow land first
        let c = actor.centerPoint
        actor.root.run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                guard let self else { return }
                actor.dying = true
                actor.flash(color: .white, until: self.realClock + 0.1)
                FX.burst(self.fxLayer, at: c, color: .white, count: 14, speed: 120, life: 0.4, size: 0.1)
                FX.burst(self.fxLayer, at: c, color: FX.gold, count: 8, speed: 80, life: 0.6, size: 0.12, angle: .pi / 2,
                         spread: 1.6, gravity: -120)
                FX.coins(self.overlayFX, from: c, to: Self.goldTarget, count: actor.boss ? 10 : 3)
                if actor.boss {
                    FX.legendary(self.fxLayer, at: CGPoint(x: c.x, y: Self.groundY))
                    FX.label(self.textLayer, "보스 처치!", at: CGPoint(x: 320, y: 70), color: FX.gold, size: 16, life: 1.6)
                    self.shake = max(self.shake, 5)
                }
            },
            .wait(forDuration: 0.35),
            .group([.fadeOut(withDuration: 0.25), .moveBy(x: 0, y: 4, duration: 0.25)]),
            .removeFromParent(),
        ]))
    }

    // MARK: Effects

    private func consumeEffects(_ b: Battle, progress p: Progress) {
        let fresh = b.effects.filter { $0.id > lastEffectID }
        guard !fresh.isEmpty else { return }
        lastEffectID = fresh.map(\.id).max() ?? lastEffectID

        // Impact delay per target x: damage numbers wait for their swing / projectile.
        var impactDelay: [Int: Double] = [:]
        for e in fresh {
            switch e.kind {
            case .slash: impactDelay[Int(e.x)] = 0.1
            case .arrow(_, let to): impactDelay[Int(to)] = 0.3
            case .bolt(_, let to): impactDelay[Int(to)] = 0.46
            case .burst: impactDelay[Int(e.x)] = 0.3
            default: break
            }
        }

        for e in fresh {
            switch e.kind {
            case .slash:
                let target = monsterPoint(nearX: e.x)
                after(0.1) { [weak self] in
                    guard let self else { return }
                    FX.slash(self.fxLayer, at: target, big: self.heroes[0].clockSkillRecent(self.clock))
                    self.hitstop(0.06); self.shake = max(self.shake, 2)
                }
            case .arrow(let from, let to):
                let start = heroes[1].handPoint
                let end = monsterPoint(nearX: to)
                _ = from
                after(0.14) { [weak self] in
                    guard let self else { return }
                    FX.arrowShot(self.fxLayer, from: start, to: end) { [weak self] in
                        guard let self else { return }
                        FX.impact(self.fxLayer, at: end, color: FX.leaf, power: 0.8)
                        self.hitstop(0.04); self.shake = max(self.shake, 1.2)
                    }
                }
            case .bolt(_, let to):
                let start = heroes[2].handPoint
                let end = monsterPoint(nearX: to)
                after(0.12) { [weak self] in
                    guard let self else { return }
                    FX.fireball(self.fxLayer, from: start, to: end) { [weak self] in
                        self?.hitstop(0.05); self?.shake = max(self?.shake ?? 0, 2.5)
                    }
                }
            case .burst:
                let target = monsterPoint(nearX: e.x)
                after(0.3) { [weak self] in
                    guard let self else { return }
                    FX.explosion(self.fxLayer, at: target, power: 1.4)
                    FX.shockwave(self.fxLayer, at: CGPoint(x: target.x, y: Self.groundY), color: FX.arcane, radius: 40)
                    self.hitstop(0.08); self.shake = max(self.shake, 4.5)
                }
            case .damage(let v, let crit):
                let key = Int(e.x)
                let delay = impactDelay[key] ?? 0.1
                let actor = monsterActor(nearX: e.x)
                after(delay) { [weak self] in
                    guard let self else { return }
                    var top = actor?.headPoint ?? CGPoint(x: e.x, y: 60)
                    top.y = min(top.y, 78)
                    actor?.hurt(clock: self.clock, realClock: self.realClock)
                    if crit {
                        FX.label(self.textLayer, "\(v)!", at: CGPoint(x: top.x + 4, y: top.y + 10), color: FX.gold,
                                 size: 16, rise: 18, life: 0.9, pop: 1.5)
                        FX.flash(self.fxLayer, at: actor?.centerPoint ?? top, color: FX.gold, size: 70)
                        self.hitstop(0.09); self.shake = max(self.shake, 3.5)
                    } else {
                        self.numberStack = (self.numberStack + 1) % 3
                        FX.label(self.textLayer, "\(v)", at: CGPoint(x: top.x + CGFloat(self.numberStack - 1) * 12,
                                                                     y: top.y + 4 + CGFloat(self.numberStack) * 7),
                                 color: .white, size: 12)
                    }
                }
            case .heroDamage(let v):
                let i = Engine.heroX.firstIndex(of: e.x) ?? 0
                let top = heroes[i].headPoint
                FX.label(textLayer, "-\(v)", at: CGPoint(x: top.x - 6, y: top.y + 6), color: NSColor(hex: 0xFF7A7A), size: 10)
                FX.burst(fxLayer, at: heroes[i].chestPoint, color: FX.blood, count: 6, speed: 70, life: 0.3, size: 0.1)
            case .text(let s):
                let i = Engine.heroX.firstIndex(of: e.x)
                let color: NSColor = i == 0 ? FX.gold : i == 1 ? FX.leaf : i == 2 ? FX.arcane : NSColor(hex: 0xFF9A9A)
                let top = i.map { heroes[$0].headPoint } ?? CGPoint(x: e.x, y: 60)
                FX.label(textLayer, s, at: CGPoint(x: top.x, y: min(88, top.y + 18)), color: color, size: 12, rise: 8, life: 1.0)
            }
        }
    }

    private func monsterActor(nearX x: Double) -> MonsterActor? {
        monsters.values.filter { !$0.dying }.min { abs($0.engineX - x) < abs($1.engineX - x) }
    }

    private func monsterPoint(nearX x: Double) -> CGPoint {
        monsterActor(nearX: x)?.centerPoint ?? CGPoint(x: x, y: Self.groundY + 20)
    }

    private func hitstop(_ t: Double) { hitstopUntil = max(hitstopUntil, realClock + t) }

    private func after(_ delay: Double, _ block: @escaping () -> Void) {
        run(.sequence([.wait(forDuration: delay), .run(block)]))
    }

    /// Desk theme after moving: multiply-tint the scenery (not the characters).
    private func applyTheme(_ theme: Int) {
        seenTheme = theme
        themeNode?.removeFromParent()
        let tint = DeskTheme.tints[theme % DeskTheme.tints.count]
        guard tint != 0xFFFFFF else { themeNode = nil; return }
        let n = SKSpriteNode(color: NSColor(hex: tint), size: Self.viewport.size)
        n.anchorPoint = .zero
        n.blendMode = .multiply
        n.zPosition = 25   // above props (20), below actors (30)
        world.addChild(n)
        themeNode = n
    }

    // MARK: Celebrations & affection

    private var seenDex = -1
    private var themeNode: SKSpriteNode?
    private var seenTheme = -1

    private func celebrations(_ store: GameStore) {
        if seenDex < 0 { seenDex = store.dexDiscoveries }
        if store.dexDiscoveries != seenDex {
            seenDex = store.dexDiscoveries
            let at = CGPoint(x: 330, y: 74)
            FX.label(textLayer, "도감 NEW! \(store.lastDexName)", at: at, color: NSColor(hex: 0x9CF4FF), size: 13, rise: 6, life: 1.8)
            FX.burst(fxLayer, at: at, color: NSColor(hex: 0x9CF4FF), count: 16, speed: 60, life: 0.8, size: 0.1)
        }
        if store.progress.theme != seenTheme { applyTheme(store.progress.theme) }
        if store.legendaryDrops != seenLegendary {
            seenLegendary = store.legendaryDrops
            FX.legendary(fxLayer, at: CGPoint(x: 300, y: Self.groundY))
            shake = max(shake, 3)
        }
        for i in 0..<min(3, store.levelUps.count) where store.levelUps[i] != seenLevelUps[i] {
            seenLevelUps[i] = store.levelUps[i]
            heroes[i].hop(at: clock)
            FX.levelUp(fxLayer, at: CGPoint(x: heroes[i].root.position.x, y: Self.groundY))
        }
    }

    /// Heroes notice the mouse cursor: wave, show their name, pop hearts. No clicks needed (works click-through).
    private func cursorReactions() {
        guard let view, let window = view.window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = view.convert(inWindow, from: nil)
        let pt = convertPoint(fromView: inView)
        for h in heroes {
            let near = abs(pt.x - h.root.position.x) < 20 && pt.y > 0 && pt.y < 80
            h.setHovered(near, clock: clock, realClock: realClock) { [weak self] in
                guard let self else { return }
                FX.hearts(self.fxLayer, at: h.headPoint)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { onOpenHQ(); return }
        let pt = event.location(in: self)
        if let h = heroes.first(where: { abs(pt.x - $0.root.position.x) < 20 && pt.y < 80 }) {
            h.hop(at: clock)
            FX.hearts(fxLayer, at: h.headPoint)
        }
    }
}

// MARK: - Actors

/// White/red "hit flash" that respects sprite alpha (premultiplied).
@MainActor
enum FlashShader {
    static let shader: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 c = texture2D(u_texture, v_tex_coord);
            vec3 rgb = c.rgb;
            if (a_hue != 0.0) {
                float ca = cos(a_hue), sa = sin(a_hue);
                vec3 r0 = vec3(0.299 + 0.701 * ca + 0.168 * sa, 0.587 - 0.587 * ca + 0.330 * sa, 0.114 - 0.114 * ca - 0.497 * sa);
                vec3 r1 = vec3(0.299 - 0.299 * ca - 0.328 * sa, 0.587 + 0.413 * ca + 0.035 * sa, 0.114 - 0.114 * ca + 0.292 * sa);
                vec3 r2 = vec3(0.299 - 0.300 * ca + 1.250 * sa, 0.587 - 0.588 * ca - 1.050 * sa, 0.114 + 0.886 * ca - 0.203 * sa);
                rgb = clamp(vec3(dot(r0, rgb), dot(r1, rgb), dot(r2, rgb)) * 1.12, 0.0, c.a);
            }
            gl_FragColor = vec4(mix(rgb, a_fc * c.a, a_flash), c.a) * v_color_mix.a;
        }
        """)
        s.attributes = [SKAttribute(name: "a_flash", type: .float), SKAttribute(name: "a_fc", type: .vectorFloat3),
                        SKAttribute(name: "a_hue", type: .float)]
        return s
    }()

    static func setHue(_ node: SKSpriteNode, _ radians: Float) {
        node.setValue(SKAttributeValue(float: radians), forAttribute: "a_hue")
    }

    static func set(_ node: SKSpriteNode, amount: Float, color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        node.setValue(SKAttributeValue(float: amount), forAttribute: "a_flash")
        node.setValue(SKAttributeValue(vectorFloat3: vector_float3(Float(c.redComponent), Float(c.greenComponent),
                                                                   Float(c.blueComponent))), forAttribute: "a_fc")
    }
}

/// Tiny pixel HP bar.
@MainActor
final class HPBar {
    let node = SKNode()
    private let back: SKSpriteNode
    private let fill: SKSpriteNode
    private let width: CGFloat

    init(width: CGFloat, color: NSColor, height: CGFloat = 3) {
        self.width = width
        back = SKSpriteNode(color: NSColor(hex: 0x120C18, alpha: 0.8), size: CGSize(width: width + 2, height: height + 2))
        back.anchorPoint = CGPoint(x: 0, y: 0.5)
        back.position = CGPoint(x: -width / 2 - 1, y: 0)
        fill = SKSpriteNode(color: color, size: CGSize(width: width, height: height))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -width / 2, y: 0)
        node.addChild(back)
        node.addChild(fill)
    }

    func set(_ f: Double) {
        fill.xScale = CGFloat(max(0, min(1, f)))
    }
}

@MainActor
final class HeroActor {
    let heroClass: HeroClass
    let index: Int
    let root = SKNode()
    private let sprite = SKSpriteNode()
    private let shadow = SKSpriteNode(texture: FX.softDot)
    private let hat = SKSpriteNode()
    private let bar = HPBar(width: 22, color: NSColor(hex: 0x6BE36F))
    private let nameLabel = SKLabelNode()
    private let sheet: SpriteSheet?

    var seenAttack = -10.0, seenSkill = -10.0, seenHit = -10.0
    var hurtUntil = 0.0
    private var attackStart = -10.0
    private var skillAt = -10.0
    private var flashUntil = 0.0, flashColor = NSColor.white
    private var jumpStart = -10.0, nextJump = 3.0
    private var waveUntil = 0.0, hoverCooldown = 0.0
    private var hovered = false
    private var heightPx = 36
    private var downSince = -1.0

    init(heroClass: HeroClass, index: Int) {
        self.heroClass = heroClass
        self.index = index
        sheet = SpriteSheet.named(heroClass.spriteKey)
        shadow.color = .black; shadow.colorBlendFactor = 1; shadow.alpha = 0.35
        shadow.size = CGSize(width: 30, height: 7)
        root.addChild(shadow)
        sprite.anchorPoint = sheet?.anchor ?? CGPoint(x: 0.5, y: 0)
        sprite.setScale(PixelArt.scale)
        sprite.shader = FlashShader.shader
        FlashShader.set(sprite, amount: 0, color: .white)
        FlashShader.setHue(sprite, 0)
        root.addChild(sprite)
        hat.anchorPoint = SpriteSheet.named("accessories")?.anchor ?? CGPoint(x: 0.5, y: 0)
        sprite.addChild(hat)
        heightPx = sheet?.height("idle") ?? 36
        bar.node.position = CGPoint(x: 0, y: CGFloat(heightPx) * PixelArt.scale + 5)
        root.addChild(bar.node)
        nameLabel.fontName = NSFont.systemFont(ofSize: 10, weight: .heavy).fontName
        nameLabel.fontSize = 10
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: CGFloat(heightPx) * PixelArt.scale + 11)
        nameLabel.alpha = 0
        root.addChild(nameLabel)
        nextJump = Double.random(in: 2...5) + Double(index)
    }

    func resetTrackers() { seenAttack = -10; seenSkill = -10; seenHit = -10 }

    private var legendGlow: SKEmitterNode?

    func apply(hero: HeroProgress) {
        let legendary = hero.weapon?.rarity == .legendary
        if legendary && legendGlow == nil {
            let e = SKEmitterNode()
            e.particleTexture = FX.softDot
            e.particleBirthRate = 14
            e.particleLifetime = 0.6
            e.particleSpeed = 14
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = 1
            e.particleScale = 0.08
            e.particleScaleSpeed = -0.1
            e.particleAlphaSpeed = -1.6
            e.particlePositionRange = CGVector(dx: 8, dy: 8)
            e.particleColor = FX.gold
            e.particleColorBlendFactor = 1
            e.particleBlendMode = .add
            e.position = CGPoint(x: 12, y: CGFloat(heightPx) * PixelArt.scale * 0.5)
            root.addChild(e)
            legendGlow = e
        } else if !legendary, let g = legendGlow {
            g.removeFromParent()
            legendGlow = nil
        }
        if nameLabel.text != hero.displayName { nameLabel.text = hero.displayName }
        let a = hero.accessory ?? 0
        if a > 0, let hats = SpriteSheet.named("accessories"), hats.frames.indices.contains(a - 1) {
            hat.texture = hats.frames[a - 1]
            hat.size = hat.texture!.size()
            hat.isHidden = false
        } else {
            hat.isHidden = true
        }
    }

    func startAttack(at clock: Double, skill: Bool) {
        attackStart = clock
        if skill { skillAt = clock }
    }
    func clockSkillRecent(_ clock: Double) -> Bool { clock - skillAt < 0.5 }
    func flash(color: NSColor, until t: Double) { flashColor = color; flashUntil = t }
    func hop(at clock: Double) { jumpStart = clock }

    var handPoint: CGPoint {
        CGPoint(x: root.position.x + 14, y: root.position.y + CGFloat(heightPx) * PixelArt.scale * 0.55)
    }
    var chestPoint: CGPoint {
        CGPoint(x: root.position.x + 4, y: root.position.y + CGFloat(heightPx) * PixelArt.scale * 0.45)
    }
    var headPoint: CGPoint {
        CGPoint(x: root.position.x, y: root.position.y + CGFloat(heightPx) * PixelArt.scale + 4)
    }

    func setHovered(_ near: Bool, clock: Double, realClock: Double, onGreet: () -> Void) {
        if near && !hovered && realClock > hoverCooldown {
            waveUntil = clock + 1.3
            hoverCooldown = realClock + 3
            onGreet()
        }
        hovered = near
    }

    func update(clock: Double, realClock: Double, dt: Double, baseX: CGFloat, groundY: CGFloat, alive: Bool,
                speed: CGFloat, victory: Bool, retreating: Bool, hpFraction: Double) {
        guard let sheet else { return }
        var frames: [SKTexture]
        var anim = "idle"
        var frameIndex = 0
        var lift: CGFloat = 0
        var x = baseX
        let moving = speed > 6

        // Random hops while marching (and on demand via hop()).
        if moving && alive && clock > nextJump {
            jumpStart = clock
            nextJump = clock + Double.random(in: 3...7)
        }
        let jt = clock - jumpStart
        if alive { downSince = -1 }

        if !alive {
            anim = "down"; frames = sheet.frames(anim)
            if downSince < 0 { downSince = clock }
            frameIndex = min(frames.count - 1, Int((clock - downSince) * 8))
        } else if clock < hurtUntil {
            anim = "hurt"; frames = sheet.frames(anim); frameIndex = Int(clock * 12)
            x -= 3
        } else if clock - attackStart < 0.34 {
            anim = "attack"; frames = sheet.frames(anim)
            frameIndex = min(frames.count - 1, Int((clock - attackStart) * 18))
            if heroClass == .warrior { x += [0, 2, 6, 8, 5, 2][min(5, frameIndex)] }
        } else if jt < 0.5 {
            anim = "jump"; frames = sheet.frames(anim)
            frameIndex = jt < 0.07 ? 0 : jt < 0.42 ? 1 : 2
            if jt >= 0.07 && jt < 0.45 {
                let f = (jt - 0.07) / 0.38
                lift = CGFloat(sin(f * .pi)) * 15
            }
        } else if victory || clock < waveUntil {
            anim = "victory"; frames = sheet.frames(anim); frameIndex = Int(clock * 5)
        } else if moving {
            anim = "walk"; frames = sheet.frames(anim); frameIndex = Int(clock * Double(7 + speed * 0.09))
        } else {
            anim = "idle"; frames = sheet.frames(anim)
            let pingPong = [0, 1, 2, 1]
            frameIndex = pingPong[Int(clock * 4) % 4]
        }
        frameIndex = frameIndex.wrapped(frames.count)
        let tex = frames[frameIndex]
        if sprite.texture !== tex {
            sprite.texture = tex
            sprite.size = CGSize(width: tex.size().width * PixelArt.scale, height: tex.size().height * PixelArt.scale)
        }
        sprite.xScale = retreating ? -PixelArt.scale : PixelArt.scale
        sprite.alpha = alive ? 1 : 0.6
        // Hats ride on the head; the frame's own height tracks crouches and jumps.
        let frameH = sheet.frameHeight(anim, frameIndex)
        hat.position = CGPoint(x: CGFloat(HatPlacement.offsetX(heroClass)),
                               y: CGFloat(frameH - HatPlacement.sink(heroClass)))
        hat.alpha = alive ? 1 : 0
        let flashing = realClock < flashUntil
        FlashShader.set(sprite, amount: flashing ? 0.85 : 0, color: flashColor)

        root.position = CGPoint(x: x.rounded(toPixel: 0.5), y: groundY)
        sprite.position = CGPoint(x: 0, y: lift.rounded(toPixel: 0.5))
        shadow.setScale(1 - lift / 40)
        shadow.position = CGPoint(x: 0, y: 1)
        bar.node.position.y = CGFloat(heightPx) * PixelArt.scale + 5 + lift
        bar.set(hpFraction)
        bar.node.alpha = alive ? 1 : 0.3
        let showName = hovered || clock < waveUntil
        nameLabel.alpha += ((showName ? 1 : 0) - nameLabel.alpha) * 0.2
        nameLabel.position.y = CGFloat(heightPx) * PixelArt.scale + 11 + lift
    }
}

@MainActor
final class MonsterActor {
    let id: UUID
    let root = SKNode()
    let boss: Bool
    private let flyer: Bool
    private let sheet: SpriteSheet?
    private let sprite = SKSpriteNode()
    private let shadow = SKSpriteNode(texture: FX.softDot)
    private let bar: HPBar
    private var x: CGFloat
    private var heightPx: Int
    private var hurtUntil = 0.0
    private var flashUntil = 0.0, flashColor = NSColor.white
    private var deadStart = 0.0
    var engineX: Double = 0
    var seenAttack = -10.0
    var attackStart = -10.0
    var dying = false {
        didSet { if dying { deadStart = lastClock } }
    }
    private var lastClock = 0.0
    private var standOff: CGFloat = 0

    let variant: MonsterVariant
    let guest: Bool

    init(id: UUID, sheet: SpriteSheet?, flyer: Bool, boss: Bool, startX: CGFloat,
         variant: MonsterVariant = .normal, guest: Bool = false) {
        self.id = id
        self.sheet = sheet
        self.flyer = flyer
        self.boss = boss
        self.variant = variant
        self.guest = guest
        self.x = startX + 40
        heightPx = sheet?.height("move") ?? 24
        let halfWidth = CGFloat(sheet?.meta.cellW ?? 30) * PixelArt.scale / 2
        standOff = max(0, halfWidth - 22)
        bar = HPBar(width: boss ? 44 : 20, color: boss ? NSColor(hex: 0xFF5050) : NSColor(hex: 0xF0A040), height: boss ? 4 : 3)
        shadow.color = .black; shadow.colorBlendFactor = 1; shadow.alpha = 0.3
        shadow.size = CGSize(width: boss ? 56 : 26, height: boss ? 10 : 6)
        root.addChild(shadow)
        sprite.anchorPoint = sheet?.anchor ?? CGPoint(x: 0.5, y: 0)
        sprite.setScale(PixelArt.scale)
        sprite.shader = FlashShader.shader
        FlashShader.set(sprite, amount: 0, color: .white)
        FlashShader.setHue(sprite, variant == .shiny ? 2.6 : 0)
        root.addChild(sprite)
        root.addChild(bar.node)
        if variant == .crowned {
            sprite.setScale(PixelArt.scale * 1.2)
            heightPx = Int(Double(heightPx) * 1.2)
            if let hats = SpriteSheet.named("accessories"), hats.frames.count > 1 {
                let crown = SKSpriteNode(texture: hats.frames[1])
                crown.anchorPoint = hats.anchor
                crown.position = CGPoint(x: 0, y: CGFloat(sheet?.height("move") ?? 20) - 3)
                sprite.addChild(crown)
            }
            let aura = FX.glow(NSColor(hex: 0xFF5A3A), size: CGFloat(heightPx) * 2.4, alpha: 0.35)
            aura.position = CGPoint(x: 0, y: CGFloat(heightPx) * 0.7)
            aura.zPosition = -1
            aura.run(.repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: 0.6), .fadeAlpha(to: 0.4, duration: 0.6)])))
            root.addChild(aura)
        }
        if variant == .shiny || guest {
            let e = SKEmitterNode()
            e.particleTexture = FX.flare
            e.particleBirthRate = 6
            e.particleLifetime = 0.7
            e.particleSize = CGSize(width: 12, height: 12)
            e.particleScaleSpeed = -1
            e.particleAlphaSpeed = -1.3
            e.particlePositionRange = CGVector(dx: 30, dy: CGFloat(heightPx) * 1.3)
            e.position = CGPoint(x: 0, y: CGFloat(heightPx) * 0.75 + (flyer ? 20 : 0))
            e.particleColor = guest ? NSColor(hex: 0x9CF4FF) : FX.gold
            e.particleColorBlendFactor = 1
            e.particleBlendMode = .add
            root.addChild(e)
        }
        root.alpha = 0
        root.run(.fadeIn(withDuration: 0.3))
    }

    private var hover: CGFloat { flyer ? 20 : 0 }

    var centerPoint: CGPoint {
        CGPoint(x: root.position.x, y: root.position.y + sprite.position.y + CGFloat(heightPx) * PixelArt.scale * 0.5)
    }
    var headPoint: CGPoint {
        CGPoint(x: root.position.x, y: root.position.y + sprite.position.y + CGFloat(heightPx) * PixelArt.scale + 6)
    }

    func hurt(clock: Double, realClock: Double) {
        hurtUntil = clock + 0.2
        flash(color: .white, until: realClock + 0.07)
    }

    func flash(color: NSColor, until t: Double) { flashColor = color; flashUntil = t }

    func update(clock: Double, realClock: Double, engineX ex: CGFloat, groundY: CGFloat, hpFraction: Double) {
        lastClock = clock
        engineX = Double(ex)
        guard let sheet else { return }
        // Smoothly follow the engine's 10 Hz positions.
        let moving = abs(ex - x) > 0.5
        x += (ex - x) * 0.25
        var frames: [SKTexture]
        var idx: Int
        var drawX = x + standOff
        if dying {
            frames = sheet.frames("dead"); idx = min(frames.count - 1, Int((clock - deadStart) * 8))
        } else if clock < hurtUntil {
            frames = sheet.frames("hurt"); idx = Int(clock * 12); drawX += 3
        } else if clock - attackStart < 0.34 {
            frames = sheet.frames("attack")
            idx = min(frames.count - 1, Int((clock - attackStart) * 12))
            drawX -= [0, 4, 8, 3][min(3, idx)]
        } else {
            frames = sheet.frames("move"); idx = Int(clock * (moving ? 8 : 4))
        }
        let tex = frames[idx.wrapped(frames.count)]
        if sprite.texture !== tex {
            sprite.texture = tex
            sprite.size = CGSize(width: tex.size().width * PixelArt.scale, height: tex.size().height * PixelArt.scale)
        }
        let bob = flyer ? CGFloat(sin(clock * 4 + Double(ex) * 0.1)) * 3 : 0
        root.position = CGPoint(x: drawX.rounded(toPixel: 0.5), y: groundY)
        sprite.position = CGPoint(x: 0, y: (hover + bob).rounded(toPixel: 0.5))
        shadow.position = CGPoint(x: 0, y: 1)
        shadow.setScale(flyer ? 0.7 : 1)
        bar.node.position = CGPoint(x: 0, y: hover + bob + CGFloat(heightPx) * PixelArt.scale + 4)
        bar.set(hpFraction)
        bar.node.isHidden = dying
        FlashShader.set(sprite, amount: realClock < flashUntil ? 1 : 0, color: flashColor)
    }
}

extension CGFloat {
    func rounded(toPixel step: CGFloat) -> CGFloat { (self / step).rounded() * step }
}

extension Int {
    /// Always-valid index into a collection of `count` (handles negatives from clock math).
    func wrapped(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let r = self % count
        return r < 0 ? r + count : r
    }
}
