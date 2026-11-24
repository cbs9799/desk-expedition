import AppKit
import SwiftUI

/// Menu bar popover: progress at a glance + strip settings.
struct MenuView: View {
    @Environment(GameStore.self) private var store
    var onOpenHQ: () -> Void = {}

    var body: some View {
        let p = store.progress
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("책상 원정대").font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                Text("🪙 \(p.gold.formatted())").font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(p.region.name).font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Text(p.isBossWave ? "보스전!" : "웨이브 \(p.wave)/\(Region.wavesPerRegion)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(p.isBossWave ? Color(hex: 0xFF7A7A) : Theme.dim)
                }
                Bar(fraction: Double(p.wave - 1) / Double(Region.wavesPerRegion - 1), color: Theme.gold, height: 5)
                ForEach(Array(p.heroes.enumerated()), id: \.offset) { i, hero in
                    HStack(spacing: 8) {
                        Text("\(hero.heroClass.name) Lv.\(hero.level)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(width: 84, alignment: .leading)
                        Bar(fraction: (store.battle.heroes[safe: i]?.hp ?? hero.maxHP) / hero.maxHP)
                    }
                }
                HStack {
                    Text("🎒 가방 \(p.bag.count)/\(Progress.bagCapacity)")
                        .foregroundStyle(p.bagIsFull ? Color(hex: 0xFF7A7A) : Theme.text)
                    Spacer()
                    Text("처치 \(p.totalKills.formatted())").foregroundStyle(Theme.dim)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))

            if let banner = store.banner {
                Text(banner).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: "원정 띠 보이기", isOn: store.settings.visible) { store.settings.visible.toggle() }
                ToggleRow(title: "클릭 통과 (작업 방해 안 함)", isOn: store.settings.clickThrough) { store.settings.clickThrough.toggle() }
                Text("위치").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                SegmentRow(options: StripSettings.Alignment.allCases, selected: store.settings.alignment,
                           label: { $0.name }, onSelect: { store.settings.alignment = $0 })
                let screenCount = max(1, NSScreen.screens.count)
                if screenCount > 1 {
                    Text("모니터").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                    SegmentRow(options: Array(0..<screenCount), selected: min(store.settings.screenIndex, screenCount - 1),
                               label: { "모니터 \($0 + 1)" }, onSelect: { store.settings.screenIndex = $0 })
                }
            }

            HStack {
                Button("원정 본부 열기", action: onOpenHQ).buttonStyle(GameButtonStyle())
                Spacer()
                Button("종료") {
                    store.save()
                    NSApp.terminate(nil)
                }
                .buttonStyle(GameButtonStyle(color: Theme.panelHi))
            }
            Text("띠를 두 번 클릭해도 본부가 열려요 (클릭 통과를 끈 경우)")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
    }
}
