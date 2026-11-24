import Foundation

// MARK: - Hero traits (영웅 특성: Lv 10 / 25 / 50에서 둘 중 하나)

struct TraitEffect {
    var atk = 1.0, hp = 1.0, crit = 0.0, cooldown = 1.0, lifesteal = 0.0, gold = 1.0, damageTaken = 1.0
}

struct Trait {
    let ko: String
    let descKo: String
    var name: String { L10n.t(ko) }
    var desc: String { L10n.t(descKo) }
    let effect: TraitEffect
}

enum Traits {
    static let tiers = [10, 25, 50]

    /// [class][tier] = (option A, option B)
    static func options(_ c: HeroClass, tier: Int) -> (Trait, Trait) {
        table[c]![tier]
    }

    private static let table: [HeroClass: [(Trait, Trait)]] = [
        .warrior: [
            (Trait(ko: "강철 골무", descKo: "체력 +25%", effect: .init(hp: 1.25)),
             Trait(ko: "날 선 바늘", descKo: "공격력 +20%", effect: .init(atk: 1.2))),
            (Trait(ko: "방패 반사", descKo: "받는 피해 -20%", effect: .init(damageTaken: 0.8)),
             Trait(ko: "돌진", descKo: "스킬 대기 -25%", effect: .init(cooldown: 0.75))),
            (Trait(ko: "수호자", descKo: "체력 +40%, 받는 피해 -15%", effect: .init(hp: 1.4, damageTaken: 0.85)),
             Trait(ko: "광전사", descKo: "공격력 +35%, 피해의 5% 회복", effect: .init(atk: 1.35, lifesteal: 0.05))),
        ],
        .archer: [
            (Trait(ko: "매의 눈", descKo: "치명타 +10%", effect: .init(crit: 0.1)),
             Trait(ko: "긴 클립", descKo: "공격력 +20%", effect: .init(atk: 1.2))),
            (Trait(ko: "속사", descKo: "스킬 대기 -30%", effect: .init(cooldown: 0.7)),
             Trait(ko: "보물 사냥꾼", descKo: "골드 +20%", effect: .init(gold: 1.2))),
            (Trait(ko: "저격", descKo: "치명타 +15%, 공격력 +15%", effect: .init(atk: 1.15, crit: 0.15)),
             Trait(ko: "바람의 화살", descKo: "스킬 대기 -40%", effect: .init(cooldown: 0.6))),
        ],
        .mage: [
            (Trait(ko: "불씨", descKo: "공격력 +20%", effect: .init(atk: 1.2)),
             Trait(ko: "지혜의 안경", descKo: "스킬 대기 -20%", effect: .init(cooldown: 0.8))),
            (Trait(ko: "화염 정령", descKo: "공격력 +25%", effect: .init(atk: 1.25)),
             Trait(ko: "마나 흡수", descKo: "피해의 8% 회복", effect: .init(lifesteal: 0.08))),
            (Trait(ko: "대폭발", descKo: "공격력 +45%", effect: .init(atk: 1.45)),
             Trait(ko: "시간 왜곡", descKo: "스킬 대기 -45%", effect: .init(cooldown: 0.55))),
        ],
    ]
}

extension HeroProgress {
    /// Chosen option (0/1) per tier, nil = not chosen yet.
    func trait(tier: Int) -> Int? {
        guard let t = traits, t.indices.contains(tier), t[tier] >= 0 else { return nil }
        return t[tier]
    }

    /// First unlocked tier still waiting for a choice.
    var pendingTraitTier: Int? {
        Traits.tiers.indices.first { level >= Traits.tiers[$0] && trait(tier: $0) == nil }
    }

    var traitEffect: TraitEffect {
        var e = TraitEffect()
        for tier in Traits.tiers.indices {
            guard let pick = trait(tier: tier) else { continue }
            let (a, b) = Traits.options(heroClass, tier: tier)
            let x = (pick == 0 ? a : b).effect
            e.atk *= x.atk; e.hp *= x.hp; e.crit += x.crit; e.cooldown *= x.cooldown
            e.lifesteal += x.lifesteal; e.gold *= x.gold; e.damageTaken *= x.damageTaken
        }
        return e
    }

    var chosenTraitNames: [String] {
        Traits.tiers.indices.compactMap { tier in
            trait(tier: tier).map { pick in
                let (a, b) = Traits.options(heroClass, tier: tier)
                return (pick == 0 ? a : b).name
            }
        }
    }
}

// MARK: - Tactics (원정 전술)

enum Tactic: Int, CaseIterable, Codable {
    case balanced, charge, careful, treasure

    var name: String { L10n.t(["균형", "돌격", "신중", "보물 찾기"][rawValue]) }
    var icon: String { ["⚖️", "⚔️", "🛡️", "💰"][rawValue] }
    var desc: String {
        L10n.t(["기본", "공격 +25%, 받는 피해 +25%, 행군 빠름", "공격 -10%, 받는 피해 -30%", "골드 +40%·드롭 +50%, 공격 -15%"][rawValue])
    }
    var atk: Double { [1, 1.25, 0.9, 0.85][rawValue] }
    var damageTaken: Double { [1, 1.25, 0.7, 1][rawValue] }
    var gold: Double { [1, 1, 1, 1.4][rawValue] }
    var drops: Double { [1, 1, 1, 1.5][rawValue] }
    var march: Double { [1, 0.7, 1.1, 1][rawValue] }
}

// MARK: - Weekly expedition rule (주간 원정 조건)

enum WeeklyRule: Int, CaseIterable {
    case arcane, wings, giants, sparkle, haste, hoard

    var name: String { L10n.t(["마법 주간", "날개 주간", "거인 주간", "반짝이 주간", "속공 주간", "보물 주간"][rawValue]) }
    var desc: String { L10n.t(descKo) }
    var descKo: String {
        [
            "마법사 피해 ×2, 궁수 피해 ×0.6",
            "날아다니는 몬스터만 나와요 · 골드 +20%",
            "골렘만 나와요 · 적 체력 +30% · 골드 +50%",
            "반짝이·왕관 몬스터 3배",
            "행군이 짧고 적이 빨라요 · 골드 +30%",
            "드롭 2배 · 적 체력 +50%",
        ][rawValue]
    }

    static func current(_ date: Date = Date()) -> WeeklyRule {
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
        let year = Calendar(identifier: .iso8601).component(.yearForWeekOfYear, from: date)
        return WeeklyRule(rawValue: (week + year) % allCases.count)!
    }

    static func weekKey(_ date: Date = Date()) -> String {
        let c = Calendar(identifier: .iso8601)
        return "\(c.component(.yearForWeekOfYear, from: date))-W\(c.component(.weekOfYear, from: date))"
    }

    /// Weekly goal: kills during this week → 추억 조각 +1.
    static let goalKills = 600

    func heroAttack(_ c: HeroClass) -> Double {
        guard self == .arcane else { return 1 }
        return c == .mage ? 2 : c == .archer ? 0.6 : 1
    }
    var enemyHP: Double { self == .giants ? 1.3 : self == .hoard ? 1.5 : 1 }
    var gold: Double { [1, 1.2, 1.5, 1, 1.3, 1][rawValue] }
    var drops: Double { self == .hoard ? 2 : 1 }
    var variantBoost: Double { self == .sparkle ? 3 : 1 }
    var march: Double { self == .haste ? 0.6 : 1 }
    var enemyAttackSpeed: Double { self == .haste ? 0.8 : 1 }
    /// Restricts which monster kinds spawn (nil = any).
    var onlyKind: Int? { self == .wings ? 1 : self == .giants ? 2 : nil }
}

// MARK: - Pity & shards (천장과 도감 조각)

enum Pity {
    /// A shiny is guaranteed after this many regular spawns without one.
    static let shinySpawns = 600
    /// A legendary is guaranteed after this many drops without one.
    static let legendaryDrops = 250
    /// Shards from meeting an already-recorded special variant again.
    static func shards(for v: MonsterVariant, guest: Bool) -> Int { guest ? 2 : v == .shiny ? 3 : v == .crowned ? 1 : 0 }
    /// Exchange price: a legendary of the chosen slot.
    static let legendaryPrice = 30
}

// MARK: - Companions (동행 펫·수레)

enum Companion: Int, CaseIterable {
    case cat, hamster, bird

    var name: String { L10n.t(["고양이 털실", "햄스터 땅콩", "파랑새 잉크"][rawValue]) }
    var anim: String { ["cat", "hamster", "bird"][rawValue] }
    var unlockText: String { L10n.t(["도감 10칸", "트로피 3개", "첫 이사"][rawValue]) }

    func unlocked(_ p: Progress) -> Bool {
        switch self {
        case .cat: return p.dex.count >= 10
        case .hamster: return p.trophies.count >= 3
        case .bird: return p.moves >= 1
        }
    }
}

enum Camp {
    /// The loot cart trailing the party appears after a few boss kills.
    static func hasCart(_ p: Progress) -> Bool { p.bossKills >= 3 }
}

// MARK: - AI captain style (원정대장 성향)

enum AIStyle: Int, CaseIterable {
    case steady, aggressive, collector

    var name: String { L10n.t(["안정형", "공격형", "수집형"][rawValue]) }
    var guide: String {
        [
            "전멸을 피하는 게 최우선. 체력·방어 특성, 신중 전술, 레벨 차이를 고르게.",
            "빠른 진행이 최우선. 공격 특성, 돌격 전술, 가장 먼 지역과 심층 기록 갱신.",
            "도감·희귀 수집이 최우선. 보물 찾기 전술, 도감 빈칸이 있는 지역 파밍, 조각으로 전설 교환.",
        ][rawValue]
    }
}

struct DiaryEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}
