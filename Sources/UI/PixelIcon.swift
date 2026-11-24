import SwiftUI

/// Pixel-art UI icons (generated sheet `icons`, 2×8) replacing emoji in the game's windows.
enum GameIcon: Int, CaseIterable {
    case coin, calendar, lock, robot, star, check, puzzle, paw
    case medal, scale, swords, shield, moneyBag, moon, flame, upArrow
}

extension Tactic {
    var gameIcon: GameIcon { [.scale, .swords, .shield, .moneyBag][rawValue] }
}

struct PixelIcon: View {
    let icon: GameIcon
    var size: CGFloat = 14

    init(_ icon: GameIcon, size: CGFloat = 14) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        if let sheet = SpriteSheet.named("icons"), let cg = sheet.cgImage(frame: icon.rawValue) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(CGFloat(sheet.meta.cellW) / CGFloat(sheet.meta.cellH), contentMode: .fit)
                .frame(height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// "[icon] text" in one line, baseline-friendly.
struct IconText: View {
    let icon: GameIcon
    let text: String
    var size: CGFloat = 14
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            PixelIcon(icon, size: size)
            Text(text)
        }
    }
}
