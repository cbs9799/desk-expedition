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
}
