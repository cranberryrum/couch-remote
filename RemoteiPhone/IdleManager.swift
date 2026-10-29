import SwiftUI
import UIKit

/// Keeps the phone awake while you're using it, but lets it auto-lock again after
/// `Tuning.idleLockDelay` without a touch, so it doesn't stay lit all night.
final class IdleManager {
    private var lastActivity = ContinuousClock.now
    private var isForeground = false
    private var monitor: Task<Void, Never>?

    func noteActivity() {
        lastActivity = .now
        if isForeground { UIApplication.shared.isIdleTimerDisabled = true }
    }

    func foregrounded() {
        isForeground = true
        noteActivity()
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if ContinuousClock.now - lastActivity > .seconds(Tuning.idleLockDelay) {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
        }
    }

    func backgrounded() {
        isForeground = false
        monitor?.cancel()
        monitor = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// Sees every touch in the window without interfering with any of them.
final class TouchActivityRecognizer: UIGestureRecognizer {
    var onTouch: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch?()
        state = .failed // never recognizes, so it never blocks other gestures
    }
}

/// Invisible view that attaches a `TouchActivityRecognizer` to the hosting window.
struct ActivityMonitor: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onTouch = onTouch
    }

    final class InstallerView: UIView {
        var onTouch: (() -> Void)?
        private var recognizer: TouchActivityRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
                self.recognizer = nil
            }
            guard let window else { return }
            let recognizer = TouchActivityRecognizer(target: nil, action: nil)
            recognizer.onTouch = { [weak self] in self?.onTouch?() }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }
    }
}
