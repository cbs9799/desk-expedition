import Foundation

// MARK: - Transient battle state (not persisted)

struct HeroCombat {
    var hp: Double
    var attackTimer: Double
    var skillTimer: Double
    var lastAttackAt: Double = -10
    var lastSkillAt: Double = -10
    var lastHitAt: Double = -10

    var alive: Bool { hp > 0 }
}

struct Monster: Identifiable {
    let id = UUID()
    var kind: Int
    var name: String
    var maxHP: Double
    var hp: Double
    var atk: Double
    var x: Double
    var isBoss: Bool
    var attackTimer: Double
    var lastAttackAt: Double = -10
    var lastHitAt: Double = -10
}

struct Effect {
    enum Kind {
        case damage(Int, crit: Bool)
        case heroDamage(Int)
        case text(String)
        case arrow(fromX: Double, toX: Double)
        case bolt(fromX: Double, toX: Double)
        case burst
        case slash
    }

    var kind: Kind
    var x: Double
    var born: Double
    var id: Int = 0
}

enum BattlePhase {
    case spawning(until: Double)
    case fighting
    case retreating(until: Double)
}

struct Battle {
    var time: Double = 0
    var heroes: [HeroCombat]
    var monsters: [Monster] = []
    var effects: [Effect] = [] {
        didSet { stampEffects(from: oldValue.count) }
    }
    var phase: BattlePhase = .spawning(until: 1.2)
    private(set) var nextEffectID = 1

    private mutating func stampEffects(from start: Int) {
        guard start < effects.count else { return }
        for i in start..<effects.count where effects[i].id == 0 {
            effects[i].id = nextEffectID
            nextEffectID += 1
        }
    }
}

/// What happened during one or more ticks — the store turns this into banners/notifications.
struct TickReport {
    var kills = 0
    var goldGained = 0
    var drops: [Item] = []
    var autoSold = 0
    var bossesDefeated: [String] = []
    var regionUnlocked: Int?
    var wipes = 0
    var bagBecameFull = false

    mutating func merge(_ other: TickReport) {
        kills += other.kills
        goldGained += other.goldGained
        drops += other.drops
        autoSold += other.autoSold
        bossesDefeated += other.bossesDefeated
        if let r = other.regionUnlocked { regionUnlocked = r }
        wipes += other.wipes
        bagBecameFull = bagBecameFull || other.bagBecameFull
    }
}

struct OfflineReport: Equatable {
    var seconds: Double
    var kills: Int
    var gold: Int
    var items: Int
    var autoSold: Int
    var bosses: Int

    var durationText: String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(max(m, 1))분"
    }
}

// MARK: - Engine

enum Engine {
    /// World x positions (points) — indexed like HeroClass.allCases (warrior, archer, mage).
    static let heroX: [Double] = [190, 140, 90]
    static let frontSlotX = 250.0
    static let slotSpacing = 46.0
    static let spawnX = 580.0
    static let monsterSpeed = 90.0
    static let attackRange = 500.0
    static let maxOfflineSeconds = 12.0 * 3600
    static let effectLifetime = 1.2
    /// Time between waves — the party marches forward while the world scrolls.
    static let marchSeconds = 2.4

    static func newBattle(for p: Progress) -> Battle {
        Battle(heroes: p.heroes.map { h in
            HeroCombat(hp: h.maxHP, attackTimer: h.heroClass.attackInterval * 0.5,
                       skillTimer: h.heroClass.skillCooldown * 0.6)
        })
    }

    static func tick<R: RandomNumberGenerator>(_ p: inout Progress, _ b: inout Battle, dt: Double,
                                               rng: inout R, effects: Bool = true) -> TickReport {
        var report = TickReport()
        b.time += dt

        switch b.phase {
        case .spawning(let until):
            if b.time >= until {
                spawnWave(p, &b, rng: &rng)
                b.phase = .fighting
            }
        case .retreating(let until):
            if b.time >= until {
                for i in b.heroes.indices { b.heroes[i].hp = p.heroes[i].maxHP }
                b.phase = .spawning(until: b.time + 0.5)
            }
        case .fighting:
            fight(&p, &b, dt: dt, rng: &rng, report: &report, effects: effects)
        }

        // Slow regeneration (1% max HP / s) for living heroes.
        for i in b.heroes.indices where b.heroes[i].alive {
            b.heroes[i].hp = min(p.heroes[i].maxHP, b.heroes[i].hp + p.heroes[i].maxHP * 0.01 * dt)
        }

        if effects {
            let now = b.time
            b.effects.removeAll { now - $0.born > effectLifetime }
        } else if !b.effects.isEmpty {
            b.effects.removeAll()
        }
        return report
    }

    // MARK: Waves

    static func spawnWave<R: RandomNumberGenerator>(_ p: Progress, _ b: inout Battle, rng: inout R) {
        let r = p.regionIndex, w = p.wave
        let region = p.region
        var list: [Monster] = []
        let hp = Region.monsterHP(region: r, wave: w)
        let atk = Region.monsterATK(region: r, wave: w)
        if p.isBossWave {
            list.append(Monster(kind: 2, name: region.bossName, maxHP: hp * 10, hp: hp * 10, atk: atk * 2.2,
                                x: spawnX, isBoss: true, attackTimer: 1.8))
            for i in 0..<2 {
                let k = Int.random(in: 0..<2, using: &rng)
                list.append(Monster(kind: k, name: region.monsterNames[k], maxHP: hp, hp: hp, atk: atk,
                                    x: spawnX + slotSpacing * Double(i + 1) + 20, isBoss: false, attackTimer: 1.5))
            }
        } else {
            let count = Int.random(in: 2...4, using: &rng)
            for i in 0..<count {
                let k = Int.random(in: 0..<3, using: &rng)
                let mhp = hp * (k == 2 ? 1.4 : 1.0)
                list.append(Monster(kind: k, name: region.monsterNames[k], maxHP: mhp, hp: mhp, atk: atk,
                                    x: spawnX + slotSpacing * Double(i), isBoss: false,
                                    attackTimer: Double.random(in: 0.8...1.6, using: &rng)))
            }
        }
        b.monsters = list
    }

    // MARK: Fight

    static func fight<R: RandomNumberGenerator>(_ p: inout Progress, _ b: inout Battle, dt: Double, rng: inout R,
                                                report: inout TickReport, effects: Bool) {
        // 1. Monsters walk to their queue slot.
        for i in b.monsters.indices {
            let target = frontSlotX + slotSpacing * Double(i)
            b.monsters[i].x = max(target, b.monsters[i].x - monsterSpeed * dt)
        }

        // 2. Heroes act.
        for hi in b.heroes.indices where b.heroes[hi].alive {
            b.heroes[hi].attackTimer -= dt
            b.heroes[hi].skillTimer -= dt
            let inRange = b.monsters.indices.filter { b.monsters[$0].x <= attackRange && b.monsters[$0].hp > 0 }
            guard let front = inRange.first else { continue }
            let cls = p.heroes[hi].heroClass
            let atk = p.heroes[hi].attack
            let engaged = b.monsters[front].x <= frontSlotX + 2
            if cls == .warrior && !engaged { continue }

            if b.heroes[hi].skillTimer <= 0 {
                b.heroes[hi].skillTimer = cls.skillCooldown
                b.heroes[hi].lastSkillAt = b.time
                b.heroes[hi].attackTimer = max(b.heroes[hi].attackTimer, cls.attackInterval * 0.5)
                switch cls {
                case .warrior:
                    hit(front, atk * 3, &b, rng: &rng, effects: effects)
                    if effects { b.effects.append(Effect(kind: .text(cls.skillName), x: heroX[hi], born: b.time)) }
                case .archer:
                    for _ in 0..<3 {
                        let t = inRange.randomElement(using: &rng)!
                        if effects { b.effects.append(Effect(kind: .arrow(fromX: heroX[hi], toX: b.monsters[t].x), x: heroX[hi], born: b.time)) }
                        hit(t, atk, &b, rng: &rng, effects: effects)
                    }
                    if effects { b.effects.append(Effect(kind: .text(cls.skillName), x: heroX[hi], born: b.time)) }
                case .mage:
                    for t in inRange {
                        hit(t, atk * 1.5, &b, rng: &rng, effects: effects)
                        if effects { b.effects.append(Effect(kind: .burst, x: b.monsters[t].x, born: b.time)) }
                    }
                    if effects { b.effects.append(Effect(kind: .text(cls.skillName), x: heroX[hi], born: b.time)) }
                }
            } else if b.heroes[hi].attackTimer <= 0 {
                b.heroes[hi].attackTimer = cls.attackInterval
                b.heroes[hi].lastAttackAt = b.time
                if effects {
                    switch cls {
                    case .warrior: b.effects.append(Effect(kind: .slash, x: b.monsters[front].x, born: b.time))
                    case .archer: b.effects.append(Effect(kind: .arrow(fromX: heroX[hi], toX: b.monsters[front].x), x: heroX[hi], born: b.time))
                    case .mage: b.effects.append(Effect(kind: .bolt(fromX: heroX[hi], toX: b.monsters[front].x), x: heroX[hi], born: b.time))
                    }
                }
                hit(front, atk, &b, rng: &rng, effects: effects)
            }
        }

        // 3. Remove the dead, pay rewards.
        var survivors: [Monster] = []
        survivors.reserveCapacity(b.monsters.count)
        for m in b.monsters {
            if m.hp > 0 { survivors.append(m); continue }
            reward(for: m, &p, rng: &rng, report: &report)
        }
        b.monsters = survivors

        // 4. Monsters act (only the first three in the queue reach the party).
        for mi in b.monsters.indices.prefix(3) {
            let target = frontSlotX + slotSpacing * Double(mi)
            guard b.monsters[mi].x <= target + 1 else { continue }
            b.monsters[mi].attackTimer -= dt
            guard b.monsters[mi].attackTimer <= 0 else { continue }
            b.monsters[mi].attackTimer = b.monsters[mi].isBoss ? 1.8 : 1.5
            b.monsters[mi].lastAttackAt = b.time
            guard let victim = b.heroes.indices.first(where: { b.heroes[$0].alive }) else { break }
            let dmg = b.monsters[mi].atk * Double.random(in: 0.85...1.15, using: &rng)
            b.heroes[victim].hp -= dmg
            b.heroes[victim].lastHitAt = b.time
            if effects { b.effects.append(Effect(kind: .heroDamage(Int(dmg.rounded())), x: heroX[victim], born: b.time)) }
        }

        // 5. Party wiped → retreat a few waves.
        if !b.heroes.contains(where: { $0.alive }) {
            report.wipes += 1
            p.wave = max(1, p.wave - 3)
            b.monsters.removeAll()
            b.phase = .retreating(until: b.time + 3)
            if effects { b.effects.append(Effect(kind: .text("후퇴!"), x: heroX[1], born: b.time)) }
            return
        }

        // 6. Wave cleared.
        if b.monsters.isEmpty {
            if p.isBossWave {
                p.bossKills += 1
                report.bossesDefeated.append(p.region.bossName)
                if p.regionIndex == p.unlockedRegion && p.unlockedRegion < Region.all.count - 1 {
                    p.unlockedRegion += 1
                    p.regionIndex = p.unlockedRegion
                    report.regionUnlocked = p.unlockedRegion
                }
                p.wave = 1
            } else {
                p.wave += 1
            }
            for i in b.heroes.indices {
                let maxHP = p.heroes[i].maxHP
                b.heroes[i].hp = min(maxHP, max(b.heroes[i].hp, 0) + maxHP * 0.25)
            }
            b.phase = .spawning(until: b.time + Engine.marchSeconds)
        }
    }

    static func hit<R: RandomNumberGenerator>(_ index: Int, _ base: Double, _ b: inout Battle, rng: inout R, effects: Bool) {
        guard b.monsters.indices.contains(index), b.monsters[index].hp > 0 else { return }
        let crit = Double.random(in: 0..<1, using: &rng) < 0.1
        let dmg = base * Double.random(in: 0.9...1.1, using: &rng) * (crit ? 2 : 1)
        b.monsters[index].hp -= dmg
        b.monsters[index].lastHitAt = b.time
        if effects {
            b.effects.append(Effect(kind: .damage(Int(dmg.rounded()), crit: crit), x: b.monsters[index].x, born: b.time))
        }
    }

    // MARK: Rewards & loot

    static func reward<R: RandomNumberGenerator>(for m: Monster, _ p: inout Progress, rng: inout R, report: inout TickReport) {
        p.totalKills += 1
        report.kills += 1
        let g = Int((Region.gold(region: p.regionIndex, wave: p.wave) * (m.isBoss ? 12 : 1)).rounded())
        p.gold += g
        report.goldGained += g

        let dropChance = m.isBoss ? 1.0 : 0.16
        guard Double.random(in: 0..<1, using: &rng) < dropChance else { return }
        let item = makeItem(region: p.regionIndex, boss: m.isBoss, rng: &rng)
        if p.bag.count < Progress.bagCapacity {
            p.bag.append(item)
            report.drops.append(item)
            if p.bag.count >= Progress.bagCapacity && !p.bagFullNotified {
                p.bagFullNotified = true
                report.bagBecameFull = true
            }
        } else {
            let half = max(1, item.sellValue / 2)
            p.gold += half
            report.goldGained += half
            report.autoSold += 1
        }
    }

    static func rollRarity<R: RandomNumberGenerator>(boss: Bool, rng: inout R) -> Rarity {
        let roll = Double.random(in: 0..<1, using: &rng)
        if boss {
            return roll < 0.5 ? .uncommon : roll < 0.88 ? .rare : .legendary
        }
        return roll < 0.70 ? .common : roll < 0.92 ? .uncommon : roll < 0.99 ? .rare : .legendary
    }

    static let weaponNames = ["바늘 검", "압정 창", "클립 활", "크레용 지팡이", "커터 단검", "자 몽둥이"]
    static let armorNames = ["골무 투구", "병뚜껑 방패", "포스트잇 망토", "지우개 갑옷", "단추 방패", "실타래 로브"]

    static func makeItem<R: RandomNumberGenerator>(region: Int, boss: Bool, rng: inout R) -> Item {
        let slot: GearSlot = Bool.random(using: &rng) ? .weapon : .armor
        let rarity = rollRarity(boss: boss, rng: &rng)
        let base = Region.gearBase(region: region, slot: slot)
        let power = max(1, Int((base * rarity.multiplier * Double.random(in: 0.85...1.15, using: &rng)).rounded()))
        let noun = (slot == .weapon ? weaponNames : armorNames).randomElement(using: &rng)!
        return Item(slot: slot, rarity: rarity, name: "\(Region.all[region].adjective) \(noun)",
                    power: power, regionIndex: region)
    }

    // MARK: Offline

    /// Simulates the time the player was away (capped) with a coarse step and no visual effects.
    static func settleOffline<R: RandomNumberGenerator>(_ p: inout Progress, seconds: Double, rng: inout R) -> OfflineReport {
        let duration = min(max(0, seconds), maxOfflineSeconds)
        var b = newBattle(for: p)
        var total = TickReport()
        let dt = 0.5
        var elapsed = 0.0
        while elapsed < duration {
            total.merge(tick(&p, &b, dt: dt, rng: &rng, effects: false))
            elapsed += dt
        }
        return OfflineReport(seconds: duration, kills: total.kills, gold: total.goldGained,
                             items: total.drops.count, autoSold: total.autoSold, bosses: total.bossesDefeated.count)
    }
}

/// Deterministic RNG for tests & snapshots.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
