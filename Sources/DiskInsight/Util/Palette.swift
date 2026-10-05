import SwiftUI

/// WinDirStat-style bright, well-separated colours for the treemap and the
/// extension list. Index `otherColorIndex` is the catch-all grey.
enum Palette {
    /// Packed 0x00RRGGBB values.
    static let colors: [UInt32] = [
        0x4E9BE8, // blue
        0xE8524E, // red
        0x5FC463, // green
        0xF0B429, // amber
        0xA05FE8, // purple
        0x2FC2C0, // teal
        0xE87CB8, // pink
        0x8FBF3F, // olive
        0xE8873A, // orange
        0x6C79E8, // indigo
        0x39C48E, // emerald
        0xD44FD1, // magenta
        0x2E8FA8, // steel
        0xC9A227, // gold
        0x7E57C2, // violet
        0x4DB6AC, // aqua
        0xEF5350, // coral
        0x66BB6A, // leaf
        0x42A5F5, // sky
        0xFFA726, // tangerine
        0xAB47BC, // orchid
        0x26A69A, // jade
        0xEC407A, // rose
        0x9CCC65  // lime
    ]

    static let otherColorIndex = colors.count
    static let distinctColorCount = colors.count

    /// Neutral colours appended after the distinct palette.
    static let otherColor: UInt32 = 0x9AA0A6
    static let directoryColor: UInt32 = 0x8C93A0

    static func packed(_ index: Int) -> UInt32 {
        index >= 0 && index < colors.count ? colors[index] : otherColor
    }

    /// WinDirStat's `MakeBrightColor`: scale a colour so its mean channel hits
    /// `target`, redistributing any overflow instead of clipping (which would
    /// wash out the hue).
    static func brightened(_ packed: UInt32, target: Double = 0.70) -> (r: Double, g: Double, b: Double) {
        var red = Double((packed >> 16) & 0xFF) / 255
        var green = Double((packed >> 8) & 0xFF) / 255
        var blue = Double(packed & 0xFF) / 255

        let sum = max(red + green + blue, 0.0001)
        let factor = 3 * target / sum
        red *= factor
        green *= factor
        blue *= factor

        normalize(&red, &green, &blue)
        return (red * 255, green * 255, blue * 255)
    }

    private static func normalize(_ red: inout Double, _ green: inout Double, _ blue: inout Double) {
        if red > 1 {
            distribute(&red, &green, &blue)
        } else if green > 1 {
            distribute(&green, &red, &blue)
        } else if blue > 1 {
            distribute(&blue, &red, &green)
        }
    }

    private static func distribute(_ first: inout Double, _ second: inout Double, _ third: inout Double) {
        let overflow = (first - 1) / 2
        first = 1
        second += overflow
        third += overflow
        if second > 1 {
            third += second - 1
            second = 1
        } else if third > 1 {
            second += third - 1
            third = 1
        }
        second = min(second, 1)
        third = min(third, 1)
    }

    static func swiftUIColor(_ index: Int) -> Color {
        let packed = Self.packed(index)
        return Color(.sRGB,
                     red: Double((packed >> 16) & 0xFF) / 255.0,
                     green: Double((packed >> 8) & 0xFF) / 255.0,
                     blue: Double(packed & 0xFF) / 255.0)
    }
}
