import SwiftUI

struct FanGaugeView: View {
    let fan: Fan
    @EnvironmentObject var controller: FanController

    private var gaugeColor: Color {
        let pct = fan.load
        if pct < 0.5 { return .green }
        if pct < 0.7 { return .yellow }
        if pct < 0.9 { return .orange }
        return .red
    }

    private var modeLabel: String {
        fan.isManualMode ? "手动" : controller.mode.rawValue
    }

    private var modeColor: Color {
        fan.isManualMode ? Color.orange : (controller.mode == .auto ? Color.accentColor : Color.orange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(fan.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(modeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(modeColor.opacity(0.12))
                    .foregroundColor(modeColor)
                    .clipShape(Capsule())
            }

            // Gauge bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gaugeColor)
                        .frame(width: max(0, geo.size.width * min(fan.load, 1.0)), height: 6)
                        .animation(.easeOut(duration: 0.4), value: fan.load)
                }
            }
            .frame(height: 6)

            // RPM
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(fan.rpm)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text("RPM")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Meta
            HStack {
                Text("最低 \(fan.minRPM)")
                Spacer()
                Text("最高 \(fan.maxRPM)")
                Spacer()
                Text("负载 \(Int(fan.load * 100))%")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}
