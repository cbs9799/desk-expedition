import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x171A24)
    static let panel = Color(hex: 0x222736)
    static let panelHi = Color(hex: 0x2C3245)
    static let gold = Color(hex: 0xFFD23F)
    static let accent = Color(hex: 0x6C8CFF)
    static let text = Color.white
    static let dim = Color.white.opacity(0.6)
}

/// Custom-drawn button so it looks game-like and renders in ImageRenderer snapshots.
struct GameButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            // Disabled stays readable: muted text on a faint tint of the button's own color.
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.72))
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(enabled ? color.opacity(configuration.isPressed ? 0.7 : 1) : color.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(enabled ? Color.clear : color.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

struct ToggleRow: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.text)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Color(hex: 0x58D26B) : Color.white.opacity(0.18)).frame(width: 32, height: 18)
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SegmentRow<T: Hashable>: View {
    let options: [T]
    let selected: T
    let label: (T) -> String
    var enabled: (T) -> Bool = { _ in true }
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { opt in
                Button { onSelect(opt) } label: {
                    Text(LocalizedStringKey(label(opt)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(opt == selected ? Color.black : Theme.text.opacity(enabled(opt) ? 0.85 : 0.35))
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(opt == selected ? Theme.gold : Color.white.opacity(0.07)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled(opt))
            }
        }
    }
}

struct Bar: View {
    let fraction: Double
    var color: Color = Color(hex: 0x58D26B)
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.4))
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// Pixel-art icon for an item (generated sheets `items_base`, `items_unique_a/b`), SF Symbol fallback.
struct ItemIcon: View {
    let item: Item
    var size: CGFloat = 36

    var body: some View {
        let (key, frame) = item.iconRef
        if let sheet = SpriteSheet.named(key), let cg = sheet.cgImage(frame: frame) {
            let s = size / CGFloat(max(sheet.meta.cellW, sheet.meta.cellH))
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(sheet.meta.cellW) * s, height: CGFloat(sheet.meta.cellH) * s)
        } else {
            Image(systemName: item.slot == .weapon ? "bolt.fill" : "shield.lefthalf.filled")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color(hex: item.rarity.colorHex))
        }
    }
}

struct ItemCell: View {
    let item: Item?
    var selected = false
    var upgrade = false
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.panelHi)
            if let item {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(hex: item.rarity.colorHex), lineWidth: selected ? 3 : 1.5)
                // Rarity glow behind the pixel icon.
                RadialGradient(colors: [Color(hex: item.rarity.colorHex, opacity: item.rarity >= .rare ? 0.45 : 0.18), .clear],
                               center: .center, startRadius: 0, endRadius: size * 0.5)
                ItemIcon(item: item, size: size * 0.78)
                if upgrade {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x58D26B))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
    }
}
