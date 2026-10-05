import CoreGraphics
import Foundation

/// One rendered rectangle of the treemap.
struct TreemapCell {
    let node: FileNode
    var rect: CGRect
    /// Cushion surface polynomial coefficients: [x², y², x, y] in image space.
    var surface: SIMD4<Double>
    var color: UInt32
}

struct TreemapLayout {
    var cells: [TreemapCell] = []
    var pixelSize: CGSize = .zero
    /// Rect of every node the builder visited, for O(1) selection highlighting.
    var nodeRects: [ObjectIdentifier: CGRect] = [:]
    var rootRect: CGRect = .zero
}

enum TreemapBuilder {

    /// Cushion parameters, matching WinDirStat's defaults closely.
    static let ridgeHeight = 0.36
    static let scaleFactor = 0.86
    static let maxDepth = 24
    static let minCellArea: CGFloat = 12
    static let cellBudget = 400_000

    static func build(root: FileNode,
                      pixelSize: CGSize,
                      sizeMode: SizeMode,
                      colorForExtIndex: [Int]) -> TreemapLayout {
        var layout = TreemapLayout()
        layout.pixelSize = pixelSize
        guard pixelSize.width >= 2, pixelSize.height >= 2 else { return layout }

        let rect = CGRect(origin: .zero, size: pixelSize)
        layout.rootRect = rect
        layout.cells.reserveCapacity(4096)

        var context = Context(sizeMode: sizeMode, colorForExtIndex: colorForExtIndex)
        recurse(node: root,
                rect: rect,
                surface: SIMD4<Double>(repeating: 0),
                height: ridgeHeight,
                depth: 0,
                isRoot: true,
                context: &context,
                cells: &layout.cells,
                nodeRects: &layout.nodeRects)
        return layout
    }

    private struct Context {
        let sizeMode: SizeMode
        let colorForExtIndex: [Int]

        func color(for node: FileNode) -> UInt32 {
            if node.isDirectory { return Palette.directoryColor }
            let index = Int(node.extIndex)
            guard index >= 0, index < colorForExtIndex.count else { return Palette.otherColor }
            let paletteIndex = colorForExtIndex[index]
            return paletteIndex == Palette.otherColorIndex ? Palette.otherColor : Palette.packed(paletteIndex)
        }
    }

    private static func recurse(node: FileNode,
                                rect: CGRect,
                                surface: SIMD4<Double>,
                                height: Double,
                                depth: Int,
                                isRoot: Bool,
                                context: inout Context,
                                cells: inout [TreemapCell],
                                nodeRects: inout [ObjectIdentifier: CGRect]) {
        guard rect.width >= 0.5, rect.height >= 0.5 else { return }
        nodeRects[ObjectIdentifier(node)] = rect

        var localSurface = surface
        if !isRoot {
            addRidge(rect: rect, surface: &localSurface, height: height)
        }

        let children = node.children ?? []
        let area = rect.width * rect.height
        let canRecurse = node.isDirectory
            && !children.isEmpty
            && area >= minCellArea
            && depth < maxDepth
            && cells.count < cellBudget

        guard canRecurse else {
            cells.append(TreemapCell(node: node,
                                     rect: rect,
                                     surface: localSurface,
                                     color: context.color(for: node)))
            return
        }

        let mode = context.sizeMode
        var entries: [(node: FileNode, value: Double)] = []
        entries.reserveCapacity(children.count)
        var total = 0.0
        for child in children {
            let value = Double(child.value(mode))
            if value <= 0 { continue }
            entries.append((child, value))
            total += value
        }

        guard total > 0, !entries.isEmpty else {
            cells.append(TreemapCell(node: node,
                                     rect: rect,
                                     surface: localSurface,
                                     color: context.color(for: node)))
            return
        }

        entries.sort { $0.value > $1.value }

        let scale = Double(area) / total
        let areas = entries.map { $0.value * scale }
        let childHeight = height * scaleFactor

        squarify(areas: areas, rect: rect) { index, childRect in
            recurse(node: entries[index].node,
                    rect: childRect,
                    surface: localSurface,
                    height: childHeight,
                    depth: depth + 1,
                    isRoot: false,
                    context: &context,
                    cells: &cells,
                    nodeRects: &nodeRects)
        }
    }

    /// Van Wijk cushion ridge: raises a parabolic bump over `rect`.
    private static func addRidge(rect: CGRect, surface: inout SIMD4<Double>, height: Double) {
        let width = Double(rect.width)
        let heightPx = Double(rect.height)
        if width > 0 {
            surface[2] += 4 * height * Double(rect.maxX + rect.minX) / width
            surface[0] -= 4 * height / width
        }
        if heightPx > 0 {
            surface[3] += 4 * height * Double(rect.maxY + rect.minY) / heightPx
            surface[1] -= 4 * height / heightPx
        }
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). `areas` must be descending.
    private static func squarify(areas: [Double], rect: CGRect, place: (Int, CGRect) -> Void) {
        var remaining = rect
        var index = 0
        let count = areas.count

        while index < count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }

            var sum = 0.0
            var rowMin = Double.greatestFiniteMagnitude
            var rowMax = 0.0
            var worst = Double.greatestFiniteMagnitude
            var end = index

            while end < count {
                let value = areas[end]
                let newSum = sum + value
                let newMin = min(rowMin, value)
                let newMax = max(rowMax, value)
                let sideSquared = side * side
                let sumSquared = newSum * newSum
                let candidate = max(sideSquared * newMax / sumSquared,
                                    sumSquared / (sideSquared * newMin))
                if end > index && candidate > worst { break }
                worst = candidate
                sum = newSum
                rowMin = newMin
                rowMax = newMax
                end += 1
            }

            let isLastRow = end >= count
            let horizontal = remaining.width < remaining.height
            var thickness = sum / side
            if isLastRow {
                thickness = horizontal ? Double(remaining.height) : Double(remaining.width)
            }
            thickness = min(thickness, horizontal ? Double(remaining.height) : Double(remaining.width))

            var offset = 0.0
            for position in index..<end {
                let isLastInRow = position == end - 1
                var extent = thickness > 0 ? areas[position] / thickness : 0
                if isLastInRow {
                    extent = (horizontal ? Double(remaining.width) : Double(remaining.height)) - offset
                }
                extent = max(0, extent)

                let childRect: CGRect
                if horizontal {
                    childRect = CGRect(x: remaining.minX + CGFloat(offset),
                                       y: remaining.minY,
                                       width: CGFloat(extent),
                                       height: CGFloat(thickness))
                } else {
                    childRect = CGRect(x: remaining.minX,
                                       y: remaining.minY + CGFloat(offset),
                                       width: CGFloat(thickness),
                                       height: CGFloat(extent))
                }
                place(position, childRect)
                offset += extent
            }

            if horizontal {
                remaining = CGRect(x: remaining.minX,
                                   y: remaining.minY + CGFloat(thickness),
                                   width: remaining.width,
                                   height: max(0, remaining.height - CGFloat(thickness)))
            } else {
                remaining = CGRect(x: remaining.minX + CGFloat(thickness),
                                   y: remaining.minY,
                                   width: max(0, remaining.width - CGFloat(thickness)),
                                   height: remaining.height)
            }
            index = end
        }
    }
}
