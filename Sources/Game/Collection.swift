import Foundation

// MARK: - Species (도감)

/// Every creature that can be recorded in the 책상 도감.
/// `kind`: 0 ground, 1 flyer, 2 heavy, 3 boss, 4 rare guest.
struct Species: Identifiable {
    let id: Int
    let name: String
    let key: String          // art key without the `mon_` prefix
    let region: Int
    let kind: Int

    var isBoss: Bool { kind == 3 }
    var isGuest: Bool { kind == 4 }
    var isFlyer: Bool { kind == 1 || key.hasSuffix("fairy") || key.hasSuffix("pencil") || key.hasSuffix("cat") }
    var spriteKey: String { "mon_" + key }

    /// Variants this species can appear in (guests are always special; bosses already wear a crown).
    var variants: [MonsterVariant] {
        isGuest ? [.normal] : isBoss ? [.normal, .shiny] : MonsterVariant.allCases
    }

    static let guests: [(name: String, key: String)] = [
        ("잃어버린 USB 요정", "guest_usb_fairy"),
        ("황금 연필 정령", "guest_gold_pencil"),
        ("각설탕 왕자", "guest_sugar_prince"),
        ("무당벌레 기사", "guest_ladybug_knight"),
        ("화면보호기 고양이", "guest_pixel_cat"),
    ]

    static let all: [Species] = {
        var list: [Species] = []
        for (r, region) in Region.all.enumerated() where !region.endless {
            for k in 0..<3 {
                list.append(Species(id: list.count, name: region.monsterNames[k], key: region.monsterKeys[k], region: r, kind: k))
            }
            list.append(Species(id: list.count, name: region.bossName, key: region.bossKey, region: r, kind: 3))
            list.append(Species(id: list.count, name: guests[r].name, key: guests[r].key, region: r, kind: 4))
        }
        return list
    }()

    static func of(region: Int, kind: Int) -> Species {
        all.first { $0.region == region && $0.kind == kind } ?? all[0]
    }

    /// Total dex slots (species × their variants).
    static let slotCount = all.reduce(0) { $0 + $1.variants.count }
}

enum MonsterVariant: Int, Codable, CaseIterable {
    case normal, shiny, crowned

    var label: String { ["", "반짝이", "왕관"][rawValue] }
    /// Chance per spawned regular monster.
    static let shinyChance = 1.0 / 400
    static let crownedChance = 1.0 / 50
    static let bossShinyChance = 1.0 / 40
    static let guestChancePerWave = 1.0 / 120
}

struct DexEntry: Codable, Equatable {
    var count: Int
    var first: Date
}

enum Dex {
    static func key(_ species: Int, _ variant: MonsterVariant) -> String { "\(species).\(variant.rawValue)" }

    /// +1% gold per dex slot filled.
    static func goldBonus(_ p: Progress) -> Double { 1 + 0.01 * Double(p.dex.count) }

    static let milestones = [10, 25, 40, 60]
}

// MARK: - Journal (원정 일지)

struct JournalPage: Codable, Equatable, Identifiable {
    var id: String
    var date: Date
}

/// Short diary pages written from the party's point of view. `{w}`, `{a}`, `{m}` become the heroes' nicknames.
enum Journal {
    struct Entry { let title: String; let text: String }

    static let entries: [String: Entry] = [
        "start": .init(title: "출발", text: "사람이 자리를 비웠다. {w}가 골무를 눌러쓰며 말했다. \"지금이야.\" {a}는 클립 활을 당겨 보고, {m}는 크레용 끝에 불을 붙였다. 책상 끝까지 가 보기로 했다."),
        "region1": .init(title: "연필꽂이 협곡", text: "연필들이 숲처럼 솟아 있다. {a}가 \"이건 그냥 거대한 HB잖아\" 하고 웃었는데, 연필밥 슬라임이 그 말을 들은 것 같다."),
        "region2": .init(title: "머그컵 늪", text: "커피 냄새가 진하다. {m}는 안경에 김이 서려 세 번이나 넘어졌다. {w}는 각설탕 바위 위에서 잠깐 쉬자고 했다."),
        "region3": .init(title: "화분 정글", text: "흙냄새와 초록. 다육이 잎 그늘이 시원하다. {a}가 \"여기 살고 싶다\"고 했다. {w}는 선인장 가시에 투구를 긁혔다."),
        "region4": .init(title: "모니터 성채", text: "푸른 빛이 성벽을 비춘다. 키캡 골렘이 WASD를 새기고 서 있다. {m}가 속삭였다. \"저 빛 너머에 사람이 산대.\""),
        "region5": .init(title: "서랍 심층", text: "모니터 성채 뒤, 반쯤 열린 서랍. 아래로 끝없이 이어진 어둠. {w}가 손전등 빛을 따라 첫 계단을 내려갔다."),
        "boss0": .init(title: "스테이플러 대왕", text: "철컥, 철컥. 대왕의 턱에 {w}의 투구가 낄 뻔했다. {a}의 화살이 경첩을 맞히자 대왕이 멈췄다. 기념으로 거대한 심 하나를 챙겼다."),
        "boss1": .init(title: "연필깎이 거인", text: "거인이 돌 때마다 나무 냄새가 났다. {m}의 불꽃이 칼날을 달궜고, {w}가 방패로 손잡이를 쳐서 멈췄다. 칼날 하나를 트로피로 가져왔다."),
        "boss2": .init(title: "머그컵 문어", text: "다리가 여덟 개라니 반칙이다. {a}는 다리 하나에 휘감겨 한참 대롱거렸다. 이긴 뒤 깨진 손잡이를 주웠다. 따뜻했다."),
        "boss3": .init(title: "다육이 왕", text: "왕은 사실 화가 났던 게 아니라 물이 고팠던 것 같다. {m}가 이슬을 모아 뿌려 주었다. 왕이 꽃 한 송이를 내밀었다."),
        "boss4": .init(title: "무선 마우스 용", text: "용의 붉은 눈이 깜빡였다. 배터리가 다 됐다는 신호였을까. 쓰러진 용에게서 스크롤 휠을 빼 왔다. {w}는 그걸 굴리며 한참 놀았다."),
        "first_shiny": .init(title: "반짝이는 것", text: "오늘 본 몬스터는 색이 달랐다. 빛을 받을 때마다 반짝였다. {a}가 \"이건 기록해야 해\" 하고 도감에 그렸다."),
        "first_crowned": .init(title: "왕관을 쓴 녀석", text: "작은 왕관을 쓴 몬스터가 유난히 단단했다. {w}의 팔이 저릴 때까지 버텼다. 대신 주머니가 두둑했다."),
        "first_guest": .init(title: "희귀 손님", text: "전투 중에 낯선 손님이 끼어들었다. 겁먹은 눈치였지만 금화를 잔뜩 떨어뜨리고 갔다. {m}는 손님 이야기를 밤새 했다."),
        "dex10": .init(title: "도감 10칸", text: "도감이 제법 두꺼워졌다. {a}는 그림 실력이 늘었다고 우긴다. 확실히 슬라임은 이제 슬라임처럼 보인다."),
        "dex25": .init(title: "도감 25칸", text: "{m}가 도감을 정리하다 말했다. \"우리 책상에 이렇게 많은 게 살고 있었어.\" 셋 다 잠깐 조용해졌다."),
        "dex40": .init(title: "도감 40칸", text: "이제 몬스터를 보면 어느 지역에서 왔는지 안다. {w}는 반짝이를 놓치면 하루 종일 시무룩하다."),
        "dex60": .init(title: "도감 완성", text: "마지막 칸을 채웠다. {a}가 도감을 덮고 한참 표지를 쓰다듬었다. 책상 위의 모든 것을 만났다. 그래도 내일 또 나가 볼 거다."),
        "floor10": .init(title: "심층 10층", text: "서랍 깊은 곳에는 오래된 영수증이 바람에 날린다. 날짜를 보니 몇 년 전이다. {m}가 \"시간이 멈춘 곳 같아\"라고 했다."),
        "floor20": .init(title: "심층 20층", text: "동전 더미 사이로 길이 났다. 예전에 무찌른 보스들이 다른 색으로 다시 나타난다. 꿈일까, 기억일까."),
        "floor30": .init(title: "심층 30층", text: "녹슨 열쇠 하나가 떨어져 있었다. 어디를 여는 열쇠인지는 모른다. {w}가 목에 걸었다."),
        "floor50": .init(title: "심층 50층", text: "손전등 빛도 닿지 않는다. 셋이 손을 잡고 걷는다. {a}가 노래를 불렀고, 조금 덜 무서워졌다."),
        "floor100": .init(title: "심층 100층", text: "바닥이 보인다고 생각했는데 또 다른 서랍이었다. {m}가 웃었다. \"끝이 없는 게 좋은 거야. 계속 갈 수 있으니까.\""),
        "first_wipe": .init(title: "후퇴", text: "오늘은 졌다. 셋 다 지우개똥 위에 대자로 뻗었다. {w}가 먼저 일어나 손을 내밀었다. \"다시 가자.\""),
        "first_legendary": .init(title: "전설의 장비", text: "빛기둥이 솟은 자리에서 장비를 주웠다. 손에 쥐자 따뜻했다. {a}는 그날 밤 그걸 끌어안고 잤다."),
        "first_unique": .init(title: "이름 있는 무기", text: "이번 장비에는 이름이 새겨져 있었다. 누군가 아끼던 물건이었을까. 소중히 쓰기로 했다."),
        "level10": .init(title: "Lv.10", text: "{w}의 방패질이 제법 자연스러워졌다. {m}는 이제 눈을 감고도 불을 붙인다."),
        "level25": .init(title: "Lv.25", text: "어느새 몬스터들이 우리를 보면 길을 비킨다. {a}는 그게 조금 쓸쓸하다고 했다."),
        "level50": .init(title: "Lv.50", text: "처음 출발한 공책 들판이 아득하다. 그때 쓰던 바늘 검은 {w}의 배낭 맨 아래에 아직 있다."),
        "level100": .init(title: "Lv.100", text: "백 번째 고비를 넘었다. 셋이 책상 끝에 앉아 모니터 빛을 바라봤다. 말은 없었지만 다 알았다."),
        "move1": .init(title: "이사", text: "짐을 쌌다. 장비는 두고 가기로 했다. 대신 도감과 일지, 그리고 추억은 챙겼다. 새 책상은 어떤 곳일까."),
        "move2": .init(title: "두 번째 이사", text: "{a}는 이제 짐 싸는 데 선수다. {w}는 여전히 트로피를 하나도 못 버린다."),
        "move3": .init(title: "세 번째 이사", text: "새 책상의 연필은 색이 조금 달랐다. 그래도 지우개똥은 어디나 똑같이 말랑하다."),
    ]

    static func text(_ id: String, names: [String]) -> Entry {
        let e = entries[id] ?? Entry(title: id, text: "")
        func fill(_ s: String) -> String {
            s.replacingOccurrences(of: "{w}", with: names[safe: 0] ?? "단추")
                .replacingOccurrences(of: "{a}", with: names[safe: 1] ?? "클립")
                .replacingOccurrences(of: "{m}", with: names[safe: 2] ?? "몽당")
        }
        return Entry(title: e.title, text: fill(e.text))
    }

    /// Adds a page once. Returns true if it was new.
    @discardableResult
    static func unlock(_ id: String, in p: inout Progress, report: inout TickReport) -> Bool {
        guard entries[id] != nil, !p.journal.contains(where: { $0.id == id }) else { return false }
        p.journal.append(JournalPage(id: id, date: Date()))
        report.journalPages.append(id)
        return true
    }
}

// MARK: - Trophies, unique legendaries, desk themes

enum Trophy {
    /// Index = frame of the `trophies` sheet. 0–4: first kill of each region boss, 5: depth floor 30.
    static let names = ["거대한 스테이플러 심", "연필깎이 칼날", "깨진 머그컵 손잡이", "다육이 꽃", "스크롤 휠", "녹슨 서랍 열쇠"]
}

enum Unique {
    static let names = [
        "단추 할머니의 바늘", "첫 출근 날의 클립", "마감 전날의 크레용", "반쯤 쓴 지우개 방패", "형광펜 기사의 창",
        "포스트잇 망토 초판", "금색 압정", "생일 카드 리본", "고무줄 투석구", "녹슨 서랍 열쇠",
        "커피 얼룩 지도", "엄지손톱 방패", "샤프심 묶음 활", "자석 단검", "수정 테이프 갑옷",
        "도장 망치", "책갈피 검", "실타래 로브", "병뚜껑 왕관", "모니터 먼지 망토",
    ]
    /// Chance that a legendary drop is one of the named uniques.
    static let chance = 0.35
}

enum DeskTheme {
    static let names = ["기본 책상", "밤샘 책상", "카페 테이블", "새벽 책상"]
    /// Multiply tint for the scenery (RGB hex), index = moves % count.
    static let tints: [UInt32] = [0xFFFFFF, 0x8C9AE0, 0xF2C69A, 0xF6B8C8]
}

enum Move {
    /// Memories (추억 조각) granted by moving now.
    static func gain(_ p: Progress) -> Int { 3 + p.runBestFloor / 2 + p.heroes.map(\.level).reduce(0, +) / 30 }
    /// Each memory: +5% attack and gold, forever.
    static func bonus(_ p: Progress) -> Double { 1 + 0.05 * Double(p.memories) }
    static func canMove(_ p: Progress) -> Bool { p.unlockedRegion >= Region.endlessIndex }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
