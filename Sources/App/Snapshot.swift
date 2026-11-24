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
        p.heroes[0].armor = Item(slot: .armor, rarity: .rare, name: "공책 골무 투구", power: 92, regionIndex: 0)
        p.heroes[1].weapon = Item(slot: .weapon, rarity: .uncommon, name: "연필꽂이 클립 활", power: 12, regionIndex: 1)
        p.heroes[2].weapon = Item(slot: .weapon, rarity: .legendary, name: "공책 크레용 지팡이", power: 11, regionIndex: 0)
        p.heroes[1].accessory = 4
        p.heroes[2].accessory = 2
        for _ in 0..<13 { p.bag.append(Engine.makeItem(region: Int.random(in: 0...1, using: &rng), boss: false, rng: &rng)) }
        p.bag.append(Engine.makeItem(region: 1, boss: true, rng: &rng))
        p.gold = 4_830
        p.totalKills = 1_284
        p.bossKills = 1

        let store = GameStore(progress: p, persist: false)
        store.lastOffline = OfflineReport(seconds: 3 * 3600 + 25 * 60, kills: 812, gold: 6_420, items: 9, autoSold: 0, bosses: 0)
        store.banner = nil
        return store
    }

    /// Runs the engine (10 Hz) and the scene (60 Hz) together until a lively moment: a full enemy line
    /// engaged and a fresh spell exploding.
    static func liveStrip(_ store: GameStore) -> CGImage? {
        guard let off = StripOffscreen(store: store) else { return nil }
        var boltSeen = false, after = 0
        for tick in 0..<4000 {
            store.step(dt: 0.1)
            for _ in 0..<6 { off.step(1.0 / 60) }
            let b = store.battle
            let lively = tick > 80 && b.monsters.count >= 3 && b.heroes.allSatisfy(\.alive)
                && b.monsters.contains { $0.x <= Engine.frontSlotX + 4 }
            if lively && !boltSeen, b.effects.contains(where: { if case .bolt = $0.kind { return b.time - $0.born < 0.05 } else { return false } }) {
                boltSeen = true
            }
            if boltSeen { after += 1; if after == 4 { break } }
        }
        store.banner = nil
        return off.image()
    }

    /// `--frames <dir>`: dumps 0.1 s strip frames for eyeballing animation.
    static func dumpFrames(to dir: URL, seconds: Double = 12) {
        let store = demoStore()
        guard let off = StripOffscreen(store: store) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out = dir
        for i in 0..<Int(seconds * 10) {
            store.step(dt: 0.1)
            for _ in 0..<6 { off.step(1.0 / 60) }
            guard let img = off.image() else { continue }
            let rep = NSBitmapImageRep(cgImage: img)
            let url = out.appendingPathComponent(String(format: "f%04d.png", i))
            if (try? rep.representation(using: .png, properties: [:])?.write(to: url)) == nil {
                out = FileManager.default.temporaryDirectory.appendingPathComponent("frames")
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(String(format: "f%04d.png", i)))
            }
        }
        print("frames written: \(out.path)")
    }

    static func render(to url: URL) {
        let store = demoStore()
        let strip = liveStrip(store)
        let view = Composite(strip: strip).environment(store).environment(\.staticRendering, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("snapshot failed\n".data(using: .utf8)!)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            print("snapshot written: \(url.path)")
        } catch {
            // Sandboxed builds can't write outside the container — fall back to the container's tmp dir.
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot.png")
            try? png.write(to: fallback)
            print("snapshot written: \(fallback.path)")
        }
    }

    private struct Composite: View {
        @Environment(GameStore.self) private var store
        let strip: CGImage?

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
                HQView()
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                            Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 12, height: 12)
                            Circle().fill(Color(hex: 0x28C840)).frame(width: 12, height: 12)
                        }
                        .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                    .offset(x: 40, y: 60)

                // Menu bar popover.
                MenuView()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                    .offset(x: 1480 - 300 - 24, y: 36)

                // Strip above a fake Dock.
                RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.25))
                    .frame(width: 520, height: 62)
                    .offset(x: (1480 - 520) / 2, y: 940 - 68)
                ZStack(alignment: .topLeading) {
                    if let strip {
                        Image(decorative: strip, scale: 2).interpolation(.none)
                    }
                    StripHUD(progress: store.progress, banner: nil)
                        .frame(width: StripLayout.width - StripLayout.battleWidth - 6, height: StripLayout.height)
                        .offset(x: StripLayout.battleWidth + 6)
                }
                .frame(width: StripLayout.width, height: StripLayout.height)
                .offset(x: 8, y: 940 - 72 - StripLayout.height)
            }
            .frame(width: 1480, height: 940)
        }
    }
}
