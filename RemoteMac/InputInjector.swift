import AppKit
import CoreGraphics
import IOKit.hidsystem
import RemoteKit

/// Turns decoded wire messages into synthetic HID events.
final class InputInjector {
    /// Flip if scrolling feels backwards once tested on the Mac.
    private static let invertScroll = false
    /// UTF-16 units per synthesized keyboard event (CGEvent's practical limit).
    private static let maxUnitsPerTextEvent = 20

    private let source = CGEventSource(stateID: .hidSystemState)
    private var heldButton: MouseButton?
    /// Where we last put the cursor. Lets sub-pixel deltas accumulate even if the
    /// system rounds the reported position, and detects a physical mouse moving it.
    private var lastPostedPoint: CGPoint?
    private var scrollRemainder = CGVector.zero

    func handle(_ message: Message) {
        switch message {
        case .move(let dx, let dy):
            move(dx: CGFloat(dx), dy: CGFloat(dy))
        case .button(let button, let state):
            setButton(button, down: state == .down)
        case .click(let button, let count):
            click(button, clickState: Int64(count))
        case .scroll(let dx, let dy, let phase):
            scroll(dx: CGFloat(dx), dy: CGFloat(dy), phase: phase)
        case .media(let key):
            postMedia(key)
        case .key(let key, let modifiers):
            postKey(key, modifiers: modifiers)
        case .text(let text):
            type(text)
        case .hello, .welcome, .sleepTimer, .macStatus, .disconnect, .ping, .pong:
            break // handled by the transport
        }
    }

    /// Called whenever a phone goes away (disconnect, replacement, forget, sleep) so a
    /// dropped link can never leave a button stuck down. Modifiers are never "held": they are
    /// applied as flags on each key event, so there is nothing to release for them.
    func releaseAll() {
        if let button = heldButton {
            heldButton = nil
            postMouse(button, down: false, at: currentPointer(), clickState: 1)
        }
        scrollRemainder = .zero
    }

    // MARK: Pointer

    private func currentPointer() -> CGPoint {
        let actual = CGEvent(source: nil)?.location ?? .zero
        if let last = lastPostedPoint, hypot(actual.x - last.x, actual.y - last.y) < 1.5 {
            return last
        }
        return actual
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        let origin = currentPointer()
        let target = ScreenGeometry.clamp(CGPoint(x: origin.x + dx, y: origin.y + dy))
        lastPostedPoint = target

        let type: CGEventType
        let button: CGMouseButton
        switch heldButton {
        case .left: (type, button) = (.leftMouseDragged, .left)
        case .right: (type, button) = (.rightMouseDragged, .right)
        case nil: (type, button) = (.mouseMoved, .left)
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button) else { return }
        // Some pages read movementX/Y, which come from these delta fields.
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((target.x - origin.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((target.y - origin.y).rounded()))
        event.post(tap: .cghidEventTap)
    }

    private func setButton(_ button: MouseButton, down: Bool) {
        let point = currentPointer()
        if down {
            guard heldButton == nil else { return }
            heldButton = button
        } else if heldButton == button {
            heldButton = nil
        }
        postMouse(button, down: down, at: point, clickState: 1)
    }

    /// A full down/up pair. `clickState` > 1 is what makes it a double/triple click.
    private func click(_ button: MouseButton, clickState: Int64) {
        let point = currentPointer()
        postMouse(button, down: true, at: point, clickState: clickState)
        postMouse(button, down: false, at: point, clickState: clickState)
    }

    private func postMouse(_ button: MouseButton, down: Bool, at point: CGPoint, clickState: Int64) {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch (button, down) {
        case (.left, true): (type, cgButton) = (.leftMouseDown, .left)
        case (.left, false): (type, cgButton) = (.leftMouseUp, .left)
        case (.right, true): (type, cgButton) = (.rightMouseDown, .right)
        case (.right, false): (type, cgButton) = (.rightMouseUp, .right)
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Scroll

    private func scroll(dx: CGFloat, dy: CGFloat, phase: ScrollPhase) {
        let sign: CGFloat = Self.invertScroll ? -1 : 1
        if phase == .began || phase == .momentumBegan { scrollRemainder = .zero }

        // Wheel deltas are integers; carry the fraction to the next event.
        let x = dx * sign + scrollRemainder.dx
        let y = dy * sign + scrollRemainder.dy
        let wheelX = Int32(max(-4000, min(4000, x.rounded(.towardZero))))
        let wheelY = Int32(max(-4000, min(4000, y.rounded(.towardZero))))
        scrollRemainder = CGVector(dx: x - CGFloat(wheelX), dy: y - CGFloat(wheelY))

        guard let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
            wheel1: wheelY, wheel2: wheelX, wheel3: 0
        ) else { return }
        event.location = currentPointer()
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)

        // CGScrollPhase: began 1, changed 2, ended 4. CGMomentumScrollPhase: begin 1, continue 2, end 3.
        let scrollPhase: Int64
        let momentumPhase: Int64
        switch phase {
        case .began: (scrollPhase, momentumPhase) = (1, 0)
        case .changed: (scrollPhase, momentumPhase) = (2, 0)
        case .ended: (scrollPhase, momentumPhase) = (4, 0)
        case .momentumBegan: (scrollPhase, momentumPhase) = (0, 1)
        case .momentumChanged: (scrollPhase, momentumPhase) = (0, 2)
        case .momentumEnded: (scrollPhase, momentumPhase) = (0, 3)
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Keys

    /// ANSI virtual key codes (kVK_*).
    private static func virtualKey(for key: KeyCode) -> CGKeyCode {
        switch key {
        case .arrowLeft: 123
        case .arrowRight: 124
        case .arrowDown: 125
        case .arrowUp: 126
        case .space: 49
        case .return: 36
        case .tab: 48
        case .backspace: 51
        case .escape: 53
        case .f: 3
        case .m: 46
        case .c: 8
        case .k: 40
        case .j: 38
        case .l: 37
        case .t: 17
        case .w: 13
        }
    }

    private static func flags(for modifiers: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        return flags
    }

    private func postKey(_ key: KeyCode, modifiers: KeyModifiers) {
        let virtualKey = Self.virtualKey(for: key)
        // Set flags explicitly so a modifier physically held on the Mac can't leak in.
        let flags = Self.flags(for: modifiers)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types arbitrary Unicode (emoji, any language) via `keyboardSetUnicodeString`.
    /// Newlines and tabs become real Return/Tab key presses.
    private func type(_ text: String) {
        var run = ""
        func flushRun() {
            typeRun(run)
            run = ""
        }
        for character in text {
            switch character {
            case "\n", "\r", "\r\n":
                flushRun()
                postKey(.return, modifiers: [])
            case "\t":
                flushRun()
                postKey(.tab, modifiers: [])
            default:
                run.append(character)
            }
        }
        flushRun()
    }

    private func typeRun(_ run: String) {
        var chunk: [UniChar] = []
        func post() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
            chunk.removeAll(keepingCapacity: true)
        }
        // Split on character boundaries so a surrogate pair or emoji sequence never straddles events.
        for character in run {
            let units = Array(String(character).utf16)
            if chunk.count + units.count > Self.maxUnitsPerTextEvent { post() }
            chunk.append(contentsOf: units)
        }
        post()
    }

    /// Media/function keys travel as NSEvent system-defined events (subtype 8, AUX
    /// control buttons), which is what the now-playing machinery listens for.
    private func postMedia(_ key: MediaKey) {
        let keyType: Int32
        switch key {
        case .playPause: keyType = NX_KEYTYPE_PLAY
        case .next: keyType = NX_KEYTYPE_NEXT
        case .previous: keyType = NX_KEYTYPE_PREVIOUS
        case .volumeUp: keyType = NX_KEYTYPE_SOUND_UP
        case .volumeDown: keyType = NX_KEYTYPE_SOUND_DOWN
        }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let data1 = (Int(keyType) << 16) | (state << 8)
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: data1,
                data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
