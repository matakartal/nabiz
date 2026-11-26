// Nabız — © 2026 Mehmet Ata Kartal. All rights reserved.
// Source-available, not open source: do not copy, reword, port or reuse any part of this file. See LICENSE and AGENTS.md.
import AppKit
import CoreGraphics
import IOKit
import SwiftUI

/// Display brightness: Apple's own displays (the built-in one, Studio Display, Pro Display XDR) through the system's
/// DisplayServices, every other external display through DDC/CI over its cable (Apple silicon), the way the
/// display's own buttons would. Displays that answer neither don't show.
@MainActor
@Observable
final class Brightness {
    static let shared = Brightness()

    struct Display: Identifiable, Equatable, Sendable {
        let id: CGDirectDisplayID
        let name: String
        /// 0…1
        var brightness: Double
        let builtIn: Bool
    }

    /// Every display that can be dimmed, the built-in one first; empty unless an external one is among them
    /// (the built-in display alone has its own keys and Control Center).
    private(set) var displays: [Display] = []
    @ObservationIgnored private var links: [CGDirectDisplayID: DisplayLink] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let writer = LatestWriter()

    /// "Dell U2723QE 60%" for the first external display.
    var summary: String {
        displays.first { !$0.builtIn }.map { "\($0.name) \(Format.percent($0.brightness))" } ?? ""
    }

    var hasExternal: Bool { displays.contains { !$0.builtIn } }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Brightness.shared.refresh() }
        }
        refresh()
    }

    /// Finds the displays again and reads their brightness (DDC answers take ~0.1 s, so off the main thread).
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let names = Self.screenNames()
        Task {
            let found = await Task.detached(priority: .utility) { DisplayScan.scan(names: names) }.value
            refreshing = false
            links = Dictionary(found.map { ($0.display.id, $0.link) }, uniquingKeysWith: { first, _ in first })
            let list = found.map(\.display)
            displays = list.contains { !$0.builtIn } ? list : []
            BrightnessKeys.shared.update()
        }
    }

    func set(_ value: Double, on id: CGDirectDisplayID) {
        let value = min(max(value, 0), 1)
        guard let index = displays.firstIndex(where: { $0.id == id }), let link = links[id] else { return }
        displays[index].brightness = value
        writer.write(value, to: link, display: id)
    }

    /// A brightness key on the display under the pointer. False when that display isn't one of ours to dim
    /// (the built-in one: macOS handles it), so the key goes on to the system.
    func step(up: Bool, fine: Bool) -> Bool {
        guard let id = Self.displayUnderPointer(), let display = displays.first(where: { $0.id == id }), !display.builtIn else { return false }
        let step = fine ? 1.0 / 64 : 1.0 / 16
        let next = ((display.brightness / step).rounded() + (up ? 1 : -1)) * step
        set(next, on: id)
        BrightnessHUD.show(min(max(next, 0), 1), on: id)
        return true
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen.flatMap(displayID)
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens { if let id = displayID(screen) { names[id] = screen.localizedName } }
        return names
    }
}

/// How one display is dimmed.
enum DisplayLink: Sendable {
    case apple
    case ddc(DDCService, max: UInt16)
}

/// The newest value for each display reaches it; ones dragged past while a slow DDC write was going are skipped.
final class LatestWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: [CGDirectDisplayID: Double] = [:]
    private let queue = DispatchQueue(label: "app.nabiz.brightness", qos: .userInitiated)

    func write(_ value: Double, to link: DisplayLink, display: CGDirectDisplayID) {
        if case .apple = link {
            DisplayServices.set(display, value)
            return
        }
        lock.withLock { latest[display] = value }
        queue.async { [self] in
            guard let value = lock.withLock({ latest.removeValue(forKey: display) }), case .ddc(let service, let max) = link else { return }
            _ = service.write(code: DDC.brightness, value: UInt16((value * Double(max)).rounded()))
        }
    }
}

// MARK: - Finding displays

enum DisplayScan {
    struct Found: Sendable {
        let display: Brightness.Display
        let link: DisplayLink
    }

    static func scan(names: [CGDirectDisplayID: String]) -> [Found] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        ids = Array(ids.prefix(Int(count))).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }

        var services = DDCService.external()
        var found: [Found] = []
        for id in ids {
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let name = names[id] ?? (builtIn ? L("Yerleşik ekran", "Built-in Display") : L("Harici ekran", "External Display"))
            if builtIn || CGDisplayVendorNumber(id) == 0x610, let value = DisplayServices.get(id) {
                found.append(Found(display: .init(id: id, name: name, brightness: value, builtIn: builtIn), link: .apple))
                continue
            }
            let externals = ids.filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != 0x610 }
            guard let index = services.firstIndex(where: { $0.matches(id) }) ?? (externals.count == 1 && services.count == 1 ? 0 : nil)
            else { continue }
            let service = services.remove(at: index)
            guard let reading = service.read(code: DDC.brightness), reading.max > 0 else { continue }
            found.append(Found(display: .init(id: id, name: name, brightness: Double(reading.current) / Double(reading.max), builtIn: false),
                               link: .ddc(service, max: reading.max)))
        }
        return found.sorted { $0.display.builtIn && !$1.display.builtIn }
    }
}

// MARK: - DisplayServices (Apple displays)

enum DisplayServices {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFunction = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setFunction = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static func get(_ display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard let getFunction, getFunction(display, &value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ display: CGDirectDisplayID, _ value: Double) {
        _ = setFunction?(display, Float(value))
    }
}

// MARK: - DDC/CI

/// The DDC/CI messages, as bytes (no hardware here, so they're tested on their own).
enum DDC {
    /// VCP code 0x10: luminance.
    static let brightness: UInt8 = 0x10
    static let displayAddress: UInt8 = 0x37
    static let hostAddress: UInt8 = 0x51

    /// Length byte, the payload, and the XOR checksum seeded with the display's write address (and the host's for a
    /// set: MonitorControl and m1ddc do the same, and displays accept it).
    static func packet(_ payload: [UInt8]) -> [UInt8] {
        let bytes = [0x80 | UInt8(payload.count + 1), UInt8(payload.count)] + payload
        var check: UInt8 = payload.count == 1 ? displayAddress << 1 : (displayAddress << 1) ^ hostAddress
        for byte in bytes { check ^= byte }
        return bytes + [check]
    }

    /// "Set VCP feature": opcode 0x03 is also the payload's length, which `packet` writes first.
    static func setPacket(code: UInt8, value: UInt16) -> [UInt8] { packet([code, UInt8(value >> 8), UInt8(value & 0xFF)]) }

    /// "Get VCP feature": opcode 0x01.
    static func getPacket(code: UInt8) -> [UInt8] { packet([code]) }

    /// An 11-byte "VCP feature reply": result code at 3, maximum at 6–7, current value at 8–9, checksum last.
    static func parseReply(_ reply: [UInt8]) -> (current: UInt16, max: UInt16)? {
        guard reply.count == 11 else { return nil }
        var check: UInt8 = 0x50
        for byte in reply.dropLast() { check ^= byte }
        guard check == reply[10], reply[3] == 0 else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return max > 0 ? (current, max) : nil
    }
}

/// One external display's I2C link on Apple silicon, through IOKit's IOAVService (looked up at run time: there is
/// no header for it, and Intel Macs don't have it, so it simply finds nothing there).
final class DDCService: @unchecked Sendable {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    nonisolated(unsafe) private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let create = iokit.flatMap { dlsym($0, "IOAVServiceCreateWithService") }.map { unsafeBitCast($0, to: Create.self) }
    private static let readI2C = iokit.flatMap { dlsym($0, "IOAVServiceReadI2C") }.map { unsafeBitCast($0, to: Transfer.self) }
    private static let writeI2C = iokit.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: Transfer.self) }

    private let service: CFTypeRef
    /// "10AC2FA1-0000-…": vendor id, then product id with its bytes swapped.
    let edidUUID: String

    private init(service: CFTypeRef, edidUUID: String) {
        self.service = service
        self.edidUUID = edidUUID
    }

    /// The display's EDID names it: vendor first, then the product id low byte first.
    func matches(_ display: CGDirectDisplayID) -> Bool {
        Self.edidMatches(edidUUID, vendor: CGDisplayVendorNumber(display), product: CGDisplayModelNumber(display))
    }

    static func edidMatches(_ uuid: String, vendor: UInt32, product: UInt32) -> Bool {
        let hex = uuid.uppercased()
        guard hex.count >= 8 else { return false }
        let wantVendor = String(format: "%04X", vendor & 0xFFFF)
        let wantProduct = String(format: "%02X%02X", product & 0xFF, (product >> 8) & 0xFF)
        return hex.prefix(4) == wantVendor && hex.dropFirst(4).prefix(4) == wantProduct
    }

    func read(code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let readI2C = Self.readI2C else { return nil }
        for _ in 0..<3 {
            guard send(DDC.getPacket(code: code)) else { usleep(20_000); continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let status = reply.withUnsafeMutableBytes { readI2C(service, UInt32(DDC.displayAddress), 0, $0.baseAddress!, 11) }
            if status == kIOReturnSuccess, let value = DDC.parseReply(reply) { return value }
            usleep(20_000)
        }
        return nil
    }

    func write(code: UInt8, value: UInt16) -> Bool {
        for _ in 0..<3 {
            if send(DDC.setPacket(code: code, value: value)) { return true }
            usleep(20_000)
        }
        return false
    }

    /// Sent twice, as some displays miss the first message after a pause.
    private func send(_ packet: [UInt8]) -> Bool {
        guard let writeI2C = Self.writeI2C else { return false }
        var bytes = packet
        var ok = false
        for _ in 0..<2 {
            usleep(10_000)
            ok = bytes.withUnsafeMutableBytes {
                writeI2C(service, UInt32(DDC.displayAddress), UInt32(DDC.hostAddress), $0.baseAddress!, UInt32($0.count))
            } == kIOReturnSuccess
        }
        return ok
    }

    /// Every external display's link: in the registry each display's framebuffer (with its EDID) comes before its
    /// DCPAVServiceProxy, whose Location says whether it's the built-in panel or a cable.
    static func external() -> [DDCService] {
        guard let create else { return [] }
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var services: [DDCService] = []
        var edid = ""
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            let name = registryName(entry)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                edid = property(entry, "EDID UUID") as? String ?? ""
            } else if name == "DCPAVServiceProxy", property(entry, "Location") as? String == "External",
                      let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                services.append(DDCService(service: service, edidUUID: edid))
                edid = ""
            }
        }
        return services
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return "" }
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively))?.takeRetainedValue()
    }
}

// MARK: - Brightness keys

/// With the setting on (and Accessibility allowed), the keyboard's brightness keys dim the external display under
/// the pointer; on the built-in display they do what they always did.
@MainActor
final class BrightnessKeys {
    static let shared = BrightnessKeys()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The key-down went to an external display, so its key-up is ours too.
    fileprivate var swallowing = false

    func update() {
        let wanted = Prefs.bool(Prefs.brightnessKeys) && Brightness.shared.hasExternal && AXIsProcessTrusted()
        if wanted && tap == nil { start() } else if !wanted && tap != nil { stop() }
    }

    private func start() {
        let mask = CGEventMask(1) << 14   // NX_SYSDEFINED: media and brightness keys
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: brightnessTapCallback, userInfo: nil) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// NX_KEYTYPE_BRIGHTNESS_UP / _DOWN.
private let brightnessUpKey = 2
private let brightnessDownKey = 3

private func brightnessTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { BrightnessKeys.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let key = NSEvent(cgEvent: event), key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
    let code = (key.data1 & 0xFFFF_0000) >> 16
    guard code == brightnessUpKey || code == brightnessDownKey else { return Unmanaged.passUnretained(event) }
    let down = (key.data1 & 0xFF00) >> 8 == 0xA
    let fine = key.modifierFlags.contains(.shift) && key.modifierFlags.contains(.option)
    let handled = MainActor.assumeIsolated { () -> Bool in
        let keys = BrightnessKeys.shared
        if down {
            keys.swallowing = Brightness.shared.step(up: code == brightnessUpKey, fine: fine)
            return keys.swallowing
        }
        return keys.swallowing
    }
    return handled ? nil : Unmanaged.passUnretained(event)
}

// MARK: - The on-screen level

/// A small level near the bottom of the display that changed, like the system's own; gone after a second and a half.
@MainActor
enum BrightnessHUD {
    private static var panel: NSPanel?
    private static var hide: DispatchWorkItem?

    static func show(_ value: Double, on display: CGDirectDisplayID) {
        let panel = panel ?? {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            return panel
        }()
        Self.panel = panel
        panel.contentView = NSHostingView(rootView: BrightnessLevel(value: value))
        if let screen = NSScreen.screens.first(where: { Brightness.displayID($0) == display })?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.minY + 80))
        }
        panel.orderFrontRegardless()
        hide?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { Self.panel?.orderOut(nil) } }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

private struct BrightnessLevel: View {
    let value: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: value < 0.01 ? "sun.min" : "sun.max.fill").font(Theme.body).foregroundStyle(Theme.text)
                .frame(width: Theme.menuIcon)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.text).frame(width: max(geometry.size.width * value, value > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(width: 220, height: 44)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Parlaklık \(Format.percent(value))", "Brightness \(Format.percent(value))"))
    }
}
