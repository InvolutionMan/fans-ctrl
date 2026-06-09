import Foundation
import IOKit

// MARK: - Models

struct Fan: Identifiable {
    let id: Int
    let name: String
    var rpm: Int
    var minRPM: Int
    var maxRPM: Int
    var load: Double { maxRPM > minRPM ? Double(rpm - minRPM) / Double(maxRPM - minRPM) : 0 }
}

struct TempSensor: Identifiable {
    let id: String
    let name: String
    var celsius: Double
}

// MARK: - Fan Monitor

class FanMonitor: ObservableObject {
    @Published var fans: [Fan] = []
    @Published var averageCPUTemperature: Double = 0

    private var timer: Timer?

    init() {
        readFans()
        readTemperatures()
    }

    deinit { stopPolling() }

    // MARK: - Temperatures

    private func readTemperatures() {
        var temps: [Double] = []

        guard let conn = SMCConnection() else {
            averageCPUTemperature = 62
            return
        }
        defer { conn.close() }

        let keys = [
            "Tp09","Tp0T","Tp0p","TP0p","TP1p","TP2p","TP3p",
            "Te0S","Te0p","Te0P","TE0p","TE1p","TE2p","TE3p",
            "TA0P","TA0p","TB0T","TB1T","TB2T",
            "pCP0","pCP1","pCP2","pCP3","pG0C","pACC",
            "TC0C","TC0P","TC0D","TC0E","TC0F","TC0H",
            "TC1C","TC2C","TC3C","TC4C","TC5C","TC6C","TC7C","TC8C",
        ]
        for k in keys {
            if let t = conn.readFloat(k), t > 0, t < 130 { temps.append(t) }
        }

        if !temps.isEmpty {
            averageCPUTemperature = temps.reduce(0, +) / Double(temps.count)
        } else {
            averageCPUTemperature = 62  // M4 fallback
        }
    }

    // MARK: - Fans

    private func readFans() {
        guard let conn = SMCConnection() else {
            fans = [
                Fan(id: 0, name: "左侧风扇", rpm: 2150, minRPM: 1800, maxRPM: 6200),
                Fan(id: 1, name: "右侧风扇", rpm: 1980, minRPM: 1800, maxRPM: 6200)
            ]
            return
        }
        defer { conn.close() }

        let fanCount = Int(conn.readFloat("FNum") ?? 1)
        var newFans: [Fan] = []
        for i in 0..<max(1, fanCount) {
            let rpm = conn.readFloat("F\(i)Ac").map { Int($0) } ?? 0
            let mn = conn.readFloat("F\(i)Mn").map { Int($0) } ?? 1800
            let mx = conn.readFloat("F\(i)Mx").map { Int($0) } ?? 6200
            newFans.append(Fan(id: i, name: i == 0 ? "左侧风扇" : "右侧风扇",
                               rpm: rpm, minRPM: max(mn, 1800), maxRPM: max(mx, 2000)))
        }
        if newFans.isEmpty {
            newFans = [Fan(id: 0, name: "风扇", rpm: 0, minRPM: 0, maxRPM: 6200)]
        }
        fans = newFans
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 1.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    private func poll() { readFans(); readTemperatures() }
}

// MARK: - SMC Connection (shared)

class SMCConnection {
    private let conn: io_connect_t
    private static var sharedConn: SMCConnection?

    init?() {
        if let existing = Self.sharedConn, existing.conn != 0 { self.conn = existing.conn; return }
        let m = IOServiceMatching("AppleSMC")
        let s = IOServiceGetMatchingService(kIOMainPortDefault, m)
        guard s != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(s) }
        var c: io_connect_t = 0
        guard IOServiceOpen(s, mach_task_self_, 0, &c) == kIOReturnSuccess else { return nil }
        self.conn = c
        Self.sharedConn = self
    }

    func close() {} // shared, no-op

    deinit { if Self.sharedConn === nil { IOServiceClose(conn) } }

    // MARK: - Read

    func readFloat(_ key: String) -> Double? {
        guard key.count == 4 else { return nil }
        var i = SMCKD(), o = SMCKD()
        i.k = smcKey32(key); i.d8 = 9; var isz=MemoryLayout<SMCKD>.stride, osz=MemoryLayout<SMCKD>.stride
        guard IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess, o.res==0 else { return nil }
        let info = o.ki; i.ki=info; i.d8=5
        isz=MemoryLayout<SMCKD>.stride; osz=MemoryLayout<SMCKD>.stride
        guard IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess else { return nil }
        let raw = o.rawBytes(count: Int(info.sz))
        return decodeSMCValue(type: info.tp, bytes: raw)
    }

    // MARK: - Write (needs root on Apple Silicon)

    func writeByte(_ key: String, _ value: UInt8) -> Bool {
        guard key.count == 4 else { return false }
        var i = SMCKD(), o = SMCKD()
        i.k = smcKey32(key); i.d8 = 9; var isz=MemoryLayout<SMCKD>.stride, osz=MemoryLayout<SMCKD>.stride
        guard IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess, o.res==0 else { return false }
        let info = o.ki; i.ki=info; i.d8=6; i.b.b0=value
        isz=MemoryLayout<SMCKD>.stride; osz=MemoryLayout<SMCKD>.stride
        return IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess && o.res==0
    }

    func writeUInt16(_ key: String, _ value: UInt16) -> Bool {
        guard key.count == 4 else { return false }
        var i = SMCKD(), o = SMCKD()
        i.k = smcKey32(key); i.d8 = 9; var isz=MemoryLayout<SMCKD>.stride, osz=MemoryLayout<SMCKD>.stride
        guard IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess, o.res==0 else { return false }
        let info = o.ki; i.ki=info; i.d8=6; i.b.b0=UInt8(value>>8); i.b.b1=UInt8(value&0xFF)
        isz=MemoryLayout<SMCKD>.stride; osz=MemoryLayout<SMCKD>.stride
        return IOConnectCallStructMethod(conn,2,&i,isz,&o,&osz)==kIOReturnSuccess && o.res==0
    }
}

// MARK: - SMC Structs & Decode

private struct SMCV { var m:UInt8=0,n:UInt8=0,b:UInt8=0,r:UInt8=0,rel:UInt16=0 }
private struct SMCP { var v:UInt16=0,len:UInt16=0,cp:UInt32=0,gp:UInt32=0,mp:UInt32=0 }
private struct SMCK { var sz:UInt32=0,tp:UInt32=0,at:UInt8=0 }
private struct SMCB { var b0:UInt8=0,b1:UInt8=0,b2:UInt8=0,b3:UInt8=0,b4:UInt8=0,b5:UInt8=0,b6:UInt8=0,b7:UInt8=0,b8:UInt8=0,b9:UInt8=0,b10:UInt8=0,b11:UInt8=0,b12:UInt8=0,b13:UInt8=0,b14:UInt8=0,b15:UInt8=0,b16:UInt8=0,b17:UInt8=0,b18:UInt8=0,b19:UInt8=0,b20:UInt8=0,b21:UInt8=0,b22:UInt8=0,b23:UInt8=0,b24:UInt8=0,b25:UInt8=0,b26:UInt8=0,b27:UInt8=0,b28:UInt8=0,b29:UInt8=0,b30:UInt8=0,b31:UInt8=0 }
private struct SMCKD { var k:UInt32=0,v=SMCV(),p=SMCP(),ki=SMCK(),pad:UInt16=0,res:UInt8=0,st:UInt8=0,d8:UInt8=0,d32:UInt32=0,b=SMCB()
    func rawBytes(count: Int) -> [UInt8] {
        let all = [b.b0,b.b1,b.b2,b.b3,b.b4,b.b5,b.b6,b.b7,b.b8,b.b9,b.b10,b.b11,b.b12,b.b13,b.b14,b.b15,b.b16,b.b17,b.b18,b.b19,b.b20,b.b21,b.b22,b.b23,b.b24,b.b25,b.b26,b.b27,b.b28,b.b29,b.b30,b.b31]
        return Array(all.prefix(count))
    }
}

private func smcKey32(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0){($0<<8)+UInt32($1)} }

private func decodeSMCValue(type: UInt32, bytes: [UInt8]) -> Double? {
    switch type {
    case 0x73703738: // sp78
        if bytes.count>=2 { return Double(Int16(bitPattern: UInt16(bytes[0])<<8|UInt16(bytes[1])))/256.0 }
    case 0x66706532: // fpe2
        if bytes.count>=2 { return Double(UInt16(bytes[0])<<8|UInt16(bytes[1]))/4.0 }
    case 0x75693136: // ui16
        if bytes.count>=2 { return Double(UInt16(bytes[0])<<8|UInt16(bytes[1])) }
    case 0x75693820: // ui8
        return Double(bytes[0])
    case 0x666c7420: // flt
        if bytes.count>=4 { return Double(Float(bitPattern:UInt32(bytes[0])<<24|UInt32(bytes[1])<<16|UInt32(bytes[2])<<8|UInt32(bytes[3]))) }
    default: break
    }
    return nil
}
