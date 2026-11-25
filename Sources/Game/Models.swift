import Foundation

// MARK: - Heroes

enum HeroClass: String, Codable, CaseIterable, Identifiable {
    case warrior, archer, mage

    var id: String { rawValue }

    /// Default nickname until the player renames the hero in HQ.
    var defaultNickname: String { L10n.t(defaultNicknameKo) }
    var defaultNicknameKo: String {
        switch self {
        case .warrior: return "단추"
        case .archer: return "클립"
        case .mage: return "몽당"
        }
    }

    var spriteKey: String { "hero_\(rawValue)" }

    var name: String { L10n.t(nameKo) }
    var nameKo: String {
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

    var skillName: String { L10n.t(skillNameKo) }
    var skillNameKo: String {
        switch self {
        case .warrior: return "방패 강타"
        case .archer: return "연사"
        case .mage: return "화염 폭발"
        }
    }

    var skillDescription: String { L10n.t(skillDescriptionKo) }
    var skillDescriptionKo: String {
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

    var name: String { L10n.t(nameKo) }
    var nameKo: String {
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

    var name: String { L10n.t(self == .weapon ? "무기" : "방어구") }
}

struct Item: Codable, Identifiable, Hashable {
    var id = UUID()
    var slot: GearSlot
    var rarity: Rarity
    var name: String
    /// weapon: +ATK, armor: +HP
    var power: Int
    var regionIndex: Int
    /// Index into `Unique.names` for named legendaries.
    var unique: Int?

    var statText: String { slot == .weapon ? "공격 +\(power)" : "체력 +\(power)" }

    /// Which icon sheet/frame draws this item: named legendaries have their own art; otherwise the noun
    /// at the end of the name picks one of 6 weapon / 6 armor icons (old item names fall back by slot).
    var iconRef: (key: String, frame: Int) {
        if let u = unique { return (u < 10 ? "items_unique_a" : "items_unique_b", u % 10) }
        if slot == .weapon, let w = Gear.weapons.first(where: { name.hasSuffix($0.name) }) { return ("items_base", w.icon) }
        let nouns = slot == .weapon ? Engine.weaponNames : Engine.armorNames
        let i = nouns.firstIndex { name.hasSuffix($0) } ?? (name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % nouns.count)
        return ("items_base", (slot == .weapon ? 0 : 6) + min(i, 5))
    }

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
    /// Chosen trait option per tier (see `Traits.tiers`), -1 = not chosen.
    var traits: [Int]?

    var id: HeroClass { heroClass }
    var displayName: String {
        let n = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? heroClass.defaultNickname : n
    }

    var maxHP: Double { (heroClass.baseHP * pow(1.1, Double(level - 1)) + Double(armor?.power ?? 0)) * traitEffect.hp }
    var attack: Double { (heroClass.baseATK * pow(1.1, Double(level - 1)) + Double(weapon?.effectivePower(for: heroClass) ?? 0)) * traitEffect.atk }
    var levelUpCost: Int { Int((15 * pow(1.17, Double(level - 1))).rounded()) }

    func item(in slot: GearSlot) -> Item? { slot == .weapon ? weapon : armor }

    mutating func setItem(_ item: Item?, in slot: GearSlot) {
        if slot == .weapon { weapon = item } else { armor = item }
    }
}

// MARK: - Regions

struct Region {
    var name: String { L10n.t(ko) }
    let ko: String
    let adjective: String
    let monsterNames: [String]
    let bossName: String
    /// Art keys: `bg_<scene>`, `props_<scene>`, `mon_<key>` for [ground, flyer, heavy] and the boss.
    let scene: String
    let monsterKeys: [String]
    let bossKey: String
    let groundColor: UInt32
    /// 서랍 심층: endless floors, monsters drawn from every region, a boss every 10 floors.
    var endless = false

    static let wavesPerRegion = 10

    static let all: [Region] = [
        Region(ko: "공책 들판", adjective: "공책",
               monsterNames: ["지우개똥 슬라임", "종이학", "지우개 골렘"], bossName: "스테이플러 대왕",
               scene: "notebook", monsterKeys: ["eraser_slime", "paper_crane", "eraser_golem"], bossKey: "stapler_king",
               groundColor: 0xD9D2BE),
        Region(ko: "연필꽂이 협곡", adjective: "연필꽂이",
               monsterNames: ["연필밥 슬라임", "클립 박쥐", "몽당연필 골렘"], bossName: "연필깎이 거인",
               scene: "pencilcup", monsterKeys: ["shaving_slime", "clip_bat", "stub_golem"], bossKey: "sharpener_giant",
               groundColor: 0xA0703F),
        Region(ko: "머그컵 늪", adjective: "머그컵",
               monsterNames: ["커피 방울 슬라임", "티백 유령", "각설탕 골렘"], bossName: "머그컵 문어",
               scene: "mug", monsterKeys: ["coffee_slime", "teabag_ghost", "sugar_golem"], bossKey: "mug_octopus",
               groundColor: 0x6B4A33),
        Region(ko: "화분 정글", adjective: "화분",
               monsterNames: ["이끼 슬라임", "민들레 씨 요정", "선인장 골렘"], bossName: "다육이 왕",
               scene: "planter", monsterKeys: ["moss_slime", "dandelion_sprite", "cactus_golem"], bossKey: "succulent_king",
               groundColor: 0x5A4030),
        Region(ko: "모니터 성채", adjective: "모니터",
               monsterNames: ["먼지 토끼", "커서 유령", "키캡 골렘"], bossName: "무선 마우스 용",
               scene: "monitor", monsterKeys: ["dust_bunny", "cursor_ghost", "keycap_golem"], bossKey: "mouse_dragon",
               groundColor: 0x2E3550),
        Region(ko: "서랍 심층", adjective: "서랍",
               monsterNames: ["심층 슬라임", "심층 비행체", "심층 골렘"], bossName: "심층의 메아리",
               scene: "drawer", monsterKeys: ["eraser_slime", "paper_crane", "eraser_golem"], bossKey: "stapler_king",
               groundColor: 0x3A2E28, endless: true),
    ]

    static let endlessIndex = 5
    static let storyRegions = 5

    static func monsterHP(region: Int, wave: Int) -> Double {
        if region >= endlessIndex { return 28 * pow(2.6, 4) * 2.2 * pow(1.075, Double(wave - 1)) }
        return 28 * pow(2.6, Double(region)) * (1 + 0.12 * Double(wave - 1))
    }

    static func monsterATK(region: Int, wave: Int) -> Double {
        if region >= endlessIndex { return 4 * pow(2.4, 4) * 2.0 * pow(1.06, Double(wave - 1)) }
        return 4 * pow(2.4, Double(region)) * (1 + 0.1 * Double(wave - 1))
    }

    static func gold(region: Int, wave: Int) -> Double {
        if region >= endlessIndex { return 2 * pow(2.2, 4) * 1.8 * pow(1.05, Double(wave - 1)) }
        return 2 * pow(2.2, Double(region)) * (1 + 0.05 * Double(wave - 1))
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
    /// Wave 1–10 in story regions; the floor number in 서랍 심층.
    var wave: Int = 1
    var totalKills: Int = 0
    var bossKills: Int = 0
    var bagFullNotified: Bool = false
    var lastActive: Date = Date()

    // Long-term collection (kept across moves).
    var dex: [String: DexEntry] = [:]
    var journal: [JournalPage] = []
    var trophies: Set<Int> = []
    var uniquesFound: Set<Int> = []
    var bestFloor: Int = 0
    var memories: Int = 0
    var moves: Int = 0
    var wipes: Int = 0
    // Current run only.
    var runBestFloor: Int = 0
    // 0.2.7 systems
    var tactic: Tactic = .balanced
    var shinyPity: Int = 0
    var legendaryPity: Int = 0
    var shards: Int = 0
    var weekKey: String = ""
    var weekKills: Int = 0
    var weekClaimed: Bool = false
    var aiDiary: [DiaryEntry] = []
    var aiDiarySeen: Int = 0
    // 0.2.17
    var wallKey: Int = -1
    var wallWipes: Int = 0
    var farmCap: Int = 0          // > 0: hold at this wave/floor and farm instead of hitting the wall
    var farmClears: Int = 0
    var weekTier: Int = 0         // weekly goals claimed this week
    var accessoryMask: Int = 0    // unlocked accessories already announced
    // 0.2.18
    var runBestAt: Date?          // when this run first reached runBestFloor (stall detection)
    var wallTotalWipes: Int = 0   // wipes at the current wall, NOT reset by level-ups
    var wallSince: Date?          // first wipe at the current wall

    var region: Region { Region.all[regionIndex] }
    var isEndless: Bool { region.endless }
    var isBossWave: Bool { isEndless ? wave % Region.wavesPerRegion == 0 : wave >= Region.wavesPerRegion }
    var bagIsFull: Bool { bag.count >= Progress.bagCapacity }
    /// "웨이브 3/10" or "심층 27층".
    var stageText: String {
        (isEndless ? "심층 \(wave)층" : "웨이브 \(wave)/\(Region.wavesPerRegion)") + (farmCap > 0 ? " · 파밍" : "")
    }
    /// Wave pips position (1…10) — in 서랍 심층 the distance to the next boss floor.
    var pipWave: Int { isEndless ? (wave - 1) % Region.wavesPerRegion + 1 : wave }
    var theme: Int { moves % DeskTheme.names.count }

    init() {}

    // Every key is optional so saves from older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Progress()
        heroes = try c.decodeIfPresent([HeroProgress].self, forKey: .heroes) ?? d.heroes
        gold = try c.decodeIfPresent(Int.self, forKey: .gold) ?? 0
        bag = try c.decodeIfPresent([Item].self, forKey: .bag) ?? []
        regionIndex = try c.decodeIfPresent(Int.self, forKey: .regionIndex) ?? 0
        unlockedRegion = try c.decodeIfPresent(Int.self, forKey: .unlockedRegion) ?? 0
        wave = try c.decodeIfPresent(Int.self, forKey: .wave) ?? 1
        totalKills = try c.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        bossKills = try c.decodeIfPresent(Int.self, forKey: .bossKills) ?? 0
        bagFullNotified = try c.decodeIfPresent(Bool.self, forKey: .bagFullNotified) ?? false
        lastActive = try c.decodeIfPresent(Date.self, forKey: .lastActive) ?? Date()
        dex = try c.decodeIfPresent([String: DexEntry].self, forKey: .dex) ?? [:]
        journal = try c.decodeIfPresent([JournalPage].self, forKey: .journal) ?? []
        trophies = try c.decodeIfPresent(Set<Int>.self, forKey: .trophies) ?? []
        uniquesFound = try c.decodeIfPresent(Set<Int>.self, forKey: .uniquesFound) ?? []
        bestFloor = try c.decodeIfPresent(Int.self, forKey: .bestFloor) ?? 0
        memories = try c.decodeIfPresent(Int.self, forKey: .memories) ?? 0
        moves = try c.decodeIfPresent(Int.self, forKey: .moves) ?? 0
        wipes = try c.decodeIfPresent(Int.self, forKey: .wipes) ?? 0
        runBestFloor = try c.decodeIfPresent(Int.self, forKey: .runBestFloor) ?? 0
        tactic = try c.decodeIfPresent(Tactic.self, forKey: .tactic) ?? .balanced
        shinyPity = try c.decodeIfPresent(Int.self, forKey: .shinyPity) ?? 0
        legendaryPity = try c.decodeIfPresent(Int.self, forKey: .legendaryPity) ?? 0
        shards = try c.decodeIfPresent(Int.self, forKey: .shards) ?? 0
        weekKey = try c.decodeIfPresent(String.self, forKey: .weekKey) ?? ""
        weekKills = try c.decodeIfPresent(Int.self, forKey: .weekKills) ?? 0
        weekClaimed = try c.decodeIfPresent(Bool.self, forKey: .weekClaimed) ?? false
        aiDiary = try c.decodeIfPresent([DiaryEntry].self, forKey: .aiDiary) ?? []
        aiDiarySeen = try c.decodeIfPresent(Int.self, forKey: .aiDiarySeen) ?? 0
        wallKey = try c.decodeIfPresent(Int.self, forKey: .wallKey) ?? -1
        wallWipes = try c.decodeIfPresent(Int.self, forKey: .wallWipes) ?? 0
        farmCap = try c.decodeIfPresent(Int.self, forKey: .farmCap) ?? 0
        farmClears = try c.decodeIfPresent(Int.self, forKey: .farmClears) ?? 0
        weekTier = try c.decodeIfPresent(Int.self, forKey: .weekTier) ?? (weekClaimed ? 1 : 0)
        accessoryMask = try c.decodeIfPresent(Int.self, forKey: .accessoryMask) ?? 0
        runBestAt = try c.decodeIfPresent(Date.self, forKey: .runBestAt)
        wallTotalWipes = try c.decodeIfPresent(Int.self, forKey: .wallTotalWipes) ?? 0
        wallSince = try c.decodeIfPresent(Date.self, forKey: .wallSince)
        regionIndex = min(max(0, regionIndex), Region.all.count - 1)
        unlockedRegion = min(max(0, unlockedRegion), Region.all.count - 1)
    }
}

// MARK: - Cosmetics

enum Accessory {
    /// Index 0 is "none"; 1… map to frames of the `accessories` sheet.
    static let all = ["없음", "리본", "왕관", "꽃", "고깔", "새싹", "별"]
}
