import Foundation

// MARK: - Heroes

enum HeroClass: String, Codable, CaseIterable, Identifiable {
    case warrior, archer, mage

    var id: String { rawValue }

    /// Default nickname until the player renames the hero in HQ.
    var defaultNickname: String {
        switch self {
        case .warrior: return "단추"
        case .archer: return "클립"
        case .mage: return "몽당"
        }
    }

    var spriteKey: String { "hero_\(rawValue)" }

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
    /// Player-chosen nickname (nil → class default). Optional so older saves still decode.
    var nickname: String?
    /// Index into `Accessory.all` (nil/0 → none).
    var accessory: Int?

    var id: HeroClass { heroClass }
    var displayName: String {
        let n = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? heroClass.defaultNickname : n
    }

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
    /// Art keys: `bg_<scene>`, `props_<scene>`, `mon_<key>` for [ground, flyer, heavy] and the boss.
    let scene: String
    let monsterKeys: [String]
    let bossKey: String
    let groundColor: UInt32

    static let wavesPerRegion = 10

    static let all: [Region] = [
        Region(name: "공책 들판", adjective: "공책",
               monsterNames: ["지우개똥 슬라임", "종이학", "지우개 골렘"], bossName: "스테이플러 대왕",
               scene: "notebook", monsterKeys: ["eraser_slime", "paper_crane", "eraser_golem"], bossKey: "stapler_king",
               groundColor: 0xD9D2BE),
        Region(name: "연필꽂이 협곡", adjective: "연필꽂이",
               monsterNames: ["연필밥 슬라임", "클립 박쥐", "몽당연필 골렘"], bossName: "연필깎이 거인",
               scene: "pencilcup", monsterKeys: ["shaving_slime", "clip_bat", "stub_golem"], bossKey: "sharpener_giant",
               groundColor: 0xA0703F),
        Region(name: "머그컵 늪", adjective: "머그컵",
               monsterNames: ["커피 방울 슬라임", "티백 유령", "각설탕 골렘"], bossName: "머그컵 문어",
               scene: "mug", monsterKeys: ["coffee_slime", "teabag_ghost", "sugar_golem"], bossKey: "mug_octopus",
               groundColor: 0x6B4A33),
        Region(name: "화분 정글", adjective: "화분",
               monsterNames: ["이끼 슬라임", "민들레 씨 요정", "선인장 골렘"], bossName: "다육이 왕",
               scene: "planter", monsterKeys: ["moss_slime", "dandelion_sprite", "cactus_golem"], bossKey: "succulent_king",
               groundColor: 0x5A4030),
        Region(name: "모니터 성채", adjective: "모니터",
               monsterNames: ["먼지 토끼", "커서 유령", "키캡 골렘"], bossName: "무선 마우스 용",
               scene: "monitor", monsterKeys: ["dust_bunny", "cursor_ghost", "keycap_golem"], bossKey: "mouse_dragon",
               groundColor: 0x2E3550),
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

// MARK: - Cosmetics

enum Accessory {
    /// Index 0 is "none"; 1… map to frames of the `accessories` sheet.
    static let all = ["없음", "리본", "왕관", "꽃", "고깔", "새싹", "별"]
}
