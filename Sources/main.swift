import AppKit
import SwiftUI
typealias ViewState<Value> = SwiftUI.State<Value>

struct WorkState {
    let start: Date
    let end: Date
    let now: Date
    var fraction: Double { min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start))) }
    var remaining: Int { max(0, Int(end.timeIntervalSince(now))) }
    static func make(now: Date, startMinutes: Int, endMinutes: Int) -> WorkState {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        var start = calendar.date(byAdding: .minute, value: startMinutes, to: midnight)!
        var end = calendar.date(byAdding: .minute, value: endMinutes, to: midnight)!
        if endMinutes <= startMinutes {
            if now < end { start = calendar.date(byAdding: .day, value: -1, to: start)! }
            else { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        }
        return WorkState(start: start, end: end, now: now)
    }
}

// Shared light palette for this intentionally light, floating desktop widget.
private enum Palette {
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.19)
    static let muted = Color(red: 0.39, green: 0.43, blue: 0.40)
    static let sage = Color(red: 0.24, green: 0.43, blue: 0.33)
    static let sageLight = Color(red: 0.91, green: 0.95, blue: 0.91)
    static let track = Color(red: 0.81, green: 0.87, blue: 0.81)
    static let canvas = Color(red: 0.995, green: 0.995, blue: 0.98)
    static let cream = Color(red: 0.965, green: 0.955, blue: 0.92)
    static let amber = Color(red: 0.63, green: 0.36, blue: 0.12)
    static let line = Color(red: 0.87, green: 0.89, blue: 0.85)
    static let error = Color(red: 0.72, green: 0.19, blue: 0.17)
}

private struct QuietButtonStyle: ButtonStyle {
    @ViewState<Bool> private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered ? Palette.ink : Palette.muted)
            .background(configuration.isPressed ? Palette.track : hovered ? Palette.sageLight : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
    }
}

struct Encourager: View {
    @AppStorage("dailyPay") private var dailyPay = 500.0
    @AppStorage("startMinutes") private var startMinutes = 540
    @AppStorage("endMinutes") private var endMinutes = 1080
    @AppStorage("widgetScale") private var widgetScale = 1.0
    @AppStorage("compactMode") private var compactMode = false
    @ViewState<Bool> private var settings = false
    @ViewState<Int> private var quote = 0
    @ViewState<Bool> private var cheered = false
    @ViewState<String> private var draftPay = "500"
    @ViewState<Int> private var draftStart = 540
    @ViewState<Int> private var draftEnd = 1080
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let quotes = ["慢慢来，你已经在向前了。", "认真生活的你，值得每一份回报。", "今天的努力，都在为自由攒底气。", "不必时刻满分，尽力就很了不起。", "工作只是生活的一部分，别忘了自己。", "再小的一步，也是在靠近下班。"]
    private var validPay: Double? {
        guard let value = Double(draftPay), value.isFinite, value >= 0, value <= 10000000 else { return nil }
        return value
    }
    private var shiftMinutes: Int { (draftEnd - draftStart + 1440) % 1440 }
    private func openSettings() {
        draftPay = String(format: "%g", dailyPay)
        draftStart = startMinutes
        draftEnd = endMinutes
        compactMode = false
        settings = true
    }
    private func saveSettings() {
        guard let pay = validPay, shiftMinutes > 0 else { return }
        dailyPay = pay
        startMinutes = draftStart
        endMinutes = draftEnd
        settings = false
    }
    private func cheer() {
        quote = (quote + 1) % quotes.count
        guard !cheered else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5)) { cheered = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { cheered = false }
        }
    }

    private var displayScale: Double { min(1.4, max(0.8, widgetScale)) }
    private var contentWidth: CGFloat { compactMode ? 404 : 640 }
    private var contentHeight: CGFloat { compactMode ? 104 : 372 }

    var body: some View {
        Group {
            if compactMode { compactView } else { fullView }
        }
        .frame(width: contentWidth, height: contentHeight)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: contentWidth * displayScale, height: contentHeight * displayScale, alignment: .topLeading)
        .padding(10)
        .environment(\.colorScheme, .light)
        .tint(Palette.sage)
        .onChange(of: compactMode) { _, _ in updateWindowSize() }
        .onChange(of: widgetScale) { _, _ in updateWindowSize() }
    }

    private func updateWindowSize() {
        (NSApp.delegate as? AppDelegate)?.resizePanel(compact: compactMode, scale: displayScale)
    }

    private var fullView: some View {
        VStack(spacing: 14) {
            toolbar
            if settings { settingsView } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let work = WorkState.make(now: context.date, startMinutes: startMinutes, endMinutes: endMinutes)
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            earnings(work)
                            countdown(work)
                        }.frame(height: 136)
                        companion(work)
                    }
                }
                encouragement
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 640, height: 372, alignment: .top)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false))
        .foregroundStyle(Palette.ink)
        .tint(Palette.sage)
        .environment(\.colorScheme, .light)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.amber)
                .frame(width: 32, height: 32).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(settings ? "偏好设置" : "上班鼓励器").font(.system(size: 13, weight: .semibold))
            if !settings {
                Text("让努力，慢慢有回响").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            WindowDragArea().frame(maxWidth: .infinity, minHeight: 32).help("拖动这里移动窗口")
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                sizeMenu
                Button { settings = false; compactMode = true } label: {
                    Image(systemName: "rectangle.compress.vertical").frame(width: 32, height: 32).contentShape(Rectangle())
                }.accessibilityLabel("切换紧凑模式").help("紧凑模式 · 只看金额和倒数")
                Button { if settings { settings = false } else { openSettings() } } label: {
                    Image(systemName: settings ? "arrow.left" : "slider.horizontal.3").frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .accessibilityLabel(settings ? "返回，放弃未保存的设置" : "打开偏好设置")
                .help(settings ? "返回 · 放弃未保存的修改" : "设置日薪与上下班时间（⌘,）")
                .keyboardShortcut(",", modifiers: .command)
                Button { (NSApp.delegate as? AppDelegate)?.panel.orderOut(nil) } label: {
                    Image(systemName: "minus").frame(width: 32, height: 32).contentShape(Rectangle())
                }.accessibilityLabel("收起到菜单栏").help("收起到菜单栏 · 点击太阳图标可找回")
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle())
                }.accessibilityLabel("退出上班鼓励器").help("关闭并退出")
            }.font(.system(size: 12, weight: .medium)).buttonStyle(QuietButtonStyle())
        }.frame(height: 32)
    }

    private var sizeMenu: some View {
        Menu {
            Text("界面大小")
            scaleOptions
        } label: {
            Image(systemName: "textformat.size").frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("调整界面大小，当前 \(Int(displayScale * 100))%")
        .help("界面大小 · 当前 \(Int(displayScale * 100))%")
    }

    private var scaleOptions: some View {
        ForEach([0.8, 1.0, 1.2, 1.4], id: \.self) { scale in
            Button {
                widgetScale = scale
            } label: {
                if abs(displayScale - scale) < 0.01 {
                    Label(scaleTitle(scale), systemImage: "checkmark")
                } else { Text(scaleTitle(scale)) }
            }
        }
    }

    private func scaleTitle(_ scale: Double) -> String {
        let name = scale == 0.8 ? "小" : scale == 1 ? "标准" : scale == 1.2 ? "大" : "特大"
        return "\(name) · \(Int(scale * 100))%"
    }

    private var compactView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let work = WorkState.make(now: context.date, startMinutes: startMinutes, endMinutes: endMinutes)
            HStack(spacing: 10) {
                Button(action: cheer) {
                    SproutBuddy(growth: work.fraction, happy: cheered)
                        .scaleEffect(0.78).frame(width: 44, height: 56)
                }.buttonStyle(.plain).accessibilityLabel("摸摸小薪芽，换一句鼓励").help(quotes[quote])
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日已赚").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("¥" + (dailyPay * work.fraction).formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 25, weight: .medium, design: .rounded)).tracking(-0.5)
                        .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                }.frame(width: 118, alignment: .leading)
                    .accessibilityElement(children: .combine)
                Rectangle().fill(Palette.line).frame(width: 1, height: 38).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(work.now < work.start ? "上班前，好好充电" : work.fraction >= 1 ? "下班快乐" : "距下班 \(work.remaining / 3600) 小时 \((work.remaining % 3600) / 60) 分")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.track)
                            Capsule().fill(Palette.sage).frame(width: geo.size.width * work.fraction)
                        }
                    }.frame(height: 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("班次进度").accessibilityValue("\(Int(work.fraction * 100))%")
                    Text("\(Int(work.fraction * 100))% 完成 · \(timeString(endMinutes))\(endMinutes < startMinutes ? " 次日" : "") 下班")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).monospacedDigit().lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 2) {
                    Button { compactMode = false } label: {
                        Image(systemName: "rectangle.expand.vertical").frame(width: 32, height: 32).contentShape(Rectangle())
                    }.buttonStyle(QuietButtonStyle()).accessibilityLabel("展开完整模式").help("展开完整模式")
                    Menu {
                        Button("展开完整模式") { compactMode = false }
                        Button("偏好设置", action: openSettings)
                        Menu("界面大小") { scaleOptions }
                        Divider()
                        Button("收起到菜单栏") { (NSApp.delegate as? AppDelegate)?.panel.orderOut(nil) }
                        Button("退出上班鼓励器") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("更多选项").help("设置、大小与退出")
                }.font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 16).frame(width: 404, height: 104)
            .foregroundStyle(Palette.ink)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false))
            .overlay(alignment: .top) { WindowDragArea().frame(height: 14).padding(.horizontal, 24).help("拖动这里移动窗口").accessibilityHidden(true) }
        }
    }

    private func earnings(_ work: WorkState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日已赚").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(.system(size: 23, weight: .regular)).foregroundStyle(Palette.sage)
                Text(dailyPay * work.fraction, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 39, weight: .medium, design: .rounded)).tracking(-1.2)
                    .monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Text("每日目标").foregroundStyle(Palette.muted)
                Text("¥" + String(format: "%g", dailyPay)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.font(.system(size: 11))
        }
        .padding(18).frame(width: 248, height: 136, alignment: .leading)
        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已赚 \(String(format: "%.2f", dailyPay * work.fraction)) 元，每日目标 \(String(format: "%g", dailyPay)) 元")
        .help("按班次进度估算，包含休息时间，不代表实际工资")
    }

    private func countdown(_ work: WorkState) -> some View {
        let beforeWork = work.now < work.start
        let finished = work.fraction >= 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("下班倒数", systemImage: "clock").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(beforeWork ? "蓄力中" : finished ? "已下班" : "进行中")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.75), in: Capsule())
            }.foregroundStyle(Palette.sage)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(beforeWork ? "上班前，好好充电" : finished ? "辛苦了，下班快乐" : "还有 \(work.remaining / 3600) 小时 \((work.remaining % 3600) / 60) 分")
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            VStack(spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track)
                        Capsule().fill(Palette.sage).frame(width: geo.size.width * work.fraction)
                    }
                }.frame(height: 7).accessibilityHidden(true)
                HStack {
                    Text(timeString(startMinutes))
                    Spacer()
                    Text("\(Int(work.fraction * 100))% 完成").fontWeight(.medium)
                    Spacer()
                    Text(timeString(endMinutes) + (endMinutes < startMinutes ? " +1" : ""))
                }.font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(Palette.muted)
            }
        }
        .padding(18).frame(maxWidth: .infinity).frame(height: 136)
        .background(Palette.sageLight, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func companion(_ work: WorkState) -> some View {
        HStack(spacing: 12) {
            Button(action: cheer) {
                SproutBuddy(growth: work.fraction, happy: cheered)
                    .scaleEffect(cheered && !reduceMotion ? 1.08 : 1)
                    .rotationEffect(.degrees(cheered && !reduceMotion ? -6 : 0))
                    .frame(width: 68, height: 68)
                    .background(Palette.sageLight.opacity(0.65), in: Circle())
            }.buttonStyle(.plain).help("摸摸小薪芽，收下一点能量")
                .accessibilityLabel("摸摸小薪芽，换一句鼓励")
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("小薪芽").font(.system(size: 13, weight: .semibold))
                    Text(cheered ? "能量 +1" : work.fraction >= 1 ? "今日开花" : work.fraction >= 0.5 ? "茁壮成长" : work.fraction > 0 ? "努力发芽" : "正在蓄力")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.sage)
                }
                Text(cheered ? "收到，今天也一起长大。" : "摸摸我，陪你慢慢走到下班。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.9)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                milestone("发芽", icon: "leaf.fill", reached: work.fraction > 0)
                milestone("半程", icon: "sun.horizon.fill", reached: work.fraction >= 0.5)
                milestone("开花", icon: "camera.macro", reached: work.fraction >= 1)
            }.accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12).frame(height: 82)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false))
    }

    private var encouragement: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Palette.amber).accessibilityHidden(true)
            Text(quotes[quote]).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .lineLimit(1).minimumScaleFactor(0.9)
            Spacer(minLength: 0)
            Button { quote = (quote + 1) % quotes.count } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).accessibilityLabel("换一句鼓励").help("换一句鼓励")
        }.frame(height: 32)
    }

    private func timeString(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
    private func timeBinding(_ key: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: key.wrappedValue / 60, minute: key.wrappedValue % 60, second: 0, of: Date())! }, set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            key.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
    private func milestone(_ title: String, icon: String, reached: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: reached ? icon : "circle.dotted")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(reached ? Palette.sage : Palette.muted)
                .background(reached ? Palette.sageLight : Palette.cream.opacity(0.6), in: Circle())
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.frame(width: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(reached ? "已达成" : "未达成")")
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("把一天，调成你的节奏").font(.system(size: 20, weight: .semibold))
                Text("设置你的日薪与班次，剩下的交给小薪芽。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.frame(height: 46, alignment: .topLeading)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("每日薪资", systemImage: "yensign.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("¥").font(.system(size: 22)).foregroundStyle(Palette.muted)
                        TextField("输入日薪", text: $draftPay).textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                            .accessibilityLabel("日薪金额")
                            .accessibilityHint("输入 0 到 10000000 之间的金额")
                        Text("/ 天").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 10).frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(validPay == nil ? Palette.error : Palette.line, lineWidth: 1))
                    Text(validPay == nil ? "请输入 0–10000000 的有效金额" : "按班次进度估算，非实际工资")
                        .font(.system(size: 11)).foregroundStyle(validPay == nil ? Palette.error : Palette.muted)
                }.padding(16).frame(width: 278, height: 160, alignment: .topLeading)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 12) {
                    Label("工作时间", systemImage: "clock").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    HStack {
                        Text("上班").foregroundStyle(Palette.muted)
                        Spacer()
                        DatePicker("上班时间", selection: timeBinding($draftStart), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
                    }
                    HStack {
                        Text("下班").foregroundStyle(Palette.muted)
                        Spacer()
                        DatePicker("下班时间", selection: timeBinding($draftEnd), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field)
                    }
                    Text(shiftMinutes == 0 ? "上下班时间不能相同" : "\(draftEnd < draftStart ? "跨天 · " : "")共 \(shiftMinutes / 60) 小时 \(shiftMinutes % 60) 分，含休息")
                        .font(.system(size: 11)).foregroundStyle(shiftMinutes == 0 ? Palette.error : Palette.muted)
                }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity).frame(height: 160, alignment: .topLeading)
                    .background(Palette.sageLight, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text("仅保存在这台 Mac")
                Spacer()
                Button("取消") { settings = false }.buttonStyle(.bordered).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Button("保存设置", action: saveSettings).buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validPay == nil || shiftMinutes == 0)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).frame(height: 36)
        }
    }
}

struct SproutBuddy: View {
    let growth: Double
    let happy: Bool
    var body: some View {
        ZStack {
            Ellipse().fill(Palette.sage.opacity(0.12)).frame(width: 40, height: 7).offset(y: 25)
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [Color(red: 0.96, green: 0.80, blue: 0.54), Color(red: 0.88, green: 0.64, blue: 0.37)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 29).offset(y: 10)
            Capsule().fill(Palette.sage).frame(width: 3, height: 20).offset(y: -9)
            Ellipse().fill(Color(red: 0.53, green: 0.69, blue: 0.39)).frame(width: 19, height: 10).rotationEffect(.degrees(30)).offset(x: -8, y: -13)
            Ellipse().fill(Palette.sage).frame(width: 20, height: 11).rotationEffect(.degrees(-35)).offset(x: 9, y: -19)
            if growth >= 1 {
                ZStack {
                    ForEach(0..<6) { petal in
                        Ellipse().fill(Palette.cream).frame(width: 7, height: 12)
                            .offset(y: -6).rotationEffect(.degrees(Double(petal) * 60))
                    }
                    Circle().fill(Color(red: 0.90, green: 0.65, blue: 0.22)).frame(width: 8, height: 8)
                }.offset(y: -23)
            }
            HStack(spacing: 9) {
                Capsule().frame(width: happy ? 6 : 3, height: happy ? 2 : 4)
                Capsule().frame(width: happy ? 6 : 3, height: happy ? 2 : 4)
            }.foregroundStyle(Palette.amber).offset(y: 8)
            Path { path in
                path.move(to: CGPoint(x: 26, y: 44))
                path.addQuadCurve(to: CGPoint(x: 34, y: 44), control: CGPoint(x: 30, y: 49))
            }.stroke(Palette.amber, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            if happy { Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Color(red: 0.77, green: 0.34, blue: 0.35)).offset(x: 24, y: -20) }
        }.frame(width: 60, height: 60).accessibilityHidden(true)
    }
}

final class DragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandle() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var statusItem: NSStatusItem!
    func resizePanel(compact: Bool, scale: Double) {
        guard let panel else { return }
        let size = NSSize(width: (compact ? 404 : 640) * scale + 20, height: (compact ? 104 : 372) * scale + 20)
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        panel.setFrame(frame, display: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 392), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "上班鼓励器"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: Encourager())
        let savedScale = UserDefaults.standard.object(forKey: "widgetScale") as? Double ?? 1
        resizePanel(compact: UserDefaults.standard.bool(forKey: "compactMode"), scale: min(1.4, max(0.8, savedScale)))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "上班鼓励器")
        let menu = NSMenu()
        menu.addItem(withTitle: "显示鼓励器", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "切换完整 / 紧凑模式", action: #selector(toggleMode), keyEquivalent: "").target = self
        let sizes = NSMenu(title: "界面大小")
        for (title, scale) in [("小 · 80%", 0.8), ("标准 · 100%", 1.0), ("大 · 120%", 1.2), ("特大 · 140%", 1.4)] {
            let item = sizes.addItem(withTitle: title, action: #selector(setWidgetScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scale
        }
        let sizeItem = menu.addItem(withTitle: "界面大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    @objc func toggleMode() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "compactMode"), forKey: "compactMode")
        showPanel()
    }
    @objc func setWidgetScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(scale, forKey: "widgetScale")
        showPanel()
    }
    @objc func showPanel() { panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
