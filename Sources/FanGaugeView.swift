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
        controller.mode.rawValue
    }

    private var modeColor: Color {
        controller.mode == .auto ? Color.accentColor : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(fan.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(modeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(modeColor.opacity(0.15))
                    .foregroundColor(modeColor)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(modeColor.opacity(0.3), lineWidth: 0.5))
            }

            // Gauge bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.25))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * min(fan.load, 1.0), height: 8)
                        .animation(.easeOut(duration: 0.4), value: fan.load)
                }
            }
            .frame(height: 8)

            // RPM
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(fan.rpm)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
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
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}
