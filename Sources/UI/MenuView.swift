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
                    Text(p.isBossWave ? "보스전!" : p.stageText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(p.isBossWave ? Color(hex: 0xFF7A7A) : Theme.dim)
                }
                Bar(fraction: Double(p.pipWave - 1) / Double(Region.wavesPerRegion - 1), color: Theme.gold, height: 5)
                ForEach(Array(p.heroes.enumerated()), id: \.offset) { i, hero in
                    HStack(spacing: 8) {
                        Text("\(hero.displayName) Lv.\(hero.level)")
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

            AIConnectSection()

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

/// "AI 원정대장" — connect a subscription AI (Claude, Codex…) over MCP and watch what it does.
struct AIConnectSection: View {
    @Environment(GameStore.self) private var store
    @State private var copied: String?

    private var exe: String { Bundle.main.executablePath ?? "/Applications/DeskExpedition.app/Contents/MacOS/DeskExpedition" }

    private var snippets: [(String, String)] {[
        ("Claude Code", "claude mcp add --scope user desk-expedition -- \"\(exe)\" --mcp"),
        ("Claude Desktop", """
        "desk-expedition": { "command": "\(exe)", "args": ["--mcp"] }
        """),
        ("Codex", """
        [mcp_servers.desk-expedition]
        command = "\(exe)"
        args = ["--mcp"]
        """),
        ("자동 플레이", "bash \"\(Bundle.main.resourcePath ?? "/Applications/DeskExpedition.app/Contents/Resources")/ai-autoplay.sh\" install claude 30"),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(store.aiConnected ? Color(hex: 0x6BE36F) : Color.white.opacity(0.25)).frame(width: 7, height: 7)
                Text("AI 원정대장").font(.system(size: 12, weight: .heavy, design: .rounded))
                Spacer()
                Text(store.aiConnected ? "연결됨" : "대기 중")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.dim)
            }
            Text("구독 중인 AI(Claude·Codex 등)에 연결하면 AI가 레벨업·장비·가방·지역·이사를 알아서 해요. 아래 설정을 AI 앱에 붙여 넣고, AI에게 \"책상 원정대 돌봐 줘\"라고 하세요.")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(snippets, id: \.0) { name, text in
                    Button(copied == name ? "복사됨" : name) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = name
                    }
                    .buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                }
            }
            ForEach(store.aiLog.suffix(3).reversed()) { line in
                Text("🤖 \(line.text)").font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x9CF4FF)).lineLimit(2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }
}
