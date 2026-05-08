import SwiftUI
import Combine

@MainActor
final class IslandModel: ObservableObject {
    enum State {
        case compact
        case peek
        case expanded
    }

    @Published var state: State = .compact
    @Published var size: CGSize = .zero
    @Published var notch: NotchInfo

    let tabWidth: CGFloat = 38
    let pillSlotWidth: CGFloat = 78
    private let expandedWidth: CGFloat = 720
    private let expandedContentHeight: CGFloat = 172

    /// Detection-pure notch from `NotchInfo.detect`. Kept separate from
    /// `notch` (which has the user's spacing override applied) so
    /// `updateNotch`'s diff guard isn't confused by override-induced
    /// width changes that originate from the store, not the screen.
    private var rawNotch: NotchInfo

    private var subs: Set<AnyCancellable> = []

    init(notch: NotchInfo) {
        self.rawNotch = notch
        self.notch = Self.applyOverride(to: notch)
        recomputeSize()
        subscribeToSpacingStore()
    }

    func setState(_ new: State) {
        guard new != state else { return }
        state = new
        recomputeSize()
    }

    func updateNotch(_ raw: NotchInfo) {
        guard raw.width != rawNotch.width
            || raw.height != rawNotch.height
            || raw.hasNotch != rawNotch.hasNotch else { return }
        rawNotch = raw
        notch = Self.applyOverride(to: raw)
        recomputeSize()
    }

    /// Substitutes the user's chosen non-notch width for the detected
    /// fallback. On notched screens the raw notch is returned untouched —
    /// the override is meaningless there (you can't shrink a physical
    /// notch).
    private static func applyOverride(to raw: NotchInfo) -> NotchInfo {
        if raw.hasNotch { return raw }
        return NotchInfo(
            width: IslandSpacingStore.shared.width,
            height: raw.height,
            hasNotch: false
        )
    }

    /// Re-applies the override and re-computes size whenever the user
    /// changes spacing mode. Wrapped in `withAnimation(.openMorph)` so
    /// the silhouette springs to its new width with the same feel as a
    /// state morph (compact ↔ peek ↔ expanded).
    private func subscribeToSpacingStore() {
        IslandSpacingStore.shared.$mode
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                let new = Self.applyOverride(to: self.rawNotch)
                guard new.width != self.notch.width else { return }
                withAnimation(.openMorph) {
                    self.notch = new
                    self.recomputeSize()
                }
            }
            .store(in: &subs)
    }

    private func recomputeSize() {
        switch state {
        case .compact:
            size = CGSize(
                width: notch.width + tabWidth * 2,
                height: notch.height
            )
        case .peek:
            size = CGSize(
                width: notch.width + tabWidth * 2 + pillSlotWidth * 2,
                height: notch.height
            )
        case .expanded:
            size = CGSize(
                width: expandedWidth,
                height: expandedContentHeight + notch.height
            )
        }
    }
}
