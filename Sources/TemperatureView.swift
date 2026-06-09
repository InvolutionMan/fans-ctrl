import SwiftUI

struct TemperatureView: View {
    let averageCPUTemperature: Double

    private func color(for temp: Double) -> Color {
        if temp < 60 { return .green }
        if temp < 75 { return .yellow }
        if temp < 90 { return .orange }
        return .red
    }

    private func statusText(for temp: Double) -> String {
        if temp < 60 { return "正常" }
        if temp < 75 { return "温热" }
        if temp < 90 { return "较高" }
        return "过热"
    }

    private func progress(_ temp: Double) -> Double {
        min(temp / 110.0, 1.0)
    }

    var body: some View {
        let temp = averageCPUTemperature

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CPU 温度")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(statusText(for: temp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color(for: temp).opacity(0.15))
                    .foregroundColor(color(for: temp))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color(for: temp).opacity(0.3), lineWidth: 0.5))
            }

            HStack(spacing: 16) {
                // CPU Icon
                Text("CPU")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    // Color bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: temp))
                                .frame(width: geo.size.width * progress(temp), height: 6)
                                .animation(.easeOut(duration: 0.4), value: temp)
                        }
                    }
                    .frame(height: 6)

                    // Value — one decimal place
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", temp))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                        Text("°C")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            )
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
