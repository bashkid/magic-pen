import AppKit

/// One toolbar cell: an icon button that highlights blue when its tool/panel
/// is active, matching the extension's `.cell[data-on='true']` styling.
final class CellButton: NSView {
    let id: String
    private let imageView = NSImageView()
    private let badge = NSView()
    private let topDivider = NSView()
    var onClick: (() -> Void)?
    var isOn: Bool = false { didSet { needsDisplay = true } }
    var badgeColor: NSColor? { didSet { badge.isHidden = badgeColor == nil; badge.layer?.backgroundColor = badgeColor?.cgColor } }
    /// Hidden on the first cell in the stack - mirrors the extension's
    /// `.cell + .cell { border-top }` hairline (no gap between rows, a 1px
    /// divider instead), which is what gives each row a visible boundary.
    var showsTopDivider: Bool = true { didSet { topDivider.isHidden = !showsTopDivider } }

    init(id: String, image: NSImage?, tooltip: String) {
        self.id = id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        toolTip = tooltip

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        NSLayoutConstraint.activate([
            // CellButton is a plain NSView (no intrinsic content size), so
            // inside a vertical NSStackView it needs an explicit width or its
            // size is undefined - this was collapsing/misaligning the icons.
            // 40pt matches the extension's compact 44px CSS strip width
            // (minus its 1px border) rather than the earlier, wider 44+8
            // margin the panel had.
            widthAnchor.constraint(equalToConstant: 40),
            heightAnchor.constraint(equalToConstant: 34),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            topDivider.heightAnchor.constraint(equalToConstant: 1),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badge.widthAnchor.constraint(equalToConstant: 8),
            badge.heightAnchor.constraint(equalToConstant: 8)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleClick() { onClick?() }

    override func updateLayer() {
        layer?.backgroundColor = isOn ? NSColor(hex: "#29abe2").cgColor : NSColor.clear.cgColor
    }

    override func draw(_ dirtyRect: NSRect) { updateLayer() }

    override func mouseEntered(with event: NSEvent) {
        if !isOn { layer?.backgroundColor = NSColor(white: 0, alpha: 0.05).cgColor }
    }
    override func mouseExited(with event: NSEvent) { updateLayer() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
}
