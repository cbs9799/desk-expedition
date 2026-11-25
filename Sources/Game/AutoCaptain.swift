import Foundation

/// Wall-clock source for run timers (stall/wall). Simulations shift it to fast-forward hours.
enum GameClock {
    nonisolated(unsafe) static var offset: TimeInterval = 0
    static func now() -> Date { Date().addingTimeInterval(offset) }
}

/// '자동 원정대장': the fixed rules distilled from hours of AI-run play, without any AI tokens.
/// `decide` is pure (state in → actions out) so it can be tested; GameStore executes the actions.
enum AutoCaptain {
    struct Config: Equatable {
        var moveGain = 150            // move when the gain reaches this…
        var moveGainStalled = 100     // …or this much once the run has stalled
        var stallMinutes = 10.0       // no new best floor for this long = stalled
        var exchangeFloor = 120       // shards → legendary only this deep (item power follows the floor)
        var longStallFactor = 3.0     // stuck this many × stallMinutes → move with any decent gain…
        var longStallMinGain = 30     // …of at least this (memories are permanent, so a small move still helps)
        var chargeCalmMinutes = 5.0   // go back to charge only after this long without a wipe
        var sellUpTo: Rarity = .rare
        var interval: TimeInterval = 45
    }

    enum Action: Equatable {
        case tidy(sellUpTo: Rarity)
        case exchange(GearSlot)
        case move(reason: String)
        case upgradeAll
        case tactic(Tactic, reason: String)
    }

    struct Input {
        var progress: Progress
        var now: Date
        var lastWipeAt: Date?
    }

    static func stallMinutes(_ p: Progress, now: Date) -> Double {
        guard let at = p.runBestAt else { return 0 }
        return now.timeIntervalSince(at) / 60
    }

    static func decide(_ i: Input, _ c: Config) -> [Action] {
        let p = i.progress
        var actions: [Action] = [.tidy(sellUpTo: c.sellUpTo)]

        if p.shards >= Pity.legendaryPrice && p.runBestFloor >= c.exchangeFloor {
            actions.append(.exchange(weakerSlot(p)))
        }

        let gain = Move.gain(p) + Move.goldMemories(p.gold)
        let stall = stallMinutes(p, now: i.now)
        let longStall = stall >= c.stallMinutes * c.longStallFactor && gain >= c.longStallMinGain
        if Move.canMove(p) && (gain >= c.moveGain || (stall >= c.stallMinutes && gain >= c.moveGainStalled) || longStall) {
            let why = gain >= c.moveGain
                ? "이득 +\(gain) → 이사"
                : "\(p.runBestFloor)층 \(Int(stall))분 정체 → 이사 (+\(gain))"
            actions += [.move(reason: why), .tactic(.charge, reason: "이사 직후 돌격"), .upgradeAll]
            return actions
        }

        actions.append(.upgradeAll)
        // Hysteresis: a fresh wipe drops to balanced at once; charge comes back only after a calm spell.
        let sinceWipe = i.lastWipeAt.map { i.now.timeIntervalSince($0) } ?? .infinity
        if sinceWipe < 180 && p.tactic == .charge {
            actions.append(.tactic(.balanced, reason: "최근 전멸 → 균형으로"))
        } else if sinceWipe >= c.chargeCalmMinutes * 60 && p.tactic != .charge {
            actions.append(.tactic(.charge, reason: "\(Int(c.chargeCalmMinutes))분째 전멸 없음 → 돌격으로"))
        }
        return actions
    }

    /// The slot where the party's gear is weakest relative to a legendary.
    static func weakerSlot(_ p: Progress) -> GearSlot {
        let weapons = p.heroes.filter { ($0.weapon?.rarity ?? .common) < .legendary }.count
        let armors = p.heroes.filter { ($0.armor?.rarity ?? .common) < .legendary }.count
        return weapons >= armors ? .weapon : .armor
    }
}
