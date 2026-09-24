#!/usr/bin/env swift
// Extract the generated 4×2 sheets into aligned, palette-limited app sprites.
// Run: swift assets/dog-sprite/created/prepare.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let size = 48
let count = 8
let palette: [[UInt8]] = [
    [48, 28, 21], [92, 49, 26], [150, 78, 30], [190, 105, 35],
    [224, 137, 44], [246, 166, 64], [255, 191, 92],
    [220, 189, 146], [248, 226, 188], [255, 245, 224],
    [177, 76, 82], [230, 131, 142],
]

struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(_ width: Int, _ height: Int, background: [UInt8] = [0, 0, 0, 0]) {
        self.width = width
        self.height = height
        pixels = Array(repeating: background, count: width * height).flatMap { $0 }
    }

    init(url: URL) {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        width = image.width
        height = image.height
        pixels = Array(repeating: 0, count: width * height * 4)
        let w = width, h = height
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    var image: CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func save(_ name: String) {
        let output = CGImageDestinationCreateWithURL(root.appendingPathComponent(name) as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, image, nil)
        precondition(CGImageDestinationFinalize(output))
    }

    mutating func paste(_ frame: Raster, x: Int, y: Int, scale: Int = 1) {
        for sy in 0..<frame.height {
            for sx in 0..<frame.width {
                let source = (sy * frame.width + sx) * 4
                guard frame.pixels[source + 3] > 0 else { continue }
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let target = ((y + sy * scale + dy) * width + x + sx * scale + dx) * 4
                        pixels.replaceSubrange(target..<target + 4, with: frame.pixels[source..<source + 4])
                    }
                }
            }
        }
    }
}

var contact = Raster(size * count * 3, size * 2 * 3, background: [239, 237, 228, 255])
for (row, variant) in ["shiba", "corgi"].enumerated() {
    let source = Raster(url: root.appendingPathComponent("source/\(variant).png"))
    // Generated sheets have approximate cell boundaries. Isolate connected
    // silhouettes so a neighboring nose cannot leak into another frame.
    var labels = Array(repeating: -1, count: source.width * source.height)
    var components: [(left: Int, top: Int, right: Int, bottom: Int, label: Int, area: Int)] = []
    for seed in labels.indices {
        guard labels[seed] == -1 && source.pixels[seed * 4 + 3] >= 200 else { continue }
        let label = components.count
        var queue = [seed], cursor = 0
        labels[seed] = label
        var left = source.width, top = source.height, right = 0, bottom = 0
        while cursor < queue.count {
            let pixel = queue[cursor]
            cursor += 1
            let x = pixel % source.width, y = pixel / source.width
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0 && nx < source.width && ny >= 0 && ny < source.height else { continue }
                    let neighbor = ny * source.width + nx
                    if labels[neighbor] == -1 && source.pixels[neighbor * 4 + 3] >= 200 {
                        labels[neighbor] = label
                        queue.append(neighbor)
                    }
                }
            }
        }
        components.append((left, top, right, bottom, label, queue.count))
    }
    let largest = components.sorted { $0.area > $1.area }.prefix(count).sorted { $0.top < $1.top }
    precondition(largest.count == count && largest.allSatisfy { $0.area > 1000 })
    let sourceOrder = largest.prefix(4).sorted { $0.left < $1.left }
        + largest.suffix(4).sorted { $0.left < $1.left }
    // The generated final pose is an early landing in-between. Place it after
    // extension so the loop ends at push-off/flight, without a backward step.
    let bounds = [0, 7, 1, 2, 3, 4, 5, 6].map { sourceOrder[$0] }
    // Uniform scale per breed, fixed nose/ear anchors, restrained vertical bob.
    // Never independently stretch each frame to fit its bounding box.
    let scale = min(40.0 / Double(bounds.map { $0.right - $0.left + 1 }.max()!),
                    35.0 / Double(bounds.map { $0.bottom - $0.top + 1 }.max()!))
    let bob = [-1, 0, 1, 2, 1, 0, -1, -1]
    var frames: [Raster] = []
    var sheet = Raster(size * count, size)
    for i in 0..<count {
        let box = bounds[i]
        let w = Int((Double(box.right - box.left + 1) * scale).rounded())
        let h = Int((Double(box.bottom - box.top + 1) * scale).rounded())
        let xOffset = 44 - w, yOffset = 7 + bob[i]
        var frame = Raster(size, size)
        for y in 0..<h {
            for x in 0..<w {
                let sx = min(box.right, box.left + Int((Double(x) + 0.5) / scale))
                let sy = min(box.bottom, box.top + Int((Double(y) + 0.5) / scale))
                let sourceIndex = (sy * source.width + sx) * 4
                let alpha = Int(source.pixels[sourceIndex + 3])
                guard labels[sy * source.width + sx] == box.label else { continue }
                let rgb = (0..<3).map { min(255, Int(source.pixels[sourceIndex + $0]) * 255 / alpha) }
                let color = palette.min { a, b in
                    func distance(_ c: [UInt8]) -> Int {
                        (0..<3).reduce(0) { sum, channel in
                            let d = rgb[channel] - Int(c[channel])
                            return sum + d * d
                        }
                    }
                    return distance(a) < distance(b)
                }!
                let target = ((y + yOffset) * size + x + xOffset) * 4
                frame.pixels.replaceSubrange(target..<target + 4, with: color + [255])
            }
        }
        let alpha = stride(from: 3, to: frame.pixels.count, by: 4).map { frame.pixels[$0] }
        precondition(alpha.contains(0) && alpha.contains(255))
        precondition(Set(alpha).count == 2, "Sprites must have hard alpha edges")
        frame.save("\(variant)/frame\(i + 1).png")
        sheet.paste(frame, x: i * size, y: 0)
        contact.paste(frame, x: i * size * 3, y: row * size * 3, scale: 3)
        frames.append(frame)
    }
    sheet.save("\(variant)-sheet.png")
    let gif = CGImageDestinationCreateWithURL(root.appendingPathComponent("\(variant)-preview.gif") as CFURL,
        UTType.gif.identifier as CFString, count, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        var preview = Raster(size * 4, size * 4, background: [239, 237, 228, 255])
        preview.paste(frame, x: 0, y: 0, scale: 4)
        CGImageDestinationAddImage(gif, preview.image,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.07]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(gif))
    print("\(variant): \(count) transparent \(size)×\(size) frames, 70 ms/frame")
}
contact.save("contact-sheet.png")
