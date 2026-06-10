# FansCtrl

一款 macOS 风扇控制工具，通过直接读写 Apple SMC（System Management Controller）实现风扇转速的精确控制。

## 功能特性

- **多种控制模式**
  - 自动模式 — 恢复 macOS 默认风扇策略
  - 手动模式 — 直接设定风扇目标转速（RPM）
  - 传感器模式 — 根据 CPU 温度自动调节风扇转速

- **预设方案**
  - 均衡 / 安静 / 性能 / 全速，一键切换

- **独立风扇控制**
  - 支持多风扇独立调节，每个风扇可单独设定 RPM

- **菜单栏集成**
  - 可在菜单栏显示风扇转速和温度
  - 支持菜单栏图标切换

- **开机自启**
  - 支持注册为登录项，开机自动运行

- **硬件兼容**
  - 支持 Apple Silicon（M1–M5+）和 Intel Mac
  - 自动检测 SMC 风扇模式键类型（`F%dMd` / `F%dmd`）
  - 自动识别数据类型（`flt` / `fpe2`）

## 系统要求

- macOS 14.0+
- 需要 SMC 访问权限（首次运行可能需要授权）

## 构建

```bash
# 使用 Makefile
make build

# 或直接使用 Swift Package Manager
swift build
```

## 运行

```bash
# 构建并运行
make run

# 或手动运行
.build/debug/FansCtrl
```

## 安装为 .app

```bash
make app
```

构建完成后，`FansCtrl.app` 会生成在项目根目录，可拖入 `/Applications` 使用。

## 项目结构

```
Sources/
├── FansCtrlApp.swift          # 应用入口
├── ContentView.swift          # 主界面
├── ControlPanelView.swift     # 控制面板
├── FanController.swift        # 风扇控制核心（SMC 读写）
├── FanMonitor.swift           # 风扇状态监控
├── FanGaugeView.swift         # 风扇转速仪表盘
├── TemperatureView.swift      # 温度显示
├── AnimatedFanIconView.swift  # 动画风扇图标
└── MenuBarController.swift    # 菜单栏控制器
SourcesAuth/
├── AuthHelper.c               # SMC 权限辅助（C 层）
└── include/
```

## 许可

MIT License
