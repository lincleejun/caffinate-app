// 绘制 App 图标 1024x1024 PNG。用法：swift scripts/make-icon.swift <输出.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS 图标网格：内容区约占 82%，圆角约 18.5%
let inset = size * 0.09
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: size * 0.185, yRadius: size * 0.185)

// 奶油底 + 细微暖色描边
NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1).setFill()
bg.fill()
NSColor(calibratedRed: 0.89, green: 0.32, blue: 0.25, alpha: 0.25).setStroke()
bg.lineWidth = size * 0.012
bg.stroke()

// 番茄红圆环（呼应番茄钟进度环），缺口朝右上
let ringRect = rect.insetBy(dx: rect.width * 0.13, dy: rect.height * 0.13)
let ring = NSBezierPath()
ring.appendArc(
    withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
    radius: ringRect.width / 2,
    startAngle: 60, endAngle: 330)
NSColor(calibratedRed: 0.89, green: 0.32, blue: 0.25, alpha: 1).setStroke()
ring.lineWidth = size * 0.045
ring.lineCapStyle = .round
ring.stroke()

func drawCentered(_ str: String, fontSize: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
    let s = NSAttributedString(string: str, attributes: attrs)
    let b = s.size()
    s.draw(at: NSPoint(x: (size - b.width) / 2 + dx, y: (size - b.height) / 2 + dy))
}

// 主体咖啡杯 + 右下角小番茄（落在圆环缺口处）
drawCentered("☕", fontSize: size * 0.42, dy: size * 0.01)
drawCentered("🍅", fontSize: size * 0.20, dx: size * 0.26, dy: -size * 0.26)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("渲染失败\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("written: \(outPath)")
