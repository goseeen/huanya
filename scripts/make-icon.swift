import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let output = CommandLine.arguments[1]
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for multiplier in [1, 2] {
                let suffix = multiplier == 2 ? "@2x" : ""
                let path = "\(output)/icon_\(size)x\(size)\(suffix).png"
                try BrandArtwork.png(size: size * multiplier, style: .applicationIcon)!.write(to: URL(fileURLWithPath: path))
            }
        }
        let parent = URL(fileURLWithPath: output).deletingLastPathComponent()
        try BrandArtwork.png(size: 256, style: .brandMark)!.write(to: parent.appendingPathComponent("brand-mark-preview.png"))
        try BrandArtwork.png(size: 144, style: .menuBar)!.write(to: parent.appendingPathComponent("menu-glyph-preview.png"))
        print("Icon artwork created from the shared RiseUp vector drawing")
    }
}
