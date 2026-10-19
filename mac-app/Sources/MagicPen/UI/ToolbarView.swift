import AppKit

/// A plain NSImageView with mouseDown/mouseDragged/mouseUp handled directly
/// instead of via NSPanGestureRecognizer - deterministic click-vs-drag
/// detection off real screen-point deltas, no gesture-recognizer state
/// machine involved (that was the suspected cause of the logo sometimes not
/// re-expanding on a second click - hard to prove blind, so removed
/// entirely rather than patched).
private final class DraggableLogoView: NSImageView {
    var onMouseDown: (() -> Void)?
    var onMouseDragged: ((CGFloat, CGFloat) -> Void)?
    var onMouseUp: ((_ didDrag: Bool) -> Void)?

    private var startScreenPoint: CGPoint = .zero
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        dragged = false
        startScreenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        onMouseDown?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let p = window.convertPoint(toScreen: event.locationInWindow)
        let dx = p.x - startScreenPoint.x
        let dy = p.y - startScreenPoint.y
        if !dragged && (abs(dx) > 3 || abs(dy) > 3) { dragged = true }
        onMouseDragged?(dx, dy)
    }
    override func mouseUp(with event: NSEvent) {
        onMouseUp?(dragged)
    }
}

final class ToolbarView: NSView {
    private let state = AnnotatorState.shared
    private let logo = DraggableLogoView()
    private let cellStack = NSStackView()
    private var cells: [CellButton] = []
    private var collapsed = false
    private var panelOrigin: CGPoint = .zero
    private let colorWell = NSColorWell()
    private let stripBackground = NSView()
    // A plain NSView with explicit constraints, not an NSStackView: nested
    // stacks (vertical quad of horizontal rows) need every level's alignment
    // set just right to stretch arranged subviews to fill, and getting that
    // wrong silently collapses the swatches to invisible slivers instead of
    // erroring - explicit constraints make the intended layout unambiguous.
    private let colorQuad = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildLogo()
        buildCells()      // must exist first so buildStripBackground() can anchor to it
        buildColorRow()   // ditto (colorWell)
        buildStripBackground()
        NotificationCenter.default.addObserver(self, selector: #selector(sync),
                                                name: .annotatorStateChanged, object: nil)
        sync()
    }
    required init?(coder: NSCoder) { fatalError() }

    // The white rounded panel behind the cells/colour row - the extension's
    // `.strip` background. Without this the toolbar was just bare floating
    // buttons over the desktop with no panel chrome. Inserted behind
    // cellStack in one step so its constraints (which reference cellStack
    // and colorWell) stay attached - removing+re-adding a view deactivates
    // any constraints tied to its old superview.
    private func buildStripBackground() {
        stripBackground.wantsLayer = true
        stripBackground.translatesAutoresizingMaskIntoConstraints = false
        stripBackground.layer?.backgroundColor = NSColor.white.cgColor
        stripBackground.layer?.cornerRadius = 10
        stripBackground.layer?.borderWidth = 1
        stripBackground.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        addSubview(stripBackground, positioned: .below, relativeTo: cellStack)
        NSLayoutConstraint.activate([
            stripBackground.topAnchor.constraint(equalTo: cellStack.topAnchor, constant: -4),
            stripBackground.bottomAnchor.constraint(equalTo: colorWell.bottomAnchor, constant: 6),
            stripBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripBackground.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    // ------------------------------------------------------------------ logo
    private func buildLogo() {
        logo.image = Icons.logo
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.wantsLayer = true
        logo.layer?.cornerRadius = 19
        logo.layer?.masksToBounds = true
        // Match the extension's dark-backed Magic Pen brand mark.
        logo.layer?.backgroundColor = NSColor(calibratedRed: 16/255, green: 20/255, blue: 39/255, alpha: 1).cgColor
        addSubview(logo)
        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            logo.centerXAnchor.constraint(equalTo: centerXAnchor),
            logo.widthAnchor.constraint(equalToConstant: 38),
            logo.heightAnchor.constraint(equalToConstant: 38)
        ])

        logo.onMouseDown = { [weak self] in
            guard let panel = self?.window else { return }
            self?.panelOrigin = panel.frame.origin
            // hasShadow=true makes the window server recompute the drop
            // shadow on every single setFrameOrigin call during the drag -
            // that's what made dragging feel laggy. Drop it for the
            // duration and restore once the move settles.
            panel.hasShadow = false
        }
        logo.onMouseDragged = { [weak self] dx, dy in
            guard let self, let panel = self.window else { return }
            panel.setFrameOrigin(CGPoint(x: self.panelOrigin.x + dx, y: self.panelOrigin.y + dy))
        }
        logo.onMouseUp = { [weak self] didDrag in
            guard let self else { return }
            self.window?.hasShadow = true
            if !didDrag { self.toggleCollapse() }
        }
    }

    // ----------------------------------------------------------------- cells
    private struct CellSpec { let id: String; let image: NSImage?; let tooltip: String; var iconSize: CGFloat = 20 }
    // pointer/eye/pen read noticeably smaller than the other cells at the
    // default 20pt - arrow.png and eye.png carry a lot of built-in padding
    // around their glyph, and pencil.tip is a thin SF Symbol - so those three
    // get a larger box to compensate.
    private let specs: [CellSpec] = [
        CellSpec(id: "pointer", image: Icons.arrow, tooltip: "Pointer — click through to the screen", iconSize: 26),
        CellSpec(id: "eye", image: Icons.eye, tooltip: "Show / hide all annotations", iconSize: 26),
        CellSpec(id: "highlighter", image: Icons.symbol("highlighter"), tooltip: "Highlighter"),
        CellSpec(id: "shapes", image: Icons.symbol("square.on.circle"), tooltip: "Shapes, text and laser"),
        CellSpec(id: "eraser", image: Icons.symbol("eraser"), tooltip: "Eraser"),
        CellSpec(id: "pen", image: Icons.symbol("pencil.tip"), tooltip: "Pen", iconSize: 26),
        CellSpec(id: "size", image: Icons.symbol("circle.fill"), tooltip: "Stroke size and opacity"),
        CellSpec(id: "undo", image: Icons.symbol("arrow.uturn.backward"), tooltip: "Undo — ⌘Z / redo ⇧⌘Z"),
        CellSpec(id: "clear", image: Icons.symbol("trash"), tooltip: "Clear all"),
        CellSpec(id: "board", image: Icons.symbol("rectangle.on.rectangle"), tooltip: "Record, save, restore"),
        CellSpec(id: "timer", image: Icons.symbol("timer"), tooltip: "On-screen countdown timer"),
        CellSpec(id: "camera", image: Icons.symbol("camera"), tooltip: "Screenshot"),
        CellSpec(id: "copy", image: Icons.symbol("doc.on.clipboard"), tooltip: "Copy full-screen screenshot")
    ]

    private func buildCells() {
        cellStack.orientation = .vertical
        cellStack.spacing = 0 // rows touch; each cell draws its own top hairline instead
        cellStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cellStack)
        // Each CellButton now carries its own fixed width, so the stack just
        // needs to be centered - pinning leading AND trailing AND a fixed
        // width all at once was an over-constraint that made Auto Layout
        // silently break one of them at runtime.
        NSLayoutConstraint.activate([
            cellStack.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 6),
            cellStack.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
        for (index, spec) in specs.enumerated() {
            let cell = CellButton(id: spec.id, image: spec.image, tooltip: spec.tooltip, iconSize: spec.iconSize)
            cell.showsTopDivider = index > 0
            cell.onClick = { [weak self] in self?.handleCell(spec.id, cell) }
            cellStack.addArrangedSubview(cell)
            cells.append(cell)
        }
    }

    private func buildColorRow() {
        let quad = colorQuad
        quad.translatesAutoresizingMaskIntoConstraints = false
        let colors = AnnotatorState.quickColors
        let gap: CGFloat = 2
        let rowHeight: CGFloat = 16
        var swatches: [NSButton] = []
        for color in colors {
            let swatch = NSButton(title: "", target: nil, action: nil)
            swatch.bezelStyle = .regularSquare
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.target = ClosureTarget.attach({ [weak self] in self?.state.setColor(color) }, to: nil)
            swatch.action = #selector(ClosureTarget.fire)
            quad.addSubview(swatch)
            swatches.append(swatch)
        }
        // 2x2 grid via explicit constraints (each column pinned to the quad's
        // leading/trailing/center, each row stacked top to bottom) rather than
        // a nested NSStackView, whose alignment defaults left the rows
        // shrunk to their buttons' intrinsic near-zero width.
        for (index, swatch) in swatches.enumerated() {
            let col = index % 2
            let row = index / 2
            if col == 0 {
                swatch.leadingAnchor.constraint(equalTo: quad.leadingAnchor).isActive = true
                swatch.trailingAnchor.constraint(equalTo: quad.centerXAnchor, constant: -gap / 2).isActive = true
            } else {
                swatch.leadingAnchor.constraint(equalTo: quad.centerXAnchor, constant: gap / 2).isActive = true
                swatch.trailingAnchor.constraint(equalTo: quad.trailingAnchor).isActive = true
            }
            swatch.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            if row == 0 {
                swatch.topAnchor.constraint(equalTo: quad.topAnchor).isActive = true
            } else {
                swatch.topAnchor.constraint(equalTo: swatches[index - 2].bottomAnchor, constant: gap).isActive = true
            }
        }
        if let lastLeft = swatches.indices.last(where: { $0 % 2 == 0 }).map({ swatches[$0] }) {
            quad.bottomAnchor.constraint(equalTo: lastLeft.bottomAnchor).isActive = true
        }

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged)

        addSubview(quad)
        addSubview(colorWell)
        // Flush to the panel edges (0 inset) - the extension's .quad/.cur
        // span their strip's full width with no side margin either; only
        // the cell icon itself has inner padding, not the row containers.
        NSLayoutConstraint.activate([
            quad.topAnchor.constraint(equalTo: cellStack.bottomAnchor, constant: 6),
            quad.leadingAnchor.constraint(equalTo: leadingAnchor),
            quad.trailingAnchor.constraint(equalTo: trailingAnchor),
            colorWell.topAnchor.constraint(equalTo: quad.bottomAnchor, constant: 4),
            colorWell.leadingAnchor.constraint(equalTo: leadingAnchor),
            colorWell.trailingAnchor.constraint(equalTo: trailingAnchor),
            colorWell.heightAnchor.constraint(equalToConstant: 22),
            colorWell.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    @objc private func colorWellChanged() { state.setColor(colorWell.color) }

    /// Same effect as clicking the logo without dragging - exposed so the
    /// ⌘T keyboard shortcut can reach it via AppController.
    func toggleCollapse() { collapsed.toggle(); sync() }

    // --------------------------------------------------------------- clicks
    private func handleCell(_ id: String, _ cell: CellButton) {
        switch id {
        case "pointer": state.selectTool(.pointer)
        case "eye": state.toggleAnnotationsVisible()
        case "eraser": state.selectTool(.eraser)
        case "clear": state.clearAll()
        case "copy": ScreenshotManager.shared.copyFullScreenToClipboard()
        case "undo": state.undo()

        case "highlighter":
            state.selectTool(.highlighter)
            showPopover(SliderViewController(tool: .highlighter), from: cell)
        case "pen":
            state.selectTool(.pen)
            showPopover(SliderViewController(tool: .pen), from: cell)
        case "size":
            showPopover(SliderViewController(tool: state.lastPaintTool), from: cell)

        case "shapes":
            let items: [IconListViewController.Item] = [
                ("Line", Icons.symbol("line.diagonal"), .line),
                ("Rectangle", Icons.symbol("rectangle"), .rect),
                ("Ellipse", Icons.symbol("oval"), .ellipse),
                ("Text", Icons.symbol("textformat"), .text),
                ("Laser", Icons.symbol("dot.radiowaves.left.and.right"), .laser)
            ].map { title, image, tool in
                IconListViewController.Item(title: title, image: image, isOn: state.currentTool == tool) {
                    self.state.selectTool(tool)
                }
            }
            showPopover(IconListViewController(items: items), from: cell)

        case "board":
            let items: [IconListViewController.Item] = [
                IconListViewController.Item(title: state.recording ? "Stop recording" : "Record screen",
                                             image: Icons.symbol("record.circle"), isOn: state.recording) {
                    RecordingManager.shared.toggle()
                    // Otherwise this flyout just sits open on screen - transient
                    // popovers only auto-dismiss on a click OUTSIDE themselves,
                    // not on a click on one of their own buttons - and gets
                    // baked into the recording that just started.
                    self.activePopover?.close()
                },
                IconListViewController.Item(title: "Save session", image: Icons.symbol("square.and.arrow.down"), isOn: false) {
                    SessionStore.shared.save()
                },
                IconListViewController.Item(title: "Restore session", image: Icons.symbol("square.and.arrow.up"), isOn: false) {
                    SessionStore.shared.restore()
                }
            ]
            showPopover(IconListViewController(items: items), from: cell)

        case "timer":
            showPopover(TimerViewController { [weak self] in self?.activePopover?.close() }, from: cell)

        case "camera":
            let items: [IconListViewController.Item] = [
                IconListViewController.Item(title: "Drag a region", image: Icons.symbol("crop"), isOn: false) {
                    ScreenshotManager.shared.captureRegion()
                },
                IconListViewController.Item(title: "Whole screen", image: Icons.symbol("rectangle.inset.filled"), isOn: false) {
                    ScreenshotManager.shared.captureFullScreen()
                },
                IconListViewController.Item(title: "Copy to clipboard", image: Icons.symbol("doc.on.clipboard"), isOn: false) {
                    ScreenshotManager.shared.copyFullScreenToClipboard()
                }
            ]
            showPopover(IconListViewController(items: items), from: cell)
        default: break
        }
    }

    private var activePopover: NSPopover?
    private func showPopover(_ vc: NSViewController, from cell: CellButton) {
        activePopover?.close()
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        // Popovers are separate windows and pick up system Dark Mode on
        // their own - pin them to light to match the always-light toolbar
        // panel, same reasoning as ToolbarPanel's appearance override.
        pop.appearance = NSAppearance(named: .aqua)
        pop.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxX)
        activePopover = pop
    }

    // -------------------------------------------------------------------- sync
    @objc private func sync() {
        for cell in cells {
            switch cell.id {
            case "pointer": cell.isOn = state.currentTool == .pointer
            case "highlighter": cell.isOn = state.currentTool == .highlighter
            case "pen": cell.isOn = state.currentTool == .pen
            case "eraser": cell.isOn = state.currentTool == .eraser
            case "shapes": cell.isOn = [.line, .rect, .ellipse, .text, .laser].contains(state.currentTool)
            case "eye": cell.isOn = !state.annotationsVisible
            case "board": cell.isOn = state.recording
            case "timer": cell.isOn = CountdownTimerManager.shared.isRunning
            default: cell.isOn = false
            }
        }
        colorWell.color = state.currentColor()
        // Collapsing must hide the whole strip - background, cells AND the
        // colour row - the same way the extension's `#strip.hidden` hides
        // its entire panel. Hiding only cellStack left the white background
        // panel and colour swatches still visible, which read as "menu not
        // actually closing".
        cellStack.isHidden = collapsed
        colorQuad.isHidden = collapsed
        colorWell.isHidden = collapsed
        stripBackground.isHidden = collapsed
        if collapsed { activePopover?.close() }
    }
}
