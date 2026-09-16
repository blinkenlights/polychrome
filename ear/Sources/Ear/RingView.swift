import AppKit
import EarKit
import SwiftUI

/// The ring from above, north up. Drag the listener to walk, drag the handle
/// on their nose (or scroll) to turn, double-click to go back to the platform.
struct RingView: View {
    let model: AppModel

    private enum DragMode: Equatable { case move, turn, ping(Int) }

    @State private var dragMode: DragMode?
    @State private var hovering = false
    @State private var scrollMonitor: Any?

    /// Panel outer width (8 × 19 cm plus frame) and the depth drawn on screen.
    private let panelWidth = 1.54
    private let panelDepth = 0.35
    private let handleDistance = 1.6

    var body: some View {
        GeometryReader { proxy in
            let projection = Projection(size: proxy.size, radius: model.layout.radius)

            Canvas { context, _ in
                drawGround(context, projection)
                drawSpeakers(context, projection)
                drawListener(context, projection)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .gesture(drag(projection))
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetListener() })
            .onContinuousHover { phase in
                if case .active = phase { hovering = true } else { hovering = false }
            }
        }
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
    }

    // MARK: Drawing

    private func drawGround(_ context: GraphicsContext, _ p: Projection) {
        let radius = model.layout.radius
        context.stroke(
            Path(ellipseIn: p.circle(radius: radius)),
            with: .color(.secondary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
        if let platform = model.layout.platformRadiusM {
            context.fill(Path(ellipseIn: p.circle(radius: platform)), with: .color(.secondary.opacity(0.12)))
        }
        let north = p.view(x: 0, y: radius + 2.0)
        context.draw(
            Text("N").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary),
            at: north
        )
    }

    private func drawSpeakers(_ context: GraphicsContext, _ p: Projection) {
        let radius = model.layout.radius

        for speaker in model.layout.speakers {
            let level = CGFloat(min(1, sqrt(model.levels[speaker.channel] ?? 0) * 1.4))
            let center = p.view(x: speaker.x, y: speaker.y)

            var panel = context
            panel.translateBy(x: center.x, y: center.y)
            panel.rotate(by: .degrees(speaker.bearing))
            let width = panelWidth * p.scale
            let depth = max(panelDepth * p.scale, 6)
            let rect = CGRect(x: -width / 2, y: -depth / 2, width: width, height: depth)
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            panel.fill(shape, with: .color(.gray.opacity(0.35)))
            panel.fill(shape, with: .color(.orange.opacity(level)))
            if model.pinging == speaker.channel {
                panel.stroke(shape, with: .color(.accentColor), lineWidth: 2)
            }

            let away = (radius + 1.0) / max(hypot(speaker.x, speaker.y), 0.001)
            let labelPoint = p.view(x: speaker.x * away, y: speaker.y * away)
            context.draw(
                Text("\(speaker.channel)").font(.system(size: 13, weight: .semibold, design: .monospaced)),
                at: labelPoint
            )
            context.draw(
                Text("P\(speaker.panel)").font(.system(size: 9)).foregroundStyle(.secondary),
                at: CGPoint(x: labelPoint.x, y: labelPoint.y + 13)
            )
        }
    }

    private func drawListener(_ context: GraphicsContext, _ p: Projection) {
        let listener = model.listener
        let body = p.view(listener.position)
        let heading = listener.heading * .pi / 180
        let bodyRadius = max(0.45 * p.scale, 9)

        // Field of view: a soft wedge, ±40° around the heading.
        var wedge = Path()
        wedge.move(to: body)
        wedge.addArc(
            center: body,
            radius: bodyRadius * 5,
            startAngle: .radians(heading - .pi / 2 - 0.7),
            endAngle: .radians(heading - .pi / 2 + 0.7),
            clockwise: false
        )
        wedge.closeSubpath()
        context.fill(wedge, with: .color(.accentColor.opacity(0.12)))

        let handle = handlePoint(p)
        var nose = Path()
        nose.move(to: body)
        nose.addLine(to: handle)
        context.stroke(nose, with: .color(.accentColor), lineWidth: 2)
        context.fill(Path(ellipseIn: CGRect(x: handle.x - 5, y: handle.y - 5, width: 10, height: 10)), with: .color(.accentColor))

        let circle = CGRect(x: body.x - bodyRadius, y: body.y - bodyRadius, width: bodyRadius * 2, height: bodyRadius * 2)
        context.fill(Path(ellipseIn: circle), with: .color(.accentColor))
        context.stroke(Path(ellipseIn: circle), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
    }

    private func handlePoint(_ p: Projection) -> CGPoint {
        let body = p.view(model.listener.position)
        let heading = model.listener.heading * .pi / 180
        let length = max(handleDistance * p.scale, 30)
        return CGPoint(x: body.x + sin(heading) * length, y: body.y - cos(heading) * length)
    }

    // MARK: Interaction

    private func drag(_ p: Projection) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    let handle = handlePoint(p)
                    if hypot(value.startLocation.x - handle.x, value.startLocation.y - handle.y) < 14 {
                        dragMode = .turn
                    } else if let channel = panel(at: value.startLocation, p) {
                        dragMode = .ping(channel)
                    } else {
                        dragMode = .move
                    }
                }
                switch dragMode {
                case .turn:
                    let body = p.view(model.listener.position)
                    let heading = Geometry.bearing(x: value.location.x - body.x, y: body.y - value.location.y)
                    model.listener.heading = NSEvent.modifierFlags.contains(.shift) ? (heading / 15).rounded() * 15 : heading
                case .move:
                    let limit = model.layout.radius + 2
                    var world = p.world(value.location)
                    let distance = hypot(world.x, world.y)
                    if distance > limit {
                        world.x *= limit / distance
                        world.y *= limit / distance
                    }
                    model.listener.position.x = world.x
                    model.listener.position.y = world.y
                case .ping, nil:
                    break
                }
            }
            .onEnded { value in
                // A tap on a panel sounds it; a drag off it was a change of mind.
                if case let .ping(channel) = dragMode, panel(at: value.location, p) == channel {
                    model.ping(channel: channel)
                }
                dragMode = nil
            }
    }

    /// The panel under a point, if the point is close enough to count as a tap.
    private func panel(at point: CGPoint, _ p: Projection) -> Int? {
        let reach = max(panelWidth * p.scale / 2, 14)
        return model.layout.speakers
            .map { ($0.channel, hypot(point.x - p.view(x: $0.x, y: $0.y).x, point.y - p.view(x: $0.x, y: $0.y).y)) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            let delta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
            let step = event.hasPreciseScrollingDeltas ? delta * 0.5 : delta * 5
            var heading = (model.listener.heading + step).truncatingRemainder(dividingBy: 360)
            if heading < 0 { heading += 360 }
            model.listener.heading = heading
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}

/// Meters in the world to points on screen and back, north up.
private struct Projection {
    let center: CGPoint
    let scale: Double

    init(size: CGSize, radius: Double) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        scale = min(size.width, size.height) / 2 / (radius + 3)
    }

    func view(x: Double, y: Double) -> CGPoint {
        CGPoint(x: center.x + x * scale, y: center.y - y * scale)
    }

    func view(_ point: WorldPoint) -> CGPoint {
        view(x: point.x, y: point.y)
    }

    func world(_ point: CGPoint) -> (x: Double, y: Double) {
        ((point.x - center.x) / scale, (center.y - point.y) / scale)
    }

    func circle(radius: Double) -> CGRect {
        CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * 2 * scale, height: radius * 2 * scale)
    }
}
