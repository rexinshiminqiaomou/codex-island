import SwiftUI

/// Stepper-style chevron that fires once on press and then auto-repeats
/// while held. Mirrors macOS's native NSStepper behavior (immediate
/// trigger, ~400ms delay before repeat, ~70ms repeat interval) so users
/// can quickly walk a percent from 50 → 90 by holding the chevron rather
/// than clicking 40 times.
///
/// Built on `DragGesture(minimumDistance: 0)` rather than `Button` because
/// `Button` fires on release; auto-repeat semantics need press-edge
/// triggering. The drag gesture also tracks the in/out hover so we can
/// suppress repeats when the pointer leaves the chevron mid-hold.
struct RepeatingChevronButton: View {
    let systemName: String
    let action: () -> Void

    @State private var pressed = false
    @State private var holdDelay: Timer?
    @State private var repeatTimer: Timer?

    private let initialDelay: TimeInterval = 0.4
    private let repeatInterval: TimeInterval = 0.07

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 12, height: 8)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.86 : 1.0)
            .animation(.easeOut(duration: 0.11), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Track hover-out during a hold: macOS native
                        // stepper stops repeating when the pointer drifts
                        // off the control. We treat any drag offset > the
                        // chevron's bounds as "no longer pressed."
                        let inside = abs(value.translation.width) < 14
                            && abs(value.translation.height) < 12
                        if inside, !pressed {
                            pressDown()
                        } else if !inside, pressed {
                            pressUp()
                        }
                    }
                    .onEnded { _ in pressUp() }
            )
    }

    private func pressDown() {
        pressed = true
        action()
        holdDelay?.invalidate()
        holdDelay = Timer.scheduledTimer(
            withTimeInterval: initialDelay,
            repeats: false
        ) { _ in
            Task { @MainActor in startRepeating() }
        }
    }

    private func startRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(
            withTimeInterval: repeatInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in action() }
        }
    }

    private func pressUp() {
        pressed = false
        holdDelay?.invalidate()
        holdDelay = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
