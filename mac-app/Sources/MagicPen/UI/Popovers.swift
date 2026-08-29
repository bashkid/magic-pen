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

/// Lets the user set a countdown, in minutes, that then runs as a small
/// on-screen pill (CountdownTimerManager) - the Timer cell's flyout. A fresh
/// instance is built each time the cell is clicked (same pattern as the
/// other popovers), so it just reads CountdownTimerManager.shared.isRunning
/// once, at open time, to pick its layout.
final class TimerViewController: NSViewController {
    private let onDone: () -> Void
    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let running = CountdownTimerManager.shared.isRunning

        if running {
            let status = NSTextField(labelWithString: "Timer running")
            status.font = .systemFont(ofSize: 11)
            let stopButton = NSButton(title: "Stop Timer", target: nil, action: nil)
            stopButton.bezelStyle = .rounded
            stopButton.target = ClosureTarget.attach({ [weak self] in
                CountdownTimerManager.shared.stop()
                self?.onDone()
            }, to: nil)
            stopButton.action = #selector(ClosureTarget.fire)

            let stack = NSStackView(views: [status, stopButton])
            stack.orientation = .vertical
            stack.spacing = 8
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            view = stack
            return
        }

        let label = NSTextField(labelWithString: "Minutes")
        label.font = .systemFont(ofSize: 10)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0.1
        formatter.maximum = 240
        formatter.maximumFractionDigits = 1

        let field = NSTextField(string: "5")
        field.formatter = formatter
        field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let inputRow = NSStackView(views: [label, field])
        inputRow.orientation = .horizontal
        inputRow.spacing = 6

        let startButton = NSButton(title: "Start Timer", target: nil, action: nil)
        startButton.bezelStyle = .rounded
        startButton.target = ClosureTarget.attach({ [weak self, weak field] in
            let minutes = field?.doubleValue ?? 5
            CountdownTimerManager.shared.start(minutes: max(0.1, minutes))
            self?.onDone()
        }, to: nil)
        startButton.action = #selector(ClosureTarget.fire)

        let stack = NSStackView(views: [inputRow, startButton])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view = stack
    }
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
