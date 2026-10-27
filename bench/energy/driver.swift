// Synthetic input driver for WM energy benchmarks.
// Posts real CGEvents so the full input path (event tap / Carbon hotkey) is exercised.
// Needs Accessibility permission for the terminal app that runs it.
//
//   swift driver.swift keys  <seconds> [actions_per_second]   # hotkey workload
//   swift driver.swift mouse <seconds> [hz]                   # cursor sweeps (focus-follows-mouse cost)
//   swift driver.swift type  <seconds> [keys_per_second]      # plain typing, no WM bindings hit
//
// Hotkeys used by `keys` (must be bound identically in both WMs, see configs/):
//   Alt+1/2/3 switch workspace, Alt+H/L focus left/right
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let seconds = Double(args[2]) else {
    FileHandle.standardError.write("usage: driver.swift keys|mouse|type <seconds> [rate]\n".data(using: .utf8)!)
    exit(2)
}
let mode = args[1]
let src = CGEventSource(stateID: .hidSystemState)
let deadline = Date().addingTimeInterval(seconds)

func tap(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(8_000)
    }
}

switch mode {
case "keys":
    let rate = args.count > 3 ? Double(args[3])! : 2.0
    // 18='1' 19='2' 20='3' 4='h' 37='l'
    let seq: [CGKeyCode] = [18, 37, 4, 19, 37, 4, 20, 37, 4]
    var i = 0
    while Date() < deadline {
        tap(seq[i % seq.count], .maskAlternate)
        i += 1
        usleep(useconds_t(1_000_000 / rate))
    }
    print("keys: \(i) actions")
case "mouse":
    let hz = args.count > 3 ? Double(args[3])! : 60.0
    let b = CGDisplayBounds(CGMainDisplayID())
    let y = b.midY
    var t = 0.0
    var n = 0
    while Date() < deadline {
        // 4 s full-width sweep, crossing every tiled window on the screen
        let x = b.minX + 20 + (b.width - 40) * (0.5 - 0.5 * cos(t * 2 * .pi / 4))
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
        t += 1 / hz
        n += 1
        usleep(useconds_t(1_000_000 / hz))
    }
    print("mouse: \(n) events")
case "type":
    let rate = args.count > 3 ? Double(args[3])! : 8.0
    // F13 (code 105): a real KeyDown/KeyUp that reaches the WM's keyboard path but is
    // unbound in both WMs and ignored by almost every app, so nothing gets typed.
    var n = 0
    while Date() < deadline {
        tap(105)
        n += 1
        usleep(useconds_t(1_000_000 / rate))
    }
    print("type: \(n) keys")
default:
    FileHandle.standardError.write("unknown mode \(mode)\n".data(using: .utf8)!)
    exit(2)
}
