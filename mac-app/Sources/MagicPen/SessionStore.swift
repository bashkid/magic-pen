import AppKit

/// Save/restore all current strokes to a single JSON file. There's no
/// per-page URL to key on system-wide (unlike the extension's chrome.storage
/// entry per origin+path), so this is one flat "session" - matching the
/// board panel's Save/Restore buttons in spirit rather than literally.
final class SessionStore {
    static let shared = SessionStore()
    private init() {}

    private struct DTO: Codable {
        struct Point: Codable { let x: CGFloat; let y: CGFloat }
        let shape: String
        let colorHex: String
        let alpha: CGFloat
        let width: CGFloat
        let points: [Point]
        let pressures: [CGFloat]?
        let text: String
        let fontSize: CGFloat
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MagicPen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    func save() {
        let state = AnnotatorState.shared
        let dtos = state.strokesSnapshot().map { s -> DTO in
            DTO(shape: shapeString(s.shape), colorHex: s.color.hexString, alpha: s.alpha, width: s.width,
                points: s.points.map { DTO.Point(x: $0.x, y: $0.y) }, pressures: s.pressures,
                text: s.text, fontSize: s.fontSize)
        }
        guard let data = try? JSONEncoder().encode(dtos) else { return }
        try? data.write(to: fileURL)
    }

    func restore() {
        guard let data = try? Data(contentsOf: fileURL),
              let dtos = try? JSONDecoder().decode([DTO].self, from: data) else { return }
        let strokes = dtos.map { dto -> Stroke in
            Stroke(shape: shapeKind(dto.shape), color: NSColor(hex: dto.colorHex), width: dto.width, alpha: dto.alpha,
                   points: dto.points.map { CGPoint(x: $0.x, y: $0.y) }, pressures: dto.pressures ?? [],
                   text: dto.text, fontSize: dto.fontSize)
        }
        AnnotatorState.shared.replaceAll(with: strokes)
    }

    private func shapeString(_ s: ShapeKind) -> String {
        switch s { case .free: "free"; case .line: "line"; case .rect: "rect"; case .ellipse: "ellipse"; case .text: "text" }
    }
    private func shapeKind(_ s: String) -> ShapeKind {
        switch s { case "line": .line; case "rect": .rect; case "ellipse": .ellipse; case "text": .text; default: .free }
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(c.redComponent * 255), g = Int(c.greenComponent * 255), b = Int(c.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
