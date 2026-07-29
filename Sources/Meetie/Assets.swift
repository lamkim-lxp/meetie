import AppKit

/// Loads bundled assets (copied into the .app by scripts/bundle.sh; see assets/ASSETS.md).
enum Assets {
    private static var frameCache: [DogVariant: [CGImage]] = [:]
    private static var imageCache: [String: CGImage] = [:]

    private static func resourceURL(_ relativePath: String) -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let url = base.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 6-frame 32×32 run cycle (R14a); rendered at 2× with nearest-neighbor.
    static func spriteFrames(for variant: DogVariant) -> [CGImage] {
        if let cached = frameCache[variant] { return cached }
        let frames: [CGImage] = (1...6).compactMap { index in
            guard let url = resourceURL("dog-sprite/\(variant.rawValue)/frame\(index).png"),
                  let image = NSImage(contentsOf: url) else { return nil }
            var rect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        frameCache[variant] = frames
        return frames
    }

    /// 9-slice pixel wood sign towed by the Dog (R14, §2.4); pre-scaled 3×.
    static func bannerSignImage() -> CGImage? {
        cgImage("banner/sign@3x.png")
    }

    /// 9-slice pixel Join button matching the sign (R14); pre-scaled 3×.
    static func joinButtonImage() -> CGImage? {
        cgImage("banner/join@3x.png")
    }

    private static func cgImage(_ path: String) -> CGImage? {
        if let cached = imageCache[path] { return cached }
        guard let url = resourceURL(path), let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        imageCache[path] = cg
        return cg
    }

    /// Pixel clock glyph, single state, template image (R20).
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["clock@1x", "clock@2x"] {
            if let url = resourceURL("menubar/\(name).png"),
               let data = try? Data(contentsOf: url),
               let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
            }
        }
        if image.representations.isEmpty,
           let fallback = NSImage(systemSymbolName: "clock", accessibilityDescription: "Meetie") {
            fallback.isTemplate = true
            return fallback
        }
        image.isTemplate = true
        return image
    }

    /// The four-sample bark pool (R16a).
    static func barkSampleURLs() -> [URL] {
        [
            "bark/bark-01.wav",
            "bark/bark-02.wav",
            "bark/bark-single.wav",
            "bark/dog_barking_mono_full.wav",
        ].compactMap(resourceURL)
    }

    static func burstSampleURL() -> URL? {
        resourceURL("bark/dog_barking_mono_full.wav")
    }
}
