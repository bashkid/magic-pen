import AppKit

/// A vertical list of icon buttons inside a popover - used for Shapes, Board
/// and Camera flyouts. NSPopover repositions itself automatically when it
/// would run off-screen, so there's no manual "flip left" logic needed here
/// (unlike the browser version, which had to compute that by hand).
final class IconListViewController: NSViewController {
    struct Item { let title: String; let image: NSImage?; let isOn: Bool; let action: () -> Void }
    private let items: [Item]

    init(items: [Item]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        for item in items {
            let btn = NSButton(title: "", target: nil, action: nil)
            // .texturedRounded always draws its own bezel/pill background
            // with built-in internal padding around the image - that pill
            // shape is what read as "a margin around the icon". Borderless
            // matches CellButton's flat look on the main toolbar.
            btn.isBordered = false
            btn.image = item.image
            btn.imagePosition = .imageOnly
            btn.toolTip = item.title
            btn.widthAnchor.constraint(equalToConstant: 30).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            if item.isOn { btn.contentTintColor = NSColor(hex: "#29abe2") }
            btn.target = ClosureTarget.attach(item.action, to: btn)
            btn.action = #selector(ClosureTarget.fire)
            stack.addArrangedSubview(btn)
        }
        view = stack
    }
}

/// Weight + opacity sliders - used for Pen, Highlighter and Size flyouts.
final class SliderViewController: NSViewController {
    private let tool: ToolID
    init(tool: ToolID) {
        self.tool = tool
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let state = AnnotatorState.shared
        let cfg = state.tools[tool]!

        let weightLabel = NSTextField(labelWithString: "Weight")
        let weightSlider = NSSlider(value: Double(cfg.width), minValue: 1, maxValue: 40,
                                     target: ClosureTarget.attach({ [weak self] in self?.weightChanged() }, to: nil),
                                     action: #selector(ClosureTarget.fire))
        weightSlider.target = ClosureTarget.attach({ [weak self, weak weightSlider] in
            guard let self, let weightSlider else { return }
            state.setWidth(CGFloat(weightSlider.doubleValue), for: self.tool)
        }, to: nil)
        weightSlider.action = #selector(ClosureTarget.fire)

        let alphaLabel = NSTextField(labelWithString: "Opacity")
        let alphaSlider = NSSlider(value: Double(cfg.alpha) * 100, minValue: 5, maxValue: 100, target: nil, action: nil)
        alphaSlider.target = ClosureTarget.attach({ [weak self, weak alphaSlider] in
            guard let self, let alphaSlider else { return }
            state.setAlpha(CGFloat(alphaSlider.doubleValue) / 100, for: self.tool)
        }, to: nil)
        alphaSlider.action = #selector(ClosureTarget.fire)

        let grid = NSStackView(views: [
            row(weightLabel, weightSlider), row(alphaLabel, alphaSlider)
        ])
        grid.orientation = .vertical
        grid.spacing = 6
        grid.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view = grid
    }

    private func row(_ label: NSTextField, _ slider: NSSlider) -> NSView {
        label.font = .systemFont(ofSize: 10)
        label.widthAnchor.constraint(equalToConstant: 34).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let row = NSStackView(views: [label, slider])
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }
    private func weightChanged() {}
}

/// NSButton/NSSlider only take @objc selector actions - this glues a Swift
/// closure to one so popovers can stay declarative without a delegate per row.
final class ClosureTarget: NSObject {
    private let closure: () -> Void
    private static var retained: [ClosureTarget] = []
    private init(_ closure: @escaping () -> Void) { self.closure = closure }
    static func attach(_ closure: @escaping () -> Void, to _: AnyObject?) -> ClosureTarget {
        let t = ClosureTarget(closure)
        retained.append(t)
        return t
    }
    @objc func fire() { closure() }
}
