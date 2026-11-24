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
            Engine.spawnWave(p, &b, rng: &rng)
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
        Engine.spawnWave(p, &b, rng: &rng)
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
}
