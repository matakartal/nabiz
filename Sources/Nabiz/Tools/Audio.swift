// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import CoreAudio
import IOBluetooth

/// The sound output: volume, mute and which device plays (speakers, AirPods, a display…).
@MainActor
enum SoundOutput {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    // MARK: Volume (through Standard Additions: works for every device, no permission)

    /// Read at most every two seconds: the launcher rebuilds its rows on every key.
    private static var cached: (volume: Int?, muted: Bool, at: Date)?

    private static var settings: (volume: Int?, muted: Bool) {
        if let cached, Date().timeIntervalSince(cached.at) < 2 { return (cached.volume, cached.muted) }
        let result = run("get volume settings")
        let volume = result?.forKeyword(AEKeyword(0x6F75_766C)).map { Int($0.int32Value) } // 'ouvl'
        let muted = result?.forKeyword(AEKeyword(0x6D75_7465))?.booleanValue ?? false     // 'mute'
        cached = (volume, muted, Date())
        return (volume, muted)
    }

    static var volume: Int? { settings.volume }

    static var isMuted: Bool { settings.muted }

    static func setVolume(_ percent: Int) {
        let percent = min(max(percent, 0), 100)
        _ = run("set volume output volume \(percent) without output muted")
        cached = nil
        Monitor.panelActions.flash(L("Ses %\(percent)", "Volume \(percent)%"))
    }

    static func change(by step: Int) {
        setVolume((volume ?? 50) + step)
    }

    static func toggleMute() {
        let muted = !isMuted
        _ = run("set volume output muted \(muted)")
        cached = nil
        Monitor.panelActions.flash(muted ? L("Ses kapalı", "Sound muted") : L("Ses açık", "Sound on"))
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    // MARK: Devices

    static var outputs: [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let name = string(id, kAudioObjectPropertyName), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  !isHidden(id) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    static var currentOutput: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    /// Plays everything, alerts included, through this device.
    static func select(_ device: Device) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id)
        }
        Monitor.panelActions.flash(L("Ses çıkışı: \(device.name)", "Sound output: \(device.name)"))
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIsHidden, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &hidden) == noErr && hidden != 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// "ses 40", "volume 40", "vol 40%": the level asked for.
    static func level(in query: String) -> Int? {
        let pattern = #"^(?:ses|sesi|volume|vol)\s*%?\s*(\d{1,3})\s*%?$"#
        guard let match = query.lowercased().firstMatch(of: try! Regex(pattern)), let range = match.output[1].range,
              let value = Int(query.lowercased()[range]), value <= 100 else { return nil }
        return value
    }
}

/// Paired Bluetooth devices, to connect or disconnect from the launcher. macOS asks once for Bluetooth access, so
/// the list is only read after the person first asks for it ("bluetooth", "bağlan").
@MainActor
enum BluetoothDevices {
    struct Device: Identifiable {
        let id: String
        let name: String
        let connected: Bool
    }

    private static let allowedKey = "bluetoothAsked"
    private static var cache: [Device] = []
    private static var readAt: Date?

    static var asked: Bool { UserDefaults.standard.bool(forKey: allowedKey) }

    /// True when the text is about Bluetooth, which is when the list may be read the first time.
    static func wanted(_ query: String) -> Bool {
        let query = Fuzzy.fold(query)
        guard query.count >= 4 else { return query == "bt" }
        return ["bluetooth", "baglan", "connect", "disconnect", "kulaklik", "airpods", "headphone"].contains { $0.hasPrefix(query) || query.hasPrefix($0) }
    }

    static func devices(for query: String) -> [Device] {
        guard asked || wanted(query) else { return [] }
        UserDefaults.standard.set(true, forKey: allowedKey)
        if readAt.map({ Date().timeIntervalSince($0) > 5 }) ?? true {
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            cache = paired.compactMap { device in
                guard let address = device.addressString, let name = device.name, !name.isEmpty else { return nil }
                return Device(id: address, name: name, connected: device.isConnected())
            }
            readAt = Date()
        }
        return cache
    }

    static func toggle(_ device: Device) {
        readAt = nil
        let address = device.id, name = device.name, connect = !device.connected
        Monitor.panelActions.flash(connect ? L("\(name) bağlanıyor…", "Connecting \(name)…") : L("\(name) ayrılıyor…", "Disconnecting \(name)…"))
        // Connecting can take a few seconds; keep it off the main thread.
        Task.detached(priority: .userInitiated) {
            guard let bluetooth = IOBluetoothDevice(addressString: address) else { return }
            let result = connect ? bluetooth.openConnection() : bluetooth.closeConnection()
            await MainActor.run {
                let message = result != kIOReturnSuccess
                    ? (connect ? L("\(name) bağlanamadı", "Couldn't connect \(name)") : L("\(name) ayrılamadı", "Couldn't disconnect \(name)"))
                    : (connect ? L("\(name) bağlandı", "\(name) connected") : L("\(name) ayrıldı", "\(name) disconnected"))
                Monitor.panelActions.flash(message)
            }
        }
    }
}
