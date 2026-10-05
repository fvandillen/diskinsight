import CoreGraphics
import Foundation

/// Renders cushion-shaded treemap cells into a BGRA bitmap.
enum TreemapRenderer {

    private static let ambient = 0.20
    private static let brightness = 0.95
    // Light source: slightly up and to the left, mostly head-on.
    private static let light: (x: Double, y: Double, z: Double) = {
        let x = -1.0, y = -1.0, z = 10.0
        let length = (x * x + y * y + z * z).squareRoot()
        return (x / length, y / length, z / length)
    }()

    static func render(layout: TreemapLayout,
                       highlighted: Set<ObjectIdentifier> = [],
                       highlightAll: Bool = false) -> CGImage? {
        let width = Int(layout.pixelSize.width.rounded())
        let height = Int(layout.pixelSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let count = width * height
        let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
        buffer.initialize(repeating: 0xFF1C1C1E, count: count)

        let specular = (1 - ambient) * brightness

        for cell in layout.cells {
            let x0 = max(0, Int(cell.rect.minX.rounded()))
            let y0 = max(0, Int(cell.rect.minY.rounded()))
            let x1 = min(width, Int(cell.rect.maxX.rounded()))
            let y1 = min(height, Int(cell.rect.maxY.rounded()))
            guard x1 > x0, y1 > y0 else { continue }

            var (red, green, blue) = Palette.brightened(cell.color)

            if highlightAll && highlighted.contains(ObjectIdentifier(cell.node)) {
                red = min(255, red * 0.3 + 255 * 0.7)
                green = min(255, green * 0.3 + 255 * 0.7)
                blue = min(255, blue * 0.3 + 255 * 0.7)
            }

            let s0 = cell.surface[0]
            let s1 = cell.surface[1]
            let s2 = cell.surface[2]
            let s3 = cell.surface[3]

            for y in y0..<y1 {
                let ny = -(2 * s1 * (Double(y) + 0.5) + s3)
                let rowBase = y * width
                for x in x0..<x1 {
                    let nx = -(2 * s0 * (Double(x) + 0.5) + s2)
                    var cosa = (nx * light.x + ny * light.y + light.z)
                        / (nx * nx + ny * ny + 1.0).squareRoot()
                    if cosa > 1 { cosa = 1 }
                    var intensity = specular * cosa
                    if intensity < 0 { intensity = 0 }
                    intensity += ambient

                    let r = UInt32(min(255, red * intensity))
                    let g = UInt32(min(255, green * intensity))
                    let b = UInt32(min(255, blue * intensity))
                    buffer[rowBase + x] = 0xFF00_0000 | (r << 16) | (g << 8) | b
                }
            }
        }

        let bytesPerRow = width * 4
        // Copy into a CFData so the scratch buffer can be freed deterministically.
        let data = buffer.withMemoryRebound(to: UInt8.self, capacity: count * 4) { bytes in
            CFDataCreate(nil, bytes, count * 4)
        }
        buffer.deallocate()
        guard let data, let provider = CGDataProvider(data: data) else { return nil }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
