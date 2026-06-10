import Foundation
import IOKit

// MARK: - Models

struct Fan: Identifiable, Equatable {
    let id: Int
    let name: String
    var rpm: Int
    var minRPM: Int
    var maxRPM: Int
    var targetRPM: Int       // F%dTg — SMC target RPM
    var isManualMode: Bool   // whether this fan is in manual control
    var load: Double { maxRPM > minRPM ? max(0, min(1, Double(rpm - minRPM) / Double(maxRPM - minRPM))) : 0 }
}

struct TempSensor: Identifiable, Equatable {
    let id: String
    let name: String
    var celsius: Double
    
    static func == (lhs: TempSensor, rhs: TempSensor) -> Bool {
        lhs.id == rhs.id && lhs.celsius == rhs.celsius
    }
}

// MARK: - Fan Monitor

class FanMonitor: ObservableObject {
    @Published var fans: [Fan] = []
    @Published var temperatures: [TempSensor] = []
    @Published var averageCPUTemperature: Double? = nil

    private var timer: Timer?

    init() {
        readFans()
        readTemperatures()
    }

    deinit { stopPolling() }

    // MARK: - Read Temperatures

    private func readTemperatures() {
        var sensors: [TempSensor] = []

        guard let connection = SMCConnection() else {
            temperatures = [TempSensor(id: "TC0P", name: "CPU", celsius: 62)]
            averageCPUTemperature = 62
            return
        }

        let cpuTemperatureKeys = [
            "Te05", "Te0S", "Te09", "Te0H",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
            "TC0C", "TC0P", "TC0E", "TC0F", "TC0D", "TC0H",
            "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C",
        ]

        for key in cpuTemperatureKeys {
            if let temp = connection.readNumericValue(for: key), temp > 0, temp < 130 {
                let name: String
                switch key {
                case let k where k.hasPrefix("TC"): name = "CPU Core \(k.dropFirst(2))"
                case let k where k.hasPrefix("Tp"): name = "CPU Proximity"
                case let k where k.hasPrefix("Te"): name = "CPU Efficiency"
                default: name = key
                }
                sensors.append(TempSensor(id: key, name: name, celsius: temp))
            }
        }

        if !sensors.isEmpty {
            let avgTemp = sensors.reduce(0.0) { $0 + $1.celsius } / Double(sensors.count)
            sensors.insert(TempSensor(id: "CPU", name: "CPU", celsius: avgTemp), at: 0)
            averageCPUTemperature = avgTemp
        }

        if sensors.isEmpty {
            sensors = [TempSensor(id: "TC0P", name: "CPU", celsius: 62)]
            averageCPUTemperature = 62
        }

        temperatures = sensors
    }

    // MARK: - Read Fans

    private func readFans() {
        guard let connection = SMCConnection() else {
            fans = [
                Fan(id: 0, name: "风扇 1", rpm: 2150, minRPM: 1800, maxRPM: 6200, targetRPM: 2150, isManualMode: false),
                Fan(id: 1, name: "风扇 2", rpm: 1980, minRPM: 1800, maxRPM: 6200, targetRPM: 1980, isManualMode: false)
            ]
            return
        }

        let fanCount = connection.readNumericValue(for: "FNum").map { max(0, Int($0.rounded(.down))) } ?? 2

        // Detect which mode key works on this hardware (M5+ uses lowercase, M1-M4 uppercase)
        let modeKeyTemplate: String = connection.readNumericValue(for: "F0md") != nil ? "F%dmd" : "F%dMd"

        var newFans: [Fan] = []
        for i in 0..<max(1, fanCount) {
            let rpm = connection.readNumericValue(for: "F\(i)Ac").map { Int($0.rounded()) } ?? 2000
            let min = connection.readNumericValue(for: "F\(i)Mn").map { Int($0.rounded()) } ?? 1800
            let max = connection.readNumericValue(for: "F\(i)Mx").map { Int($0.rounded()) } ?? 6200
            let target = connection.readNumericValue(for: "F\(i)Tg").map { Int($0.rounded()) } ?? rpm
            let modeKey = String(format: modeKeyTemplate, i)
            let modeValue = connection.readNumericValue(for: modeKey).map { Int($0) } ?? 0
            let isManual = modeValue == 1
            newFans.append(Fan(id: i, name: i == 0 ? "风扇 1" : "风扇 2",
                              rpm: rpm, minRPM: min, maxRPM: max,
                              targetRPM: target, isManualMode: isManual))
        }

        if newFans.isEmpty {
            newFans = [
                Fan(id: 0, name: "风扇 1", rpm: 2150, minRPM: 1800, maxRPM: 6200, targetRPM: 2150, isManualMode: false),
                Fan(id: 1, name: "风扇 2", rpm: 1980, minRPM: 1800, maxRPM: 6200, targetRPM: 1980, isManualMode: false)
            ]
        }

        fans = newFans
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 3.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    private func poll() { readFans(); readTemperatures() }
}

// MARK: - SMC Connection

private class SMCConnection {
    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { return nil }

        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    func readNumericValue(for key: String) -> Double? {
        guard let value = readKey(key), value.result == 0 else { return nil }
        return value.numericValue
    }

    private func readKey(_ key: String) -> SMCValue? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.smcKeyCode
        input.data8 = SMC_CMD_READ_KEY_INFO

        guard call(input: &input, output: &output) == kIOReturnSuccess, output.result == 0 else { return nil }

        let keyInfo = output.keyInfo
        input.keyInfo = keyInfo
        input.data8 = SMC_CMD_READ_BYTES

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        return SMCValue(keyInfo: keyInfo, result: output.result, bytes: output.byteArray(size: keyInfo.dataSize))
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC, &input, inputSize, &output, &outputSize)
    }
}

// MARK: - SMC Constants

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEY_INFO: UInt8 = 9

// MARK: - SMC Value

private struct SMCValue {
    let keyInfo: SMCKeyInfoData
    let result: UInt8
    let bytes: [UInt8]

    var numericValue: Double? {
        switch keyInfo.dataType.stringValue {
        case "ui8 ": return bytes.first.map(Double.init)
        case "ui16": guard bytes.count >= 2 else { return nil }; return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "sp78": guard bytes.count >= 2 else { return nil }; return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2": guard bytes.count >= 2 else { return nil }; return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "flt ": guard bytes.count >= 4 else { return nil }; return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        default: return nil
        }
    }
}

// MARK: - SMC Data Structures

private struct SMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
private struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

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

    func byteArray(size: UInt32) -> [UInt8] { Array(bytes.array.prefix(Int(size))) }
}

private struct SMCBytes {
    var byte0: UInt8 = 0; var byte1: UInt8 = 0; var byte2: UInt8 = 0; var byte3: UInt8 = 0
    var byte4: UInt8 = 0; var byte5: UInt8 = 0; var byte6: UInt8 = 0; var byte7: UInt8 = 0
    var byte8: UInt8 = 0; var byte9: UInt8 = 0; var byte10: UInt8 = 0; var byte11: UInt8 = 0
    var byte12: UInt8 = 0; var byte13: UInt8 = 0; var byte14: UInt8 = 0; var byte15: UInt8 = 0
    var byte16: UInt8 = 0; var byte17: UInt8 = 0; var byte18: UInt8 = 0; var byte19: UInt8 = 0
    var byte20: UInt8 = 0; var byte21: UInt8 = 0; var byte22: UInt8 = 0; var byte23: UInt8 = 0
    var byte24: UInt8 = 0; var byte25: UInt8 = 0; var byte26: UInt8 = 0; var byte27: UInt8 = 0
    var byte28: UInt8 = 0; var byte29: UInt8 = 0; var byte30: UInt8 = 0; var byte31: UInt8 = 0
    var array: [UInt8] { [byte0,byte1,byte2,byte3,byte4,byte5,byte6,byte7,byte8,byte9,byte10,byte11,byte12,byte13,byte14,byte15,byte16,byte17,byte18,byte19,byte20,byte21,byte22,byte23,byte24,byte25,byte26,byte27,byte28,byte29,byte30,byte31] }
}

private extension String {
    var smcKeyCode: UInt32 { unicodeScalars.prefix(4).reduce(UInt32(0)) { ($0 << 8) + UInt32($1.value) } }
}

private extension UInt32 {
    var stringValue: String {
        let s = [UnicodeScalar((self>>24)&0xff),UnicodeScalar((self>>16)&0xff),UnicodeScalar((self>>8)&0xff),UnicodeScalar(self&0xff)]
        return String(String.UnicodeScalarView(s.compactMap{$0}))
    }
}
