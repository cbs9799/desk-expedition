import SwiftUI

/// 자동 원정대장 settings: rule-based auto play that runs every 45 s without any AI tokens.
struct CaptainPanel: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        let c = store.settings.captain
        let p = store.progress
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PixelIcon(.robot, size: 18)
                Text("자동 원정대장").font(.system(size: 14, weight: .heavy, design: .rounded))
                Text("AI 없이 규칙대로 45초마다 정비·전술·교환·이사").font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                Spacer()
                ToggleRow(title: "", isOn: store.settings.autoCaptain) {
                    store.settings.autoCaptain.toggle()
                    if store.settings.autoCaptain { store.runCaptain() }
                }
                .frame(width: 44)
            }
            HStack(spacing: 12) {
                stepper("이사 이득", value: c.moveGain, step: 10, range: 10...2000) { store.settings.captain.moveGain = $0 }
                stepper("정체 시 이득", value: c.moveGainStalled, step: 10, range: 10...2000) { store.settings.captain.moveGainStalled = $0 }
                stepper("정체 판정(분)", value: Int(c.stallMinutes), step: 1, range: 1...120) { store.settings.captain.stallMinutes = Double($0) }
                stepper("교환 최소층", value: c.exchangeFloor, step: 10, range: 0...1000) { store.settings.captain.exchangeFloor = $0 }
                VStack(alignment: .leading, spacing: 2) {
                    Text("판매 등급").font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.dim)
                    SegmentRow(options: [0, 1, 2], selected: c.sellUpTo.rawValue,
                               label: { L10n.t(["일반", "고급", "희귀"][$0]) },
                               onSelect: { store.settings.captain.sellUpTo = Rarity(rawValue: $0) ?? .rare })
                        .frame(width: 150)
                }
            }
            HStack(spacing: 10) {
                let gain = Move.gain(p) + Move.goldMemories(p.gold)
                let stall = Int(AutoCaptain.stallMinutes(p, now: Date()))
                Text("지금 이사 이득 +\(gain) · 이번 판 최고 \(p.runBestFloor)층 (\(stall)분째) · 벽 누적 전멸 \(p.wallTotalWipes)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.gold)
                Spacer()
                if let last = store.captainLog.last {
                    Text(last.text).font(.system(size: 10, design: .rounded)).foregroundStyle(Color(hex: 0x9CF4FF)).lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    private func stepper(_ title: String, value: Int, step: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title)).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.dim)
            HStack(spacing: 4) {
                Button("−") { set(max(range.lowerBound, value - step)) }.buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                Text("\(value)").font(.system(size: 12, weight: .heavy, design: .rounded)).frame(minWidth: 34)
                Button("+") { set(min(range.upperBound, value + step)) }.buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
            }
        }
    }
}
