import AppKit
import SwiftUI
typealias ViewState<Value> = SwiftUI.State<Value>

// Shared light palette for this intentionally light, floating desktop widget.
enum Palette {
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
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colorScheme == .dark ? (hovered ? NightPalette.ink : NightPalette.muted) : (hovered ? Palette.ink : Palette.muted))
            .background(colorScheme == .dark ? Color.white.opacity(configuration.isPressed ? 0.16 : hovered ? 0.08 : 0) : (configuration.isPressed ? Palette.track : hovered ? Palette.sageLight : Color.clear),
                        in: RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
    }
}

// An independent common-mode clock keeps income linear while menus, window
// dragging, and the slower status timeline update around it.
private final class EarningsClock: ObservableObject {
    @Published private(set) var text = Money.text(0)
    private var timer: Timer?
    private var pay = 0.0
    private var startMinutes = 0
    private var endMinutes = 0
    private var anchorDate = Date()
    private var anchorUptime = ProcessInfo.processInfo.systemUptime
    private var nextRefresh = Date()
    private var rate = EarningsRate(dailyPay: 0, start: Date(), end: Date().addingTimeInterval(1))

    func start(pay: Double, startMinutes: Int, endMinutes: Int) {
        self.pay = pay
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        resetAnchor()
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
    private func resetAnchor() {
        anchorDate = Date()
        anchorUptime = ProcessInfo.processInfo.systemUptime
        let work = WorkState.make(now: anchorDate, startMinutes: startMinutes, endMinutes: endMinutes)
        rate = EarningsRate(dailyPay: pay, start: work.start, end: work.end)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchorDate))!
        let nextStart = calendar.nextDate(after: anchorDate, matching: DateComponents(hour: startMinutes / 60, minute: startMinutes % 60, second: 0), matchingPolicy: .nextTime)!
        nextRefresh = min(midnight, nextStart)
        text = Money.text(rate.amount(at: anchorDate))
    }
    private func tick() {
        let now = Date()
        let elapsed = ProcessInfo.processInfo.systemUptime - anchorUptime
        if abs(now.timeIntervalSince(anchorDate) - elapsed) > 0.5 || now >= nextRefresh {
            resetAnchor()
            return
        }
        let next = Money.text(rate.amount(at: anchorDate.addingTimeInterval(elapsed)))
        if next != text { text = next }
    }
}

private struct LiveEarnings: View {
    let dailyPay: Double
    let startMinutes: Int
    let endMinutes: Int
    var compact = false
    @StateObject private var clock = EarningsClock()
    @Environment(\.buddyMotionEnabled) private var isVisible
    private func refresh() {
        if isVisible { clock.start(pay: dailyPay, startMinutes: startMinutes, endMinutes: endMinutes) }
        else { clock.stop() }
    }
    var body: some View {
        Text((compact ? "¥" : "") + clock.text)
            .font(.system(size: compact ? 25 : 36, weight: .medium, design: .rounded))
            .tracking(compact ? -0.5 : -1.2).monospacedDigit()
            .minimumScaleFactor(compact ? 0.4 : 0.45).lineLimit(1)
            .accessibilityLabel("今日已赚 \(clock.text) 元")
            .onAppear(perform: refresh).onDisappear { clock.stop() }
            .onChange(of: dailyPay) { _, _ in refresh() }
            .onChange(of: startMinutes) { _, _ in refresh() }
            .onChange(of: endMinutes) { _, _ in refresh() }
            .onChange(of: isVisible) { _, _ in refresh() }
    }
}

private struct ChargingButtonLabel: View {
    let session: BreakSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.buddyMotionEnabled) private var isVisible
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: session == nil ? "bolt.heart" : "bolt.fill")
                    .symbolEffect(.pulse, isActive: session != nil && !reduceMotion && isVisible)
                if let session {
                    let seconds = session.elapsed(at: context.date)
                    Text(String(format: "爆气中 %02d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                    Image(systemName: "stop.circle.fill")
                } else { Text("带薪充电") }
            }
            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
            .foregroundStyle(session == nil ? Palette.sage : Palette.amber)
            .background(session == nil ? Palette.sageLight : Color(red: 1, green: 0.87, blue: 0.39), in: Capsule())

        }
    }
}

struct Encourager: View {
    @ObservedObject var windowState: WidgetWindowState
    @AppStorage("lastCelebratedShift") private var lastCelebratedShift = 0.0
    @ViewState<Date> private var currentDate = Date()
    @ViewState<Date?> private var celebrationStart = nil
    @ViewState<Bool> private var previewingOffDuty = false
    @ViewState<Bool> private var sizeEditor = false
    @ViewState<String> private var draftWidth = "640"
    @ViewState<String> private var draftHeight = "372"
    @ViewState<BreakSession?> private var breakSession = nil
    @ViewState<Bool> private var showBreakReward = false
    @ViewState<Double> private var breakEarnings = 0
    @ViewState<Int> private var breakSeconds = 0
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
        draftPay = dailyPay.formatted(.number.grouping(.never).precision(.fractionLength(0...4)))
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

    private var displayScale: Double { WidgetLayout.renderScale(size: windowState.size, compact: compactMode, requested: widgetScale) }
    private var contentWidth: CGFloat { (windowState.size.width - 20) / displayScale }
    private var contentHeight: CGFloat { (windowState.size.height - 20) / displayScale }

    private var currentWork: WorkState { WorkState.make(now: currentDate, startMinutes: startMinutes, endMinutes: endMinutes) }
    private var romantic: Bool { currentWork.fraction >= 1 || previewingOffDuty }
    private var night: Bool { romantic && !settings }
    private var ink: Color { night ? NightPalette.ink : Palette.ink }
    private var muted: Color { night ? NightPalette.muted : Palette.muted }
    private var accent: Color { night ? NightPalette.rose : Palette.sage }
    private var border: Color { night ? NightPalette.line : Palette.line }


    var body: some View {
        Group {
            if compactMode { compactView } else { fullView }
        }
        .frame(width: contentWidth, height: contentHeight)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: contentWidth * displayScale, height: contentHeight * displayScale, alignment: .topLeading)
        .padding(10)
        .tint(accent)
        .overlay {
            if let celebrationStart {
                FireworkShow(startedAt: celebrationStart).padding(10)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle().frame(width: 24, height: 24).padding(11)
        }
        .popover(isPresented: $sizeEditor) { customSizeEditor.environment(\.colorScheme, .light) }
        .popover(isPresented: $showBreakReward) { breakReward.environment(\.colorScheme, .light) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
            if let start = celebrationStart, date.timeIntervalSince(start) >= 12 { celebrationStart = nil }
            checkOffDutyCelebration()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PaySproutPreviewOffDuty"))) { _ in previewOffDuty() }
        .onAppear(perform: checkOffDutyCelebration)
        .onChange(of: compactMode) { _, _ in updateWindowSize() }
        .environment(\.buddyMotionEnabled, windowState.isVisible)
        .environment(\.colorScheme, night ? .dark : .light)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: night)
    }

    private func updateWindowSize() {
        (NSApp.delegate as? AppDelegate)?.resizePanel(compact: compactMode, scale: widgetScale, restoringCustom: true)
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
                        }.frame(maxHeight: .infinity)
                        companion(work)
                    }
                }
                encouragement
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: contentWidth, height: contentHeight, alignment: .top)
        .background {
            if night { RomanticBackdrop().clipShape(RoundedRectangle(cornerRadius: 26)) }
            else { RoundedRectangle(cornerRadius: 26).fill(Palette.canvas) }
        }
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(border, lineWidth: 1).allowsHitTesting(false))
        .foregroundStyle(ink)
        .tint(accent)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
            Image(systemName: night ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(night ? NightPalette.rose : Palette.amber)
                .frame(width: 32, height: 32).background(night ? NightPalette.surface : Palette.cream, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(settings ? "偏好设置" : "上班鼓励器").font(.system(size: 13, weight: .semibold))
            if !settings {
                Text(night ? "今晚，时间属于你" : "让努力，慢慢有回响").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(muted.opacity(0.7)).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay { WindowDragArea().help("按住标题或此处空白拖动窗口").accessibilityHidden(true) }
            HStack(spacing: 4) {
                Button(action: previewOffDuty) {
                    Image(systemName: "party.popper").frame(width: 32, height: 32).contentShape(Rectangle())
                }.accessibilityLabel("预览下班彩蛋").help("预览下班彩蛋 · 不改变真实收入和进度")
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
            Divider()
            Button("自定义大小…", action: openSizeEditor)
            Text("也可拖动窗口右下角")
        } label: {
            Image(systemName: "textformat.size").frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("调整界面大小，当前 \(Int(displayScale * 100))%")
        .help("当前窗口 \(Int(windowState.size.width)) × \(Int(windowState.size.height))，可拖动右下角调整")
    }

    private var scaleOptions: some View {
        ForEach([0.8, 1.0, 1.2, 1.4], id: \.self) { scale in
            Button {
                chooseScale(scale)
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
                    SproutBuddy(growth: night ? 1 : work.fraction, happy: night || cheered, charging: !night && breakSession != nil)
                        .scaleEffect(0.78).frame(width: 44, height: 56)
                }.buttonStyle(.plain).accessibilityLabel("摸摸小薪芽，换一句鼓励").help(quotes[quote])
                VStack(alignment: .leading, spacing: 5) {
                    Text(night && !previewingOffDuty ? "今日份努力，已收好" : "今日已赚").font(.system(size: 11)).foregroundStyle(muted)
                    LiveEarnings(dailyPay: dailyPay, startMinutes: startMinutes, endMinutes: endMinutes, compact: true).foregroundStyle(ink)
                }.frame(width: 118, alignment: .leading)
                    .accessibilityElement(children: .combine)
                Rectangle().fill(border).frame(width: 1, height: 38).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(night ? (previewingOffDuty ? "下班彩蛋 · 预览" : "下班啦，今天也很棒") : work.now < work.start ? "上班前，好好充电" : work.fraction >= 1 ? "下班快乐" : "距下班 \(work.remaining / 3600) 小时 \((work.remaining % 3600) / 60) 分")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(night ? NightPalette.line : Palette.track)
                            Capsule().fill(accent).frame(width: geo.size.width * work.fraction)
                        }
                    }.frame(height: 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("班次进度").accessibilityValue("\(Int(work.fraction * 100))%")
                    Text(night ? "把时间还给自己" : breakSession == nil ? "\(Int(work.fraction * 100))% 完成 · \(timeString(endMinutes))\(endMinutes < startMinutes ? " 次日" : "") 下班" : "充电中 · 收入继续生长")
                        .font(.system(size: 10)).foregroundStyle(muted).monospacedDigit().lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 2) {
                    Button { compactMode = false } label: {
                        Image(systemName: "rectangle.expand.vertical").frame(width: 32, height: 32).contentShape(Rectangle())
                    }.buttonStyle(QuietButtonStyle()).accessibilityLabel("展开完整模式").help("展开完整模式")
                    Menu {
                        Button("展开完整模式") { compactMode = false }
                        Button("偏好设置", action: openSettings)
                        Button("检查更新…") { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }
                        Button("预览下班彩蛋", action: previewOffDuty)
                        if previewingOffDuty { Button("结束预览", action: endOffDutyPreview) }
                        Menu("界面大小") {
                            scaleOptions
                            Divider()
                            Button("自定义大小…", action: openSizeEditor)
                        }
                        Button(breakSession == nil ? "带薪充电" : "充电完成，看看赚了多少", action: toggleBreak)
                        Divider()
                        Button("收起到菜单栏") { (NSApp.delegate as? AppDelegate)?.panel.orderOut(nil) }
                        Button("退出上班鼓励器") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("更多选项").help("设置、大小与退出")
                }.font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 16).frame(width: contentWidth, height: contentHeight)
            .foregroundStyle(ink)
            .background {
                if night { RomanticBackdrop().clipShape(RoundedRectangle(cornerRadius: 20)) }
                else { RoundedRectangle(cornerRadius: 20).fill(Palette.canvas) }
            }
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(border, lineWidth: 1).allowsHitTesting(false))
            .overlay(alignment: .top) { WindowDragArea().frame(height: 20).padding(.horizontal, 24).help("按住顶部留白拖动窗口").accessibilityHidden(true) }
        }
    }

    private func earnings(_ work: WorkState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(night && !previewingOffDuty ? "今日份努力，已收好" : "今日已赚").font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(.system(size: 23, weight: .regular)).foregroundStyle(accent)
                LiveEarnings(dailyPay: dailyPay, startMinutes: startMinutes, endMinutes: endMinutes).foregroundStyle(night ? NightPalette.rose : ink)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Text("目标").foregroundStyle(muted)
                Text("¥" + Money.text(dailyPay)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.font(.system(size: 11))
            Text(work.now >= work.start && work.fraction < 1 ? "每秒 +¥" + Money.text(dailyPay / work.end.timeIntervalSince(work.start)) : work.fraction >= 1 ? "今日小金库已攒满" : "小金库等待开工")
                .font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(accent)
        }
        .padding(18).frame(width: (contentWidth - 60) * 0.428, alignment: .leading).frame(maxHeight: .infinity)
        .background(night ? NightPalette.surface.opacity(0.9) : Palette.cream, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已赚 \(Money.text(dailyPay * work.fraction)) 元，每日目标 \(Money.text(dailyPay)) 元")
        .help("按班次进度估算，包含休息时间，不代表实际工资")
    }

    @ViewBuilder private func countdown(_ work: WorkState) -> some View {
        if night {
            OffDutyInlineMessage(preview: previewingOffDuty, replay: replayFireworks, endPreview: endOffDutyPreview)
        } else { regularCountdown(work) }
    }

    private func regularCountdown(_ work: WorkState) -> some View {
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
            }.foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(beforeWork ? "上班前，好好充电" : finished ? "辛苦了，下班快乐" : "还有 \(work.remaining / 3600) 小时 \((work.remaining % 3600) / 60) 分")
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            VStack(spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track)
                        Capsule().fill(accent).frame(width: geo.size.width * work.fraction)
                    }
                }.frame(height: 7).accessibilityHidden(true)
                HStack {
                    Text(timeString(startMinutes))
                    Spacer()
                    Text("\(Int(work.fraction * 100))% 完成").fontWeight(.medium)
                    Spacer()
                    Text(timeString(endMinutes) + (endMinutes < startMinutes ? " +1" : ""))
                }.font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(muted)
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(night ? NightPalette.surface.opacity(0.88) : Palette.sageLight, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func companion(_ work: WorkState) -> some View {
        HStack(spacing: 12) {
            Button(action: cheer) {
                SproutBuddy(growth: night ? 1 : work.fraction, happy: night || cheered, charging: !night && breakSession != nil)
                    .scaleEffect(cheered && !reduceMotion ? 1.08 : 1)
                    .rotationEffect(.degrees(cheered && !reduceMotion ? -6 : 0))
                    .frame(width: 68, height: 68)
                    .background(night ? NightPalette.rose.opacity(0.12) : Palette.sageLight.opacity(0.65), in: Circle())

            }.buttonStyle(.plain).help("摸摸小薪芽，收下一点能量")
                .accessibilityLabel("摸摸小薪芽，换一句鼓励")
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("小薪芽").font(.system(size: 13, weight: .semibold))
                    Text(night ? (previewingOffDuty ? "开花预览" : "今日开花") : breakSession != nil ? "超能薪芽 · 爆气中" : cheered ? "能量 +1" : GrowthStage(progress: work.fraction).title)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                }
                Text(night ? "把小花送给你，把时间还给自己。" : breakSession.map { "休息 \($0.elapsed(at: work.now) / 60) 分 \($0.elapsed(at: work.now) % 60) 秒 · 已攒 ¥" + Money.text($0.earnings(at: work.now)) } ?? (cheered ? "收到，今天也一起长大。" : GrowthStage(progress: work.fraction).message))
                    .font(.system(size: 11)).foregroundStyle(muted)
                    .lineLimit(1).minimumScaleFactor(0.9)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                milestone("发芽", icon: "leaf.fill", reached: work.fraction > 0)
                milestone("半程", icon: "sun.horizon.fill", reached: work.fraction >= 0.5)
                milestone("开花", icon: "camera.macro", reached: work.fraction >= 1)
            }.accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12).frame(height: 82)
        .background(night ? NightPalette.surface.opacity(0.8) : breakSession == nil ? Color.white : Color(red: 1, green: 0.95, blue: 0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(night ? NightPalette.line : breakSession == nil ? Palette.line : Color.orange.opacity(0.55), lineWidth: breakSession == nil ? 1 : 1.5).allowsHitTesting(false))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: breakSession != nil)
    }

    private var encouragement: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(night ? NightPalette.rose : Palette.amber).accessibilityHidden(true)
            Text(romantic ? "把工作留在这里，余下的时间属于你。" : quotes[quote]).font(.system(size: 12)).foregroundStyle(muted)
                .lineLimit(1).minimumScaleFactor(0.9)
            Spacer(minLength: 0)
            if night {
                Button(action: previewingOffDuty ? endOffDutyPreview : replayFireworks) {
                    Label(previewingOffDuty ? "结束预览" : "再放烟花", systemImage: previewingOffDuty ? "arrow.uturn.backward" : "sparkles")
                        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).frame(height: 32)
                        .background(NightPalette.rose.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain).foregroundStyle(NightPalette.rose)
            } else {
                Button(action: toggleBreak) { ChargingButtonLabel(session: breakSession) }.buttonStyle(.plain)
                    .accessibilityLabel(breakSession == nil ? "开始带薪充电" : "爆气充电中，点击结束充电并查看收益")
                    .help(breakSession == nil ? "开始休息计时，工资按班次进度继续增长" : "点击结束充电，看看休息时攒下的收入")
            }
            Button { quote = (quote + 1) % quotes.count } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).accessibilityLabel("换一句鼓励").help("换一句鼓励")
        }.frame(height: 32)
    }

    private func checkOffDutyCelebration() {
        guard windowState.isVisible, !settings, !sizeEditor, !showBreakReward,
              !previewingOffDuty, CelebrationGate.shouldCelebrate(work: currentWork, lastShift: lastCelebratedShift) else { return }
        lastCelebratedShift = currentWork.start.timeIntervalSince1970
        celebrationStart = Date()
    }
    private func previewOffDuty() {
        settings = false
        sizeEditor = false
        showBreakReward = false
        previewingOffDuty = true
        replayFireworks()
    }
    private func replayFireworks() { celebrationStart = Date() }
    private func endOffDutyPreview() {
        previewingOffDuty = false
        celebrationStart = nil
    }

    private func chooseScale(_ scale: Double) {
        widgetScale = scale
        (NSApp.delegate as? AppDelegate)?.resizePanel(compact: compactMode, scale: scale)
    }

    private func openSizeEditor() {
        draftWidth = String(Int(windowState.size.width.rounded()))
        draftHeight = String(Int(windowState.size.height.rounded()))
        sizeEditor = true
    }
    private var customSize: CGSize? {
        guard let width = Double(draftWidth), let height = Double(draftHeight), width.isFinite, height.isFinite else { return nil }
        let size = CGSize(width: width, height: height)
        let maxSize = (NSApp.delegate as? AppDelegate)?.maximumWindowSize ?? CGSize(width: 1600, height: 1000)
        guard size == WidgetLayout.clamped(size, compact: compactMode, maximum: maxSize) else { return nil }
        return size
    }
    private var customSizeEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自定义窗口大小").font(.headline)
            Text("长宽分别调整，内容会跟随窗口排布。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            HStack {
                Text("宽度")
                TextField("宽度", text: $draftWidth).textFieldStyle(.roundedBorder).accessibilityLabel("窗口宽度")
                Text("高度")
                TextField("高度", text: $draftHeight).textFieldStyle(.roundedBorder).accessibilityLabel("窗口高度")
            }.font(.system(size: 12))
            let minimum = WidgetLayout.minimum(compact: compactMode)
            Text(customSize == nil ? "请输入屏幕可容纳的尺寸，最小 \(Int(ceil(minimum.width))) × \(Int(ceil(minimum.height)))。" : "单位：屏幕点；也可直接拖动窗口右下角。")
                .font(.system(size: 11)).foregroundStyle(customSize == nil ? Palette.error : Palette.muted)
            HStack {
                Spacer()
                Button("取消") { sizeEditor = false }.keyboardShortcut(.cancelAction)
                Button("应用大小") {
                    guard let size = customSize else { return }
                    (NSApp.delegate as? AppDelegate)?.applyCustomSize(size)
                    sizeEditor = false
                }.buttonStyle(.borderedProminent).disabled(customSize == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 340).tint(Palette.sage)
    }

    private func toggleBreak() {
        let now = Date()
        if let session = breakSession {
            breakEarnings = session.earnings(at: now)
            breakSeconds = session.elapsed(at: now)
            breakSession = nil
            showBreakReward = true
            cheer()
        } else {
            let work = WorkState.make(now: now, startMinutes: startMinutes, endMinutes: endMinutes)
            breakSession = BreakSession(startedAt: now, earnedAtStart: dailyPay * work.fraction,
                                        shiftStart: work.start, shiftEnd: work.end, dailyPay: dailyPay)
        }
    }
    private var breakReward: some View {
        VStack(spacing: 12) {
            SproutBuddy(growth: 1, happy: true).scaleEffect(1.15).frame(height: 72)
            Text("电量回来了，小金库也长大了").font(.system(size: 17, weight: .semibold))
            Text("充电 \(breakSeconds / 60) 分 \(breakSeconds % 60) 秒，期间估算收入")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text("+¥" + Money.text(breakEarnings)).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Palette.sage)
            Text("休息也是照顾自己，欢迎回来。 ").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button("收下这点小快乐") { showBreakReward = false }.buttonStyle(.borderedProminent).tint(Palette.sage)
        }.padding(24).frame(width: 340).foregroundStyle(Palette.ink)
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
                .foregroundStyle(reached ? accent : muted)
                .background(night ? NightPalette.rose.opacity(reached ? 0.16 : 0.06) : reached ? Palette.sageLight : Palette.cream.opacity(0.6), in: Circle())
            Text(title).font(.system(size: 10)).foregroundStyle(muted)
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
                Button("检查更新…") { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }
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

struct BuddyMotionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var buddyMotionEnabled: Bool {
        get { self[BuddyMotionKey.self] }
        set { self[BuddyMotionKey.self] = newValue }
    }
}

struct SproutBuddy: View {
    let growth: Double
    let happy: Bool
    var charging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.buddyMotionEnabled) private var motionEnabled
    private var stage: GrowthStage { GrowthStage(progress: growth) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !motionEnabled)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let wave = sin(time * (stage == .resting ? 1.2 : 2.1))
            let amplitude: Double = charging ? 1.5 : stage == .resting ? 1 : stage == .budding ? 2 : 4
            drawing(time: time)
                .rotationEffect(.degrees(reduceMotion ? 0 : wave * amplitude), anchor: .bottom)
                .offset(y: reduceMotion ? 0 : stage == .blooming ? -abs(wave) * 2 : wave * 0.6)
        }
        .frame(width: 60, height: 60)
        .background { if charging { PowerAura() } }
        .accessibilityHidden(true)
    }

    private func drawing(time: Double) -> some View {
        let stem = 8 + 12 * min(1, max(0, growth) * 2)
        let leafScale = 0.65 + 0.35 * min(1, max(0, growth) * 2)
        let blinking = !reduceMotion && time.truncatingRemainder(dividingBy: 5) < 0.18
        return ZStack {
            Ellipse().fill(Palette.sage.opacity(0.12)).frame(width: 40, height: 7).offset(y: 25)
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [charging ? Color(red: 1, green: 0.89, blue: 0.39) : Color(red: 0.96, green: 0.80, blue: 0.54), charging ? Color(red: 0.97, green: 0.67, blue: 0.16) : Color(red: 0.88, green: 0.64, blue: 0.37)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 29).offset(y: 10)
            Capsule().fill(charging ? Palette.amber : Palette.sage).frame(width: 3, height: stem).offset(y: 1 - stem / 2)
            Ellipse().fill(charging ? Color(red: 1, green: 0.72, blue: 0.05) : Color(red: 0.53, green: 0.69, blue: 0.39)).frame(width: 19, height: 10)
                .rotationEffect(.degrees(stage == .resting ? 8 : 30)).scaleEffect(leafScale).offset(x: -8, y: 3 - stem)
            if growth >= 0.25 {
                Ellipse().fill(charging ? Color(red: 0.93, green: 0.53, blue: 0.05) : Palette.sage).frame(width: 20, height: 11)
                    .rotationEffect(.degrees(-35)).scaleEffect(leafScale).offset(x: 9, y: -3 - stem)
            }
            if stage == .budding {
                Ellipse().fill(Color(red: 0.91, green: 0.64, blue: 0.36)).frame(width: 8, height: 12)
                    .overlay(Capsule().fill(Palette.sage).frame(width: 2, height: 7).offset(y: 4))
                    .offset(y: -24)
            }
            if stage == .blooming {
                ZStack {
                    ForEach(0..<6) { petal in
                        Ellipse().fill(Color(red: 0.99, green: 0.92, blue: 0.66)).frame(width: 7, height: 12)
                            .offset(y: -7).rotationEffect(.degrees(Double(petal) * 60))
                    }
                    Circle().fill(Color(red: 0.90, green: 0.65, blue: 0.22)).frame(width: 8, height: 8)
                }.rotationEffect(.degrees(reduceMotion ? 0 : sin(time) * 12)).offset(y: -24)
            }
            HStack(spacing: 9) {
                Capsule().frame(width: happy || stage == .resting ? 6 : 3, height: happy || blinking || stage == .resting ? 2 : 4)
                Capsule().frame(width: happy || stage == .resting ? 6 : 3, height: happy || blinking || stage == .resting ? 2 : 4)
            }.foregroundStyle(Palette.amber).offset(y: 8)
            Path { path in
                path.move(to: CGPoint(x: 26, y: 44))
                path.addQuadCurve(to: CGPoint(x: 34, y: 44), control: CGPoint(x: 30, y: 49))
            }.stroke(Palette.amber, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.65, green: 0.33, blue: 0.03)).offset(y: 15)
                Path { path in
                    path.move(to: CGPoint(x: 20, y: 32)); path.addLine(to: CGPoint(x: 27, y: 35))
                    path.move(to: CGPoint(x: 33, y: 35)); path.addLine(to: CGPoint(x: 40, y: 32))
                }.stroke(Palette.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            } else if happy {
                Image(systemName: "heart.fill").font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.77, green: 0.34, blue: 0.35)).offset(x: 24, y: -20)
            } else if stage == .resting {
                Text("z").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Palette.muted).offset(x: 22, y: -15)
            }
            if !reduceMotion && !charging && stage.rawValue >= GrowthStage.growing.rawValue {
                ForEach(0..<3) { index in
                    let phase = (time / 4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Image(systemName: stage == .blooming ? "sparkle" : "circle.fill")
                        .font(.system(size: stage == .blooming ? 6 : 3))
                        .foregroundStyle(Palette.amber.opacity(sin(phase * .pi) * 0.7))
                        .offset(x: Double(index - 1) * 22, y: -8 - phase * 24)
                }
            }
        }.frame(width: 60, height: 60)
    }
}

final class WidgetWindowState: ObservableObject {
    @Published var isVisible = true
    @Published var size = WidgetLayout.preset(compact: false, scale: 1)
}

final class ResizeHandle: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var initialFrame = NSRect.zero
    private var initialMouse = NSPoint.zero
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        for offset in [CGFloat(5), 10, 15] {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialMouse = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let delegate = NSApp.delegate as? AppDelegate else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        delegate.applyCustomSize(CGSize(width: initialFrame.width + mouse.x - initialMouse.x,
                                        height: initialFrame.height - mouse.y + initialMouse.y), persist: false,
                                 topLeft: NSPoint(x: initialFrame.minX, y: initialFrame.maxY))
    }
    override func mouseUp(with event: NSEvent) { (NSApp.delegate as? AppDelegate)?.saveWindowSize() }
}

struct WindowResizeHandle: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSView {
        let view = ResizeHandle()
        view.toolTip = "拖动调整长宽；也可在大小菜单中输入精确尺寸"
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("拖动调整窗口大小，精确尺寸可在大小菜单设置")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        nsView.needsDisplay = true
    }
}

final class DragHandle: NSView {
    private var initialOrigin = NSPoint.zero
    private var initialMouse = NSPoint.zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialOrigin = window.frame.origin
        initialMouse = window.convertPoint(toScreen: event.locationInWindow)
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: initialOrigin.x + pointer.x - initialMouse.x,
                                      y: initialOrigin.y + pointer.y - initialMouse.y))
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
    }
}
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandle() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func orderOut(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.windowState.isVisible = false
        super.orderOut(sender)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let updater = AppUpdater()
    let windowState = WidgetWindowState()
    var panel: NSPanel!
    var statusItem: NSStatusItem!
    private var isProgrammaticResize = false
    var maximumWindowSize: CGSize { (panel?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1600, height: 1000) }
    private var isCompact: Bool { UserDefaults.standard.bool(forKey: "compactMode") }

    func resizePanel(compact: Bool, scale: Double, restoringCustom: Bool = false) {
        guard let panel else { return }
        var size = WidgetLayout.preset(compact: compact, scale: scale)
        let key = WidgetLayout.storageKey(compact: compact)
        if restoringCustom, let width = UserDefaults.standard.object(forKey: key + "Width") as? Double,
           let height = UserDefaults.standard.object(forKey: key + "Height") as? Double,
           width.isFinite, height.isFinite {
            size = CGSize(width: width, height: height)
        } else if !restoringCustom {
            UserDefaults.standard.removeObject(forKey: key + "Width")
            UserDefaults.standard.removeObject(forKey: key + "Height")
        }
        let minSize = WidgetLayout.minimum(compact: compact)
        panel.minSize = minSize
        applyCustomSize(WidgetLayout.clamped(size, compact: compact, maximum: maximumWindowSize), persist: false)
    }

    func applyCustomSize(_ proposed: CGSize, persist: Bool = true, topLeft: NSPoint? = nil) {
        guard let panel else { return }
        let size = WidgetLayout.clamped(proposed, compact: isCompact, maximum: maximumWindowSize)
        let anchor = topLeft ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        var frame = NSRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        isProgrammaticResize = true
        windowState.size = size
        panel.setFrame(frame, display: true)
        isProgrammaticResize = false
        if persist { saveWindowSize() }
    }
    func windowDidResize(_ notification: Notification) {
        guard let panel, !isProgrammaticResize else { return }
        windowState.size = panel.frame.size
    }
    func windowDidEndLiveResize(_ notification: Notification) { saveWindowSize() }
    func saveWindowSize() {
        guard let panel else { return }
        let key = WidgetLayout.storageKey(compact: isCompact)
        UserDefaults.standard.set(panel.frame.width, forKey: key + "Width")
        UserDefaults.standard.set(panel.frame.height, forKey: key + "Height")
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
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 392), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "上班鼓励器"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: Encourager(windowState: windowState))
        hosting.sizingOptions = []
        panel.contentView = hosting
        let savedScale = UserDefaults.standard.object(forKey: "widgetScale") as? Double ?? 1
        resizePanel(compact: UserDefaults.standard.bool(forKey: "compactMode"), scale: min(1.4, max(0.8, savedScale)), restoringCustom: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "上班鼓励器")
        let menu = NSMenu()
        menu.addItem(withTitle: "显示鼓励器", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "预览下班彩蛋", action: #selector(previewCelebration), keyEquivalent: "").target = self
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
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
        AppUpdater.acknowledgeLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.updater.check(manual: false) }
    }
    func applicationWillTerminate(_ notification: Notification) { updater.cancel(); updater.discardPreparedUpdate() }
    @objc func checkForUpdates() { updater.check(manual: true) }
    @objc func previewCelebration() {
        showPanel()
        NotificationCenter.default.post(name: Notification.Name("PaySproutPreviewOffDuty"), object: nil)
    }
    @objc func toggleMode() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "compactMode"), forKey: "compactMode")
        showPanel()
    }
    @objc func setWidgetScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(scale, forKey: "widgetScale")
        resizePanel(compact: isCompact, scale: scale)
        showPanel()
    }
    @objc func showPanel() { windowState.isVisible = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
}
