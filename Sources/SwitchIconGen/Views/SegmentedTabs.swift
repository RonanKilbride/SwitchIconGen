import AppKit
import SwiftUI

/// A segmented control whose segments fill the width equally, which SwiftUI's segmented
/// `Picker` doesn't do on macOS.
struct SegmentedTabs<Tab: Hashable>: NSViewRepresentable {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: tabs.map(title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillEqually
        control.controlSize = .large
        return control
    }

    /// Sized by SwiftUI rather than by the control's intrinsic size, so it never feeds a size
    /// change back into the split view while the window lays out.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 28)
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = tabs.firstIndex(of: selection), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SegmentedTabs

        init(parent: SegmentedTabs) { self.parent = parent }

        @objc func changed(_ control: NSSegmentedControl) {
            let index = control.selectedSegment
            guard parent.tabs.indices.contains(index) else { return }
            parent.selection = parent.tabs[index]
        }
    }
}
