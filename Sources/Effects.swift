import SwiftUI

struct FlameAura: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            .init(x: 0.14, y: 0.94), .init(x: 0.03, y: 0.63), .init(x: 0.20, y: 0.71),
            .init(x: 0.12, y: 0.32), .init(x: 0.32, y: 0.49), .init(x: 0.33, y: 0.10),
            .init(x: 0.46, y: 0.28), .init(x: 0.56, y: 0.00), .init(x: 0.65, y: 0.35),
            .init(x: 0.82, y: 0.17), .init(x: 0.79, y: 0.54), .init(x: 0.98, y: 0.39),
            .init(x: 0.88, y: 0.76), .init(x: 0.98, y: 0.71), .init(x: 0.84, y: 0.96)
        ]
        return Path { path in
            for (index, point) in points.enumerated() {
                let point = CGPoint(x: point.x * rect.width, y: point.y * rect.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

struct PowerAura: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.buddyMotionEnabled) private var isVisible
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !isVisible)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                FlameAura().fill(LinearGradient(colors: [Color.orange.opacity(0.1), Color.yellow.opacity(0.8), Color.orange.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 1 + sin(time * 5) * 0.035, y: 1 + cos(time * 4) * 0.04, anchor: .bottom)
                    .shadow(color: Color.orange.opacity(0.3), radius: 7)
                FlameAura().fill(Color(red: 1, green: 0.91, blue: 0.43).opacity(0.65)).padding(8)
                Canvas { context, size in
                    for side in 0..<2 {
                        let x = side == 0 ? size.width * 0.12 : size.width * 0.88
                        let jitter = reduceMotion ? 0 : sin(time * 8 + Double(side) * 2) * 3
                        var bolt = Path()
                        bolt.move(to: CGPoint(x: x, y: size.height * 0.25))
                        bolt.addLine(to: CGPoint(x: x - 4 + jitter, y: size.height * 0.46))
                        bolt.addLine(to: CGPoint(x: x + 5, y: size.height * 0.43))
                        bolt.addLine(to: CGPoint(x: x - 2, y: size.height * 0.76))
                        context.stroke(bolt, with: .color(Color(red: 0.48, green: 0.63, blue: 0.96).opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                    if !reduceMotion {
                        for index in 0..<6 {
                            let phase = (time / 1.6 + Double(index) / 6).truncatingRemainder(dividingBy: 1)
                            let x = size.width * (0.12 + Double(index % 3) * 0.36)
                            let y = size.height * (1 - phase)
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 4)), with: .color(.orange.opacity(sin(phase * .pi) * 0.8)))
                        }
                    }
                }
            }.frame(width: 74, height: 80).offset(y: -7)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct RomanticBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.13), Color(red: 0.18, green: 0.09, blue: 0.20), Color(red: 0.10, green: 0.10, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                GeometryReader { geometry in
                    RadialGradient(colors: [Color(red: 0.60, green: 0.20, blue: 0.40).opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.75)
                    RadialGradient(colors: [Color(red: 0.34, green: 0.28, blue: 0.68).opacity(0.25), .clear], center: .bottomLeading, startRadius: 0, endRadius: geometry.size.width * 0.65)
                }
            }
            .overlay {
                Canvas { context, size in
                    for index in 0..<38 {
                        let x = Double((index * 73 + 11) % 101) / 101 * size.width
                        let y = Double((index * 37 + 5) % 97) / 97 * size.height
                        let radius = index % 5 == 0 ? 1.6 : 0.8
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(Color(red: 1, green: 0.85, blue: 0.95).opacity(index % 3 == 0 ? 0.75 : 0.35)))
                    }
                }
            }
    }
}

struct FireworkShow: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.buddyMotionEnabled) private var isVisible
    private let colors: [Color] = [Color(red: 1, green: 0.67, blue: 0.82), Color(red: 0.80, green: 0.68, blue: 1), Color(red: 1, green: 0.82, blue: 0.5), Color(red: 0.6, green: 0.83, blue: 1)]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isVisible)) { timeline in
            Canvas { context, size in
                let elapsed = reduceMotion ? 1.0 : timeline.date.timeIntervalSince(startedAt)
                guard elapsed >= 0, elapsed < 12 else { return }
                for burst in 0..<10 {
                    let age = elapsed - Double(burst) * 0.8
                    guard age >= 0, age < 2.1 else { continue }
                    let center = CGPoint(x: size.width * (0.15 + Double((burst * 3) % 8) / 11), y: size.height * (0.16 + Double((burst * 5) % 6) / 14))
                    let progress = min(1, age / 1.8)
                    let radius = min(size.width, size.height) * 0.23 * (1 - pow(1 - progress, 2))
                    let opacity = max(0, 1 - progress)
                    for particle in 0..<28 {
                        let angle = Double(particle) / 28 * .pi * 2
                        let distance = radius * (particle % 2 == 0 ? 1 : 0.72)
                        let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance + progress * progress * 20)
                        let previous = CGPoint(x: center.x + cos(angle) * distance * 0.78, y: center.y + sin(angle) * distance * 0.78 + progress * progress * 16)
                        var trail = Path(); trail.move(to: previous); trail.addLine(to: point)
                        let color = colors[burst % colors.count].opacity(opacity)
                        context.stroke(trail, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)), with: .color(color))
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Night colors are kept together so text, cards, and controls change as one scene.
enum NightPalette {
    static let ink = Color(red: 1, green: 0.95, blue: 0.99)
    static let muted = Color(red: 0.83, green: 0.74, blue: 0.85)
    static let rose = Color(red: 1, green: 0.70, blue: 0.83)
    static let surface = Color(red: 0.17, green: 0.12, blue: 0.23)
    static let line = Color(red: 0.39, green: 0.28, blue: 0.40)
}

struct OffDutyInlineMessage: View {
    let preview: Bool
    let replay: () -> Void
    let endPreview: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("属于你的夜晚", systemImage: "moon.stars").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(preview ? "彩蛋预览" : "今日已收工")
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(NightPalette.rose.opacity(0.12), in: Capsule())
            }.foregroundStyle(NightPalette.rose)
            Text("下班啦，今天也很棒！").font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(NightPalette.ink).lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 12) {
                Button(action: replay) {
                    Label("再放一次烟花", systemImage: "sparkles")
                }.buttonStyle(.plain).foregroundStyle(NightPalette.rose)
                if preview {
                    Button("结束预览", action: endPreview).buttonStyle(.plain).foregroundStyle(NightPalette.muted)
                }
            }.font(.system(size: 11, weight: .medium)).frame(height: 28)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(NightPalette.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(NightPalette.line, lineWidth: 1))
    }
}
