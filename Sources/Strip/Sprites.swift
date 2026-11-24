import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// A tiny pixel sprite defined by a character grid + palette (placeholder art until licensed assets land).
struct PixelSprite {
    struct Pixel { let x: Int; let y: Int; let key: Character }

    let width: Int
    let height: Int
    let pixels: [Pixel]
    let palette: [Character: UInt32]

    init(_ rows: [String], palette: [Character: UInt32]) {
        width = rows.map(\.count).max() ?? 0
        height = rows.count
        var px: [Pixel] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                px.append(Pixel(x: x, y: y, key: ch))
            }
        }
        pixels = px
        self.palette = palette
    }

    /// Draws with the sprite's feet at `bottomCenter`.
    func draw(in ctx: GraphicsContext, bottomCenter: CGPoint, scale: CGFloat, flipped: Bool = false,
              overrides: [Character: UInt32] = [:], flash: Bool = false, opacity: Double = 1) {
        let originX = bottomCenter.x - CGFloat(width) * scale / 2
        let originY = bottomCenter.y - CGFloat(height) * scale
        for p in pixels {
            let col = flipped ? (width - 1 - p.x) : p.x
            let rect = CGRect(x: originX + CGFloat(col) * scale, y: originY + CGFloat(p.y) * scale,
                              width: scale + 0.3, height: scale + 0.3)
            let hex = flash ? 0xFFFFFF : (overrides[p.key] ?? palette[p.key] ?? 0xFF00FF)
            ctx.fill(Path(rect), with: .color(Color(hex: hex, opacity: opacity)))
        }
    }
}

enum Sprites {
    static let common: [Character: UInt32] = [
        "s": 0xF2C9A0, "e": 0x1E1E28, "l": 0x444C5C, "b": 0x5B3B22, "w": 0xFFFFFF,
    ]

    static let warrior = PixelSprite([
        "...hhhh...",
        "..hhhhhh..",
        "..hssssh..",
        "..sesses.x",
        "...ssss..x",
        ".aaaaaaa.x",
        "saaaaaaasx",
        "s.aaBaa.sg",
        "..aaaaa...",
        "..ll.ll...",
        "..bb.bb...",
    ], palette: common.merging(["h": 0xB8C0CC, "a": 0x3B6FD8, "B": 0x8A5A2B, "x": 0xE6EBF2, "g": 0xC08A2E]) { $1 })

    static let archer = PixelSprite([
        "...ffff...",
        "..ffffff.k",
        "..fssssf.k",
        "..sesses..k",
        "...ssss...k",
        ".ggggggg..k",
        "sgggggggs.k",
        "..ggBgg...k",
        "..ggggg..k",
        "..ll.ll..k",
        "..bb.bb...",
    ], palette: common.merging(["f": 0x2E7D4F, "g": 0x4CAF50, "B": 0x8A5A2B, "k": 0xA0703A]) { $1 })

    static let mage = PixelSprite([
        "....p...o.",
        "...ppp.ooo",
        "..ppppp.o.",
        ".ppppppp.t",
        "..sesse..t",
        "..ssss...t",
        ".rrrrrr..t",
        "srrrrrrs.t",
        "..rrrrr..t",
        "..rr.rr..t",
        "..bb.bb...",
    ], palette: common.merging(["p": 0x6A3FB5, "o": 0x7FE7FF, "t": 0x8B5A2B, "r": 0x8E5CD9]) { $1 })

    static let heroes: [PixelSprite] = [warrior, archer, mage]

    static let slime = PixelSprite([
        "...mmmm...",
        "..mmmmmm..",
        ".mmwmmwmm.",
        ".mmemmemm.",
        "mmmmmmmmmm",
        "mmmmddmmmm",
        ".dddddddd.",
    ], palette: common)

    static let bat = PixelSprite([
        "m........m",
        "mm......mm",
        "mmm.mm.mmm",
        ".mmmmmmmm.",
        "..mwmmwm..",
        "..memmem..",
        "...mddm...",
        "....mm....",
        "..........",
        "..........",
    ], palette: common)

    static let golem = PixelSprite([
        "...mmmm...",
        "..mmmmmm..",
        "..mwmmwm..",
        "..memmem..",
        "...mddm...",
        ".dmmmmmmd.",
        "dmmmmmmmmd",
        "d.mmmmmm.d",
        "..mmmmmm..",
        "..mm..mm..",
        "..dd..dd..",
    ], palette: common)

    static let crown = PixelSprite([
        "y.y.y",
        "yyyyy",
    ], palette: ["y": 0xFFD23F])

    static let monsters: [PixelSprite] = [slime, bat, golem]
}

/// Static pixel portrait for SwiftUI layouts (HQ window, menu).
struct SpriteView: View {
    let sprite: PixelSprite
    var scale: CGFloat = 4
    var overrides: [Character: UInt32] = [:]

    var body: some View {
        Canvas { ctx, size in
            sprite.draw(in: ctx, bottomCenter: CGPoint(x: size.width / 2, y: size.height),
                        scale: scale, overrides: overrides)
        }
        .frame(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale)
    }
}
