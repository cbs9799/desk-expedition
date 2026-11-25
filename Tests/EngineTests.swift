import XCTest
@testable import DeskExpedition

final class EngineTests: XCTestCase {
    func testFreshPartyClearsEarlyWavesAndEarnsGold() {
        var rng = SplitMix64(seed: 1)
        var p = Progress()
        var b = Engine.newBattle(for: p)
        var total = TickReport()
        for _ in 0..<600 { total.merge(Engine.tick(&p, &b, dt: 0.1, rng: &rng)) } // 60 s
        XCTAssertGreaterThan(total.kills, 10)
        XCTAssertGreaterThan(p.gold, 0)
        XCTAssertGreaterThan(p.wave, 3)
    }

    func testLevelOneBossEventuallyNeedsUpgradesButLeveledPartyWins() {
        var rng = SplitMix64(seed: 7)
        var p = Progress()
        for i in p.heroes.indices { p.heroes[i].level = 8 }
        var b = Engine.newBattle(for: p)
        var total = TickReport()
        for _ in 0..<6000 { total.merge(Engine.tick(&p, &b, dt: 0.1, rng: &rng)) } // 10 min
        XCTAssertFalse(total.bossesDefeated.isEmpty)
        XCTAssertEqual(p.unlockedRegion, 1)
    }

    func testOfflineSettlementIsCappedAndFast() {
        var rng = SplitMix64(seed: 3)
        var p = Progress()
        let start = Date()
        let report = Engine.settleOffline(&p, seconds: 48 * 3600, rng: &rng)
        XCTAssertEqual(report.seconds, Engine.maxOfflineSeconds)
        XCTAssertGreaterThan(report.kills, 100)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0)
        XCTAssertLessThanOrEqual(p.bag.count, Progress.bagCapacity)
    }

    func testBagFullAutoSellsAndFlagsOnce() {
        var rng = SplitMix64(seed: 9)
        var p = Progress()
        for _ in 0..<(Progress.bagCapacity - 1) { p.bag.append(Engine.makeItem(region: 0, boss: false, rng: &rng)) }
        var report = TickReport()
        let boss = Monster(kind: 2, name: "boss", maxHP: 1, hp: 0, atk: 1, x: 0, isBoss: true, attackTimer: 1)
        Engine.reward(for: boss, &p, rng: &rng, report: &report)
        XCTAssertTrue(report.bagBecameFull)
        var second = TickReport()
        Engine.reward(for: boss, &p, rng: &rng, report: &second)
        XCTAssertFalse(second.bagBecameFull)
        XCTAssertEqual(second.autoSold, 1)
        XCTAssertEqual(p.bag.count, Progress.bagCapacity)
    }

    func testItemRarityScalesPower() {
        var rng = SplitMix64(seed: 11)
        let items = (0..<500).map { _ in Engine.makeItem(region: 2, boss: false, rng: &rng) }.filter { $0.slot == .weapon }
        let common = items.filter { $0.rarity == .common }.map(\.power)
        let uncommon = items.filter { $0.rarity == .uncommon }.map(\.power)
        XCTAssertFalse(common.isEmpty); XCTAssertFalse(uncommon.isEmpty)
        XCTAssertLessThan(common.reduce(0, +) / common.count, uncommon.reduce(0, +) / uncommon.count)
    }

    @MainActor
    func testEquipSwapsAndSellAllKeepsUpgrades() {
        var p = Progress()
        let weak = Item(slot: .weapon, rarity: .common, name: "a", power: 2, regionIndex: 0)
        let strong = Item(slot: .weapon, rarity: .common, name: "b", power: 9, regionIndex: 0)
        p.bag = [weak, strong]
        let store = GameStore(progress: p, persist: false)
        store.equip(weak, on: 0)
        XCTAssertEqual(store.progress.heroes[0].weapon?.id, weak.id)
        store.equip(strong, on: 0)
        XCTAssertEqual(store.progress.heroes[0].weapon?.id, strong.id)
        XCTAssertTrue(store.progress.bag.contains { $0.id == weak.id })
        // `weak` is still an upgrade for the archer/mage (empty slots) → kept.
        store.sellAll(upTo: .common)
        XCTAssertEqual(store.progress.bag.count, 1)
        store.autoEquip()
        XCTAssertTrue(store.progress.bag.isEmpty)
    }

    // MARK: Long-term systems

    func testKillsAreRecordedInDexWithVariantsAndJournal() {
        var rng = SplitMix64(seed: 11)
        var p = Progress()
        var report = TickReport()
        var m = Monster(kind: 0, name: "x", maxHP: 1, hp: 0, atk: 1, x: 0, isBoss: false, attackTimer: 1)
        m.species = Species.of(region: 0, kind: 0).id
        Engine.reward(for: m, &p, rng: &rng, report: &report)
        m.variant = .shiny
        Engine.reward(for: m, &p, rng: &rng, report: &report)
        Engine.reward(for: m, &p, rng: &rng, report: &report)
        XCTAssertEqual(p.dex.count, 2)
        XCTAssertEqual(p.dex[Dex.key(m.species, .shiny)]?.count, 2)
        XCTAssertEqual(report.newDex.count, 2)
        XCTAssertTrue(p.journal.contains { $0.id == "first_shiny" })
        XCTAssertEqual(Species.slotCount, 60)
    }

    func testSpawnsUseSpeciesAndSometimesRareVariants() {
        var rng = SplitMix64(seed: 5)
        var p = Progress()
        var b = Engine.newBattle(for: p)
        var variants = Set<MonsterVariant>(), guests = 0
        for _ in 0..<3000 {
            Engine.spawnWave(&p, &b, rng: &rng)
            for m in b.monsters {
                XCTAssertEqual(Species.all[m.species].region, 0)
                variants.insert(m.variant)
                if m.isGuest { guests += 1 }
            }
        }
        XCTAssertTrue(variants.contains(.crowned))
        XCTAssertTrue(variants.contains(.shiny))
        XCTAssertGreaterThan(guests, 5)
        p.wave = Region.wavesPerRegion
        Engine.spawnWave(&p, &b, rng: &rng)
        XCTAssertTrue(b.monsters.first?.isBoss ?? false)
    }

    func testEndlessDepthClimbsFloorsAndRecordsBest() {
        var rng = SplitMix64(seed: 21)
        var p = Progress()
        p.unlockedRegion = Region.endlessIndex
        p.regionIndex = Region.endlessIndex
        for i in p.heroes.indices { p.heroes[i].level = 80 }
        var b = Engine.newBattle(for: p)
        for _ in 0..<6000 { _ = Engine.tick(&p, &b, dt: 0.1, rng: &rng) }   // 10 min
        XCTAssertTrue(p.isEndless)
        XCTAssertGreaterThan(p.wave, 10, "should pass at least one boss floor")
        XCTAssertGreaterThanOrEqual(p.bestFloor, 10)
        XCTAssertTrue(p.journal.contains { $0.id == "floor10" })
        XCTAssertTrue(Move.canMove(p))
    }

    @MainActor
    func testMovingResetsRunButKeepsCollection() {
        var p = Progress()
        p.unlockedRegion = Region.endlessIndex
        p.regionIndex = Region.endlessIndex
        p.runBestFloor = 20
        p.gold = 999
        p.heroes[0].level = 40
        p.heroes[0].nickname = "보리"
        p.dex["0.0"] = DexEntry(count: 3, first: Date())
        p.trophies = [0, 1]
        let store = GameStore(progress: p, persist: false)
        let gain = Move.gain(store.progress)
        store.moveDesk()
        let q = store.progress
        XCTAssertEqual(q.memories, gain)
        XCTAssertEqual(q.moves, 1)
        XCTAssertEqual(q.gold, 0)
        XCTAssertEqual(q.heroes[0].level, 1)
        XCTAssertEqual(q.unlockedRegion, 0)
        XCTAssertEqual(q.heroes[0].displayName, "보리")
        XCTAssertEqual(q.dex.count, 1)
        XCTAssertEqual(q.trophies, [0, 1])
        XCTAssertGreaterThan(Move.bonus(q), 1)
    }

    func testOldSaveWithoutNewFieldsStillLoads() throws {
        let old = """
        {"heroes":[{"heroClass":"warrior","level":7},{"heroClass":"archer","level":5},{"heroClass":"mage","level":6}],
         "gold":1234,"bag":[],"regionIndex":1,"unlockedRegion":1,"wave":4,"totalKills":321,"bossKills":1,
         "bagFullNotified":false,"lastActive":700000000}
        """
        let p = try JSONDecoder().decode(Progress.self, from: Data(old.utf8))
        XCTAssertEqual(p.gold, 1234)
        XCTAssertEqual(p.heroes[0].level, 7)
        XCTAssertEqual(p.regionIndex, 1)
        XCTAssertTrue(p.dex.isEmpty)
        XCTAssertEqual(p.memories, 0)
        let round = try JSONDecoder().decode(Progress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(round, p)
    }

    // MARK: MCP

    @MainActor
    func testMCPHandshakeToolsAndPlay() throws {
        var p = Progress()
        p.gold = 10_000
        var rng = SplitMix64(seed: 2)
        for _ in 0..<6 { p.bag.append(Engine.makeItem(region: 0, boss: true, rng: &rng)) }
        let store = GameStore(progress: p, persist: false)
        let mcp = MCPHandler(store: store)

        let initR = mcp.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                "params": ["protocolVersion": "2025-06-18", "capabilities": [:]]])
        let info = (initR?["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
        XCTAssertEqual(info?["name"] as? String, "desk-expedition")
        XCTAssertNil(mcp.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))

        let list = (mcp.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(list?.compactMap { $0["name"] as? String } ?? [])
        XCTAssertTrue(names.isSuperset(of: ["get_status", "level_up", "auto_equip", "sell_all", "move_desk"]))
        for t in list ?? [] { XCTAssertTrue(JSONSerialization.isValidJSONObject(t)) }

        func call(_ name: String, _ args: [String: Any]) -> (Bool, String) {
            let r = mcp.handle(["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": name, "arguments": args]])
            let res = r?["result"] as? [String: Any]
            let text = ((res?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            return (res?["isError"] as? Bool ?? true, text)
        }
        let (statusErr, statusText) = call("get_status", [:])
        XCTAssertFalse(statusErr)
        XCTAssertTrue(statusText.contains("\"gold\""))

        XCTAssertFalse(call("level_up", ["hero": 2, "times": 3, "reason": "마법사 화력"]).0)
        XCTAssertEqual(store.progress.heroes[2].level, 4)
        XCTAssertTrue(store.banner?.contains("🤖") ?? false)
        XCTAssertEqual(store.aiLog.count, 1)

        XCTAssertFalse(call("auto_equip", [:]).0)
        XCTAssertTrue(call("select_region", ["region": 3]).0, "locked region must be refused")
        XCTAssertTrue(call("move_desk", ["confirm": true]).0, "cannot move before depths unlock")
        XCTAssertTrue(call("nope", [:]).0)

        let unknown = mcp.handle(["jsonrpc": "2.0", "id": 5, "method": "bogus"])
        XCTAssertEqual((unknown?["error"] as? [String: Any])?["code"] as? Int, -32601)
        let prompt = mcp.handle(["jsonrpc": "2.0", "id": 6, "method": "prompts/get", "params": ["name": "play"]])
        XCTAssertNotNil((prompt?["result"] as? [String: Any])?["messages"])
    }

    func testHTTPRequestParsing() {
        let raw = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\nContent-Length: 2\r\n\r\n{}"
        let r = HTTPRequest(Data(raw.utf8))
        XCTAssertEqual(r?.method, "POST")
        XCTAssertEqual(r?.headers["authorization"], "Bearer abc")
        XCTAssertEqual(r?.body, Data("{}".utf8))
        XCTAssertNil(HTTPRequest(Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}".utf8)), "waits for full body")
    }

    // MARK: 0.2.7 systems

    @MainActor
    func testTraitsUnlockAndApply() {
        var p = Progress()
        p.heroes[0].level = 25
        let store = GameStore(progress: p, persist: false)
        XCTAssertEqual(store.progress.heroes[0].pendingTraitTier, 0)
        let hp0 = store.progress.heroes[0].maxHP
        store.chooseTrait(0, tier: 0, option: 0)            // 강철 골무: HP +25%
        XCTAssertEqual(store.progress.heroes[0].maxHP, hp0 * 1.25, accuracy: 0.01)
        XCTAssertEqual(store.progress.heroes[0].pendingTraitTier, 1)
        store.chooseTrait(0, tier: 2, option: 0)            // Lv50 tier is locked at Lv25
        XCTAssertNil(store.progress.heroes[0].trait(tier: 2))
        XCTAssertEqual(store.progress.heroes[0].chosenTraitNames.count, 1)
    }

    func testTacticsShiftRiskAndReward() {
        XCTAssertGreaterThan(Tactic.charge.atk, Tactic.balanced.atk)
        XCTAssertLessThan(Tactic.careful.damageTaken, 1)
        XCTAssertGreaterThan(Tactic.treasure.gold, 1)
        // Same kill, same RNG seed: treasure tactic pays 40% more gold.
        let m = Monster(kind: 0, name: "x", maxHP: 1, hp: 0, atk: 1, x: 0, isBoss: false, attackTimer: 1)
        var a = Progress(), b = Progress()
        b.tactic = .treasure
        var r1 = SplitMix64(seed: 4), r2 = SplitMix64(seed: 4)
        var rep1 = TickReport(), rep2 = TickReport()
        Engine.reward(for: m, &a, rng: &r1, report: &rep1)
        Engine.reward(for: m, &b, rng: &r2, report: &rep2)
        XCTAssertGreaterThan(b.gold, a.gold)
    }

    func testShinyPityAndLegendaryPity() {
        var rng = SplitMix64(seed: 8)
        var p = Progress()
        p.shinyPity = Pity.shinySpawns - 1
        var b = Engine.newBattle(for: p)
        Engine.spawnWave(&p, &b, rng: &rng)
        XCTAssertEqual(b.monsters.first?.variant, .shiny, "pity forces a shiny")
        XCTAssertEqual(p.shinyPity, b.monsters.dropFirst().count == 0 ? 0 : p.shinyPity)
        let forced = Engine.makeItem(region: 0, boss: false, forceLegendary: true, slot: .armor, rng: &rng)
        XCTAssertEqual(forced.rarity, .legendary)
        XCTAssertEqual(forced.slot, .armor)
    }

    @MainActor
    func testShardsExchangeAndAutoTidy() {
        var p = Progress()
        p.shards = Pity.legendaryPrice
        let store = GameStore(progress: p, persist: false)
        let item = store.exchangeShards(slot: .weapon)
        XCTAssertEqual(item?.rarity, .legendary)
        XCTAssertEqual(store.progress.shards, 0)
        XCTAssertNil(store.exchangeShards(slot: .weapon), "not enough shards")

        var rng = SplitMix64(seed: 12)
        for _ in 0..<20 { store.progress.bag.append(Engine.makeItem(region: 0, boss: false, rng: &rng)) }
        store.autoTidy()
        XCTAssertTrue(store.progress.heroes[2].weapon != nil || store.progress.heroes[1].weapon != nil, "upgrades equipped")
        XCTAssertLessThan(store.progress.bag.count, 21)
    }

    func testWeeklyRuleIsStableWithinAWeek() {
        let monday = ISO8601DateFormatter().date(from: "2026-11-23T09:00:00Z")!
        let sunday = monday.addingTimeInterval(6 * 86400)
        XCTAssertEqual(WeeklyRule.current(monday), WeeklyRule.current(sunday))
        XCTAssertEqual(WeeklyRule.weekKey(monday), WeeklyRule.weekKey(sunday))
        XCTAssertNotEqual(WeeklyRule.weekKey(monday), WeeklyRule.weekKey(monday.addingTimeInterval(7 * 86400)))
    }

    @MainActor
    func testAIDiaryPersistsAndSummarizes() throws {
        let store = GameStore(progress: Progress(), persist: false)
        store.aiAct("단추 Lv.2", reason: "전사가 약해서")
        XCTAssertEqual(store.unseenDiary.count, 1)
        store.markDiarySeen()
        XCTAssertTrue(store.unseenDiary.isEmpty)
        let data = try JSONEncoder().encode(store.progress)
        let back = try JSONDecoder().decode(Progress.self, from: data)
        XCTAssertEqual(back.aiDiary.first?.text, "단추 Lv.2 — 전사가 약해서")
    }

    @MainActor
    func testHQWindowIsResizableWithMinimumSize() {
        let hq = HQWindowController(store: GameStore(progress: Progress(), persist: false))
        hq.show()
        let w = hq.hqWindow
        XCTAssertTrue(w?.styleMask.contains(.resizable) ?? false)
        XCTAssertEqual(w?.contentMinSize, HQLayout.min)
        w?.setContentSize(NSSize(width: 1300, height: 900))
        XCTAssertEqual(w?.contentLayoutRect.width ?? 0, 1300, accuracy: 1, "window grows past the view's ideal size")
        w?.close()
    }

    func testAppIconIsBundled() {
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
    }

    @MainActor
    func testStripScalesWindowAndKeepsHUDClickable() {
        let store = GameStore(progress: Progress(), persist: false)
        store.settings.stripScale = 0.5
        let strip = StripWindowController(store: store, onOpenHQ: {})
        strip.apply()
        XCTAssertEqual(strip.panel.frame.height, StripLayout.height * 0.5, accuracy: 0.5)
        XCTAssertEqual(strip.panel.frame.width, min(StripLayout.width * 0.5, (NSScreen.main?.visibleFrame.width ?? 2000) - 16), accuracy: 0.5)
        store.settings.stripScale = 1.25
        strip.apply()
        XCTAssertEqual(strip.panel.frame.height, StripLayout.height * 1.25, accuracy: 0.5)
        strip.panel.orderOut(nil)
    }

    @MainActor
    func testBulkSellPreviewMatchesSaleAndKeepsUpgrades() {
        var p = Progress()
        p.heroes[0].weapon = Item(slot: .weapon, rarity: .rare, name: "x", power: 50, regionIndex: 0)
        p.heroes[1].weapon = Item(slot: .weapon, rarity: .rare, name: "x", power: 50, regionIndex: 0)
        p.heroes[2].weapon = Item(slot: .weapon, rarity: .rare, name: "x", power: 50, regionIndex: 0)
        p.bag = [
            Item(slot: .weapon, rarity: .common, name: "a", power: 3, regionIndex: 0),
            Item(slot: .weapon, rarity: .rare, name: "b", power: 10, regionIndex: 0),
            Item(slot: .weapon, rarity: .legendary, name: "c", power: 20, regionIndex: 0),
            Item(slot: .weapon, rarity: .legendary, name: "upgrade", power: 999, regionIndex: 0),
        ]
        let store = GameStore(progress: p, persist: false)
        let preview = store.sellPreview(upTo: .legendary)
        XCTAssertEqual(preview.count, 3, "the upgrade is never offered for sale")
        let gold0 = store.progress.gold
        let sold = store.sellAll(upTo: .legendary)
        XCTAssertEqual(sold.count, preview.count)
        XCTAssertEqual(store.progress.gold - gold0, preview.gold)
        XCTAssertEqual(store.progress.bag.map(\.name), ["upgrade"])
        XCTAssertEqual(store.sellAll(upTo: .legendary).count, 0)
    }

    // MARK: 0.2.17 feedback fixes

    func testWallDropsToFarmingAndHoldsUntilStronger() {
        var rng = SplitMix64(seed: 31)
        var p = Progress()
        p.unlockedRegion = Region.endlessIndex
        p.regionIndex = Region.endlessIndex
        p.wave = 40                                  // far too deep for a level-1 party
        var b = Engine.newBattle(for: p)
        var wall: String?
        for _ in 0..<12_000 {
            let r = Engine.tick(&p, &b, dt: 0.1, rng: &rng)
            if let w = r.wallHit { wall = w; break }
        }
        XCTAssertNotNil(wall, "three wipes at one floor switch to farming")
        XCTAssertGreaterThan(p.farmCap, 0)
        let cap = p.farmCap
        for _ in 0..<3_000 { _ = Engine.tick(&p, &b, dt: 0.1, rng: &rng) }
        XCTAssertLessThanOrEqual(p.wave, cap, "farming holds below the wall")
    }

    @MainActor
    func testGettingStrongerRetriesTheWall() {
        var p = Progress()
        p.farmCap = 5; p.wallWipes = 3; p.gold = 1_000
        let store = GameStore(progress: p, persist: false)
        store.levelUp(0)
        XCTAssertEqual(store.progress.farmCap, 0)
    }

    func testWeaponsBelongToAClass() {
        var rng = SplitMix64(seed: 41)
        for _ in 0..<200 {
            let it = Engine.makeItem(region: 1, boss: true, slot: .weapon, rng: &rng)
            XCTAssertNotNil(it.affinity, "\(it.name) should be a class weapon")
        }
        let staff = Item(slot: .weapon, rarity: .legendary, name: "x 크레용 지팡이", power: 100, regionIndex: 0)
        XCTAssertEqual(staff.affinity, .mage)
        XCTAssertEqual(staff.effectivePower(for: .archer), 50)
        XCTAssertEqual(staff.effectivePower(for: .mage), 100)
    }

    @MainActor
    func testAutoEquipGivesWeaponsToTheirClass() {
        var p = Progress()
        p.bag = [Item(slot: .weapon, rarity: .legendary, name: "a 크레용 지팡이", power: 500, regionIndex: 0),
                 Item(slot: .weapon, rarity: .rare, name: "b 클립 활", power: 80, regionIndex: 0)]
        let store = GameStore(progress: p, persist: false)
        store.autoEquip()
        XCTAssertEqual(store.progress.heroes[2].weapon?.name, "a 크레용 지팡이")
        XCTAssertEqual(store.progress.heroes[1].weapon?.name, "b 클립 활")
        XCTAssertNil(store.progress.heroes[0].weapon)
    }

    @MainActor
    func testEvenLevelUpKeepsHeroesTogether() {
        var p = Progress()
        p.heroes[0].level = 10
        p.gold = 5_000
        let store = GameStore(progress: p, persist: false)
        store.levelUpEvenly()
        let levels = store.progress.heroes.map(\.level)
        XCTAssertLessThanOrEqual((levels.max() ?? 0) - (levels.min() ?? 0), 1)
        XCTAssertLessThan(store.progress.gold, store.progress.heroes.map(\.levelUpCost).min() ?? 0)
    }

    @MainActor
    func testMovingConvertsLeftoverGoldAndResetsTraits() {
        var p = Progress()
        p.unlockedRegion = Region.endlessIndex
        p.gold = 55_890_000
        p.heroes[0].level = 60
        p.heroes[0].traits = [0, 1, 0]
        let base = Move.gain(p)
        let store = GameStore(progress: p, persist: false)
        store.moveDesk()
        XCTAssertEqual(store.progress.memories, base + Move.goldMemories(55_890_000))
        XCTAssertGreaterThan(Move.goldMemories(55_890_000), 5)
        XCTAssertNil(store.progress.heroes[0].traits)
    }

    func testWeeklyGoalsHaveTiers() {
        var rng = SplitMix64(seed: 2)
        var p = Progress()
        p.weekKey = WeeklyRule.weekKey()
        p.weekKills = 2_999
        p.weekTier = 1
        var r = TickReport()
        let m = Monster(kind: 0, name: "x", maxHP: 1, hp: 0, atk: 1, x: 0, isBoss: false, attackTimer: 1)
        Engine.reward(for: m, &p, rng: &rng, report: &r)
        XCTAssertEqual(p.weekTier, 2)
        XCTAssertEqual(p.memories, 1)
        XCTAssertEqual(WeeklyGoal.next(p), 10_000)
    }

    func testMasteryAndRegionSets() {
        var p = Progress()
        let sp = Species.all[0]
        p.dex[Dex.key(sp.id, .normal)] = DexEntry(count: 150, first: Date())
        XCTAssertEqual(Mastery.stars(sp, p), 2)
        for s in Species.all where s.region == 0 { for v in s.variants { p.dex[Dex.key(s.id, v)] = DexEntry(count: 1, first: Date()) } }
        XCTAssertTrue(Mastery.regionComplete(0, p))
        XCTAssertEqual(Mastery.attackBonus(p), 1.03, accuracy: 0.0001)
        XCTAssertFalse(Accessory.unlocked(2, p))
        p.bossKills = 10
        XCTAssertTrue(Accessory.unlocked(2, p))
    }

    @MainActor
    func testMCPUpgradeAllDoesEverythingInOneCall() {
        var p = Progress()
        p.gold = 20_000
        p.heroes[1].level = 10
        p.bag = [Item(slot: .weapon, rarity: .rare, name: "a 클립 활", power: 60, regionIndex: 0),
                 Item(slot: .armor, rarity: .common, name: "b 단추 방패", power: 1, regionIndex: 0)]
        let store = GameStore(progress: p, persist: false)
        let mcp = MCPHandler(store: store)
        let r = mcp.handle(["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                            "params": ["name": "upgrade_all", "arguments": ["reason": "테스트"]]])
        let res = r?["result"] as? [String: Any]
        XCTAssertEqual(res?["isError"] as? Bool, false)
        XCTAssertEqual(store.progress.heroes[1].weapon?.name, "a 클립 활")
        XCTAssertNotNil(store.progress.heroes[1].trait(tier: 0), "pending trait chosen")
        XCTAssertGreaterThan(store.progress.heroes[0].level, 1)
    }
}
