import SwitchIconGenKit
import SwiftUI

/// Confirms an apply or restore, listing each target with its current icon.
struct ConfirmChangeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let change: PendingChange

    private var isApply: Bool { change.kind == .apply }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                if isApply, let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(isApply
                         ? "These items will show the new icon in Finder and the Dock. You can undo this afterwards."
                         : "These items will go back to their built-in icon. You can undo this afterwards.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(change.targets.enumerated()), id: \.element) { index, url in
                    if index > 0 { Divider() }
                    TargetRow(url: url, isApply: isApply)
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isApply ? "Apply Icon" : "Restore Original") {
                    model.confirmPendingChange()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var title: String {
        let count = change.targets.count
        let what = count == 1 ? IconApplier.displayName(change.targets[0]) : "\(count) items"
        return isApply ? "Apply this icon to \(what)?" : "Restore the original icon of \(what)?"
    }
}

private struct TargetRow: View {
    let url: URL
    let isApply: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconApplier.currentIcon(of: url))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(IconApplier.displayName(url))
                    .fontWeight(.medium)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isApply && IconApplier.hasCustomIcon(url) {
                Text("Replaces custom icon")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !isApply && !IconApplier.hasCustomIcon(url) {
                Text("Already original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// The message bar over the canvas.
struct BannerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let banner = model.banner {
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: banner.style))
                        .foregroundStyle(color(for: banner.style))
                    Text(banner.message)
                        .font(.callout)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if banner.change != nil {
                        Button("Undo") { model.undo(banner) }
                    }
                    Button("Dismiss", systemImage: "xmark") { model.banner = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Dismiss")
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 560)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: banner.id) {
                    guard banner.dismissesAutomatically else { return }
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, model.banner?.id == banner.id else { return }
                    withAnimation { model.banner = nil }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .animation(.snappy, value: model.banner?.id)
    }

    private func symbol(for style: Banner.Style) -> String {
        switch style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private func color(for style: Banner.Style) -> Color {
        switch style {
        case .info: .secondary
        case .success: .green
        case .failure: .orange
        }
    }
}
