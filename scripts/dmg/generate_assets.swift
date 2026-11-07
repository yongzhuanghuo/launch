#!/usr/bin/env swift
import AppKit

// 生成 macOS DMG 安装窗口背景图（800 x 500）。
// 参考 Downie6：顶部图标/标题，左侧“安装失败”卡片，右侧“安装”卡片，
// 下方是安装说明缩略图、启动台.app 和 Applications 快捷方式。
//
// 运行：swift scripts/dmg/generate_assets.swift scripts/dmg <icon.png>

struct Canvas {
    let w: CGFloat
    let h: CGFloat
    let rep: NSBitmapImageRep

    init(w: CGFloat, h: CGFloat, top: NSColor, bottom: NSColor) {
        self.w = w
        self.h = h
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w),
            pixelsHigh: Int(h),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let gradient = NSGradient(starting: top, ending: bottom)!
        gradient.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
    }

    func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x, y: h - top - height, width: width, height: height)
    }

    func point(_ x: CGFloat, _ top: CGFloat) -> NSPoint {
        NSPoint(x: x, y: h - top)
    }

    func text(
        _ value: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        size: CGFloat,
        bold: Bool = false,
        color: NSColor = .black,
        align: NSTextAlignment = .left,
        lineSpacing: CGFloat = 6
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineSpacing = lineSpacing
        let font = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: value, attributes: attrs)
            .draw(in: rect(x, top, width, height))
    }

    func card(
        _ x: CGFloat,
        _ top: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat,
        fill: NSColor,
        stroke: NSColor
    ) {
        let path = NSBezierPath(
            roundedRect: rect(x, top, width, height),
            xRadius: 16,
            yRadius: 16
        )
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func arrow(
        _ x1: CGFloat,
        _ top1: CGFloat,
        _ x2: CGFloat,
        _ top2: CGFloat,
        color: NSColor
    ) {
        let a = point(x1, top1)
        let b = point(x2, top2)
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.lineWidth = 2
        color.setStroke()
        path.stroke()

        let angle = atan2(b.y - a.y, b.x - a.x)
        let length: CGFloat = 10
        let p1 = NSPoint(
            x: b.x - length * cos(angle - .pi / 6),
            y: b.y - length * sin(angle - .pi / 6)
        )
        let p2 = NSPoint(
            x: b.x - length * cos(angle + .pi / 6),
            y: b.y - length * sin(angle + .pi / 6)
        )
        let head = NSBezierPath()
        head.move(to: b)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        color.setFill()
        head.fill()
    }

    func logo(_ path: String, x: CGFloat, top: CGFloat, size: CGFloat) {
        guard let image = NSImage(contentsOfFile: path) else { return }
        image.draw(
            in: rect(x, top, size, size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    func save(_ path: String) {
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: path))
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

let blue = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1)
let lightBlue = NSColor(calibratedRed: 0.91, green: 0.95, blue: 1.0, alpha: 1)
let softStroke = NSColor(calibratedRed: 0.84, green: 0.89, blue: 0.97, alpha: 1)
let red = NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.20, alpha: 1)
let darkGray = NSColor(calibratedWhite: 0.22, alpha: 1)
let muted = NSColor(calibratedWhite: 0.48, alpha: 1)

let c = Canvas(w: 800, h: 500, top: lightBlue, bottom: .white)
c.logo(iconPath, x: 368, top: 24, size: 64)
c.text(
    "启动台",
    x: 0, top: 100, width: 800, height: 40,
    size: 28, bold: true, align: .center
)
c.text(
    "适用于 macOS 26.0 或更高版本",
    x: 0, top: 144, width: 800, height: 24,
    size: 14, color: muted, align: .center
)

c.card(40, 205, 280, 100, fill: NSColor.white.withAlphaComponent(0.94), stroke: softStroke)
c.text(
    "安装失败？",
    x: 58, top: 218, width: 244, height: 26,
    size: 17, bold: true, color: red
)
c.text(
    "双击左侧「安装说明」\n查看详细步骤",
    x: 58, top: 248, width: 244, height: 48,
    size: 13, color: darkGray
)
c.arrow(180, 305, 180, 332, color: red)

c.card(480, 205, 280, 100, fill: NSColor.white.withAlphaComponent(0.94), stroke: softStroke)
c.text(
    "安装",
    x: 498, top: 218, width: 244, height: 26,
    size: 17, bold: true, color: darkGray
)
c.text(
    "将启动台拖入\n「应用程序」文件夹",
    x: 498, top: 248, width: 244, height: 48,
    size: 13, color: darkGray
)
c.arrow(560, 305, 560, 332, color: blue)
c.arrow(548, 365, 608, 365, color: blue)

c.text(
    "双击启动台启动 · 详细步骤见左侧安装说明",
    x: 0, top: 440, width: 800, height: 24,
    size: 12, color: muted, align: .center
)
c.save(outDir.appendingPathComponent("background.png").path)
print("generated background.png in \(outDir.path)")
