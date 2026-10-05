import SwiftUI

/// Primary action bar.
///
/// The Scan control lives here rather than in the window toolbar because macOS
/// toolbars impose their own chrome — they drop the button's text label and
/// ignore `.borderedProminent`, which made the main action of the app look like
/// a dim icon. Here it is unmistakably the primary button.
struct ScanBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            scanButton

            if model.isScanning {
                Button(role: .destructive) {
                    model.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.large)
            } else if model.root != nil {
                Button {
                    if let root = model.root { model.scan(url: root.url) }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.large)
                .help("Scan the current folder again (⌘R)")
            }

            location

            Spacer(minLength: 8)

            Picker("", selection: $model.sizeMode) {
                ForEach(SizeMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 168)
            .help("Show bytes actually allocated on disk, or logical file size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Split button: a filled accent "Scan" action plus a menu of quick targets.
    ///
    /// `Menu` with a custom label refuses to draw a background on macOS, so the
    /// filled part is a real `Button` with `.borderedProminent` and the chooser
    /// sits beside it.
    private var scanButton: some View {
        HStack(spacing: 4) {
            Button {
                model.chooseFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                    Text("Scan")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(height: 15)
                .padding(.horizontal, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .help("Choose a folder or volume to analyse (⌘O)")

            Menu {
                ForEach(model.scanTargets) { target in
                    Button {
                        model.scan(url: target.url)
                    } label: {
                        Label(target.title, systemImage: target.isVolume ? "internaldrive" : "house")
                    }
                }
                Divider()
                Button("Choose Folder…") { model.chooseFolder() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Scan a common location")
        }
        .disabled(model.isScanning)
    }

    @ViewBuilder
    private var location: some View {
        if let root = model.root {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(root.path)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
        }
    }
}
