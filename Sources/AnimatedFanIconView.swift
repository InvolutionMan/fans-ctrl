import AppKit
import QuartzCore

/// 菜单栏用的旋转风扇视图（eaf4fa 浅蓝白色，转速随温度变化）
final class AnimatedFanIconView: NSView {

    // MARK: - Configuration

    /// 温度区间 → 动画时长（秒，越小越快）
    private static let tempMin: Double = 30
    private static let tempMax: Double = 100
    /// 最慢一圈（秒）— 低温怠速
    private static let durationSlow: Double = 3.0
    /// 最快一圈（秒）— 高温全速
    private static let durationFast: Double = 0.3

    private let bladeCount = 5
    private let rotationLayer = CAShapeLayer()
    private let centerDot = CAShapeLayer()

    /// 固定颜色 #eaf4fa（浅蓝白）
    private static let fanColor = NSColor(
        red: 234.0 / 255.0,
        green: 244.0 / 255.0,
        blue: 250.0 / 255.0,
        alpha: 1.0
    )

    // MARK: - Init

    init(size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers(size: size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layer Setup

    private func setupLayers(size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2

        // -- Blade group (rotates as a whole) --
        rotationLayer.frame = bounds
        rotationLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        rotationLayer.position = center

        let bladePath = CGMutablePath()
        for i in 0..<bladeCount {
            let angle = CGFloat(i) * (2 * .pi / CGFloat(bladeCount)) - .pi / 2
            addBlade(to: bladePath, center: center, radius: radius, angle: angle)
        }
        rotationLayer.path = bladePath
        rotationLayer.fillColor = Self.fanColor.cgColor
        rotationLayer.strokeColor = nil

        // -- Center hub dot --
        let dotRadius = radius * 0.17
        let dotPath = CGMutablePath()
        dotPath.addArc(center: center, radius: dotRadius,
                       startAngle: 0, endAngle: .pi * 2, clockwise: false)
        centerDot.path = dotPath
        centerDot.fillColor = Self.fanColor.cgColor
        centerDot.strokeColor = Self.fanColor.cgColor
        centerDot.lineWidth = 0.8

        layer?.addSublayer(rotationLayer)
        layer?.addSublayer(centerDot)
    }

    /// 构建一个扇叶形状（水滴形，从中心向外延伸）
    private func addBlade(to path: CGMutablePath, center: CGPoint, radius: CGFloat, angle: CGFloat) {
        let innerR = radius * 0.24
        let outerR = radius * 0.90
        let widthFactor: CGFloat = 0.42

        // 扇叶中心线方向
        let dx = cos(angle)
        let dy = sin(angle)
        // 垂直方向
        let nx = -dy
        let ny = dx

        let base = CGPoint(x: center.x + dx * innerR, y: center.y + dy * innerR)
        let tip  = CGPoint(x: center.x + dx * outerR, y: center.y + dy * outerR)

        // 控制点：向一侧弯曲，形成水滴弧
        let bulge = outerR * widthFactor
        let mid = (innerR + outerR) / 2
        let cp1 = CGPoint(x: center.x + dx * mid + nx * bulge,
                          y: center.y + dy * mid + ny * bulge)
        let cp2 = CGPoint(x: center.x + dx * mid - nx * bulge * 0.35,
                          y: center.y + dy * mid - ny * bulge * 0.35)

        path.move(to: base)
        path.addQuadCurve(to: tip, control: cp1)
        path.addQuadCurve(to: base, control: cp2)
        path.closeSubpath()
    }

    // MARK: - Public API

    /// 更新风扇转速动画。temperature 为 CPU 温度（°C）。
    /// 使用 layer.speed + timeOffset 方案：基准动画永不移除，
    /// 通过 convertTime 对齐时间轴后调节 speed，避免长时间开机后时间溢出卡死。
    func updateSpeed(temperature: Double) {
        let t = max(Self.tempMin, min(Self.tempMax, temperature))
        let normalized = (t - Self.tempMin) / (Self.tempMax - Self.tempMin)

        let minSpeed: Double = 1.0 / Self.durationSlow   // 低温怠速 ≈ 0.33×
        let maxSpeed: Double = 1.0 / Self.durationFast    // 高温全速 ≈ 3.33×
        let newSpeed = Float(minSpeed + (maxSpeed - minSpeed) * normalized)

        // 速度变化极小时跳过，减少无意义的状态翻转
        if rotationLayer.animation(forKey: "spin") != nil && abs(rotationLayer.speed - newSpeed) < 0.01 {
            return
        }

        if rotationLayer.animation(forKey: "spin") == nil {
            // 重新添加动画前归零时间轴，防止上次残留干扰
            rotationLayer.speed = 1.0
            rotationLayer.timeOffset = 0.0
            rotationLayer.beginTime = 0.0

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.byValue = CGFloat.pi * 2   // 增量旋转，引擎自动衔接角度
            spin.duration = 1.0             // 基准时间
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.isRemovedOnCompletion = false
            rotationLayer.add(spin, forKey: "spin")
        }

        // 核心：安全无缝变速 — convertTime 对齐当前动画进度，再应用新 speed
        let currentMediaTime = CACurrentMediaTime()
        let pausedTime = rotationLayer.convertTime(currentMediaTime, from: nil)

        rotationLayer.speed = newSpeed
        rotationLayer.timeOffset = pausedTime
        rotationLayer.beginTime = currentMediaTime
    }

    /// 停止旋转
    func stopSpin() {
        // 停止瞬间抓取当前视觉角度，写入 model layer，避免"复位回 0°"跳帧
        if let presentation = rotationLayer.presentation(),
           let angle = presentation.value(forKeyPath: "transform.rotation.z") as? CGFloat {
            rotationLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }

        rotationLayer.removeAnimation(forKey: "spin")

        // 归零时间轴，下次启动时干净起步
        rotationLayer.speed = 1.0
        rotationLayer.timeOffset = 0.0
        rotationLayer.beginTime = 0.0
    }

    /// 静态模式（不转）时显示的淡色
    func setIdleAppearance() {
        rotationLayer.opacity = 0.45
        centerDot.opacity = 0.45
    }

    func setActiveAppearance() {
        rotationLayer.opacity = 1.0
        centerDot.opacity = 1.0
    }

}
