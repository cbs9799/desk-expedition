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
        for sp in Species.all.prefix(12) { p.dex[Dex.key(sp.id, .normal)] = DexEntry(count: 3, first: Date()) }
        p.trophies = [0, 1, 2]
        p.moves = 1
        p.memories = 4
        p.bossKills = 5
        p.shards = 18
        p.heroes[2].weapon?.rarity = .legendary
        for _ in 0..<13 { p.bag.append(Engine.makeItem(region: Int.random(in: 0...1, using: &rng), boss: false, rng: &rng)) }
        p.bag.append(Engine.makeItem(region: 1, boss: true, rng: &rng))
        p.gold = 4_830
        p.totalKills = 1_284
        p.bossKills = 1

        if let r = ProcessInfo.processInfo.environment["DE_REGION"].flatMap(Int.init), Region.all.indices.contains(r) {
            p.unlockedRegion = max(p.unlockedRegion, r)
            p.regionIndex = r
            p.wave = 3
        }
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

    /// `--soak <seconds>`: fast-forwards boss fights with a weak party in every region (heroes die often)
    /// to shake out renderer crashes. Prints a summary and exits.
    static func soak(seconds: Double) {
        var p = Progress()
        p.unlockedRegion = Region.all.count - 1
        p.wave = Region.wavesPerRegion
        let store = GameStore(progress: p, persist: false)
        guard let off = StripOffscreen(store: store) else { print("soak: no Metal"); return }
        var wipes = 0, bosses = 0
        let ticks = Int(seconds * 10)
        for t in 0..<ticks {
            if t % 600 == 0 {   // every simulated minute: next region, boss wave, weak party
                store.selectRegion((t / 600) % Region.all.count)
                store.progress.wave = Region.wavesPerRegion
                for i in 0..<3 { store.progress.heroes[i].level = 1 + (t / 600) * 6 }
            }
            let before = store.progress.bossKills
            var wasRetreating = false
            if case .retreating = store.battle.phase { wasRetreating = true }
            store.step(dt: 0.1)
            if store.progress.bossKills > before { bosses += 1 }
            if case .retreating = store.battle.phase, !wasRetreating { wipes += 1 }
            for _ in 0..<6 { off.step(1.0 / 60) }
            if t % 200 == 0 { _ = off.image() }
        }
        print("soak ok: \(Int(seconds))s simulated, wipes \(wipes), bosses \(bosses), kills \(store.progress.totalKills)")
    }

    /// `--bench <seconds>`: runs the live strip scene in real time at 60 fps offscreen (engine at 10 Hz) and reports
    /// CPU time, average CPU %, and memory footprint — the numbers published in docs/PERFORMANCE.md.
    static func bench(seconds: Double, fps: Double = 60) {
        let store = demoStore()
        guard let off = StripOffscreen(store: store) else { print("bench: no Metal"); return }
        func cpu() -> Double {
            var u = rusage(); getrusage(RUSAGE_SELF, &u)
            return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        }
        func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
            }
            return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
        }
        // warm up
        for _ in 0..<60 { off.step(1.0 / 60); _ = off.image() }
        let c0 = cpu(), t0 = Date(), m0 = footprintMB()
        var frame = 0, peak = m0
        while Date().timeIntervalSince(t0) < seconds {
            let target = t0.addingTimeInterval(Double(frame) / fps)
            if frame % Int(fps / 10) == 0 { store.step(dt: 0.1) }
            off.step(1.0 / fps)
            _ = off.renderOnly()
            frame += 1
            if frame % 600 == 0 { peak = max(peak, footprintMB()) }
            let wait = target.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        let wall = Date().timeIntervalSince(t0), used = cpu() - c0
        print(String(format: "bench@%.0ffps: %.0fs wall, %d frames (%.1f fps), CPU %.2fs = %.1f%% of one core, memory %.0f→%.0f MB (peak %.0f)",
                     fps, wall, frame, Double(frame) / wall, used, used / wall * 100, m0, footprintMB(), max(peak, footprintMB())))
    }

    /// `--hq W H <out.png>`: renders only the HQ window content at a given size (resizing check).
    static func renderHQ(width: CGFloat, height: CGFloat, to url: URL) {
        let store = demoStore()
        let view = HQView().environment(store).environment(\.staticRendering, true).frame(width: width, height: height)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        let target = (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil ? url
            : FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? rep.representation(using: .png, properties: [:])?.write(to: target)
        print("hq written: \(target.path)")
    }

    /// `--hq-live W H <out.png>`: renders the real HQ window (AppKit text fields, pickers, menus included)
    /// offscreen via NSView caching — checks colors/contrast of system controls.
    static func renderHQLive(width: CGFloat, height: CGFloat, to url: URL) {
        let store = demoStore()
        let hq = HQWindowController(store: store)
        hq.show()
        guard let w = hq.hqWindow, let view = w.contentView else { return }
        w.setContentSize(NSSize(width: width, height: height))
        w.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard let frameView = view.superview, let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])
        let target = (try? png?.write(to: url)) != nil ? url : FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? png?.write(to: target)
        print("hq-live written: \(target.path)")
    }

    /// `--frames <dir>`: dumps 0.1 s strip frames for eyeballing animation.
    static func dumpFrames(to dir: URL, seconds: Double = 12, showcase: Bool = false) {
        let store = demoStore()
        if showcase {   // force one of each rare kind into the next wave
            for _ in 0..<40 { store.step(dt: 0.1) }
            var b = store.battle
            let r = store.progress.regionIndex
            let picks: [(Int, MonsterVariant)] = [(0, .shiny), (2, .crowned), (4, .normal), (1, .normal)]
            for (i, pick) in picks.enumerated() where i < b.monsters.count || i < 4 {
                let sp = Species.of(region: r, kind: pick.0)
                var m = Monster(kind: min(sp.kind, 2), name: sp.name, maxHP: 9e9, hp: 9e9, atk: 1,
                                x: Engine.spawnX + Engine.slotSpacing * Double(i), isBoss: false, attackTimer: 2)
                m.species = sp.id
                m.variant = pick.1
                if i < b.monsters.count { b.monsters[i] = m } else { b.monsters.append(m) }
            }
            store.battle = b
        }
        let scale = ProcessInfo.processInfo.environment["DE_SCALE"].flatMap(Double.init) ?? 1
        guard let off = StripOffscreen(store: store, scale: 2 * scale) else { return }
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
                    .frame(width: 920, height: 660)
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
