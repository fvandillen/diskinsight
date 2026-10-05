import SwiftUI

struct TreemapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hoverNode: FileNode?
    @State private var hoverPoint: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)

                    if let image = model.treemapImage {
                        Image(decorative: image, scale: scale)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if let rect = selectionRect(in: geo.size) {
                        Rectangle()
                            .stroke(Color.black.opacity(0.85), lineWidth: 3)
                            .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                            .frame(width: max(rect.width, 3), height: max(rect.height, 3))
                            .offset(x: rect.minX - 1, y: rect.minY - 1)
                            .allowsHitTesting(false)
                    }

                    if model.treemapImage == nil {
                        placeholder
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { model.setTreemapViewport(pixelSize: pixels(geo.size, scale), scale: scale) }
                .onChange(of: geo.size) { _, newValue in
                    model.setTreemapViewport(pixelSize: pixels(newValue, scale), scale: scale)
                }
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            if let node = node(at: value.location, in: geo.size) {
                                let target = node.isDirectory ? node : (node.parent ?? node)
                                model.zoomTreemap(to: target)
                            }
                        }
                )
                .gesture(
                    SpatialTapGesture(count: 1)
                        .onEnded { value in
                            if let node = node(at: value.location, in: geo.size) {
                                model.select(node: node)
                            }
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                        hoverNode = node(at: point, in: geo.size)
                    case .ended:
                        hoverPoint = nil
                        hoverNode = nil
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hoverNode, let hoverPoint {
                        tooltip(for: hoverNode)
                            .offset(x: min(max(0, hoverPoint.x + 14), max(0, geo.size.width - 320)),
                                    y: min(max(0, hoverPoint.y + 18), max(0, geo.size.height - 46)))
                            .allowsHitTesting(false)
                    }
                }
                .contextMenu {
                    if let hoverNode {
                        NodeContextMenu(node: hoverNode)
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.fill.square")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.isScanning ? "Building map…" : "The treemap appears here after a scan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Treemap")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if let treemapRoot = model.treemapRoot {
                Text(treemapRoot.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if model.isRenderingTreemap {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }

            Button {
                model.zoomTreemapOut()
            } label: {
                Label("Zoom Out", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Zoom out one level")
            .disabled(model.treemapRoot?.parent == nil)

            Button {
                model.resetTreemapZoom()
            } label: {
                Label("Whole Tree", systemImage: "arrow.counterclockwise")
            }
            .help("Reset treemap zoom")
            .disabled(model.treemapRoot == nil || model.treemapRoot === model.root)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tooltip(for node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(node.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text("\(Format.bytes(node.value(model.sizeMode)))  ·  \(node.path)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.15)))
        .shadow(radius: 4, y: 1)
    }

    private func pixels(_ size: CGSize, _ scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private func node(at point: CGPoint, in size: CGSize) -> FileNode? {
        let pixelSize = model.treemapPixelSize
        guard size.width > 0, size.height > 0, pixelSize.width > 0 else { return nil }
        let scaled = CGPoint(x: point.x / size.width * pixelSize.width,
                             y: point.y / size.height * pixelSize.height)
        return model.node(atTreemapPoint: scaled)
    }

    private func selectionRect(in size: CGSize) -> CGRect? {
        // Highlighting the treemap root would just outline the whole panel.
        guard let selected = model.selectedNode, selected !== model.treemapRoot else { return nil }
        guard let rect = model.selectionRectInTreemap else { return nil }
        let pixelSize = model.treemapPixelSize
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let scaleX = size.width / pixelSize.width
        let scaleY = size.height / pixelSize.height
        return CGRect(x: rect.minX * scaleX,
                      y: rect.minY * scaleY,
                      width: rect.width * scaleX,
                      height: rect.height * scaleY)
    }
}
