import AppKit
import Foundation
import Observation
import UserNotifications

struct StripSettings: Equatable {
    enum Alignment: Int, CaseIterable { case left, center, right
        var name: String { L10n.t(["왼쪽", "가운데", "오른쪽"][rawValue]) }
    }

    var visible = true
    var clickThrough = true
    var screenIndex = 0
    var alignment: Alignment = .left
    /// Display to show the band on (CGDirectDisplayID) — survives monitors being unplugged/replugged. 0 = use index.
    var displayID: UInt32 = 0
    /// Exclude the band from screenshots and screen sharing.
    var hideInCapture = true
    /// Auto-tidy: equip upgrades and sell low-rarity spares so a full bag never stalls progress.
    var autoEquip = true
    var autoSell = true
    var sound = false
    var aiStyle = 0
    /// Desk theme chosen in the shop's theme pack (-1 = follow moves).
    var themeOverride = -1
    /// Band size, 0.5…1.5 (1 = 920×100 pt).
    var stripScale = 1.0
    /// Check, download, install and relaunch automatically when a new version is out.
    var autoUpdate = true
    static let scaleRange = 0.5...1.5
}

@MainActor
@Observable
final class GameStore {
    static let shared = GameStore()

    var progress: Progress
    var battle: Battle
    var banner: String?
    var lastOffline: OfflineReport?
    var settings: StripSettings {
        didSet { saveSettings(); onSettingsChanged?() }
    }

    /// Lowered when the strip is hidden/occluded to save power.
    var lowPower = false {
        didSet { if oldValue != lowPower { restartTimer() } }
    }

    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    /// Counters the strip renderer polls to fire one-shot celebrations.
    @ObservationIgnored private(set) var legendaryDrops = 0
    @ObservationIgnored private(set) var levelUps = [0, 0, 0]
    @ObservationIgnored private(set) var dexDiscoveries = 0
    /// Loot dropped this session, for the strip's "item pops out" effect.
    @ObservationIgnored private(set) var dropEvents = 0
    @ObservationIgnored private(set) var lastDrop: Item?
    @ObservationIgnored private(set) var lastDexName = ""
    @ObservationIgnored private(set) var movesSeen = 0

    // MARK: AI (MCP) bookkeeping
    struct LogLine: Identifiable { let id = UUID(); let date: Date; let text: String }
    /// Notable game events the AI can read back ("what happened while you were away").
    @ObservationIgnored private(set) var events: [LogLine] = []
    /// What the connected AI did, shown in the menu.
    private(set) var aiLog: [LogLine] = []
    private(set) var lastAIContact: Date?
    /// Bumped on every AI action so the strip can show a 🤖 callout.
    @ObservationIgnored private(set) var aiActions = 0
    @ObservationIgnored private(set) var lastAIText = ""

    func noteAIContact() {
        if lastAIContact.map({ Date().timeIntervalSince($0) > 5 }) ?? true { lastAIContact = Date() }
    }

    var aiConnected: Bool { lastAIContact.map { Date().timeIntervalSince($0) < 15 * 60 } ?? false }

    /// Records an AI action and surfaces it on the strip with the AI's reason.
    func aiAct(_ what: String, reason: String?) {
        let text = reason.map { $0.isEmpty ? what : "\(what) — \($0)" } ?? what
        aiLog.append(LogLine(date: Date(), text: text))
        if aiLog.count > 50 { aiLog.removeFirst(aiLog.count - 50) }
        aiActions += 1
        lastAIText = text
        progress.aiDiary.append(DiaryEntry(date: Date(), text: text))
        if progress.aiDiary.count > 200 {
            let drop = progress.aiDiary.count - 200
            progress.aiDiary.removeFirst(drop)
            progress.aiDiarySeen = max(0, progress.aiDiarySeen - drop)
        }
        showBanner("🤖 \(text)", seconds: 6)
    }

    private func logEvent(_ text: String) {
        events.append(LogLine(date: Date(), text: text))
        if events.count > 60 { events.removeFirst(events.count - 60) }
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var bannerExpiry = Date.distantPast
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private let persist: Bool

    init(progress: Progress? = nil, persist: Bool = true) {
        self.persist = persist
        let loaded = progress ?? (persist ? GameStore.loadProgress() : nil) ?? Progress()
        self.progress = loaded
        self.battle = Engine.newBattle(for: loaded)
        self.settings = persist ? GameStore.loadSettings() : StripSettings()
    }

    // MARK: Lifecycle

    func start() {
        if progress.journal.isEmpty {
            var r = TickReport()
            Journal.unlock("start", in: &progress, report: &r)
        }
        settleOfflineTime()
        restartTimer()
        requestNotificationPermission()
    }

    func settleOfflineTime() {
        let away = Date().timeIntervalSince(progress.lastActive)
        guard away > 120 else { return }
        var p = progress
        let report = Engine.settleOffline(&p, seconds: away, rng: &rng)
        p.lastActive = Date()
        progress = p
        battle = Engine.newBattle(for: p)
        lastOffline = report
        logEvent("자리 비움 정산: \(report.durationText), \(report.kills)마리, 골드 +\(report.gold)")
        var extra = ""
        if report.newDex > 0 { extra += " · 새 도감 \(report.newDex)" }
        if report.pages > 0 { extra += " · 일지 \(report.pages)장" }
        showBanner("자리를 비운 \(report.durationText) 동안 \(report.kills)마리 처치 · 골드 +\(report.gold.formatted()) · 전리품 \(report.items)개\(extra)",
                   seconds: 20)
        save()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = lowPower ? 0.5 : 0.1
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(dt: interval) }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func step(dt: Double) {
        var p = progress
        var b = battle
        let report = Engine.tick(&p, &b, dt: dt, rng: &rng, effects: !lowPower)
        if p != progress { progress = p }
        battle = b
        handle(report)
        if let _ = banner, Date() > bannerExpiry { banner = nil }
        if Date().timeIntervalSince(lastSave) > 30 { save() }
    }

    private func handle(_ report: TickReport) {
        if let d = report.drops.max(by: { $0.rarity < $1.rarity }) { lastDrop = d; dropEvents += 1 }
        for b in report.bossesDefeated { logEvent("보스 처치: \(b)") }
        if let r = report.regionUnlocked { logEvent("새 지역 해금: \(Region.all[r].name)") }
        for d in report.drops where d.rarity >= .rare { logEvent("\(d.rarity.name) 전리품: \(d.name)") }
        for n in report.newDex { logEvent("도감 등록: \(n)") }
        if report.wipes > 0 { logEvent("전멸 → 3웨이브 후퇴 (\(progress.stageText))") }
        if report.weeklyGoal {
            showBanner("주간 목표 달성! \(WeeklyRule.goalKills)마리 처치 · 추억 조각 +1", seconds: 6)
            logEvent("주간 목표 달성 → 추억 조각 +1")
        }
        if !report.drops.isEmpty { autoTidy() }
        if report.bagBecameFull { logEvent("가방이 가득 참") }
        if let name = report.newDex.last {
            dexDiscoveries += report.newDex.count
            lastDexName = name
        }
        if let r = report.regionUnlocked {
            showBanner("새 지역 해금: \(Region.all[r].name)!", seconds: 6)
        } else if let boss = report.bossesDefeated.last {
            showBanner("보스 처치: \(boss)!", seconds: 5)
        } else if let legendary = report.drops.first(where: { $0.rarity == .legendary }) {
            showBanner("전설 전리품! \(legendary.name)", seconds: 6)
        }
        if report.drops.contains(where: { $0.rarity == .legendary }) { legendaryDrops += 1 }
        if report.regionUnlocked == nil, report.bossesDefeated.isEmpty, banner == nil || Date() > bannerExpiry {
            if let t = report.trophies.last {
                showBanner("트로피 획득: \(Trophy.names[t])", seconds: 5)
            } else if let page = report.journalPages.last {
                let e = Journal.text(page, names: progress.heroes.map(\.displayName))
                showBanner("📖 일지 한 장: \(e.title)", seconds: 5)
            } else if let name = report.newDex.last {
                showBanner("도감 등록: \(name)!", seconds: 4)
            }
        }
        if report.bagBecameFull {
            showBanner("가방이 가득 찼어요 — 새 전리품은 절반 값에 자동 판매돼요", seconds: 8)
            notify(title: "가방이 가득 찼어요", body: "원정 본부에서 장비를 정리하세요. 그동안 새 전리품은 절반 값에 자동 판매돼요.")
        }
    }

    func showBanner(_ text: String, seconds: Double) {
        banner = text
        bannerExpiry = Date().addingTimeInterval(seconds)
    }

    // MARK: Player actions

    func levelUp(_ heroIndex: Int) {
        let cost = progress.heroes[heroIndex].levelUpCost
        guard progress.gold >= cost else { return }
        let oldMax = progress.heroes[heroIndex].maxHP
        progress.gold -= cost
        progress.heroes[heroIndex].level += 1
        adjustHP(heroIndex, oldMax: oldMax)
        levelUps[heroIndex] += 1
        var r = TickReport()
        for lv in [10, 25, 50, 100] where progress.heroes[heroIndex].level >= lv {
            Journal.unlock("level\(lv)", in: &progress, report: &r)
        }
        if let page = r.journalPages.last {
            showBanner("📖 일지 한 장: \(Journal.text(page, names: progress.heroes.map(\.displayName)).title)", seconds: 5)
        }
    }

    /// 이사: resets the run, converts it into permanent 추억 조각, and changes the desk theme.
    /// Dex, journal, trophies, uniques, names and hats stay.
    func moveDesk() {
        guard Move.canMove(progress) else { return }
        let gain = Move.gain(progress)
        var p = progress
        p.memories += gain
        p.moves += 1
        p.gold = 0
        p.bag = []
        p.regionIndex = 0
        p.unlockedRegion = 0
        p.wave = 1
        p.runBestFloor = 0
        p.bagFullNotified = false
        for i in p.heroes.indices {
            p.heroes[i].level = 1
            p.heroes[i].weapon = nil
            p.heroes[i].armor = nil
        }
        var r = TickReport()
        Journal.unlock("move\(min(p.moves, 3))", in: &p, report: &r)
        progress = p
        battle = Engine.newBattle(for: p)
        showBanner("새 책상으로 이사했어요: \(DeskTheme.names[p.theme]) · 추억 조각 +\(gain)", seconds: 8)
        save()
    }

    func rename(_ heroIndex: Int, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        progress.heroes[heroIndex].nickname = trimmed.isEmpty ? nil : trimmed
    }

    func setAccessory(_ heroIndex: Int, _ accessory: Int) {
        progress.heroes[heroIndex].accessory = accessory == 0 ? nil : accessory
    }

    func equip(_ item: Item, on heroIndex: Int) {
        guard let bagIndex = progress.bag.firstIndex(where: { $0.id == item.id }) else { return }
        let oldMax = progress.heroes[heroIndex].maxHP
        progress.bag.remove(at: bagIndex)
        if let previous = progress.heroes[heroIndex].item(in: item.slot) {
            progress.bag.insert(previous, at: min(bagIndex, progress.bag.count))
        }
        progress.heroes[heroIndex].setItem(item, in: item.slot)
        adjustHP(heroIndex, oldMax: oldMax)
        refreshBagFlag()
    }

    func unequip(slot: GearSlot, from heroIndex: Int) {
        guard let item = progress.heroes[heroIndex].item(in: slot), !progress.bagIsFull else { return }
        let oldMax = progress.heroes[heroIndex].maxHP
        progress.heroes[heroIndex].setItem(nil, in: slot)
        progress.bag.append(item)
        adjustHP(heroIndex, oldMax: oldMax)
    }

    func sell(_ item: Item) {
        guard let i = progress.bag.firstIndex(where: { $0.id == item.id }) else { return }
        progress.gold += item.sellValue
        progress.bag.remove(at: i)
        refreshBagFlag()
    }

    /// Sells every bag item at or below `rarity` that is not an upgrade for anyone.
    /// Items a bulk sale would remove: everything at or below `rarity` that is not an upgrade for anyone.
    func sellCandidates(upTo rarity: Rarity) -> [Item] {
        progress.bag.filter { $0.rarity <= rarity && !isUpgrade($0) }
    }

    /// What a bulk sale up to `rarity` would yield: (items, gold).
    func sellPreview(upTo rarity: Rarity) -> (count: Int, gold: Int) {
        let c = sellCandidates(upTo: rarity)
        return (c.count, c.reduce(0) { $0 + $1.sellValue })
    }

    /// Sells every bag item at or below `rarity` in one go (upgrades are always kept). Returns (items, gold).
    @discardableResult
    func sellAll(upTo rarity: Rarity) -> (count: Int, gold: Int) {
        let doomed = sellCandidates(upTo: rarity)
        guard !doomed.isEmpty else { return (0, 0) }
        let gold = doomed.reduce(0) { $0 + $1.sellValue }
        progress.gold += gold
        let ids = Set(doomed.map(\.id))
        progress.bag.removeAll { ids.contains($0.id) }
        refreshBagFlag()
        return (doomed.count, gold)
    }

    /// Bulk sale triggered by the player (HQ / strip): sells and tells them what happened.
    func bulkSell(upTo rarity: Rarity) {
        let r = sellAll(upTo: rarity)
        showBanner(r.count == 0 ? L10n.t("팔 장비가 없어요 (업그레이드는 남겨요)")
                                : "🎒 \(r.count)개 판매 · 🪙 +\(r.gold.formatted())", seconds: 4)
    }

    /// Equips the best item per slot, giving the biggest weapon to the hardest hitter and armor to the front line.
    func autoEquip() {
        for slot in GearSlot.allCases {
            let order: [Int] = slot == .weapon ? [2, 1, 0] : [0, 1, 2]
            for hero in order {
                let current = progress.heroes[hero].item(in: slot)?.score ?? 0
                if let best = progress.bag.filter({ $0.slot == slot }).max(by: { $0.score < $1.score }),
                   best.score > current {
                    equip(best, on: hero)
                }
            }
        }
    }

    func isUpgrade(_ item: Item) -> Bool {
        progress.heroes.contains { ($0.item(in: item.slot)?.score ?? 0) < item.score }
    }

    /// Desk theme actually shown: the theme pack lets the player pick any; otherwise it follows moves.
    var effectiveTheme: Int {
        if CosmeticShop.shared.owns(.themes), DeskTheme.names.indices.contains(settings.themeOverride) { return settings.themeOverride }
        return progress.theme
    }

    // MARK: 0.2.7 systems

    /// Equip upgrades and sell spare low-rarity gear (both optional, on by default).
    func autoTidy() {
        if settings.autoEquip, progress.bag.contains(where: { isUpgrade($0) }) { autoEquip() }
        if settings.autoSell, progress.bag.count >= Progress.bagCapacity - 6 { sellAll(upTo: .uncommon) }
    }

    func chooseTrait(_ hero: Int, tier: Int, option: Int) {
        guard progress.heroes.indices.contains(hero), Traits.tiers.indices.contains(tier), (0...1).contains(option),
              progress.heroes[hero].level >= Traits.tiers[tier] else { return }
        let oldMax = progress.heroes[hero].maxHP
        var t = progress.heroes[hero].traits ?? Array(repeating: -1, count: Traits.tiers.count)
        while t.count < Traits.tiers.count { t.append(-1) }
        t[tier] = option
        progress.heroes[hero].traits = t
        adjustHP(hero, oldMax: oldMax)
        let (a, b) = Traits.options(progress.heroes[hero].heroClass, tier: tier)
        showBanner("\(progress.heroes[hero].displayName) 특성: \((option == 0 ? a : b).name)", seconds: 4)
        levelUps[hero] += 1   // reuse the level-up sparkle
    }

    func setTactic(_ t: Tactic) {
        guard progress.tactic != t else { return }
        progress.tactic = t
        showBanner("전술: \(t.icon) \(t.name) — \(t.desc)", seconds: 4)
    }

    /// 도감 조각 → a legendary of the chosen slot.
    @discardableResult
    func exchangeShards(slot: GearSlot) -> Item? {
        guard progress.shards >= Pity.legendaryPrice, !progress.bagIsFull else { return nil }
        var rng = SystemRandomNumberGenerator()
        let item = Engine.makeItem(region: progress.regionIndex, boss: true, floor: progress.isEndless ? progress.wave : 0,
                                   forceLegendary: true, slot: slot, rng: &rng)
        progress.shards -= Pity.legendaryPrice
        progress.bag.append(item)
        if let u = item.unique { progress.uniquesFound.insert(u) }
        legendaryDrops += 1
        showBanner("조각 교환: \(item.name)", seconds: 5)
        return item
    }

    var unseenDiary: [DiaryEntry] { Array(progress.aiDiary.dropFirst(min(progress.aiDiarySeen, progress.aiDiary.count))) }
    func markDiarySeen() { progress.aiDiarySeen = progress.aiDiary.count }

    // Sleep/wake: timers stop while the Mac sleeps, so settle that time like an absence.
    @ObservationIgnored private var sleptAt: Date?
    func willSleep() { sleptAt = Date(); save() }
    func didWake() {
        guard let at = sleptAt else { return }
        sleptAt = nil
        let away = Date().timeIntervalSince(at)
        guard away > 120 else { return }
        progress.lastActive = at
        settleOfflineTime()
    }

    /// Waves the player may jump to in the current region: every wave in a cleared region,
    /// otherwise up to the wave reached now. Not offered in 서랍 심층.
    var selectableWaves: ClosedRange<Int>? {
        let p = progress
        if p.isEndless { return nil }
        return 1...(p.regionIndex < p.unlockedRegion ? Region.wavesPerRegion : max(1, p.wave))
    }

    func selectWave(_ wave: Int) {
        guard let range = selectableWaves, range.contains(wave), wave != progress.wave else { return }
        progress.wave = wave
        battle = Engine.newBattle(for: progress)
    }

    func selectRegion(_ index: Int) {
        guard index <= progress.unlockedRegion, index != progress.regionIndex else { return }
        progress.regionIndex = index
        progress.wave = 1
        battle = Engine.newBattle(for: progress)
    }

    private func adjustHP(_ heroIndex: Int, oldMax: Double) {
        guard battle.heroes.indices.contains(heroIndex) else { return }
        let newMax = progress.heroes[heroIndex].maxHP
        var h = battle.heroes[heroIndex]
        if h.alive { h.hp = min(newMax, max(1, h.hp + (newMax - oldMax))) }
        battle.heroes[heroIndex] = h
    }

    private func refreshBagFlag() {
        if !progress.bagIsFull { progress.bagFullNotified = false }
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard persist, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard persist, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Persistence

    private static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskExpedition", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("save.json")
    }

    func save() {
        lastSave = Date()
        guard persist else { return }
        progress.lastActive = Date()
        do {
            let data = try JSONEncoder().encode(progress)
            try data.write(to: GameStore.saveURL, options: .atomic)
        } catch {
            NSLog("DeskExpedition save failed: \(error)")
        }
    }

    private static func loadProgress() -> Progress? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }

    private static func loadSettings() -> StripSettings {
        let d = UserDefaults.standard
        var s = StripSettings()
        if d.object(forKey: "strip.visible") != nil { s.visible = d.bool(forKey: "strip.visible") }
        if d.object(forKey: "strip.clickThrough") != nil { s.clickThrough = d.bool(forKey: "strip.clickThrough") }
        s.screenIndex = d.integer(forKey: "strip.screen")
        s.alignment = StripSettings.Alignment(rawValue: d.integer(forKey: "strip.alignment")) ?? .left
        s.displayID = UInt32(truncatingIfNeeded: d.integer(forKey: "strip.displayID"))
        for (key, path) in [("strip.hideInCapture", \StripSettings.hideInCapture), ("tidy.autoEquip", \StripSettings.autoEquip),
                            ("tidy.autoSell", \StripSettings.autoSell), ("fx.sound", \StripSettings.sound)]
        where d.object(forKey: key) != nil {
            s[keyPath: path] = d.bool(forKey: key)
        }
        s.aiStyle = d.integer(forKey: "ai.style")
        s.themeOverride = d.object(forKey: "shop.theme") == nil ? -1 : d.integer(forKey: "shop.theme")
        if d.object(forKey: "update.auto") != nil { s.autoUpdate = d.bool(forKey: "update.auto") }
        if d.object(forKey: "strip.scale") != nil {
            s.stripScale = min(StripSettings.scaleRange.upperBound, max(StripSettings.scaleRange.lowerBound, d.double(forKey: "strip.scale")))
        }
        return s
    }

    private func saveSettings() {
        guard persist else { return }
        let d = UserDefaults.standard
        d.set(settings.visible, forKey: "strip.visible")
        d.set(settings.clickThrough, forKey: "strip.clickThrough")
        d.set(settings.screenIndex, forKey: "strip.screen")
        d.set(settings.alignment.rawValue, forKey: "strip.alignment")
        d.set(Int(settings.displayID), forKey: "strip.displayID")
        d.set(settings.hideInCapture, forKey: "strip.hideInCapture")
        d.set(settings.autoEquip, forKey: "tidy.autoEquip")
        d.set(settings.autoSell, forKey: "tidy.autoSell")
        d.set(settings.sound, forKey: "fx.sound")
        d.set(settings.aiStyle, forKey: "ai.style")
        d.set(settings.themeOverride, forKey: "shop.theme")
        d.set(settings.stripScale, forKey: "strip.scale")
        d.set(settings.autoUpdate, forKey: "update.auto")
    }
}
