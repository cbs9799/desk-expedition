import Foundation

// MARK: - Heroes

enum HeroClass: String, Codable, CaseIterable, Identifiable {
    case warrior, archer, mage

    var id: String { rawValue }

    var name: String {
        switch self {
        case .warrior: return "전사"
        case .archer: return "궁수"
        case .mage: return "마법사"
        }
    }

    var baseHP: Double {
        switch self {
        case .warrior: return 130
        case .archer: return 80
        case .mage: return 70
        }
    }

    var baseATK: Double {
        switch self {
        case .warrior: return 8
        case .archer: return 9
        case .mage: return 12
        }
    }

    /// Seconds between basic attacks.
    var attackInterval: Double {
        switch self {
        case .warrior: return 1.2
        case .archer: return 0.9
        case .mage: return 1.6
        }
    }

    var skillName: String {
        switch self {
        case .warrior: return "방패 강타"
        case .archer: return "연사"
        case .mage: return "화염 폭발"
        }
    }

    var skillDescription: String {
        switch self {
        case .warrior: return "맨 앞 적에게 공격력 300% 피해"
        case .archer: return "화살 3발을 무작위 적에게 발사"
        case .mage: return "사거리 안 모든 적에게 150% 피해"
        }
    }

    var skillCooldown: Double {
        switch self {
        case .warrior: return 7
        case .archer: return 6
        case .mage: return 9
        }
    }
}

// MARK: - Items

enum Rarity: Int, Codable, CaseIterable, Comparable {
    case common, uncommon, rare, legendary

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .common: return "일반"
        case .uncommon: return "고급"
        case .rare: return "희귀"
        case .legendary: return "전설"
        }
    }

    var multiplier: Double {
        switch self {
        case .common: return 1.0
        case .uncommon: return 1.5
        case .rare: return 2.2
        case .legendary: return 3.2
        }
    }

    /// 0xRRGGBB
    var colorHex: UInt32 {
        switch self {
        case .common: return 0xB9C0C8
        case .uncommon: return 0x5FD36A
        case .rare: return 0x4FA3FF
        case .legendary: return 0xFFB13B
        }
    }
}

enum GearSlot: String, Codable, CaseIterable {
    case weapon, armor

    var name: String { self == .weapon ? "무기" : "방어구" }
}

struct Item: Codable, Identifiable, Hashable {
    var id = UUID()
    var slot: GearSlot
    var rarity: Rarity
    var name: String
    /// weapon: +ATK, armor: +HP
    var power: Int
    var regionIndex: Int

    var statText: String { slot == .weapon ? "공격 +\(power)" : "체력 +\(power)" }

    /// Rough "goodness" score used for comparisons and auto-equip.
    var score: Double { slot == .weapon ? Double(power) : Double(power) / 5 }

    var sellValue: Int {
        let base = slot == .weapon ? Double(power) * 2 : Double(power) * 0.4
        return max(1, Int((base * (1 + Double(rarity.rawValue) * 0.5)).rounded()))
    }
}

struct HeroProgress: Codable, Identifiable, Equatable {
    var heroClass: HeroClass
    var level: Int = 1
    var weapon: Item?
    var armor: Item?

    var id: HeroClass { heroClass }

    var maxHP: Double { heroClass.baseHP * pow(1.1, Double(level - 1)) + Double(armor?.power ?? 0) }
    var attack: Double { heroClass.baseATK * pow(1.1, Double(level - 1)) + Double(weapon?.power ?? 0) }
    var levelUpCost: Int { Int((15 * pow(1.17, Double(level - 1))).rounded()) }

    func item(in slot: GearSlot) -> Item? { slot == .weapon ? weapon : armor }

    mutating func setItem(_ item: Item?, in slot: GearSlot) {
        if slot == .weapon { weapon = item } else { armor = item }
    }
}

// MARK: - Regions

struct Region {
    let name: String
    let adjective: String
    let monsterNames: [String]
    let bossName: String
    let monsterColor: UInt32
    let monsterDark: UInt32
    let groundColor: UInt32

    static let wavesPerRegion = 10

    static let all: [Region] = [
        Region(name: "속삭이는 숲", adjective: "숲의",
               monsterNames: ["초록 슬라임", "숲 박쥐", "이끼 골렘"], bossName: "거대 버섯왕",
               monsterColor: 0x5BBF5A, monsterDark: 0x2F7A35, groundColor: 0x3E6B35),
        Region(name: "모래바람 협곡", adjective: "사막의",
               monsterNames: ["모래 슬라임", "협곡 독수리", "사암 골렘"], bossName: "모래 전갈 여왕",
               monsterColor: 0xE0B65A, monsterDark: 0x9C7430, groundColor: 0xA07B45),
        Region(name: "얼음 동굴", adjective: "서리",
               monsterNames: ["얼음 슬라임", "눈 박쥐", "서리 골렘"], bossName: "빙하의 거인",
               monsterColor: 0x8FD8F0, monsterDark: 0x3E8BB0, groundColor: 0x5D8BA6),
        Region(name: "잿빛 화산", adjective: "불꽃",
               monsterNames: ["용암 슬라임", "화염 박쥐", "흑요석 골렘"], bossName: "용암 군주",
               monsterColor: 0xF06A3A, monsterDark: 0x9E2E1B, groundColor: 0x5A3A34),
        Region(name: "별빛 성채", adjective: "별빛",
               monsterNames: ["별 슬라임", "유령 박쥐", "성채 수호자"], bossName: "별을 삼킨 기사",
               monsterColor: 0xB79CF5, monsterDark: 0x6448B0, groundColor: 0x3E3566),
    ]

    static func monsterHP(region: Int, wave: Int) -> Double {
        28 * pow(2.6, Double(region)) * (1 + 0.12 * Double(wave - 1))
    }

    static func monsterATK(region: Int, wave: Int) -> Double {
        4 * pow(2.4, Double(region)) * (1 + 0.1 * Double(wave - 1))
    }

    static func gold(region: Int, wave: Int) -> Double {
        2 * pow(2.2, Double(region)) * (1 + 0.05 * Double(wave - 1))
    }

    static func gearBase(region: Int, slot: GearSlot) -> Double {
        (slot == .weapon ? 3 : 15) * pow(2.6, Double(region))
    }
}

// MARK: - Persistent progress

struct Progress: Codable, Equatable {
    static let bagCapacity = 24

    var heroes: [HeroProgress] = HeroClass.allCases.map { HeroProgress(heroClass: $0) }
    var gold: Int = 0
    var bag: [Item] = []
    var regionIndex: Int = 0
    var unlockedRegion: Int = 0
    var wave: Int = 1
    var totalKills: Int = 0
    var bossKills: Int = 0
    var bagFullNotified: Bool = false
    var lastActive: Date = Date()

    var region: Region { Region.all[regionIndex] }
    var isBossWave: Bool { wave >= Region.wavesPerRegion }
    var bagIsFull: Bool { bag.count >= Progress.bagCapacity }
}
