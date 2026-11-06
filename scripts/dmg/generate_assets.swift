#!/usr/bin/env swift
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

func writePNG(_ image: NSImage, to name: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to render \(name)\n", stderr)
        exit(1)
    }
    try! png.write(to: outDir.appendingPathComponent(name))
}

func makeImage(size: NSSize, draw: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    draw(NSRect(origin: .zero, size: size))
    image.unlockFocus()
    return image
}

let background = makeImage(size: NSSize(width: 660, height: 420)) { rect in
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.09, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)

    let title = "启动台" as NSString
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(
        at: NSPoint(x: (rect.width - titleSize.width) / 2, y: rect.height - 82),
        withAttributes: titleAttrs
    )

    let subtitle = "拖入「应用程序」即可安装" as NSString
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.65),
    ]
    let subSize = subtitle.size(withAttributes: subAttrs)
    subtitle.draw(
        at: NSPoint(x: (rect.width - subSize.width) / 2, y: rect.height - 108),
        withAttributes: subAttrs
    )

    if !iconPath.isEmpty, let icon = NSImage(contentsOfFile: iconPath) {
        icon.draw(in: NSRect(x: (rect.width - 72) / 2, y: rect.height - 188, width: 72, height: 72))
    } else if let symbol = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "启动台") {
        let config = NSImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
        let icon = symbol.withSymbolConfiguration(config) ?? symbol
        icon.isTemplate = false
        let tinted = NSImage(size: NSSize(width: 64, height: 64))
        tinted.lockFocus()
        NSColor.white.set()
        icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (rect.width - 64) / 2, y: rect.height - 180, width: 64, height: 64))
    }
}

let guide = makeImage(size: NSSize(width: 300, height: 260)) { rect in
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 16, yRadius: 16).fill()

    let title = "安装说明" as NSString
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "PingFang SC Semibold", size: 18) ?? NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    ]
    title.draw(at: NSPoint(x: 24, y: rect.height - 48), withAttributes: titleAttrs)

    let lines = [
        "1. 把启动台拖到「应用程序」",
        "2. 首次打开如被拦截，右键打开",
        "   或在系统设置中放行",
        "3. 可选 14 天试用，或输入激活码",
        "4. 找回/支持：huoyongzhuang@qq.com",
    ]
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "PingFang SC", size: 13) ?? NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
    ]
    var y = rect.height - 88
    for line in lines {
        (line as NSString).draw(at: NSPoint(x: 24, y: y), withAttributes: bodyAttrs)
        y -= 28
    }
}

writePNG(background, to: "background.png")
writePNG(guide, to: "install-guide.png")
print("generated background.png / install-guide.png in \(outDir.path)")
