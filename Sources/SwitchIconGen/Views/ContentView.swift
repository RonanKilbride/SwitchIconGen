import SwitchIconGenKit
import SwiftUI

/// The sidebar: game search or history.
struct SearchResultsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case games = "Games", history = "History"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .games

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SegmentedTabs(tabs: Tab.allCases, title: \.rawValue, selection: $tab)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)

            switch tab {
            case .games:
                SearchField(text: $model.query, prompt: "Search Switch games")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                List(model.results, selection: $model.selectionID) { game in
                    ResultRow(game: game)
                }
                .overlay { emptyState }
            case .history:
                HistoryView()
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.searchState {
        case .idle:
            ContentUnavailableView {
                Label("Find a Game", systemImage: "gamecontroller")
            } description: {
                Text("Search for any Switch or Switch 2 game to use its box art.")
            }
        case .searching where model.results.isEmpty:
            ProgressView("Searching…")
                .controlSize(.small)
        case .loaded where model.results.isEmpty:
            ContentUnavailableView.search(text: model.query)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Search", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.retrySearch() }
            }
        default:
            EmptyView()
        }
    }
}

struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let game: GameArtwork
    @State private var thumbnail: CGImage?

    private var platforms: [Platform] {
        Platform.allCases.filter(game.platforms.contains)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    ForEach(platforms, id: \.self) { PlatformBadge(platform: $0) }
                    if let year = game.releaseYear {
                        Text(year)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: game.imageURL) {
            // 44pt at 2x.
            thumbnail = try? await model.imageLoader.image(at: game.imageURL, maxPixelSize: 88)
        }
    }

    private var accessibilityText: String {
        var parts = [game.title, platforms.map(\.displayName).joined(separator: " and ")]
        if let year = game.releaseYear { parts.append(year) }
        return parts.joined(separator: ", ")
    }
}

struct PlatformBadge: View {
    let platform: Platform

    var body: some View {
        Text(platform.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .foregroundStyle(platform == .switch2 ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background {
                Capsule().fill(platform == .switch2 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.quaternary))
            }
            .fixedSize()
    }
}
