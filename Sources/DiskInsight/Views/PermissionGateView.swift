import SwiftUI

/// Up-front Full Disk Access request.
///
/// Shown before the first scan so macOS never has to ask, folder by folder,
/// mid-scan. Polls in the background so granting access in System Settings
/// moves the app on without any further clicking.
struct PermissionGateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                icon

                VStack(spacing: 9) {
                    Text("Give DiskInsight Full Disk Access")
                        .font(.system(size: 21, weight: .semibold))

                    Text("macOS keeps folders like Desktop, Documents, Downloads and iCloud Drive private. Granting access once here means DiskInsight can measure your whole disk — and never has to interrupt a scan to ask again.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }

                steps

                VStack(spacing: 10) {
                    Button {
                        model.beginGrantingFullDiskAccess()
                    } label: {
                        Text(model.isAwaitingPermission ? "Waiting for access…" : "Open Full Disk Access Settings")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isAwaitingPermission)

                    if model.isAwaitingPermission {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.62)
                                .frame(width: 13, height: 13)
                            Text("Checking… this continues automatically once access is granted.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Button("Quit & Reopen") { Permissions.relaunch() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                            .help("macOS sometimes only applies the new setting after a restart")
                    }

                    Button("Continue with limited access") {
                        model.continueWithLimitedAccess()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .help("Protected folders are skipped and shown as locked. No permission prompts will appear.")
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 34)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 78, height: 78)
            Image(systemName: "lock.open.fill")
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 9) {
            step(1, "Click the button below — System Settings opens on the right page.")
            step(2, "Switch on **DiskInsight** in the list.")
            step(3, "Come back. DiskInsight continues on its own.")
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Color.accentColor, in: Circle())
            Text(.init(text))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
