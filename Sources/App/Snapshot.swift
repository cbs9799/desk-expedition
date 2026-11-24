import AppKit
import SwiftUI

/// `DeskExpedition --snapshot out.png` renders a marketing-style composite of every screen
/// (strip, menu popover, HQ window) from a deterministic, mid-game state.
@MainActor
enum Snapshot {
    static func demoStore() -> GameStore {
        var rng = SplitMix64(seed: 42)
        var p = Progress()
        p.unlockedRegion = 1
        p.regionIndex = 1
        p.wave = 6
        p.heroes[0].level = 14
        p.heroes[1].level = 13
        p.heroes[2].level = 13
        p.heroes[0].armor = Item(slot: .armor, rarity: .rare, name: "숲의 판금 갑옷", power: 92, regionIndex: 0)
        p.heroes[1].weapon = Item(slot: .weapon, rarity: .uncommon, name: "사막의 장궁", power: 12, regionIndex: 1)
        p.heroes[2].weapon = Item(slot: .weapon, rarity: .legendary, name: "숲의 룬 지팡이", power: 11, regionIndex: 0)
        for _ in 0..<13 { p.bag.append(Engine.makeItem(region: Int.random(in: 0...1, using: &rng), boss: false, rng: &rng)) }
        p.bag.append(Engine.makeItem(region: 1, boss: true, rng: &rng))
        p.gold = 4_830
        p.totalKills = 1_284
        p.bossKills = 1

        let store = GameStore(progress: p, persist: false)
        // Advance the fight to a lively moment.
        for i in 0..<3000 {
            store.step(dt: 0.1)
            let b = store.battle
            if i > 60, b.monsters.count >= 3, b.monsters.allSatisfy({ $0.x < 420 }),
               b.effects.count >= 4, b.heroes.allSatisfy({ $0.alive }) { break }
        }
        store.lastOffline = OfflineReport(seconds: 3 * 3600 + 25 * 60, kills: 812, gold: 6_420, items: 9, autoSold: 0, bosses: 0)
        store.banner = nil
        return store
    }

    static func render(to url: URL) {
        let store = demoStore()
        let view = Composite().environment(store)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("snapshot failed\n".data(using: .utf8)!)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        print("snapshot written: \(url.path)")
    }

    private struct Composite: View {
        @Environment(GameStore.self) private var store

        var body: some View {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x3B4C7A), Color(hex: 0x8A6FA8), Color(hex: 0xE3A27C)],
                               startPoint: .top, endPoint: .bottom)
                // Fake menu bar.
                HStack(spacing: 18) {
                    Image(systemName: "apple.logo")
                    Text("Finder").bold()
                    Text("파일"); Text("편집"); Text("보기")
                    Spacer()
                    Image(systemName: "shield.lefthalf.filled")
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.25)))
                    Image(systemName: "wifi"); Text("11월 24일 (화) 오후 2:41")
                }
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(width: 1480, height: 28)
                .background(Color.black.opacity(0.25))

                // HQ window.
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                        Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 12, height: 12)
                        Circle().fill(Color(hex: 0x28C840)).frame(width: 12, height: 12)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 0)
                    .offset(y: 16)
                    .zIndex(1)
                    HQView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .offset(x: 60, y: 70)

                // Menu bar popover.
                MenuView()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                    .offset(x: 1480 - 300 - 150, y: 36)

                // Strip above a fake Dock.
                RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.25))
                    .frame(width: 520, height: 62)
                    .offset(x: (1480 - 520) / 2, y: 940 - 68)
                StripCanvas(progress: store.progress, battle: store.battle, banner: store.banner)
                    .frame(width: StripLayout.width, height: StripLayout.height)
                    .offset(x: 8, y: 940 - 72 - StripLayout.height)
            }
            .frame(width: 1480, height: 940)
        }
    }
}
