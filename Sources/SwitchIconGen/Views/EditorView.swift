import SwitchIconGenKit
import SwiftUI

/// The detail column.
struct EditorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PreviewCanvas()
            .sheet(item: $model.pendingChange) { change in
                ConfirmChangeSheet(change: change)
            }
    }
}

// MARK: - Canvas

struct PreviewCanvas: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            GameHeader()
            IconPreview()
                .frame(maxWidth: 336, maxHeight: 336)
                .aspectRatio(1, contentMode: .fit)
            SizeStrip()
                .opacity(model.hasArt ? 1 : 0)
                .accessibilityHidden(!model.hasArt)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { BannerView() }
    }
}

/// The game's name and platform, or a prompt to get started.
struct GameHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if let title = model.artTitle {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let game = model.selectedGame {
                        ForEach(Platform.allCases.filter(game.platforms.contains), id: \.self) {
                            PlatformBadge(platform: $0)
                        }
                        if let year = game.releaseYear {
                            Text(year).monospacedDigit().foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Your image").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            } else {
                Text("No Game Selected")
                    .font(.title2.weight(.semibold))
                Text("Search for a game, or drop an image onto the case.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        // Fixed height so the icon doesn't move as titles change.
        .frame(maxWidth: 400, minHeight: 56, alignment: .bottom)
        .animation(nil, value: model.artTitle)
    }
}

/// The live icon. Drag to pan, pinch to zoom, drop images or apps onto it.
struct IconPreview: View {
    @Environment(AppModel.self) private var model
    @State private var cropAtGestureStart: CropSettings?
    @State private var isDropTargeted = false
    @State private var showsHandCursor = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .accessibilityLabel(model.artTitle.map { "Icon preview for \($0)" } ?? "Empty icon preview")
                }
                if model.isLoadingArt {
                    ProgressView().controlSize(.large)
                }
                if isDropTargeted {
                    let body = CaseLayout.bodyRect(canvas: side, onGrid: true)
                    RoundedRectangle(cornerRadius: body.width * CaseLayout.cornerRadiusFraction, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .frame(width: body.width, height: body.height)
                }
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(panGesture(previewSide: side).simultaneously(with: zoomGesture))
            .onTapGesture(count: 2) { model.resetCrop() }
            .dropDestination(for: URL.self) { urls, _ in
                model.handleDrop(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .onHover { inside in
                // Keep cursor push/pop balanced if the art changes mid-hover.
                let wantsHand = inside && model.hasArt
                guard wantsHand != showsHandCursor else { return }
                if wantsHand { NSCursor.openHand.push() } else { NSCursor.pop() }
                showsHandCursor = wantsHand
            }
        }
        .help(model.hasArt ? "Drag to reposition · Pinch to zoom · Double-click to reset · Drop a game here to apply" : "Drop an image here to use it as artwork")
        .accessibilityHint(model.hasArt ? "Drag to reposition the artwork. Drop an image or a game onto it." : "Drop an image to use it as artwork.")
    }

    private func panGesture(previewSide: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard model.hasArt else { return }
                let start = cropAtGestureStart ?? model.options.crop
                cropAtGestureStart = start
                model.setAdjustingCrop(true)

                // Preview points → design units → fraction of the available pan range.
                let body = CaseLayout.bodyRect(canvas: previewSide, onGrid: model.options.macOSGrid)
                let pointsPerUnit = body.width / CaseLayout.designSize
                let range = model.panRange
                var crop = start
                if range.width > 0 {
                    crop.offset.x = start.offset.x + value.translation.width / pointsPerUnit / range.width
                }
                if range.height > 0 {
                    crop.offset.y = start.offset.y + value.translation.height / pointsPerUnit / range.height
                }
                model.options.crop = crop
            }
            .onEnded { _ in
                cropAtGestureStart = nil
                model.setAdjustingCrop(false)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard model.hasArt else { return }
                let start = cropAtGestureStart ?? model.options.crop
                cropAtGestureStart = start
                model.setAdjustingCrop(true)
                model.options.crop.zoom = start.zoom * value.magnification
            }
            .onEnded { _ in
                cropAtGestureStart = nil
                model.setAdjustingCrop(false)
            }
    }
}

/// The icon at Finder and Dock sizes. Each can be dragged out as a PNG.
struct SizeStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach(AppModel.sizePreviewPoints, id: \.self) { points in
                VStack(spacing: 6) {
                    if let image = model.sizePreviews[points] {
                        Image(decorative: image, scale: 2)
                            .onDrag {
                                guard let url = model.dragFile(pixels: points * 2) else { return NSItemProvider() }
                                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                            }
                            .help("Drag to save a \(points * 2)×\(points * 2) PNG")
                            .accessibilityLabel("\(points) point icon. Drag to save as a PNG file.")
                    } else {
                        Color.clear.frame(width: CGFloat(points), height: CGFloat(points))
                    }
                    Text("\(points) pt")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Case") {
                Picker("Top strip", selection: $model.options.style) {
                    ForEach(CaseStyle.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Side spine", isOn: $model.options.showsSpine)
            }

            Section("Artwork") {
                LabeledContent("Zoom") {
                    HStack {
                        Slider(value: $model.options.crop.zoom, in: CropSettings.zoomRange) { editing in
                            editing ? model.beginContinuousEdit() : model.endContinuousEdit()
                        }
                        Text(model.options.crop.zoom, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!model.hasArt)
                LabeledContent("Position") {
                    Button("Reset") { model.resetCrop() }
                        .disabled(!model.hasArt || model.options.crop == CropSettings())
                }
                Button { Panels.chooseArt(for: model) } label: {
                    Text("Choose Custom Image…").frame(maxWidth: .infinity)
                }
            }

            Section {
                Button { Panels.chooseTargets(for: model) } label: {
                    Text("Apply to Game…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.hasArt)

                PopUpMenuButton(title: "Export", items: [
                    .init(title: "PNG (1024 × 1024)…") { Panels.export(model, as: .png) },
                    .init(title: "ICNS…") { Panels.export(model, as: .icns) },
                    .divider,
                    .init(title: "Copy Icon") { model.copyToPasteboard() },
                ])
                .controlSize(.large)
                .help("Export the icon as PNG or ICNS")
                .disabled(!model.hasArt)

                if let latest = model.appliedTargets.first {
                    Button { model.requestRestoreApplied() } label: {
                        Text(model.appliedTargets.count == 1
                             ? "Restore \(IconApplier.displayName(latest))'s Icon"
                             : "Restore \(model.appliedTargets.count) Original Icons")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Put back the original icon of the apps you changed")
                }
            } footer: {
                Text("Works on apps, folders and files.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}
