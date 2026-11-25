import Foundation

// MARK: - Class weapons (#6)

enum Gear {
    /// Weapon nouns and which class they belong to; icon frame in `items_base`.
    static let weapons: [(name: String, cls: HeroClass, icon: Int)] = [
        ("바늘 검", .warrior, 0), ("압정 창", .archer, 1), ("클립 활", .archer, 2), ("크레용 지팡이", .mage, 3),
        ("커터 단검", .warrior, 4), ("자 몽둥이", .warrior, 5), ("형광펜 지팡이", .mage, 3),
    ]
    /// Unique legendaries: slot and (for weapons) class.
    static let uniqueInfo: [(slot: GearSlot, cls: HeroClass?)] = [
        (.weapon, .warrior), (.weapon, .archer), (.weapon, .mage), (.armor, nil), (.weapon, .archer),
        (.armor, nil), (.weapon, .archer), (.weapon, .mage), (.weapon, .archer), (.weapon, .warrior),
        (.weapon, .mage), (.armor, nil), (.weapon, .archer), (.weapon, .warrior), (.armor, nil),
        (.weapon, .warrior), (.weapon, .warrior), (.armor, nil), (.armor, nil), (.armor, nil),
    ]
    /// A weapon in the wrong hands works at half strength.
    static let offClassFactor = 0.5
}

extension Item {
    /// The class a weapon is made for (nil = anyone: armor, or unknown old items).
    var affinity: HeroClass? {
        guard slot == .weapon else { return nil }
        if let u = unique { return Gear.uniqueInfo[safe: u]?.cls }
        return Gear.weapons.first { name.hasSuffix($0.name) }?.cls
    }

    func fits(_ c: HeroClass) -> Bool { affinity == nil || affinity == c }

    /// Stat this item gives a hero of class `c`.
    func effectivePower(for c: HeroClass) -> Int {
        fits(c) ? power : Int((Double(power) * Gear.offClassFactor).rounded())
    }

    func effectiveScore(for c: HeroClass) -> Double {
        slot == .weapon ? Double(effectivePower(for: c)) : Double(power) / 5
    }

    var classTag: String? { affinity.map { L10n.t("\($0.nameKo) 전용") } }
}

// MARK: - Walls (#1)

enum Wall {
    /// Wipes at the same stage before the party drops back to farm.
    static let wipesToFarm = 3
    /// Farm clears before automatically trying the wall again.
    static let retryAfterClears = 40

    static func key(_ p: Progress) -> Int { p.regionIndex * 100_000 + p.wave }
}

// MARK: - Dex mastery & region sets (#2)

enum Mastery {
    static let tiers = [10, 100, 1_000, 10_000]

    /// Total kills of a species across all its variants.
    static func kills(_ sp: Species, _ p: Progress) -> Int {
        sp.variants.reduce(0) { $0 + (p.dex[Dex.key(sp.id, $1)]?.count ?? 0) }
    }

    static func stars(_ sp: Species, _ p: Progress) -> Int { tiers.filter { kills(sp, p) >= $0 }.count }
    static func totalStars(_ p: Progress) -> Int { Species.all.reduce(0) { $0 + stars($1, p) } }
    static var maxStars: Int { Species.all.count * tiers.count }

    /// Region fully recorded (every species, every variant).
    static func regionComplete(_ r: Int, _ p: Progress) -> Bool {
        Species.all.filter { $0.region == r }.allSatisfy { sp in sp.variants.allSatisfy { p.dex[Dex.key(sp.id, $0)] != nil } }
    }
    static func completedRegions(_ p: Progress) -> Int { (0..<Region.storyRegions).filter { regionComplete($0, p) }.count }

    /// +0.1% gold per mastery star.
    static func goldBonus(_ p: Progress) -> Double { cached(p).gold }
    /// +3% attack per completed region set.
    static func attackBonus(_ p: Progress) -> Double { cached(p).attack }

    // Stars and sets change rarely; recomputing them every tick made offline settlement slow.
    // Recalculate when a new dex entry appears or every 200 kills.
    private struct Cache { var key = (-1, -1); var gold = 1.0; var attack = 1.0 }
    nonisolated(unsafe) private static var cache = Cache()
    private static let lock = NSLock()

    private static func cached(_ p: Progress) -> (gold: Double, attack: Double) {
        let key = (p.dex.count, p.totalKills / 200)
        lock.lock(); defer { lock.unlock() }
        if cache.key != key {
            cache = Cache(key: key, gold: 1 + 0.001 * Double(totalStars(p)), attack: 1 + 0.03 * Double(completedRegions(p)))
        }
        return (cache.gold, cache.attack)
    }
}

// MARK: - Weekly tiers (#7)

enum WeeklyGoal {
    static let goals = [600, 3_000, 10_000, 30_000]
    static let rewards = [1, 1, 2, 3]
    static func next(_ p: Progress) -> Int? { goals[safe: p.weekTier] }
}

// MARK: - Accessory unlocks (#8)

extension Accessory {
    /// Unlock rule per accessory index (0 = none, always available).
    static func unlocked(_ i: Int, _ p: Progress) -> Bool {
        switch i {
        case 2: return p.bossKills >= 10
        case 3: return p.dex.count >= 20
        case 4: return p.heroes.contains { $0.level >= 25 }
        case 6: return p.bestFloor >= 50
        default: return true
        }
    }

    static func rule(_ i: Int) -> String {
        switch i {
        case 2: return L10n.t("보스 10회 처치")
        case 3: return L10n.t("도감 20칸")
        case 4: return L10n.t("영웅 Lv.25")
        case 6: return L10n.t("심층 50층")
        default: return L10n.t("기본")
        }
    }

    static func mask(_ p: Progress) -> Int { all.indices.reduce(0) { unlocked($1, p) ? $0 | (1 << $1) : $0 } }
}

// MARK: - Move leftovers (#3)

extension Move {
    /// Leftover gold turns into memories: +1 at 100k, then +1 per doubling.
    static func goldMemories(_ gold: Int) -> Int {
        guard gold >= 100_000 else { return 0 }
        return Int(log2(Double(gold) / 100_000)) + 1
    }
}

// MARK: - Trait picks by captain style (#9)

enum TraitPick {
    /// Which option (0/1) fits a captain style best.
    static func choose(_ c: HeroClass, tier: Int, style: AIStyle) -> Int {
        let (a, b) = Traits.options(c, tier: tier)
        func score(_ e: TraitEffect) -> Double {
            switch style {
            case .steady: return (e.hp - 1) * 2 + (1 - e.damageTaken) * 2 + e.lifesteal * 3 + (e.atk - 1)
            case .aggressive: return (e.atk - 1) * 2 + e.crit * 2 + (1 - e.cooldown) * 1.5
            case .collector: return (e.gold - 1) * 3 + (e.atk - 1) + (1 - e.cooldown)
            }
        }
        return score(b.effect) > score(a.effect) ? 1 : 0
    }
}
