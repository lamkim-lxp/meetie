import AppKit
import QuartzCore

/// Borderless, transparent, non-activating panel at screen-saver level: above
/// fullscreen apps, all Spaces, all monitors (R12, §2.3). Never key (R13).
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    weak var manager: OverlayManager?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        manager?.handleClick(at: point, in: self)
    }
}

/// One panel per NSScreen, shared by all active Alerts (§2.3). A CADisplayLink
/// synced to the display refresh drives every Alert; nothing runs while no
/// Alert is active (R25, R26).
final class OverlayManager: NSObject {
    // Layout constants (§2.4).
    private static let dogSize: CGFloat = 96        // 48 px sprite at 2×
    private static let bannerGap: CGFloat = 12
    private static let bannerHeight: CGFloat = 72   // 24 art px at 3× (sign asset)
    private static let bannerPadding: CGFloat = 22  // sign frame (18) + breathing room
    private static let joinSize = CGSize(width: 78, height: 42)  // 26×14 art px at 3×
    private static let signSliceInset: CGFloat = 18 // 6 art px at 3×
    private static let joinSliceInset: CGFloat = 15 // 5 art px at 3×
    private static let edgeMargin: CGFloat = 8

    private struct DogLayerSet {
        let sprite: CALayer
        let rope: CAShapeLayer     // tow-rope from Dog to Banner
        let banner: CALayer?
        let countdown: CATextLayer?
        let bannerSize: CGSize
        let joinRect: CGRect?  // relative to banner origin
        var lastCountdownText: String = ""
        var bannerPos: CGPoint?  // per-screen chase state — the Banner trails the Dog
    }

    private struct HitRegion {
        let rect: CGRect
        weak var alert: AlertController?
        let isJoin: Bool
    }

    private final class ScreenContext {
        let panel: OverlayPanel
        let view: OverlayView
        let screenFrame: NSRect
        let scale: CGFloat
        var dogLayers: [UUID: DogLayerSet] = [:]
        var hitRegions: [HitRegion] = []

        init(panel: OverlayPanel, view: OverlayView, screenFrame: NSRect, scale: CGFloat) {
            self.panel = panel
            self.view = view
            self.screenFrame = screenFrame
            self.scale = scale
        }
    }

    private var contexts: [ScreenContext] = []
    private var alerts: [AlertController] = []
    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Display plugged/unplugged: rebuild panels; Alerts re-render (§2.3, edge table).
            guard let self, !self.alerts.isEmpty else { return }
            self.stopTicking()
            self.teardownPanels()
            self.buildPanels()
            self.startTicking()
        }
    }

    // MARK: - Alert attachment

    func attach(_ alert: AlertController) {
        alerts.append(alert)
        if contexts.isEmpty { buildPanels() }
        startTicking()
    }

    func detach(_ alert: AlertController) {
        alerts.removeAll { $0 === alert }
        for context in contexts {
            if let layerSet = context.dogLayers.removeValue(forKey: alert.dog.id) {
                layerSet.sprite.removeFromSuperlayer()
                layerSet.rope.removeFromSuperlayer()
                layerSet.banner?.removeFromSuperlayer()
            }
        }
        if alerts.isEmpty {
            stopTicking()
            teardownPanels()  // ordered out, not just hidden (R26)
        }
    }

    // MARK: - Panels

    private func buildPanels() {
        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true  // must precede `level` — it resets level to .floating
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true  // click-through by default (R13)
            panel.isReleasedWhenClosed = false
            // sharingType left at default: visible in screen shares (R17)

            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.manager = self
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()

            contexts.append(ScreenContext(
                panel: panel, view: view,
                screenFrame: screen.frame,
                scale: screen.backingScaleFactor
            ))
        }
    }

    private func teardownPanels() {
        for context in contexts {
            context.panel.orderOut(nil)
            context.panel.contentView = nil
        }
        contexts = []
    }

    // MARK: - Display tick (CADisplayLink — synced to the display refresh)

    private func startTicking() {
        guard displayLink == nil, let view = contexts.first?.view else { return }
        lastTickTime = CACurrentMediaTime()
        let link = view.displayLink(target: self, selector: #selector(displayTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayTick(_ link: CADisplayLink) {
        let now = Date()
        let mediaTime = CACurrentMediaTime()
        let dt = min(mediaTime - lastTickTime, 0.1)  // clamp after stalls
        lastTickTime = mediaTime

        // advance() may finish an Alert → detach mutates `alerts`; iterate a copy.
        for alert in Array(alerts) {
            alert.advance(by: dt, now: now)
        }
        guard !alerts.isEmpty else { return }
        render(dt: dt, now: now)
        updateClickThrough()
    }

    // MARK: - Rendering

    private func render(dt: TimeInterval, now: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for context in contexts {
            var regions: [HitRegion] = []
            for alert in alerts {
                renderAlert(alert, in: context, dt: dt, regions: &regions, now: now)
            }
            context.hitRegions = regions
        }
        CATransaction.commit()
    }

    /// One Dog per Alert bouncing in the lower-⅔ band; the Banner chases the
    /// Dog with a soft lag so it swings around smoothly on bounces (R14, §2.4).
    private func renderAlert(
        _ alert: AlertController, in context: ScreenContext,
        dt: TimeInterval, regions: inout [HitRegion], now: Date
    ) {
        var layerSet = ensureLayers(for: alert, in: context)
        let dogSize = Self.dogSize
        let screenSize = context.screenFrame.size
        let bannerSize = layerSet.bannerSize

        // Map the unit square to the Dog's roaming band (lower ⅔, §2.4).
        let minX = Self.edgeMargin + dogSize / 2
        let maxX = max(minX, screenSize.width - Self.edgeMargin - dogSize / 2)
        let minY = 24 + dogSize / 2
        let maxY = max(minY, screenSize.height * 2 / 3 - dogSize / 2)
        let dogCenter = CGPoint(
            x: minX + alert.position.x * (maxX - minX),
            y: minY + alert.position.y * (maxY - minY)
        )

        layerSet.sprite.position = dogCenter
        layerSet.sprite.contents = Assets.spriteFrames(for: alert.dog.variant)[safe: alert.dog.frameIndex]
        layerSet.sprite.setAffineTransform(
            alert.facing < 0 ? CGAffineTransform(scaleX: -1, y: 1) : .identity  // R14a
        )

        let dogRect = CGRect(
            x: dogCenter.x - dogSize / 2, y: dogCenter.y - dogSize / 2,
            width: dogSize, height: dogSize
        ).insetBy(dx: -8, dy: -8)
        regions.append(HitRegion(rect: dogRect, alert: alert, isJoin: false))

        if let banner = layerSet.banner {
            // Target: trailing the Dog opposite its facing, clamped on-screen.
            var targetX = dogCenter.x - alert.facing * (dogSize / 2 + Self.bannerGap + bannerSize.width / 2)
            targetX = min(
                max(targetX, Self.edgeMargin + bannerSize.width / 2),
                screenSize.width - Self.edgeMargin - bannerSize.width / 2
            )
            let target = CGPoint(x: targetX, y: dogCenter.y)
            var pos = layerSet.bannerPos ?? target
            let ease = CGFloat(min(1, dt * 3.0))
            pos.x += (target.x - pos.x) * ease
            pos.y += (target.y - pos.y) * ease
            layerSet.bannerPos = pos
            banner.position = pos

            // Tow-rope: sign edge → the Dog's harness, with a little sag.
            let hitchSign = CGPoint(
                x: pos.x + alert.facing * (bannerSize.width / 2 - 6),
                y: pos.y
            )
            let hitchDog = CGPoint(
                x: dogCenter.x - alert.facing * dogSize * 0.28,
                y: dogCenter.y - dogSize * 0.12
            )
            let slack = (hitchDog.x - hitchSign.x) * alert.facing
            if slack < 12 {
                layerSet.rope.isHidden = true  // Banner swinging past the Dog after a bounce
            } else {
                layerSet.rope.isHidden = false
                let ropePath = CGMutablePath()
                ropePath.move(to: hitchSign)
                ropePath.addQuadCurve(
                    to: hitchDog,
                    control: CGPoint(
                        x: (hitchSign.x + hitchDog.x) / 2,
                        y: min(hitchSign.y, hitchDog.y) - 10
                    )
                )
                layerSet.rope.path = ropePath
            }

            let bannerRect = CGRect(
                x: pos.x - bannerSize.width / 2,
                y: pos.y - bannerSize.height / 2,
                width: bannerSize.width, height: bannerSize.height
            )
            regions.append(HitRegion(rect: bannerRect, alert: alert, isJoin: false))
            if let joinRect = layerSet.joinRect {
                regions.append(HitRegion(
                    rect: joinRect.offsetBy(dx: bannerRect.minX, dy: bannerRect.minY),
                    alert: alert, isJoin: true
                ))
            }
            let text = alert.countdownText(now: now)
            if text != layerSet.lastCountdownText {
                layerSet.countdown?.string = text
                layerSet.lastCountdownText = text
            }
        }
        context.dogLayers[alert.dog.id] = layerSet
    }

    private func ensureLayers(
        for alert: AlertController, in context: ScreenContext
    ) -> DogLayerSet {
        if let existing = context.dogLayers[alert.dog.id] { return existing }
        guard let rootLayer = context.view.layer else {
            return DogLayerSet(sprite: CALayer(), rope: CAShapeLayer(), banner: nil,
                               countdown: nil, bannerSize: .zero, joinRect: nil)
        }

        let sprite = CALayer()
        sprite.bounds = CGRect(x: 0, y: 0, width: Self.dogSize, height: Self.dogSize)
        sprite.magnificationFilter = .nearest  // crisp pixels (§2.4)
        sprite.minificationFilter = .nearest

        let rope = CAShapeLayer()
        rope.strokeColor = NSColor(srgbRed: 0x3A / 255, green: 0x23 / 255,
                                   blue: 0x17 / 255, alpha: 1).cgColor
        rope.fillColor = nil
        rope.lineWidth = 3
        rope.lineCap = .round

        let (banner, countdown, size, joinRect) = makeBanner(for: alert, scale: context.scale)
        rootLayer.addSublayer(rope)    // rope under everything
        rootLayer.addSublayer(banner)
        rootLayer.addSublayer(sprite)  // Dog above its Banner
        let layerSet = DogLayerSet(sprite: sprite, rope: rope, banner: banner,
                                   countdown: countdown, bannerSize: size, joinRect: joinRect)
        context.dogLayers[alert.dog.id] = layerSet
        return layerSet
    }

    /// Image-backed layer that stretches only its center region, keeping the
    /// pixel-art border crisp at any size (CALayer contentsCenter 9-slice).
    private static func nineSliceLayer(image: CGImage, inset: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        layer.contentsCenter = CGRect(
            x: inset / w, y: inset / h,
            width: (w - 2 * inset) / w, height: (h - 2 * inset) / h
        )
        layer.contentsScale = 1  // art pixels are pre-scaled 3× in the asset
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        return layer
    }

    // MARK: - Banner (R14, R18, R24)

    private func makeBanner(
        for alert: AlertController, scale: CGFloat
    ) -> (CALayer, CATextLayer, CGSize, CGRect?) {
        let outline = NSColor(srgbRed: 0x3A / 255, green: 0x23 / 255, blue: 0x17 / 255, alpha: 1)
        let cream = NSColor(srgbRed: 0xF7 / 255, green: 0xE3 / 255, blue: 0xC0 / 255, alpha: 1)
        let alarmRed = NSColor(srgbRed: 0xD6 / 255, green: 0x45 / 255, blue: 0x3D / 255, alpha: 1)

        let title = alert.meeting.title.truncatedForBanner()
        let titleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)  // system font (R14a)
        let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let hasJoin = alert.meeting.joinURL != nil

        let titleWidth = (title as NSString)
            .size(withAttributes: [.font: titleFont]).width
        let countdownWidth = ("started 59m ago" as NSString)
            .size(withAttributes: [.font: countdownFont]).width
        let textWidth = ceil(max(titleWidth, countdownWidth))

        let pad = Self.bannerPadding
        let width = pad + textWidth + (hasJoin ? 14 + Self.joinSize.width : 0) + pad
        let size = CGSize(width: width, height: Self.bannerHeight)

        let banner = CALayer()
        banner.bounds = CGRect(origin: .zero, size: size)

        if let signImage = Assets.bannerSignImage() {
            // 9-slice pixel wood sign (assets/banner/created, R14).
            let sign = Self.nineSliceLayer(image: signImage, inset: Self.signSliceInset)
            sign.frame = banner.bounds
            banner.addSublayer(sign)
        } else {
            // Fallback if the asset is missing: flat cream plaque.
            banner.backgroundColor = cream.cgColor
            banner.borderColor = outline.cgColor
            banner.borderWidth = 2
            banner.cornerRadius = 12
        }

        // Soft drop shadow lifts the sign off busy backgrounds.
        banner.shadowColor = NSColor.black.cgColor
        banner.shadowOpacity = 0.30
        banner.shadowRadius = 5
        banner.shadowOffset = CGSize(width: 0, height: -4)
        banner.shadowPath = CGPath(
            roundedRect: banner.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil
        )

        let titleLayer = CATextLayer()
        titleLayer.string = title
        titleLayer.font = titleFont
        titleLayer.fontSize = 16
        titleLayer.foregroundColor = outline.cgColor
        titleLayer.truncationMode = .end
        titleLayer.contentsScale = scale
        titleLayer.frame = CGRect(x: pad, y: size.height - 15 - 22, width: textWidth, height: 22)
        banner.addSublayer(titleLayer)

        let countdownLayer = CATextLayer()
        countdownLayer.string = ""
        countdownLayer.font = countdownFont
        countdownLayer.fontSize = 14
        countdownLayer.foregroundColor = outline.withAlphaComponent(0.72).cgColor
        countdownLayer.contentsScale = scale
        countdownLayer.frame = CGRect(x: pad, y: 15, width: textWidth, height: 18)
        banner.addSublayer(countdownLayer)

        var joinRect: CGRect?
        if hasJoin {
            let rect = CGRect(
                x: size.width - pad - Self.joinSize.width,
                y: (size.height - Self.joinSize.height) / 2,
                width: Self.joinSize.width, height: Self.joinSize.height
            )
            let joinLayer: CALayer
            if let joinImage = Assets.joinButtonImage() {
                joinLayer = Self.nineSliceLayer(image: joinImage, inset: Self.joinSliceInset)
            } else {
                joinLayer = CALayer()
                joinLayer.backgroundColor = alarmRed.cgColor
                joinLayer.cornerRadius = 9
            }
            joinLayer.frame = rect

            let joinText = CATextLayer()
            joinText.string = "Join"
            joinText.font = NSFont.systemFont(ofSize: 15, weight: .bold)
            joinText.fontSize = 15
            joinText.foregroundColor = NSColor.white.cgColor
            joinText.alignmentMode = .center
            joinText.contentsScale = scale
            joinText.frame = CGRect(x: 0, y: 11, width: rect.width, height: 20)
            joinLayer.addSublayer(joinText)
            banner.addSublayer(joinLayer)
            joinRect = rect
        }
        return (banner, countdownLayer, size, joinRect)
    }

    // MARK: - Click-through and ack routing (R13, §2.3)

    /// Per-frame cursor check: with the Dog moving under a possibly stationary
    /// cursor, event-driven mouse-moved monitoring would miss transitions — the
    /// tick already runs at display rate while any Alert is active.
    private func updateClickThrough() {
        let mouse = NSEvent.mouseLocation
        for context in contexts {
            guard context.screenFrame.contains(mouse) else {
                context.panel.ignoresMouseEvents = true
                continue
            }
            let local = CGPoint(
                x: mouse.x - context.screenFrame.origin.x,
                y: mouse.y - context.screenFrame.origin.y
            )
            let overHit = context.hitRegions.contains { $0.rect.contains(local) }
            context.panel.ignoresMouseEvents = !overHit
        }
    }

    /// A click resolves to the owning Alert; that Alert alone is affected (R10).
    /// The Banner's Join button joins directly; any other Dog/Banner click opens
    /// the meeting details and actions (R7).
    func handleClick(at point: CGPoint, in view: OverlayView) {
        guard let context = contexts.first(where: { $0.view === view }) else { return }
        for region in context.hitRegions.reversed()
        where region.isJoin && region.rect.contains(point) {
            region.alert?.acknowledge(join: true)
            return
        }
        for region in context.hitRegions.reversed() where region.rect.contains(point) {
            if let alert = region.alert {
                showActionMenu(for: alert, at: point, in: context)
            }
            return
        }
    }

    private func showActionMenu(
        for alert: AlertController, at point: CGPoint, in context: ScreenContext
    ) {
        alert.setMovementHeld(true)
        defer { alert.setMovementHeld(false) }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let details = MeetingDetailsMenuView(
            meeting: alert.meeting,
            onDismiss: { [weak alert] in
                alert?.acknowledge(join: false)
            },
            onJoin: alert.meeting.joinURL == nil ? nil : { [weak alert] in
                alert?.acknowledge(join: true)
            }
        )
        let detailsItem = NSMenuItem()
        detailsItem.view = details
        menu.addItem(detailsItem)

        // Menus draw at pop-up level (~101), below the overlay (1000): drop the
        // panel beneath the menu while it tracks so the menu stays readable.
        let savedLevel = context.panel.level
        context.panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        menu.popUp(positioning: nil, at: point, in: context.view)
        context.panel.level = savedLevel
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension String {
    /// R18: long Meeting titles truncate with an ellipsis at ~40 characters.
    func truncatedForBanner(limit: Int = 40) -> String {
        count <= limit ? self : String(prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
