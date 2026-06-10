import Foundation
import IOKit
import ServiceManagement

// MARK: - Errors

enum FanControlError: Error, CustomStringConvertible {
    case smcConnectionFailed
    case unlockFailed(String)
    case rpmOutOfRange(requested: Int, min: Int, max: Int)

    var description: String {
        switch self {
        case .smcConnectionFailed:
            return "无法连接到 AppleSMC"
        case .unlockFailed(let detail):
            return "风扇解锁失败: \(detail)"
        case .rpmOutOfRange(let req, let min, let max):
            return "RPM \(req) 超出范围 [\(min)–\(max)]"
        }
    }
}

enum FanMode: String, CaseIterable, Identifiable {
    case auto = "自动"
    case manual = "手动"
    case sensor = "传感器"
    var id: String { rawValue }
}

enum Preset: String, CaseIterable, Identifiable {
    case balanced = "均衡"
    case quiet = "安静"
    case performance = "性能"
    case fullSpeed = "全速"
    var id: String { rawValue }
}

struct PresetConfig {
    let minRPM: Int
    let maxRPM: Int
    let mode: FanMode
}

let presets: [Preset: PresetConfig] = [
    .balanced:    .init(minRPM: 1800, maxRPM: 4000, mode: .auto),
    .quiet:       .init(minRPM: 1800, maxRPM: 3000, mode: .manual),
    .performance: .init(minRPM: 2500, maxRPM: 5500, mode: .manual),
    .fullSpeed:   .init(minRPM: 5800, maxRPM: 6200, mode: .manual),
]

class FanController: ObservableObject {
    @Published var mode: FanMode = .auto
    @Published var activePreset: Preset = .balanced
    @Published var sliderMin: Double = 1800
    @Published var sliderMax: Double = 4000

    // Per-fan target RPMs (keyed by fan index)
    @Published var fanTargetRPMs: [Int: Double] = [:]

    @Published var startupAuto = false {
        didSet { toggleLaunchAtLogin(startupAuto) }
    }
    @Published var menuBarIcon = true
    @Published var menuBarShowFan = true
    @Published var menuBarShowTemp = true

    // 温度联动设置
    @Published var sensorBasedControl = false
    @Published var selectedSensorID: String = "CPU"
    @Published var targetTemperature: Double = 75.0
    @Published var tempHysteresis: Double = 3.0

    // 可用传感器列表
    @Published var availableSensors: [TempSensor] = []

    // SMC 连接状态
    @Published var smcConnected: Bool = false
    @Published var lastError: String? = nil

    private var smcConnection: SMCConnection?
    private var sensorTimer: Timer?
    /// Fan bounds from monitor (min/max RPM per fan)
    private var fanBounds: [Int: (min: Int, max: Int)] = [:]

    init() {
        smcConnection = SMCConnection()
        smcConnected = smcConnection != nil

        if !smcConnected {
            lastError = "无法连接到 SMC。请确保应用有足够的权限。"
        }
    }

    deinit {
        stopSensorTimer()
    }

    // MARK: - Sync from Monitor

    /// Update per-fan state from FanMonitor's latest readings
    func syncFromMonitor(fans: [Fan]) {
        for fan in fans {
            fanBounds[fan.id] = (min: fan.minRPM, max: fan.maxRPM)
            // Initialize target RPM if not yet set
            if fanTargetRPMs[fan.id] == nil {
                fanTargetRPMs[fan.id] = Double(fan.targetRPM > 0 ? fan.targetRPM : 3000)
            }
        }
    }

    // MARK: - Per-Fan Control

    /// Set a single fan's target RPM (manual mode)
    func setFanRPM(_ rpm: Double, fanIndex: Int) {
        let clamped = clampRPM(rpm, fanIndex: fanIndex)
        fanTargetRPMs[fanIndex] = clamped

        guard let connection = smcConnection else { return }

        let rpmInt = Int(clamped)
        connection.writeFanMode(1, fanIndex: fanIndex)
        connection.writeFanSpeed(rpmInt, fanIndex: fanIndex)
    }

    /// Set all fans to the same RPM
    func setAllFansRPM(_ rpm: Double) {
        guard let connection = smcConnection else { return }

        let fanCount = connection.readNumericValue(for: "FNum").map { max(0, Int($0.rounded(.down))) } ?? 2

        for i in 0..<fanCount {
            let clamped = clampRPM(rpm, fanIndex: i)
            fanTargetRPMs[i] = clamped
            let rpmInt = Int(clamped)
            connection.writeFanMode(1, fanIndex: i)
            connection.writeFanSpeed(rpmInt, fanIndex: i)
        }
    }

    /// Reset a single fan to Apple auto mode
    func resetFanToAuto(fanIndex: Int) {
        guard let connection = smcConnection else { return }
        connection.writeFanMode(0, fanIndex: fanIndex)
        fanTargetRPMs.removeValue(forKey: fanIndex)
    }

    /// Reset all fans to Apple auto mode
    func resetAllToAuto() {
        guard let connection = smcConnection else { return }
        let fanCount = connection.readNumericValue(for: "FNum").map { max(0, Int($0.rounded(.down))) } ?? 2
        connection.resetAllToAuto(fanCount: fanCount)
        fanTargetRPMs.removeAll()
        mode = .auto
    }

    /// Clamp RPM to the fan's hardware bounds
    private func clampRPM(_ rpm: Double, fanIndex: Int) -> Double {
        guard let bounds = fanBounds[fanIndex] else { return rpm }
        return Double(max(bounds.min, min(bounds.max, Int(rpm))))
    }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        activePreset = preset
        guard let config = presets[preset] else { return }
        stopSensorTimer()

        sliderMin = Double(config.minRPM)
        sliderMax = Double(config.maxRPM)

        switch config.mode {
        case .auto:
            mode = .auto
            resetAllToAuto()
        case .manual:
            mode = .manual
            setAllFansRPM(Double(config.minRPM))
        case .sensor:
            mode = .sensor
            sensorBasedControl = true
            startSensorTimer()
            if let temp = availableSensors.first(where: { $0.id == selectedSensorID })?.celsius {
                applySensorBasedControl(temperature: temp)
            }
        }
    }

    // MARK: - Apply Settings (legacy path for sensor mode)

    func applyFanSettings() {
        guard let connection = smcConnection else {
            return
        }

        let fanCount = connection.readNumericValue(for: "FNum").map { max(0, Int($0.rounded(.down))) } ?? 2

        for i in 0..<fanCount {
            switch mode {
            case .auto:
                connection.writeFanMode(0, fanIndex: i)
            case .manual:
                // Per-fan control is handled by setFanRPM/setAllFansRPM
                break
            case .sensor:
                break // 传感器模式由 applySensorBasedControl 处理
            }
        }
    }

    func targetRPM(normalized: Double) -> Int {
        let range = sliderMax - sliderMin
        return Int(sliderMin + range * normalized)
    }

    func resetToAuto() {
        resetAllToAuto()
    }

    // MARK: - 开机自启

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: - 传感器联动

    func setMode(_ newMode: FanMode) {
        mode = newMode
        sensorBasedControl = (newMode == .sensor)

        // 立即应用设置
        switch newMode {
        case .auto:
            stopSensorTimer()
            resetAllToAuto()
        case .manual:
            stopSensorTimer()
            // Initialize per-fan RPMs from current targets if empty
            if fanTargetRPMs.isEmpty {
                setAllFansRPM(3000)
            }
        case .sensor:
            startSensorTimer()
            // 立即应用一次
            if let temp = availableSensors.first(where: { $0.id == selectedSensorID })?.celsius {
                applySensorBasedControl(temperature: temp)
            }
        }
    }

    private func startSensorTimer() {
        stopSensorTimer()
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateSensorBasedFans()
        }
    }

    private func stopSensorTimer() {
        sensorTimer?.invalidate()
        sensorTimer = nil
    }

    private func updateSensorBasedFans() {
        guard mode == .sensor else { return }
        if let temp = availableSensors.first(where: { $0.id == selectedSensorID })?.celsius {
            applySensorBasedControl(temperature: temp)
        }
    }

    func updateAvailableSensors(_ sensors: [TempSensor]) {
        availableSensors = sensors
        if !sensors.contains(where: { $0.id == selectedSensorID }) {
            selectedSensorID = sensors.first?.id ?? "CPU"
        }
    }

    func calculateFanSpeed(currentTemperature: Double) -> Int {
        let tempDiff = currentTemperature - targetTemperature

        if tempDiff <= -tempHysteresis {
            return Int(sliderMin)
        } else if tempDiff >= tempHysteresis * 2 {
            return Int(sliderMax)
        } else {
            let normalizedTemp = max(0, min(1, (tempDiff + tempHysteresis) / (tempHysteresis * 3)))
            return Int(sliderMin + (sliderMax - sliderMin) * normalizedTemp)
        }
    }

    func applySensorBasedControl(temperature: Double) {
        guard mode == .sensor else { return }
        guard let connection = smcConnection else { return }

        let targetSpeed = calculateFanSpeed(currentTemperature: temperature)
        let fanCount = connection.readNumericValue(for: "FNum").map { max(0, Int($0.rounded(.down))) } ?? 2

        for i in 0..<fanCount {
            connection.writeFanMode(1, fanIndex: i)
            connection.writeFanSpeed(targetSpeed, fanIndex: i)
        }
    }
}

// MARK: - SMC Connection for Fan Control

private class SMCConnection {
    private let connection: io_connect_t
    /// Hardware-detected mode key template (lowercase for M5+, uppercase for M1-M4)
    private(set) var modeKeyTemplate: String = "F%dMd"
    /// Whether Ftst unlock key exists (M1-M4 only)
    private(set) var hasFtst: Bool = false

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var conn = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else {
            return nil
        }
        self.connection = conn

        // Detect hardware: which mode key exists?
        // M5+ uses F%dmd (lowercase), M1-M4 use F%dMd (uppercase)
        if readNumericValue(for: "F0md") != nil {
            modeKeyTemplate = "F%dmd"
        }

        // Check if Ftst exists (M1-M4 unlock mechanism)
        let ftstInfo = readKeyInfo("Ftst")
        hasFtst = ftstInfo != nil
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: - Fan Mode Key

    func fanModeKey(_ fanIndex: Int) -> String {
        String(format: modeKeyTemplate, fanIndex)
    }

    // MARK: - Read

    func readNumericValue(for key: String) -> Double? {
        guard let value = readKey(key), value.result == 0 else {
            return nil
        }
        return value.numericValue
    }

    // MARK: - Fan Unlock

    /// Ensure a fan is in manual mode. Fire-and-forget — matches original working behavior.
    func ensureManualMode(fanIndex: Int) {
        if hasFtst {
            writeRawKey("Ftst", bytes: [1])
            Thread.sleep(forTimeInterval: 0.3)
        }
        writeKey(fanModeKey(fanIndex), value: UInt8(1))
    }

    // MARK: - Write Fan Control

    /// Set fan mode (0=auto, 1=manual)
    func writeFanMode(_ mode: Int, fanIndex: Int) {
        let key = fanModeKey(fanIndex)
        writeKey(key, value: UInt8(mode))
    }

    /// 写入风扇目标转速 (F%dTg)，自动区分 flt 和 fpe2 数据类型
    func writeFanSpeed(_ speed: Int, fanIndex: Int) {
        let key = "F\(fanIndex)Tg"
        guard let keyInfo = readKeyInfo(key) else {
            return
        }

        let typeStr = keyInfo.dataType.stringValue

        if typeStr == "flt " {
            // M 系列芯片：写入 4 字节 Float
            let bytes = floatToSMCBytes(Float(speed))
            writeRawKey(key, bytes: bytes)
        } else if typeStr == "fpe2" {
            // Intel 芯片：写入 2 字节 fpe2
            let fpe2Value = UInt16(speed * 4)
            writeKey(key, value: fpe2Value)
        }
    }

    /// Read target RPM from F%dTg
    func readFanTarget(_ fanIndex: Int) -> Int? {
        readNumericValue(for: "F\(fanIndex)Tg").map { Int($0.rounded()) }
    }

    /// Reset all fans to Apple auto mode
    func resetAllToAuto(fanCount: Int) {
        for i in 0..<fanCount {
            writeFanMode(0, fanIndex: i)
        }
        if hasFtst {
            writeRawKey("Ftst", bytes: [0])
        }
    }

    /// Clear Ftst flag (M1-M4 unlock mechanism)
    func clearFtst() {
        if hasFtst {
            writeRawKey("Ftst", bytes: [0])
        }
    }

    // MARK: - Private Write Methods

    private func writeRawKey(_ key: String, bytes: [UInt8]) {
        guard let keyInfo = readKeyInfo(key) else {
            return
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_WRITE_BYTES
        input.keyInfo = keyInfo

        // Copy bytes into the 32-byte SMCBytes struct
        var padded = bytes + [UInt8](repeating: 0, count: max(0, 32 - bytes.count))
        if padded.count > 32 { padded = Array(padded.prefix(32)) }
        input.bytes = SMCBytes(
            byte0: padded[0], byte1: padded[1], byte2: padded[2], byte3: padded[3],
            byte4: padded[4], byte5: padded[5], byte6: padded[6], byte7: padded[7],
            byte8: padded[8], byte9: padded[9], byte10: padded[10], byte11: padded[11],
            byte12: padded[12], byte13: padded[13], byte14: padded[14], byte15: padded[15],
            byte16: padded[16], byte17: padded[17], byte18: padded[18], byte19: padded[19],
            byte20: padded[20], byte21: padded[21], byte22: padded[22], byte23: padded[23],
            byte24: padded[24], byte25: padded[25], byte26: padded[26], byte27: padded[27],
            byte28: padded[28], byte29: padded[29], byte30: padded[30], byte31: padded[31]
        )

        _ = call(input: &input, output: &output)
    }

    private func writeKey(_ key: String, value: UInt8) {
        guard let keyInfo = readKeyInfo(key) else {
            return
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_WRITE_BYTES
        input.keyInfo = keyInfo
        input.bytes.byte0 = value

        _ = call(input: &input, output: &output)
    }

    private func writeKey(_ key: String, value: UInt16) {
        guard let keyInfo = readKeyInfo(key) else {
            return
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_WRITE_BYTES
        input.keyInfo = keyInfo
        input.bytes.byte0 = UInt8(value >> 8)
        input.bytes.byte1 = UInt8(value & 0xFF)

        _ = call(input: &input, output: &output)
    }

    private func readKeyInfo(_ key: String) -> SMCKeyInfoData? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_READ_KEY_INFO

        guard call(input: &input, output: &output) == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        return output.keyInfo
    }

    private func readKey(_ key: String) -> SMCValue? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_READ_KEY_INFO

        guard call(input: &input, output: &output) == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        let keyInfo = output.keyInfo
        input.keyInfo = keyInfo
        input.data8 = SMC_CMD_READ_BYTES

        guard call(input: &input, output: &output) == kIOReturnSuccess else {
            return nil
        }

        return SMCValue(keyInfo: keyInfo, result: output.result, bytes: output.byteArray(size: keyInfo.dataSize))
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            KERNEL_INDEX_SMC,
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    /// Convert Float to SMC bytes (IEEE 754 little-endian, 4 bytes) — used for F%dTg
    private func floatToSMCBytes(_ value: Float) -> [UInt8] {
        var v = value
        return withUnsafeBytes(of: &v) { Array($0) }
    }
}

// MARK: - SMC Constants

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_WRITE_BYTES: UInt8 = 6
private let SMC_CMD_READ_KEY_INFO: UInt8 = 9

// MARK: - SMC Value

private struct SMCValue {
    let keyInfo: SMCKeyInfoData
    let result: UInt8
    let bytes: [UInt8]

    var numericValue: Double? {
        switch keyInfo.dataType.stringValue {
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        default:
            return nil
        }
    }
}

// MARK: - SMC Data Structures

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes()

    func byteArray(size: UInt32) -> [UInt8] {
        Array(bytes.array.prefix(Int(size)))
    }
}

private struct SMCBytes {
    var byte0: UInt8 = 0
    var byte1: UInt8 = 0
    var byte2: UInt8 = 0
    var byte3: UInt8 = 0
    var byte4: UInt8 = 0
    var byte5: UInt8 = 0
    var byte6: UInt8 = 0
    var byte7: UInt8 = 0
    var byte8: UInt8 = 0
    var byte9: UInt8 = 0
    var byte10: UInt8 = 0
    var byte11: UInt8 = 0
    var byte12: UInt8 = 0
    var byte13: UInt8 = 0
    var byte14: UInt8 = 0
    var byte15: UInt8 = 0
    var byte16: UInt8 = 0
    var byte17: UInt8 = 0
    var byte18: UInt8 = 0
    var byte19: UInt8 = 0
    var byte20: UInt8 = 0
    var byte21: UInt8 = 0
    var byte22: UInt8 = 0
    var byte23: UInt8 = 0
    var byte24: UInt8 = 0
    var byte25: UInt8 = 0
    var byte26: UInt8 = 0
    var byte27: UInt8 = 0
    var byte28: UInt8 = 0
    var byte29: UInt8 = 0
    var byte30: UInt8 = 0
    var byte31: UInt8 = 0

    var array: [UInt8] {
        [
            byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7,
            byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15,
            byte16, byte17, byte18, byte19, byte20, byte21, byte22, byte23,
            byte24, byte25, byte26, byte27, byte28, byte29, byte30, byte31,
        ]
    }
}

// MARK: - String Extension

private extension String {
    var smcKeyCode: UInt32 {
        unicodeScalars.prefix(4).reduce(UInt32(0)) { result, scalar in
            (result << 8) + UInt32(scalar.value)
        }
    }
}

private extension UInt32 {
    var stringValue: String {
        let scalars = [
            UnicodeScalar((self >> 24) & 0xff),
            UnicodeScalar((self >> 16) & 0xff),
            UnicodeScalar((self >> 8) & 0xff),
            UnicodeScalar(self & 0xff),
        ]
        return String(String.UnicodeScalarView(scalars.compactMap { $0 }))
    }
}
