import AppKit
import Carbon

@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var installationStatus: OSStatus = noErr
    var action: (() -> Void)?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        installationStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(keyCode: UInt32, modifiers: UInt32) throws {
        guard installationStatus == noErr else {
            throw StorageError.message("グローバルショートカットのイベントを受け取れませんでした。")
        }
        let old = hotKey
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers,
                                        EventHotKeyID(signature: 0x54534854, id: 1),
                                        GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else {
            throw StorageError.message("ショートカットを登録できませんでした。別の組み合わせを選んでください。")
        }
        if let old { UnregisterEventHotKey(old) }
        hotKey = replacement
    }
}

struct RecordedShortcut {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option, .shift]).isEmpty,
              ![UInt16(kVK_Escape), UInt16(kVK_Return), UInt16(kVK_Tab)].contains(event.keyCode) else { return nil }
        keyCode = UInt32(event.keyCode)
        var carbon: UInt32 = 0
        var prefix = ""
        for (flag, value, symbol): (NSEvent.ModifierFlags, Int, String) in [
            (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
            (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
        ] where flags.contains(flag) {
            carbon |= UInt32(value)
            prefix += symbol
        }
        modifiers = carbon
        label = prefix + (event.keyCode == kVK_Space ? "Space" : (event.charactersIgnoringModifiers ?? "?").uppercased())
    }
}
