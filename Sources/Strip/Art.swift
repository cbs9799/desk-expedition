import AppKit
import SpriteKit
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

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// On-screen size of one art pixel (3 device pixels on Retina).
enum PixelArt {
    static let scale: CGFloat = 1.5
}

/// A processed sprite sheet from `Resources/Art` (see scripts/art/process.py):
/// equal cells, every frame bottom-aligned with its feet column at `anchorX`.
final class SpriteSheet {
    struct Meta: Decodable {
        let cellW: Int, cellH: Int, rows: Int, cols: Int, anchorX: Int
        let frameHeights: [Int]
        let anims: [String: [Int]]
    }

    let key: String
    let meta: Meta
    let image: CGImage
    let frames: [SKTexture]

    private init?(key: String) {
        guard let pngURL = Bundle.main.url(forResource: key, withExtension: "png"),
              let jsonURL = Bundle.main.url(forResource: key, withExtension: "json"),
              let data = try? Data(contentsOf: jsonURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              let src = CGImageSourceCreateWithURL(pngURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.key = key
        self.meta = meta
        self.image = image
        let sheet = SKTexture(cgImage: image)
        sheet.filteringMode = .nearest
        var frames: [SKTexture] = []
        let w = CGFloat(meta.cellW * meta.cols), h = CGFloat(meta.cellH * meta.rows)
        for i in 0..<(meta.rows * meta.cols) {
            let r = i / meta.cols, c = i % meta.cols
            // SpriteKit texture rects are unit-space with a bottom-left origin.
            let rect = CGRect(x: CGFloat(c * meta.cellW) / w, y: 1 - CGFloat((r + 1) * meta.cellH) / h,
                              width: CGFloat(meta.cellW) / w, height: CGFloat(meta.cellH) / h)
            let t = SKTexture(rect: rect, in: sheet)
            t.filteringMode = .nearest
            frames.append(t)
        }
        self.frames = frames
    }

    /// Feet position inside a cell, as a SpriteKit anchor point.
    var anchor: CGPoint { CGPoint(x: (CGFloat(meta.anchorX) + 0.5) / CGFloat(meta.cellW), y: 0) }

    func frames(_ anim: String) -> [SKTexture] {
        (meta.anims[anim] ?? [0]).map { frames[$0] }
    }

    /// Height (art px) of the first frame of an animation — used to place HP bars and hats.
    func height(_ anim: String) -> Int {
        meta.frameHeights[(meta.anims[anim] ?? [0]).first ?? 0]
    }

    /// Height (art px, from the feet) of a given frame of an animation.
    func frameHeight(_ anim: String, _ i: Int) -> Int {
        guard let list = meta.anims[anim], !list.isEmpty else { return meta.frameHeights.first ?? 0 }
        return meta.frameHeights[list[i % list.count]]
    }

    /// A single cell as a CGImage (for SwiftUI portraits).
    func cgImage(frame: Int) -> CGImage? {
        let r = frame / meta.cols, c = frame % meta.cols
        return image.cropping(to: CGRect(x: c * meta.cellW, y: r * meta.cellH, width: meta.cellW, height: meta.cellH))
    }

    // MARK: Cache

    @MainActor private static var cache: [String: SpriteSheet] = [:]

    @MainActor static func named(_ key: String) -> SpriteSheet? {
        if let s = cache[key] { return s }
        let s = SpriteSheet(key: key)
        cache[key] = s
        return s
    }
}

/// Tileable background bands (`bg_<scene>_far.png`, `bg_<scene>_ground.png`).
/// Stored pre-upscaled ×3 with nearest neighbour (one texel per Retina pixel), so the bands stay
/// crisp even when a custom shader samples them with linear filtering.
@MainActor
enum Backdrop {
    static let upscale = 3
    /// Node scale that shows one art pixel as `PixelArt.scale` points.
    static var nodeScale: CGFloat { PixelArt.scale / CGFloat(upscale) }

    static func texture(_ name: String) -> SKTexture? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = image.width * upscale, h = image.height * upscale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let big = ctx.makeImage() else { return nil }
        let t = SKTexture(cgImage: big)
        t.filteringMode = .nearest
        return t
    }
}

/// Crisp pixel portrait for SwiftUI screens (HQ, menu): the first idle frame of a hero sheet.
struct HeroPortrait: View {
    let heroClass: HeroClass
    var accessory: Int? = nil
    var scale: CGFloat = 3

    var body: some View {
        if let sheet = SpriteSheet.named(heroClass.spriteKey),
           let cg = sheet.cgImage(frame: sheet.meta.anims["idle"]?.first ?? 0) {
            ZStack(alignment: .bottom) {
                Image(decorative: cg, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: CGFloat(sheet.meta.cellW) * scale, height: CGFloat(sheet.meta.cellH) * scale)
                if let a = accessory, a > 0, let hats = SpriteSheet.named("accessories"),
                   let hat = hats.cgImage(frame: a - 1) {
                    Image(decorative: hat, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(hats.meta.cellW) * scale, height: CGFloat(hats.meta.cellH) * scale)
                        .offset(x: CGFloat(HatPlacement.offsetX(heroClass)) * scale,
                                y: -CGFloat(sheet.height("idle") - HatPlacement.sink(heroClass)) * scale)
                }
            }
        } else {
            Image(systemName: "person.fill").font(.system(size: 28))
        }
    }
}

/// Where a hat sits on each hero's head (art px from the feet column / from the top of the head).
enum HatPlacement {
    static func offsetX(_ c: HeroClass) -> Int {
        switch c { case .warrior: return 2; case .archer: return 1; case .mage: return 0 }
    }
    /// How far the hat sinks into the top of the sprite (pointy mage hat needs more).
    static func sink(_ c: HeroClass) -> Int {
        switch c { case .warrior: return 3; case .archer: return 3; case .mage: return 5 }
    }
}
