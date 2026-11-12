import ColorSync
import CoreGraphics
import Foundation
import IOKit

struct BacklightRange {
    let minimum: Double
    let maximum: Double

    init?(sdrLimit: Double, panelLimit: Double, bonus: Double) {
        guard (450...650).contains(sdrLimit), panelLimit.isFinite, bonus.isFinite else { return nil }
        minimum = sdrLimit
        maximum = min(1_000, panelLimit, sdrLimit * (1 + bonus))
        guard maximum > minimum else { return nil }
    }

    func request(strength: Double, activeLimit: Double) -> Double? {
        guard strength.isFinite, activeLimit.isFinite, activeLimit > minimum + 1 else { return nil }
        let desired = minimum + (maximum - minimum) * min(max(strength, 0), 1)
        return min(desired, activeLimit)
    }
}

@MainActor
final class NativeBacklight {
    let display: CGDirectDisplayID
    private let range: BacklightRange
    private let panel: BacklightPanel
    private let preset: UInt64
    private let readyAfter: TimeInterval
    private var lastTarget: Double?
    private(set) var resets = 0

    private struct RestorePoint: Codable {
        let displayUUID: String
        let originalPreset: Data
        let directPreset: Data
        let brightness: Float
        let automatic: Bool
        let backlight: Double
    }

    private static let restoreFile = URL.applicationSupportDirectory
        .appendingPathComponent("Sunbar", isDirectory: true)
        .appendingPathComponent("BacklightRestore.plist")

    init(display: CGDirectDisplayID, bonus: Double) throws {
        try Self.restorePending(display: display)
        guard let api = DisplayControls.shared, let uuid = Self.uuid(display),
              let panel = BacklightPanel.find(), let limit = panel.panelLimit,
              let original = api.preset(at: api.activePreset(display), display: display),
              let brightness = api.brightness(display), let automatic = api.automaticBrightness(display),
              let backlight = panel.nits, backlight > 0,
              let direct = api.presets(display).first(where: \.isStockSDR),
              let range = BacklightRange(sdrLimit: direct.sdrNits, panelLimit: limit, bonus: bonus) else {
            throw Failure("Direct backlight control is unavailable on this display.")
        }

        let point = RestorePoint(displayUUID: uuid, originalPreset: original.id, directPreset: direct.id,
                                 brightness: brightness, automatic: automatic, backlight: backlight)
        let file = Self.restoreFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListEncoder().encode(point).write(to: file, options: .atomic)

        self.display = display
        self.range = range
        self.panel = panel
        preset = direct.index
        readyAfter = ProcessInfo.processInfo.systemUptime + 0.5

        do {
            if original.index != direct.index, !api.activatePreset(display, direct.index) {
                throw Failure("macOS could not select the stock SDR preset.")
            }
        } catch {
            try Self.restorePending(display: display)
            throw error
        }
    }

    func update(strength: Double) throws -> (request: Double, register: Double, cap: Double)? {
        guard ProcessInfo.processInfo.systemUptime >= readyAfter else { return nil }
        guard let api = DisplayControls.shared, api.activePreset(display) == preset else {
            throw Failure("The display preset changed. Turn the boost off and on to resume.")
        }
        guard let current = panel.nits, current > 0, let cap = panel.activeLimit, cap.isFinite, cap > 0 else {
            throw Failure("The built-in backlight is unavailable.")
        }
        guard let target = range.request(strength: strength, activeLimit: cap) else {
            throw Failure("macOS caps this preset at \(Int(cap.rounded())) nits.")
        }
        if lastTarget == nil {
            guard let automatic = api.automaticBrightness(display), !automatic || api.setAutomatic(display, false) == 0 else {
                throw Failure("macOS could not pause automatic brightness.")
            }
        }
        if lastTarget == target, abs(current - target) >= 1 { resets += 1 }
        lastTarget = target
        if abs(current - target) < 1 { return (target, current, cap) }
        guard panel.setNits(target), let observed = panel.nits, observed > 0 else {
            throw Failure("macOS could not set the built-in backlight.")
        }
        return (target, observed, cap)
    }

    static func restorePending(display: CGDirectDisplayID) throws {
        let file = restoreFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let point = try PropertyListDecoder().decode(RestorePoint.self, from: Data(contentsOf: file))
        guard (0...1).contains(point.brightness), point.backlight.isFinite, point.backlight > 0,
              uuid(display) == point.displayUUID, let api = DisplayControls.shared,
              let current = api.preset(at: api.activePreset(display), display: display) else {
            throw Failure("Waiting to restore the original display settings.")
        }
        if current.id == point.directPreset, point.originalPreset != point.directPreset {
            guard let original = api.presets(display).first(where: { $0.id == point.originalPreset }),
                  api.activatePreset(display, original.index) else {
                throw Failure("macOS could not restore the original display preset.")
            }
        }
        if current.id == point.directPreset || current.id == point.originalPreset {
            if let brightness = api.brightness(display), abs(brightness - point.brightness) > 0.001,
               api.setBrightness(display, point.brightness) != 0 {
                throw Failure("macOS could not restore the original brightness.")
            }
            if point.originalPreset == point.directPreset {
                guard let panel = BacklightPanel.find(), panel.setNits(point.backlight) else {
                    throw Failure("macOS could not restore the original backlight level.")
                }
            }
            if api.automaticBrightness(display) != point.automatic, api.setAutomatic(display, point.automatic) != 0 {
                throw Failure("macOS could not restore automatic brightness.")
            }
        }
        try FileManager.default.removeItem(at: file)
    }

    private static func uuid(_ display: CGDirectDisplayID) -> String? {
        guard CGDisplayIsBuiltin(display) != 0, let id = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, id) as String
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

private final class BacklightPanel {
    let service: io_service_t
    private static let scale = 65_536.0

    private init(_ service: io_service_t) { self.service = service }
    deinit { IOObjectRelease(service) }

    static func find() -> BacklightPanel? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferAP"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let panel = BacklightPanel(service)
            if panel.property("BLMPowergateEnable") != nil { return panel }
        }
        return nil
    }

    var nits: Double? { property("IOMFBBrightnessLevel").map { $0.doubleValue / Self.scale } }
    var panelLimit: Double? { property("limit_max_physical_brightness").map { $0.doubleValue / Self.scale } }
    var activeLimit: Double? { property("BLNitsCap").map { $0.doubleValue / Self.scale } }

    func setNits(_ nits: Double) -> Bool {
        guard let limit = panelLimit, nits.isFinite, nits > 0, nits <= limit else { return false }
        let raw = NSNumber(value: Int64((nits * Self.scale).rounded()))
        return IORegistryEntrySetCFProperty(service, "IOMFBBrightnessLevel" as CFString, raw) == KERN_SUCCESS
    }

    private func property(_ name: String) -> NSNumber? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
    }
}

@MainActor
private struct DisplayControls {
    typealias GetPresetIndex = @convention(c) (CGDirectDisplayID) -> UInt64
    typealias CopyPreset = @convention(c) (CGDirectDisplayID, UInt64) -> Unmanaged<CFDictionary>?
    typealias ActivatePreset = @convention(c) (CGDirectDisplayID, UInt64) -> Bool
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias GetAutomatic = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    typealias SetAutomatic = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    static let shared: Self? = {
        guard let core = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let services = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return nil }
        func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let active = symbol(core, "CoreDisplay_Display_GetActivePresetIndex", as: GetPresetIndex.self),
              let count = symbol(core, "CoreDisplay_Display_GetPresetCount", as: GetPresetIndex.self),
              let copy = symbol(core, "CoreDisplay_Display_CopyPreset", as: CopyPreset.self),
              let activate = symbol(core, "CoreDisplay_Display_SetActivePresetIndex", as: ActivatePreset.self),
              let read = symbol(services, "DisplayServicesGetBrightness", as: GetBrightness.self),
              let write = symbol(services, "DisplayServicesSetBrightness", as: SetBrightness.self),
              let getAuto = symbol(services, "DisplayServicesAmbientLightCompensationEnabled", as: GetAutomatic.self),
              let setAuto = symbol(services, "DisplayServicesEnableAmbientLightCompensation", as: SetAutomatic.self) else { return nil }
        return Self(activePreset: active, presetCount: count, copyPreset: copy, activatePreset: activate,
                    getBrightness: read, setBrightness: write, getAutomatic: getAuto, setAutomatic: setAuto)
    }()

    let activePreset: GetPresetIndex
    let presetCount: GetPresetIndex
    let copyPreset: CopyPreset
    let activatePreset: ActivatePreset
    let getBrightness: GetBrightness
    let setBrightness: SetBrightness
    let getAutomatic: GetAutomatic
    let setAutomatic: SetAutomatic

    struct Preset {
        let index: UInt64
        let id: Data
        let sdrNits: Double
        let isStockSDR: Bool
    }

    func preset(at index: UInt64, display: CGDirectDisplayID) -> Preset? {
        guard index < 128, let data = copyPreset(display, index)?.takeRetainedValue() as? [String: Any],
              (data["PresetValid"] as? NSNumber)?.boolValue == true,
              let id = data["PresetUniqueID"] as? Data else { return nil }
        let sdr = (data["PresetMaxSDRLuminance"] as? NSNumber)?.doubleValue ?? 0
        let hdr = (data["PresetMaxHDRLuminance"] as? NSNumber)?.doubleValue ?? 0
        let origin = (data["PresetOrigin"] as? NSNumber)?.intValue
        return Preset(index: index, id: id, sdrNits: sdr, isStockSDR: origin == 0 && sdr == hdr && (450...650).contains(sdr))
    }

    func presets(_ display: CGDirectDisplayID) -> [Preset] {
        let count = presetCount(display)
        guard count <= 128 else { return [] }
        return (0..<count).compactMap { preset(at: $0, display: display) }
    }

    func brightness(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard getBrightness(display, &value) == 0, (0...1).contains(value) else { return nil }
        return value
    }

    func automaticBrightness(_ display: CGDirectDisplayID) -> Bool? {
        var enabled = false
        return getAutomatic(display, &enabled) == 0 ? enabled : nil
    }
}
