import Foundation

/// Model Context Protocol (JSON-RPC 2.0) handler that lets a connected AI read and play the game.
/// Transport-agnostic: `MCPServer` (local HTTP) and `MCPBridge` (stdio) both feed messages here.
@MainActor
final class MCPHandler {
    static let protocolVersion = "2025-06-18"
    let store: GameStore

    init(store: GameStore) { self.store = store }

    /// Returns the JSON-RPC response, or nil for notifications.
    func handle(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : error(id, -32600, "invalid request")
        }
        let params = message["params"] as? [String: Any] ?? [:]
        if id == nil { return nil }   // notifications (initialized, cancelled, …)
        store.noteAIContact()

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return result(id, [
                "protocolVersion": requested ?? Self.protocolVersion,
                "capabilities": ["tools": ["listChanged": false], "prompts": ["listChanged": false]],
                "serverInfo": ["name": "desk-expedition", "title": "책상 원정대",
                               "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": Self.instructions,
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": MCPTools.definitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let payload = try MCPTools.call(name, args, store: store)
                return result(id, ["content": [["type": "text", "text": Self.json(payload)]], "isError": false])
            } catch let e as MCPToolError {
                return result(id, ["content": [["type": "text", "text": e.message]], "isError": true])
            } catch {
                return result(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        case "prompts/list":
            return result(id, ["prompts": [[
                "name": "play", "title": "책상 원정대 돌보기",
                "description": "원정대 상태를 보고 레벨업·장비·가방 정리·지역 이동·이사를 알아서 해 줘요.",
            ]]])
        case "prompts/get":
            return result(id, ["description": "책상 원정대 돌보기",
                               "messages": [["role": "user", "content": ["type": "text", "text": Self.playPrompt]]]])
        default:
            return error(id, -32601, "method not found: \(method)")
        }
    }

    private func result(_ id: Any?, _ r: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": r]
    }

    private func error(_ id: Any?, _ code: Int, _ msg: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": msg]]
    }

    static func json(_ any: Any) -> String {
        guard JSONSerialization.isValidJSONObject(any),
              let d = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys]) else {
            return "\(any)"
        }
        return String(decoding: d, as: UTF8.self)
    }

    static let instructions = """
    책상 원정대(Desk Expedition)는 macOS 화면 아래 띠에서 영웅 셋이 자동으로 싸우는 방치형 RPG입니다. \
    전투는 저절로 진행되고, 당신은 원정대장으로서 성장 결정을 내립니다: 골드로 레벨업, 장비 장착, 가방 정리, \
    지역 선택, 이사(환생). 먼저 get_status로 상황을 보고, 행동할 때마다 reason에 사용자에게 보여 줄 짧은 한국어 이유를 \
    적으세요(띠에 '🤖'와 함께 표시됩니다). 영웅 이름·꾸미기는 사용자가 원할 때만 바꾸세요.
    """

    static let playPrompt = """
    책상 원정대를 돌봐 줘. 순서:
    1. get_status로 현재 상황(골드, 영웅 레벨·체력·공격력, 가방, 지역·웨이브, 최근 사건)을 확인해.
    2. 가방에 업그레이드가 있으면 auto_equip.
    3. 골드로 레벨업: 가장 싼 영웅부터, 셋의 레벨 차이가 5 이상 벌어지지 않게. 전멸(wipes)이 잦으면 전사 체력 위주로.
    4. 가방이 18칸 넘으면 sell_all로 일반(필요하면 고급)까지 정리. 업그레이드 장비는 자동으로 남아.
    5. 보스에서 계속 전멸하면 한 단계 앞 지역에서 골드를 모으고, 새 지역이 열려 있고 여유가 있으면 가장 먼 지역으로.
    6. 서랍 심층이 열렸고 최고층이 한동안 오르지 않으면 move_desk로 이사(추억 조각 영구 보너스)를 고려해.
    7. 끝나면 한두 문장으로 무엇을 했고 다음엔 무엇을 노리는지 요약해.
    행동마다 reason에 짧은 한국어 이유를 적어.
    """
}

struct MCPToolError: Error { let message: String }

/// The game actions exposed to the AI.
@MainActor
enum MCPTools {
    private static let reasonProp: [String: Any] = [
        "type": "string", "description": "사용자에게 띠에 보여 줄 짧은 한국어 이유 (예: '궁수가 가장 약해서')",
    ]
    private static let heroProp: [String: Any] = [
        "type": "integer", "minimum": 0, "maximum": 2, "description": "영웅 번호: 0 전사, 1 궁수, 2 마법사",
    ]

    static var definitions: [[String: Any]] {
        [
            tool("get_status", "원정대 전체 상황: 골드, 영웅(레벨·체력·공격력·장비·레벨업 비용), 지역·웨이브, 가방 요약, 도감·일지·기록, 최근 사건.",
                 [:], readOnly: true),
            tool("get_bag", "가방 속 장비 목록(id, 부위, 등급, 수치, 판매가, 누구에게 업그레이드인지).", [:], readOnly: true),
            tool("get_dex", "책상 도감: 종별로 만난 변종(일반/반짝이/왕관)과 횟수.", [:], readOnly: true),
            tool("get_journal", "원정 일지 최근 페이지.", ["limit": ["type": "integer", "minimum": 1, "maximum": 40]], readOnly: true),
            tool("level_up", "골드로 영웅 레벨업(여러 번 가능, 골드가 모자라면 가능한 만큼).",
                 ["hero": heroProp, "times": ["type": "integer", "minimum": 1, "maximum": 100], "reason": reasonProp],
                 required: ["hero"]),
            tool("equip", "가방의 장비를 영웅에게 장착(기존 장비는 가방으로).",
                 ["item_id": ["type": "string"], "hero": heroProp, "reason": reasonProp], required: ["item_id", "hero"]),
            tool("auto_equip", "가방에서 부위별 최고 장비를 알아서 장착(무기는 마법사→궁수→전사, 방어구는 전사부터).",
                 ["reason": reasonProp]),
            tool("sell_item", "가방의 장비 하나 판매.", ["item_id": ["type": "string"], "reason": reasonProp], required: ["item_id"]),
            tool("sell_all", "지정 등급 이하 장비를 일괄 판매(누군가에게 업그레이드인 장비는 남김).",
                 ["max_rarity": ["type": "string", "enum": ["common", "uncommon", "rare"]], "reason": reasonProp],
                 required: ["max_rarity"]),
            tool("select_region", "원정 지역 바꾸기(열린 지역만). 5는 서랍 심층(끝없는 층).",
                 ["region": ["type": "integer", "minimum": 0, "maximum": Region.all.count - 1], "reason": reasonProp],
                 required: ["region"]),
            tool("move_desk", "새 책상으로 이사(환생): 레벨·장비·골드·지역 초기화, 추억 조각 획득(공격·골드 영구 +5%/개). 되돌릴 수 없음.",
                 ["confirm": ["type": "boolean", "description": "정말 이사하려면 true"], "reason": reasonProp],
                 required: ["confirm"], destructive: true),
            tool("set_nickname", "영웅 이름 바꾸기(사용자가 원할 때만).",
                 ["hero": heroProp, "name": ["type": "string", "maxLength": 8], "reason": reasonProp], required: ["hero", "name"]),
            tool("set_accessory", "영웅 머리 꾸미기(0 없음, 1 리본, 2 왕관, 3 꽃, 4 고깔, 5 새싹, 6 별).",
                 ["hero": heroProp, "accessory": ["type": "integer", "minimum": 0, "maximum": Accessory.all.count - 1],
                  "reason": reasonProp], required: ["hero", "accessory"]),
            tool("say", "띠에 짧은 한마디 남기기(행동 없이 사용자에게 알릴 때).",
                 ["message": ["type": "string", "maxLength": 60]], required: ["message"]),
        ]
    }

    private static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String] = [],
                             readOnly: Bool = false, destructive: Bool = false) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": props, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": desc, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "openWorldHint": false]]
    }

    // MARK: Calls

    static func call(_ name: String, _ a: [String: Any], store: GameStore) throws -> Any {
        let reason = (a["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        func hero() throws -> Int {
            guard let h = int(a["hero"]), (0..<3).contains(h) else { throw MCPToolError(message: "hero는 0(전사)·1(궁수)·2(마법사) 중 하나") }
            return h
        }
        func item() throws -> Item {
            guard let s = a["item_id"] as? String, let id = UUID(uuidString: s),
                  let it = store.progress.bag.first(where: { $0.id == id }) else {
                throw MCPToolError(message: "가방에 그 item_id가 없어요. get_bag으로 확인하세요.")
            }
            return it
        }

        switch name {
        case "get_status": return status(store)
        case "get_bag": return bag(store)
        case "get_dex": return dex(store)
        case "get_journal":
            let limit = int(a["limit"]) ?? 10
            let names = store.progress.heroes.map(\.displayName)
            return store.progress.journal.suffix(limit).reversed().map { page -> [String: Any] in
                let e = Journal.text(page.id, names: names)
                return ["title": e.title, "text": e.text, "date": iso(page.date)]
            }

        case "level_up":
            let h = try hero()
            let times = max(1, min(100, int(a["times"]) ?? 1))
            let before = store.progress.heroes[h].level
            for _ in 0..<times where store.progress.gold >= store.progress.heroes[h].levelUpCost { store.levelUp(h) }
            let gained = store.progress.heroes[h].level - before
            guard gained > 0 else {
                throw MCPToolError(message: "골드가 모자라요 (필요 \(store.progress.heroes[h].levelUpCost), 보유 \(store.progress.gold))")
            }
            store.aiAct("\(store.progress.heroes[h].displayName) Lv.\(store.progress.heroes[h].level)", reason: reason)
            return ["hero": h, "level": store.progress.heroes[h].level, "levelsGained": gained, "gold": store.progress.gold,
                    "nextCost": store.progress.heroes[h].levelUpCost]

        case "equip":
            let it = try item(), h = try hero()
            store.equip(it, on: h)
            store.aiAct("\(store.progress.heroes[h].displayName)에게 \(it.name)", reason: reason)
            return ["equipped": it.name, "hero": h, "status": heroJSON(h, store)]

        case "auto_equip":
            let before = store.progress.heroes.map { [$0.weapon?.id, $0.armor?.id] }
            store.autoEquip()
            let changed = zip(before, store.progress.heroes.map { [$0.weapon?.id, $0.armor?.id] }).filter { $0 != $1 }.count
            if changed > 0 { store.aiAct("장비 정리 (\(changed)명)", reason: reason) }
            return ["heroesChanged": changed, "heroes": (0..<3).map { heroJSON($0, store) }]

        case "sell_item":
            let it = try item()
            store.sell(it)
            store.aiAct("\(it.name) 판매 +\(it.sellValue)", reason: reason)
            return ["sold": it.name, "gold": store.progress.gold]

        case "sell_all":
            let map: [String: Rarity] = ["common": .common, "uncommon": .uncommon, "rare": .rare]
            guard let r = map[a["max_rarity"] as? String ?? ""] else { throw MCPToolError(message: "max_rarity: common | uncommon | rare") }
            let beforeCount = store.progress.bag.count, beforeGold = store.progress.gold
            store.sellAll(upTo: r)
            let sold = beforeCount - store.progress.bag.count
            if sold > 0 { store.aiAct("가방 정리 \(sold)개 +\(store.progress.gold - beforeGold)", reason: reason) }
            return ["sold": sold, "goldGained": store.progress.gold - beforeGold, "bag": store.progress.bag.count]

        case "select_region":
            guard let r = int(a["region"]), Region.all.indices.contains(r) else { throw MCPToolError(message: "region 범위 밖") }
            guard r <= store.progress.unlockedRegion else { throw MCPToolError(message: "아직 안 열린 지역이에요 (열린 곳: 0…\(store.progress.unlockedRegion))") }
            store.selectRegion(r)
            store.aiAct("\(Region.all[r].name)(으)로 이동", reason: reason)
            return ["region": r, "name": Region.all[r].name]

        case "move_desk":
            guard a["confirm"] as? Bool == true else { throw MCPToolError(message: "confirm: true 가 필요해요") }
            guard Move.canMove(store.progress) else { throw MCPToolError(message: "서랍 심층이 열려야 이사할 수 있어요") }
            let gain = Move.gain(store.progress)
            store.moveDesk()
            store.aiAct("이사! 추억 조각 +\(gain)", reason: reason)
            return ["memories": store.progress.memories, "gained": gain, "theme": DeskTheme.names[store.progress.theme]]

        case "set_nickname":
            let h = try hero()
            store.rename(h, to: a["name"] as? String ?? "")
            store.aiAct("이름: \(store.progress.heroes[h].displayName)", reason: reason)
            return ["hero": h, "name": store.progress.heroes[h].displayName]

        case "set_accessory":
            let h = try hero()
            guard let acc = int(a["accessory"]), Accessory.all.indices.contains(acc) else { throw MCPToolError(message: "accessory 0…\(Accessory.all.count - 1)") }
            store.setAccessory(h, acc)
            store.aiAct("\(store.progress.heroes[h].displayName) 꾸미기: \(Accessory.all[acc])", reason: reason)
            return ["hero": h, "accessory": Accessory.all[acc]]

        case "say":
            let m = String((a["message"] as? String ?? "").prefix(60))
            guard !m.isEmpty else { throw MCPToolError(message: "message가 비었어요") }
            store.aiAct(m, reason: nil)
            return ["shown": m]

        default:
            throw MCPToolError(message: "알 수 없는 도구: \(name)")
        }
    }

    // MARK: Snapshots

    static func heroJSON(_ i: Int, _ store: GameStore) -> [String: Any] {
        let h = store.progress.heroes[i]
        let hp = store.battle.heroes[safe: i]?.hp ?? h.maxHP
        func gear(_ it: Item?) -> Any {
            guard let it else { return NSNull() }
            return ["name": it.name, "rarity": "\(it.rarity)", "power": it.power]
        }
        return ["index": i, "class": h.heroClass.rawValue, "name": h.displayName, "level": h.level,
                "hp": Int(max(0, hp)), "maxHP": Int(h.maxHP), "attack": Int(h.attack * Move.bonus(store.progress)),
                "levelUpCost": h.levelUpCost, "weapon": gear(h.weapon), "armor": gear(h.armor),
                "accessory": Accessory.all[h.accessory ?? 0]]
    }

    static func status(_ store: GameStore) -> [String: Any] {
        let p = store.progress
        let upgrades = p.bag.filter { store.isUpgrade($0) }.count
        return [
            "gold": p.gold,
            "region": ["index": p.regionIndex, "name": p.region.name, "endless": p.isEndless],
            "stage": p.stageText, "bossWave": p.isBossWave, "wave": p.wave,
            "unlockedRegions": (0...p.unlockedRegion).map { ["index": $0, "name": Region.all[$0].name] },
            "heroes": (0..<3).map { heroJSON($0, store) },
            "partyAlive": store.battle.heroes.filter(\.alive).count,
            "bag": ["count": p.bag.count, "capacity": Progress.bagCapacity, "upgrades": upgrades],
            "dex": ["filled": p.dex.count, "total": Species.slotCount, "goldBonusPercent": p.dex.count],
            "journalPages": p.journal.count,
            "records": ["totalKills": p.totalKills, "bossKills": p.bossKills, "wipes": p.wipes, "bestFloor": p.bestFloor,
                        "trophies": p.trophies.sorted().map { Trophy.names[$0] }],
            "move": ["memories": p.memories, "moves": p.moves, "canMove": Move.canMove(p),
                     "gainIfMovedNow": Move.canMove(p) ? Move.gain(p) : 0, "bonusPercent": p.memories * 5],
            "recentEvents": store.events.suffix(12).map { ["at": iso($0.date), "text": $0.text] },
        ]
    }

    static func bag(_ store: GameStore) -> [[String: Any]] {
        store.progress.bag.map { it in
            let forHeroes = (0..<3).filter { (store.progress.heroes[$0].item(in: it.slot)?.score ?? 0) < it.score }
            return ["id": it.id.uuidString, "name": it.name, "slot": it.slot.rawValue, "rarity": "\(it.rarity)",
                    "power": it.power, "stat": it.statText, "sellValue": it.sellValue, "upgradeFor": forHeroes]
        }
    }

    static func dex(_ store: GameStore) -> [[String: Any]] {
        Species.all.map { sp in
            var seen: [String: Int] = [:]
            for v in sp.variants { if let e = store.progress.dex[Dex.key(sp.id, v)] { seen["\(v)"] = e.count } }
            return ["name": sp.name, "region": Region.all[sp.region].name,
                    "kind": ["ground", "flyer", "heavy", "boss", "guest"][sp.kind],
                    "variants": sp.variants.map { "\($0)" }, "seen": seen]
        }
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}
