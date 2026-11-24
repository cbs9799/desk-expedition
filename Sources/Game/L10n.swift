import Foundation

/// Runtime translation for strings built in code (region/monster/class names, banners).
/// SwiftUI literals use the String Catalog; this covers the rest. Korean is the source language.
enum L10n {
    static let isEnglish: Bool = {
        let pref = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "ko"
        return !pref.hasPrefix("ko")
    }()

    static func t(_ ko: String) -> String {
        guard isEnglish else { return ko }
        if let exact = en[ko] { return exact }
        // Translate known words inside longer strings (e.g. "연필꽂이 협곡 · 웨이브 3/10").
        var out = ko
        for (k, v) in en.sorted(by: { $0.key.count > $1.key.count }) where out.contains(k) {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }

    static let en: [String: String] = [
        // skills, traits, tactics, weekly
        "맨 앞 적에게 공격력 300% 피해": "300% damage to the front enemy",
        "화살 3발을 무작위 적에게 발사": "Fires 3 arrows at random enemies",
        "사거리 안 모든 적에게 150% 피해": "150% damage to every enemy in range",
        "강철 골무": "Steel Thimble", "날 선 바늘": "Sharp Needle", "방패 반사": "Shield Reflect", "돌진": "Dash",
        "수호자": "Guardian", "광전사": "Berserker", "매의 눈": "Hawk Eye", "긴 클립": "Long Clip", "속사": "Rapid Fire",
        "보물 사냥꾼": "Treasure Hunter", "저격": "Sniper", "바람의 화살": "Wind Arrows", "불씨": "Ember",
        "지혜의 안경": "Wise Glasses", "화염 정령": "Fire Spirit", "마나 흡수": "Mana Drain", "대폭발": "Big Bang", "시간 왜곡": "Time Warp",
        "체력 +25%": "HP +25%", "공격력 +20%": "Attack +20%", "받는 피해 -20%": "Damage taken -20%",
        "스킬 대기 -25%": "Skill cooldown -25%", "체력 +40%, 받는 피해 -15%": "HP +40%, damage taken -15%",
        "공격력 +35%, 피해의 5% 회복": "Attack +35%, heal 5% of damage", "치명타 +10%": "Crit +10%",
        "스킬 대기 -30%": "Skill cooldown -30%", "골드 +20%": "Gold +20%", "치명타 +15%, 공격력 +15%": "Crit +15%, attack +15%",
        "스킬 대기 -40%": "Skill cooldown -40%", "스킬 대기 -20%": "Skill cooldown -20%", "공격력 +25%": "Attack +25%",
        "피해의 8% 회복": "Heal 8% of damage", "공격력 +45%": "Attack +45%", "스킬 대기 -45%": "Skill cooldown -45%",
        "기본": "Default", "공격 +25%, 받는 피해 +25%, 행군 빠름": "Attack +25%, damage taken +25%, faster march",
        "공격 -10%, 받는 피해 -30%": "Attack -10%, damage taken -30%", "골드 +40%·드롭 +50%, 공격 -15%": "Gold +40%, drops +50%, attack -15%",
        "마법사 피해 ×2, 궁수 피해 ×0.6": "Mage damage ×2, archer ×0.6",
        "날아다니는 몬스터만 나와요 · 골드 +20%": "Only flying monsters · gold +20%",
        "골렘만 나와요 · 적 체력 +30% · 골드 +50%": "Only golems · enemy HP +30% · gold +50%",
        "반짝이·왕관 몬스터 3배": "Shiny & Crowned monsters ×3",
        "행군이 짧고 적이 빨라요 · 골드 +30%": "Shorter marches, faster enemies · gold +30%",
        "드롭 2배 · 적 체력 +50%": "Drops ×2 · enemy HP +50%",
        "고양이 털실": "Yarn the Cat", "햄스터 땅콩": "Peanut the Hamster", "파랑새 잉크": "Ink the Bluebird",
        "도감 10칸": "10 dex entries", "트로피 3개": "3 trophies", "첫 이사": "First move",
        // monsters
        "지우개똥 슬라임": "Eraser-Crumb Slime", "종이학": "Paper Crane", "지우개 골렘": "Eraser Golem", "스테이플러 대왕": "Stapler King",
        "연필밥 슬라임": "Shaving Slime", "클립 박쥐": "Clip Bat", "몽당연필 골렘": "Stub-Pencil Golem", "연필깎이 거인": "Sharpener Giant",
        "커피 방울 슬라임": "Coffee-Drop Slime", "티백 유령": "Teabag Ghost", "각설탕 골렘": "Sugar-Cube Golem", "머그컵 문어": "Mug Octopus",
        "이끼 슬라임": "Moss Slime", "민들레 씨 요정": "Dandelion Sprite", "선인장 골렘": "Cactus Golem", "다육이 왕": "Succulent King",
        "먼지 토끼": "Dust Bunny", "커서 유령": "Cursor Ghost", "키캡 골렘": "Keycap Golem", "무선 마우스 용": "Wireless Mouse Dragon",
        "잃어버린 USB 요정": "Lost USB Fairy", "황금 연필 정령": "Golden Pencil Spirit", "각설탕 왕자": "Sugar-Cube Prince",
        "무당벌레 기사": "Ladybug Knight", "화면보호기 고양이": "Screensaver Cat",

        // classes & heroes
        "전사": "Warrior", "궁수": "Archer", "마법사": "Mage", "단추": "Button", "클립": "Clip", "몽당": "Stubby",
        "방패 강타": "Shield Bash", "연사": "Volley", "화염 폭발": "Fire Burst",
        // regions
        "공책 들판": "Notebook Meadow", "연필꽂이 협곡": "Pencil-Cup Canyon", "머그컵 늪": "Mug Marsh",
        "화분 정글": "Planter Jungle", "모니터 성채": "Monitor Citadel", "서랍 심층": "Drawer Depths",
        // stage words
        "웨이브": "Wave", "심층": "Depth", "층": "F", "보스전": "Boss!", "보스": "Boss",
        // tactics & weekly
        "균형": "Balanced", "돌격": "Charge", "신중": "Careful", "보물 찾기": "Treasure Hunt",
        "마법 주간": "Arcane Week", "날개 주간": "Wings Week", "거인 주간": "Giants Week",
        "반짝이 주간": "Sparkle Week", "속공 주간": "Haste Week", "보물 주간": "Hoard Week",
        // accessories, styles, slots, rarities
        "없음": "None", "리본": "Ribbon", "왕관": "Crown", "꽃": "Flower", "고깔": "Party Hat", "새싹": "Sprout", "별": "Star",
        "안정형": "Steady", "공격형": "Aggressive", "수집형": "Collector",
        "무기": "Weapon", "방어구": "Armor", "일반": "Common", "고급": "Uncommon", "희귀": "Rare", "전설": "Legendary",
        "반짝이": "Shiny", "손님": "Guest",
        // alignment
        "왼쪽": "Left", "가운데": "Center", "오른쪽": "Right", "모니터": "Display",
        // banners
        "새 지역 해금": "New region", "보스 처치": "Boss defeated", "전설 전리품!": "Legendary loot!",
        "도감 등록": "New dex entry", "일지 한 장": "Journal page", "트로피 획득": "Trophy",
        "자리를 비운": "While you were away for", "동안": "", "마리 처치": " kills", "골드": "gold", "전리품": "loot",
        "가방이 가득 찼어요": "Bag is full", "전술": "Tactic", "특성": "Trait", "이사": "Moved",
    ]
}
