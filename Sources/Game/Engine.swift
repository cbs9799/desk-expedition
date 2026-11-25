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
    /// Index into `Species.all` (drives sprite + dex entry).
    var species: Int = 0
    var variant: MonsterVariant = .normal

    var isGuest: Bool { Species.all[safe: species]?.isGuest ?? false }
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
    var newDex: [String] = []
    var journalPages: [String] = []
    var trophies: [Int] = []
    var weeklyGoal = false
    var wallHit: String?
    var wallRetry = false

    mutating func merge(_ other: TickReport) {
        kills += other.kills
        goldGained += other.goldGained
        drops += other.drops
        autoSold += other.autoSold
        bossesDefeated += other.bossesDefeated
        if let r = other.regionUnlocked { regionUnlocked = r }
        wipes += other.wipes
        bagBecameFull = bagBecameFull || other.bagBecameFull
        newDex += other.newDex
        journalPages += other.journalPages
        trophies += other.trophies
        weeklyGoal = weeklyGoal || other.weeklyGoal
        if let w = other.wallHit { wallHit = w }
        wallRetry = wallRetry || other.wallRetry
    }
}

struct OfflineReport: Equatable {
    var seconds: Double
    var kills: Int
    var gold: Int
    var items: Int
    var autoSold: Int
    var bosses: Int
    var newDex: Int = 0
    var pages: Int = 0

    var durationText: String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if L10n.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(max(m, 1))m" }
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
                spawnWave(&p, &b, rng: &rng)
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

    static func spawnWave<R: RandomNumberGenerator>(_ p: inout Progress, _ b: inout Battle, rng: inout R) {
        let r = p.regionIndex, w = p.wave
        var list: [Monster] = []
        let week = WeeklyRule.current()
        let hp = Region.monsterHP(region: r, wave: w) * week.enemyHP
        let atk = Region.monsterATK(region: r, wave: w)
        let endless = p.isEndless
        // Story regions use their own species; 서랍 심층 draws from every region.
        func speciesRegion() -> Int { endless ? Int.random(in: 0..<Region.storyRegions, using: &rng) : r }
        var pity = p.shinyPity
        func roll() -> MonsterVariant {
            pity += 1
            if pity >= Pity.shinySpawns { pity = 0; return .shiny }   // 천장: guaranteed shiny
            let x = Double.random(in: 0..<1, using: &rng)
            let shiny = MonsterVariant.shinyChance * week.variantBoost
            let crowned = MonsterVariant.crownedChance * week.variantBoost
            if x < shiny { pity = 0; return .shiny }
            return x < shiny + crowned ? .crowned : .normal
        }
        func kind() -> Int { week.onlyKind ?? Int.random(in: 0..<3, using: &rng) }
        func make(_ sp: Species, variant: MonsterVariant, hpMul: Double, atkMul: Double, x: Double, timer: Double) -> Monster {
            let mhp = hp * hpMul * (variant == .crowned ? 3 : 1)
            var m = Monster(kind: min(sp.kind, 2), name: variant == .normal ? sp.name : "\(variant.label) \(sp.name)",
                            maxHP: mhp, hp: mhp, atk: atk * atkMul * (variant == .crowned ? 1.5 : 1), x: x,
                            isBoss: sp.isBoss, attackTimer: timer)
            m.species = sp.id
            m.variant = variant
            return m
        }

        if p.isBossWave {
            let boss = Species.of(region: speciesRegion(), kind: 3)
            let v: MonsterVariant = Double.random(in: 0..<1, using: &rng) < MonsterVariant.bossShinyChance ? .shiny : .normal
            var m = make(boss, variant: v, hpMul: 10, atkMul: 2.2, x: spawnX, timer: 1.8)
            if p.isEndless { m.name = "\(boss.name)의 메아리" }
            list.append(m)
            for i in 0..<2 {
                let sp = Species.of(region: speciesRegion(), kind: week.onlyKind ?? Int.random(in: 0..<2, using: &rng))
                list.append(make(sp, variant: roll(), hpMul: 1, atkMul: 1, x: spawnX + slotSpacing * Double(i + 1) + 20, timer: 1.5))
            }
        } else {
            let count = Int.random(in: 2...4, using: &rng)
            for i in 0..<count {
                let k = kind()
                let sp = Species.of(region: speciesRegion(), kind: k)
                list.append(make(sp, variant: roll(), hpMul: k == 2 ? 1.4 : 1, atkMul: 1,
                                 x: spawnX + slotSpacing * Double(i), timer: Double.random(in: 0.8...1.6, using: &rng)))
            }
            if Double.random(in: 0..<1, using: &rng) < MonsterVariant.guestChancePerWave {
                let guest = Species.of(region: speciesRegion(), kind: 4)
                list.append(make(guest, variant: .normal, hpMul: 2, atkMul: 0.5,
                                 x: spawnX + slotSpacing * Double(count), timer: 2.0))
            }
        }
        b.monsters = list
        p.shinyPity = pity
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
        let week = WeeklyRule.current()
        let setAttack = Mastery.attackBonus(p)
        for hi in b.heroes.indices where b.heroes[hi].alive {
            let te = p.heroes[hi].traitEffect
            let critChance = 0.1 + te.crit
            var dealt = 0.0
            b.heroes[hi].attackTimer -= dt
            b.heroes[hi].skillTimer -= dt
            let inRange = b.monsters.indices.filter { b.monsters[$0].x <= attackRange && b.monsters[$0].hp > 0 }
            guard let front = inRange.first else { continue }
            let cls = p.heroes[hi].heroClass
            let atk = p.heroes[hi].attack * Move.bonus(p) * p.tactic.atk * week.heroAttack(cls) * setAttack
            let engaged = b.monsters[front].x <= frontSlotX + 2
            if cls == .warrior && !engaged { continue }

            if b.heroes[hi].skillTimer <= 0 {
                b.heroes[hi].skillTimer = cls.skillCooldown * te.cooldown
                b.heroes[hi].lastSkillAt = b.time
                b.heroes[hi].attackTimer = max(b.heroes[hi].attackTimer, cls.attackInterval * 0.5)
                switch cls {
                case .warrior:
                    dealt += hit(front, atk * 3, &b, rng: &rng, effects: effects, crit: critChance)
                    if effects { b.effects.append(Effect(kind: .text(cls.skillName), x: heroX[hi], born: b.time)) }
                case .archer:
                    for _ in 0..<3 {
                        let t = inRange.randomElement(using: &rng)!
                        if effects { b.effects.append(Effect(kind: .arrow(fromX: heroX[hi], toX: b.monsters[t].x), x: heroX[hi], born: b.time)) }
                        dealt += hit(t, atk, &b, rng: &rng, effects: effects, crit: critChance)
                    }
                    if effects { b.effects.append(Effect(kind: .text(cls.skillName), x: heroX[hi], born: b.time)) }
                case .mage:
                    for t in inRange {
                        dealt += hit(t, atk * 1.5, &b, rng: &rng, effects: effects, crit: critChance)
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
                dealt += hit(front, atk, &b, rng: &rng, effects: effects, crit: critChance)
            }
            if te.lifesteal > 0, dealt > 0 {
                b.heroes[hi].hp = min(p.heroes[hi].maxHP, b.heroes[hi].hp + dealt * te.lifesteal)
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
            b.monsters[mi].attackTimer = (b.monsters[mi].isBoss ? 1.8 : 1.5) * week.enemyAttackSpeed
            b.monsters[mi].lastAttackAt = b.time
            guard let victim = b.heroes.indices.first(where: { b.heroes[$0].alive }) else { break }
            let dmg = b.monsters[mi].atk * Double.random(in: 0.85...1.15, using: &rng)
                * p.heroes[victim].traitEffect.damageTaken * p.tactic.damageTaken
            b.heroes[victim].hp -= dmg
            b.heroes[victim].lastHitAt = b.time
            if effects { b.effects.append(Effect(kind: .heroDamage(Int(dmg.rounded())), x: heroX[victim], born: b.time)) }
        }

        // 5. Party wiped → retreat a few waves.
        if !b.heroes.contains(where: { $0.alive }) {
            report.wipes += 1
            p.wipes += 1
            let wallAt = Wall.key(p), stage = p.stageText
            if p.wallKey == wallAt { p.wallWipes += 1 } else { p.wallKey = wallAt; p.wallWipes = 1 }
            Journal.unlock("first_wipe", in: &p, report: &report)
            p.wave = max(1, p.wave - 3)
            if p.wallWipes >= Wall.wipesToFarm && p.farmCap == 0 {
                p.farmCap = p.wave            // hold a few stages below the wall and farm
                p.farmClears = 0
                report.wallHit = stage
            }
            b.monsters.removeAll()
            b.phase = .retreating(until: b.time + 3)
            if effects { b.effects.append(Effect(kind: .text("후퇴!"), x: heroX[1], born: b.time)) }
            return
        }

        // 6. Wave cleared.
        if b.monsters.isEmpty {
            if p.farmCap > 0 && p.wave >= p.farmCap && !p.isBossWave {
                p.farmClears += 1
                if p.farmClears >= Wall.retryAfterClears { p.farmCap = 0; p.wallWipes = 0; report.wallRetry = true }
                for i in b.heroes.indices {
                    let maxHP = p.heroes[i].maxHP
                    b.heroes[i].hp = min(maxHP, max(b.heroes[i].hp, 0) + maxHP * 0.25)
                }
                b.phase = .spawning(until: b.time + Engine.marchSeconds * p.tactic.march * week.march)
                return
            }
            if p.isEndless {
                if p.isBossWave {
                    p.bossKills += 1
                    report.bossesDefeated.append("심층 \(p.wave)층 보스")
                }
                p.bestFloor = max(p.bestFloor, p.wave)
                p.runBestFloor = max(p.runBestFloor, p.wave)
                for f in [10, 20, 30, 50, 100] where p.wave >= f { Journal.unlock("floor\(f)", in: &p, report: &report) }
                if p.wave >= 30, !p.trophies.contains(5) { p.trophies.insert(5); report.trophies.append(5) }
                p.wave += 1
            } else if p.isBossWave {
                p.bossKills += 1
                report.bossesDefeated.append(p.region.bossName)
                let r = p.regionIndex
                if !p.trophies.contains(r) { p.trophies.insert(r); report.trophies.append(r) }
                Journal.unlock("boss\(r)", in: &p, report: &report)
                if p.regionIndex == p.unlockedRegion && p.unlockedRegion < Region.all.count - 1 {
                    p.unlockedRegion += 1
                    p.regionIndex = p.unlockedRegion
                    report.regionUnlocked = p.unlockedRegion
                    Journal.unlock("region\(p.unlockedRegion)", in: &p, report: &report)
                }
                p.wave = 1
            } else {
                p.wave += 1
            }
            for i in b.heroes.indices {
                let maxHP = p.heroes[i].maxHP
                b.heroes[i].hp = min(maxHP, max(b.heroes[i].hp, 0) + maxHP * 0.25)
            }
            b.phase = .spawning(until: b.time + Engine.marchSeconds * p.tactic.march * week.march)
        }
    }

    @discardableResult
    static func hit<R: RandomNumberGenerator>(_ index: Int, _ base: Double, _ b: inout Battle, rng: inout R, effects: Bool,
                                              crit critChance: Double = 0.1) -> Double {
        guard b.monsters.indices.contains(index), b.monsters[index].hp > 0 else { return 0 }
        let crit = Double.random(in: 0..<1, using: &rng) < critChance
        let dmg = base * Double.random(in: 0.9...1.1, using: &rng) * (crit ? 2 : 1)
        b.monsters[index].hp -= dmg
        b.monsters[index].lastHitAt = b.time
        if effects {
            b.effects.append(Effect(kind: .damage(Int(dmg.rounded()), crit: crit), x: b.monsters[index].x, born: b.time))
        }
        return dmg
    }

    // MARK: Rewards & loot

    static func reward<R: RandomNumberGenerator>(for m: Monster, _ p: inout Progress, rng: inout R, report: inout TickReport) {
        p.totalKills += 1
        report.kills += 1
        record(m, &p, report: &report)
        let week = WeeklyRule.current()
        let wk = WeeklyRule.weekKey()
        if p.weekKey != wk { p.weekKey = wk; p.weekKills = 0; p.weekClaimed = false; p.weekTier = 0 }
        p.weekKills += 1
        while let goal = WeeklyGoal.next(p), p.weekKills >= goal {
            p.memories += WeeklyGoal.rewards[p.weekTier]
            p.weekTier += 1
            p.weekClaimed = true
            report.weeklyGoal = true
        }
        let traitGold = p.heroes.reduce(1.0) { $0 * $1.traitEffect.gold }
        let variantGold = m.isGuest ? 15.0 : m.variant == .crowned ? 5 : m.variant == .shiny ? 3 : 1
        let g = Int((Region.gold(region: p.regionIndex, wave: p.wave) * (m.isBoss ? 12 : 1) * variantGold
                     * Dex.goldBonus(p) * Mastery.goldBonus(p) * Move.bonus(p) * p.tactic.gold * week.gold * traitGold).rounded())
        p.gold += g
        report.goldGained += g

        let baseDrop = m.isBoss || m.isGuest ? 1.0 : m.variant == .normal ? 0.16 : 0.6
        let dropChance = min(1, baseDrop * p.tactic.drops * week.drops)
        guard Double.random(in: 0..<1, using: &rng) < dropChance else { return }
        p.legendaryPity += 1
        let force = p.legendaryPity >= Pity.legendaryDrops
        let item = makeItem(region: p.regionIndex, boss: m.isBoss || m.isGuest, floor: p.isEndless ? p.wave : 0,
                            forceLegendary: force, rng: &rng)
        if item.rarity == .legendary { p.legendaryPity = 0 }
        if item.rarity == .legendary {
            Journal.unlock("first_legendary", in: &p, report: &report)
            if let u = item.unique {
                p.uniquesFound.insert(u)
                Journal.unlock("first_unique", in: &p, report: &report)
            }
        }
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

    /// Writes the kill into the 책상 도감 and unlocks the matching journal pages.
    static func record(_ m: Monster, _ p: inout Progress, report: inout TickReport) {
        let key = Dex.key(m.species, m.variant)
        if var e = p.dex[key] {
            e.count += 1
            p.dex[key] = e
            p.shards += Pity.shards(for: m.variant, guest: m.isGuest)
            return
        }
        p.dex[key] = DexEntry(count: 1, first: Date())
        let name = Species.all[safe: m.species]?.name ?? m.name
        report.newDex.append(m.variant == .normal ? name : "\(m.variant.label) \(name)")
        if m.variant == .shiny { Journal.unlock("first_shiny", in: &p, report: &report) }
        if m.variant == .crowned { Journal.unlock("first_crowned", in: &p, report: &report) }
        if m.isGuest { Journal.unlock("first_guest", in: &p, report: &report) }
        for n in Dex.milestones where p.dex.count >= n { Journal.unlock("dex\(n)", in: &p, report: &report) }
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

    static func makeItem<R: RandomNumberGenerator>(region: Int, boss: Bool, floor: Int = 0, forceLegendary: Bool = false,
                                                   slot forcedSlot: GearSlot? = nil, rng: inout R) -> Item {
        let slot: GearSlot = forcedSlot ?? (Bool.random(using: &rng) ? .weapon : .armor)
        let rarity = forceLegendary ? .legendary : rollRarity(boss: boss, rng: &rng)
        let base = Region.gearBase(region: min(region, Region.storyRegions), slot: slot) * pow(1.04, Double(floor))
        var power = max(1, Int((base * rarity.multiplier * Double.random(in: 0.85...1.15, using: &rng)).rounded()))
        let noun = slot == .weapon ? Gear.weapons.randomElement(using: &rng)!.name : armorNames.randomElement(using: &rng)!
        var item = Item(slot: slot, rarity: rarity, name: "\(Region.all[region].adjective) \(noun)",
                        power: power, regionIndex: region)
        if rarity == .legendary, Double.random(in: 0..<1, using: &rng) < Unique.chance,
           let u = Gear.uniqueInfo.indices.filter({ Gear.uniqueInfo[$0].slot == slot }).randomElement(using: &rng) {
            power = Int((Double(power) * 1.25).rounded())
            item.power = power
            item.unique = u
            item.name = Unique.names[u]
        }
        return item
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
                             items: total.drops.count, autoSold: total.autoSold, bosses: total.bossesDefeated.count,
                             newDex: total.newDex.count, pages: total.journalPages.count)
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
