import SwiftUI
import AppKit

enum Palette {
    static let background = Color(hex: 0xF7F8F2)
    static let sidebar = Color(hex: 0xEFF1E8)
    static let green = Color(hex: 0x274E3D)
    static let ink = Color(hex: 0x273C32)
    static let muted = Color(hex: 0x7E887D)
    static let line = Color(hex: 0xE4E8DE)
    static let lime = Color(hex: 0xD7EDAE)
    static let water = Color(hex: 0x4C8198)
    static let eyes = Color(hex: 0x8B925A)
    static let stretch = Color(hex: 0xB18462)
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
extension ReminderKind {
    var color: Color { switch self { case .water: return Palette.water; case .eyes: return Palette.eyes; case .stretch: return Palette.stretch } }
    var wash: Color { switch self { case .water: return Color(hex: 0xEEF5F7); case .eyes: return Color(hex: 0xF3F4E9); case .stretch: return Color(hex: 0xFAF0E6) } }
}

struct PrimaryButton: ButtonStyle {
    var light = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 19).padding(.vertical, 12)
            .background(light ? Palette.lime : Palette.green)
            .foregroundStyle(light ? Palette.green : .white)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(Palette.green)
            .background(configuration.isPressed ? Palette.line : Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line, lineWidth: 1))
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let notice = model.notice {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "info.circle")
                                Text(notice).frame(maxWidth: .infinity, alignment: .leading)
                                if model.canUndoWater { Button("撤销饮水") { model.undoWater() }.buttonStyle(.plain).fontWeight(.semibold) }
                                Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭提示")
                            }.font(.system(size: 12)).foregroundStyle(Palette.green).padding(13).background(Palette.lime.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        switch model.page {
                        case "提醒计划": PlansView(model: model)
                        case "健康统计": StatisticsView(model: model)
                        case "设置": SettingsView(model: model)
                        default: DashboardView(model: model)
                        }
                    }.padding(.horizontal, 32).padding(.bottom, 28).padding(.top, 5)
                }
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .font(.custom("PingFang SC", size: 13))
        .tint(Palette.green)
        .frame(minWidth: 1020, minHeight: 730)
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark().frame(width: 37, height: 39)
                VStack(alignment: .leading, spacing: 0) {
                    Text("缓芽").font(.custom("PingFang SC", size: 25).weight(.semibold)).tracking(3)
                    Text("huǎn yá").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.8).foregroundStyle(Palette.muted)
                }
            }.padding(.leading, 25).padding(.top, 31).padding(.bottom, 47)
            Text("为自己，留一点时间").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 25).padding(.bottom, 15)
            ForEach([("今日概览", "square.grid.2x2"), ("提醒计划", "bell.badge"), ("健康统计", "chart.bar.xaxis"), ("设置", "slider.horizontal.3")], id: \.0) { item in
                Button { withAnimation(.easeInOut(duration: 0.15)) { model.page = item.0 } } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.1).font(.system(size: 15, weight: .medium)).frame(width: 20)
                        Text(item.0).font(.system(size: 13, weight: model.page == item.0 ? .semibold : .regular))
                        Spacer()
                        if model.page == item.0 { Circle().fill(Palette.green).frame(width: 5, height: 5) }
                    }.foregroundStyle(model.page == item.0 ? Palette.green : Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15).padding(.vertical, 13)
                        .background(model.page == item.0 ? Color.white.opacity(0.85) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .padding(.horizontal, 13)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "leaf").font(.system(size: 24, weight: .light)).rotationEffect(.degrees(-20))
                Text("工作很重要，\n你也是。").font(.custom("Songti SC", size: 18)).lineSpacing(5)
                Text("TAKE A LITTLE BREATH").font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(Palette.muted)
            }.foregroundStyle(Palette.green).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xE4E9D8)).clipShape(RoundedRectangle(cornerRadius: 14)).padding(16)
            HStack(spacing: 7) {
                Circle().fill(model.engine.paused || model.engine.idle ? Palette.stretch : Palette.eyes).frame(width: 6, height: 6)
                Text(model.status).font(.system(size: 10))
            }.foregroundStyle(Palette.muted).padding(.horizontal, 25).padding(.bottom, 23)
        }.background(Palette.sidebar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.page).font(.system(size: 23, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 11))
                Text(model.now.formatted(.dateTime.month(.twoDigits).day(.twoDigits).weekday(.wide).locale(Locale(identifier: "zh_CN"))))
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.trailing, 14)
            Button { model.togglePause() } label: {
                Label(model.hasManualPause ? "继续提醒" : "暂停提醒", systemImage: model.hasManualPause ? "play.fill" : "pause.fill")
            }.buttonStyle(QuietButton())
        }.padding(.horizontal, 32).padding(.top, 29).padding(.bottom, 25)
    }
    private var subtitle: String {
        switch model.page {
        case "提醒计划": return "找到适合你的节奏，让休息自然发生。"
        case "健康统计": return "每一次小小的休息，都值得被看见。"
        case "设置": return "让缓芽，更合你的习惯。"
        default: return "小习惯，让好状态发生。"
        }
    }
}

struct BrandMark: View {
    var body: some View {
        Image(nsImage: BrandArtwork.markImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel("缓芽 · huǎn yá")
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            HStack {
                SectionTitle(title: "给身体的三个小约定", caption: "YOUR DAILY RITUALS")
                Spacer()
                Button { model.page = "提醒计划" } label: { HStack(spacing: 5) { Text("调整计划"); Image(systemName: "arrow.up.right") } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(ReminderKind.allCases) { kind in RitualCard(model: model, kind: kind) }
            }
            HStack(alignment: .top, spacing: 20) {
                sittingCard.frame(maxWidth: .infinity)
                activityCard.frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("只在本机记录 · 无需登录 · 关掉窗口，菜单栏继续陪伴")
                Spacer()
                Text("A LITTLE BREAK, A BETTER DAY.").tracking(1).font(.system(size: 8))
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) { Circle().fill(Palette.lime).frame(width: 5, height: 5); Text("A MOMENT FOR YOURSELF").tracking(1.8).font(.system(size: 9, weight: .medium)) }.foregroundStyle(Palette.lime)
                Text(model.activeBreak != nil ? "放下工作，\n好好休息一会儿。" : "坐久了，\n就起身走走。").font(.custom("Songti SC", size: 30).weight(.medium)).lineSpacing(4).foregroundStyle(Color(hex: 0xFAFBEF))
                Text("从一杯水、一次远眺、一个伸展开始。").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
                Button { model.trigger(.stretch) } label: { HStack(spacing: 8) { Text("现在休息一下"); Image(systemName: "arrow.up.right") } }.buttonStyle(PrimaryButton(light: true)).padding(.top, 3)
            }.frame(maxWidth: .infinity, alignment: .leading)
            BotanicalFigure().frame(width: 160, height: 178).padding(.horizontal, 5).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(model.activeBreak != nil ? "休息剩余" : (model.nextBatch.map { "下次 · \($0.title)" } ?? model.status)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(2)
                ZStack {
                    Circle().stroke(.white.opacity(0.13), lineWidth: 2)
                    Circle().trim(from: 0, to: progress).stroke(Palette.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(model.activeBreak != nil ? clockText(model.breakRemaining) : model.countdown).font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Palette.lime)
                        Text(model.engine.paused ? "PAUSED" : "慢慢来，不着急").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                }.frame(width: 140, height: 140)
                if let until = model.engine.busyUntil ?? model.engine.pausedUntil { Text("\(until.formatted(date: .omitted, time: .shortened)) 自动恢复 · \(model.status)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }.frame(width: 157)
        }.padding(.horizontal, 27).padding(.vertical, 22).background(Palette.green).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private var progress: Double {
        if let active = model.activeBreak { return min(1, max(0, 1 - Double(model.breakRemaining) / Double(max(1, active.duration)))) }
        guard let batch = model.nextBatch, let kind = batch.kinds.first else { return 0 }
        let total = batch.planned == nil ? Double(model.preferences[kind].intervalMinutes * 60) : max(60, batch.dueAt.timeIntervalSince(Calendar.current.startOfDay(for: batch.dueAt)))
        return min(1, max(0.01, 1 - batch.dueAt.timeIntervalSince(model.now) / total))
    }

    private var sittingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("本轮使用时长（估算）").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "clock").foregroundStyle(Palette.muted) }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(model.engine.sittingSeconds / 60))").font(.system(size: 35, weight: .light, design: .rounded)).monospacedDigit()
                Text("分钟").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("我已起身 ✓") { model.stoodUp() }.buttonStyle(QuietButton())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) { Capsule().fill(Palette.line); Capsule().fill(Palette.eyes.opacity(0.7)).frame(width: g.size.width * min(1, model.engine.sittingSeconds / Double(model.preferences.stretch.intervalMinutes * 60))) }
            }.frame(height: 5)
            Text("唤醒、跨天或离开满 5 分钟后重新计时\n今日累计工作 \(minutesText(model.today.workSeconds))").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(5)
        }.padding(18).background(.white.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Palette.line))
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("今天的小小进步").font(.system(size: 14, weight: .semibold)); Spacer(); Text("\(model.todayEvents.count) 次记录").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            if model.todayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("好习惯，从这一次开始。").font(.system(size: 13))
                    Text("喝一杯水，或完成一次休息，\n你的第一条记录就会出现在这里。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
                }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            } else {
                ForEach(Array(model.todayEvents.prefix(3))) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.kind.symbol).font(.system(size: 11)).foregroundStyle(event.kind.color).frame(width: 28, height: 28).background(event.kind.wash).clipShape(Circle())
                        Text(event.kind == .water ? "喝水 \(event.amount) ml" : "\(event.kind.short)休息 \(event.amount) 秒").font(.system(size: 11))
                        Spacer()
                        Text(event.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
                    }
                }
            }
        }.padding(18).frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading).background(.white.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Palette.line))
    }
}

struct RitualCard: View {
    @ObservedObject var model: AppModel
    let kind: ReminderKind
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: kind.symbol).font(.system(size: 19, weight: .light)).foregroundStyle(kind.color).frame(width: 39, height: 39).background(kind.wash).clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
                Text(model.preferences[kind].enabled ? "每 \(model.preferences[kind].intervalMinutes) 分钟" : "已关闭").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Text(kind.title).font(.system(size: 14, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) { Capsule().fill(kind.wash); Capsule().fill(kind.color.opacity(0.65)).frame(width: g.size.width * ratio) }
            }.frame(height: 4)
            Button { if kind == .water { model.logWater() } else { model.trigger(kind) } } label: {
                HStack { Text(kind == .water ? "+ 记一杯水" : "开始一次休息"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .medium)).foregroundStyle(kind.color).padding(.top, 1)
            }.buttonStyle(.plain)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Palette.line.opacity(0.7)))
    }
    var value: String { switch kind { case .water: return "\(model.today.waterML)"; case .eyes: return "\(model.today.eyeBreaks)"; case .stretch: return "\(model.today.stretches)" } }
    var unit: String { kind == .water ? "/ \(model.preferences.waterGoalML) ml" : "次 · 今日完成" }
    var ratio: Double { min(1, kind == .water ? Double(model.today.waterML) / Double(model.preferences.waterGoalML) : Double(kind == .eyes ? model.today.eyeBreaks : model.today.stretches) / Double(model.preferences.breakGoal)) }
}

struct SectionTitle: View {
    let title: String
    var caption: String = ""
    var body: some View { HStack(alignment: .firstTextBaseline, spacing: 12) { Text(title).font(.system(size: 15, weight: .semibold)); if !caption.isEmpty { Text(caption).font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted) } } }
}

struct BotanicalFigure: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 180, sy = size.height / 220
            context.scaleBy(x: sx, y: sy)
            func line(_ points: [CGPoint], _ color: Color, _ width: CGFloat) {
                var p = Path(); p.addLines(points); context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: 20, y: 199, width: 145, height: 8)), with: .color(.black.opacity(0.1)))
            var leaf = Path(); leaf.move(to: CGPoint(x: 25,y: 174)); leaf.addQuadCurve(to: CGPoint(x: 34,y: 104), control: CGPoint(x: -8,y: 123)); leaf.addQuadCurve(to: CGPoint(x: 25,y: 174), control: CGPoint(x: 57,y: 146)); context.fill(leaf, with: .color(Color(hex: 0x789573)))
            var leaf2 = Path(); leaf2.move(to: CGPoint(x: 30,y: 168)); leaf2.addQuadCurve(to: CGPoint(x: 61,y: 133), control: CGPoint(x: 32,y: 133)); leaf2.addQuadCurve(to: CGPoint(x: 30,y: 168), control: CGPoint(x: 68,y: 167)); context.fill(leaf2, with: .color(Color(hex: 0xA6B48B)))
            line([CGPoint(x: 28,y: 190),CGPoint(x: 32,y: 126)], Color(hex: 0xC0CBA6), 1)
            var pot = Path(); pot.addLines([CGPoint(x: 15,y: 176),CGPoint(x: 45,y: 176),CGPoint(x: 40,y: 199),CGPoint(x: 20,y: 199)]); pot.closeSubpath(); context.fill(pot, with: .color(Color(hex: 0xD1C7A3)))
            // A calm, hand-drawn stretch, with the arms opening into the surrounding space.
            line([CGPoint(x: 92,y: 139),CGPoint(x: 84,y: 168),CGPoint(x: 70,y: 198)], Color(hex: 0xE5DFC7), 13)
            line([CGPoint(x: 104,y: 141),CGPoint(x: 112,y: 172),CGPoint(x: 124,y: 198)], Color(hex: 0xD5D2BA), 13)
            line([CGPoint(x: 64,y: 201),CGPoint(x: 76,y: 201)], Color(hex: 0xA2B18D), 6)
            line([CGPoint(x: 122,y: 201),CGPoint(x: 134,y: 201)], Color(hex: 0xA2B18D), 6)
            var torso = Path(); torso.move(to: CGPoint(x: 85,y: 89)); torso.addQuadCurve(to: CGPoint(x: 109,y: 89), control: CGPoint(x: 96,y: 83)); torso.addLine(to: CGPoint(x: 117,y: 143)); torso.addQuadCurve(to: CGPoint(x: 81,y: 143), control: CGPoint(x: 98,y: 152)); torso.closeSubpath(); context.fill(torso, with: .color(Palette.lime))
            line([CGPoint(x: 88,y: 96),CGPoint(x: 68,y: 70),CGPoint(x: 60,y: 40)], Palette.lime, 11)
            line([CGPoint(x: 107,y: 96),CGPoint(x: 128,y: 70),CGPoint(x: 137,y: 39)], Palette.lime, 11)
            line([CGPoint(x: 60,y: 40),CGPoint(x: 57,y: 30)], Color(hex: 0xE2BC96), 7)
            line([CGPoint(x: 137,y: 39),CGPoint(x: 141,y: 30)], Color(hex: 0xE2BC96), 7)
            context.fill(Path(ellipseIn: CGRect(x: 86,y: 58,width: 24,height: 27)), with: .color(Color(hex: 0xE2BC96)))
            var hair = Path(); hair.move(to: CGPoint(x: 86,y: 72)); hair.addCurve(to: CGPoint(x: 110,y: 65), control1: CGPoint(x: 78,y: 46), control2: CGPoint(x: 116,y: 46)); hair.addQuadCurve(to: CGPoint(x: 86,y: 65), control: CGPoint(x: 91,y: 57)); context.fill(hair, with: .color(Color(hex: 0x172E26)))
            line([CGPoint(x: 153,y: 87),CGPoint(x: 160,y: 82)], Palette.lime.opacity(0.4), 1)
            line([CGPoint(x: 155,y: 98),CGPoint(x: 165,y: 99)], Palette.lime.opacity(0.4), 1)
            line([CGPoint(x: 45,y: 80),CGPoint(x: 38,y: 76)], Palette.lime.opacity(0.4), 1)
        }
    }
}

struct PlansView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max").font(.system(size: 25, weight: .light))
                VStack(alignment: .leading, spacing: 6) { Text("休息，是工作节奏的一部分。").font(.custom("Songti SC", size: 24)); Text("分别调整间隔，按你的习惯来。修改后，该项会重新开始计时。").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Palette.sidebar).clipShape(RoundedRectangle(cornerRadius: 16))
            ForEach(ReminderKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 13) {
                        Image(systemName: kind.symbol).font(.system(size: 23, weight: .light)).foregroundStyle(kind.color).frame(width: 49, height: 49).background(kind.wash).clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) { Text(kind.title).font(.system(size: 16, weight: .semibold)); Text(kind.message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        Spacer()
                        Toggle("开启\(kind.title)", isOn: Binding(get: { model.preferences[kind].enabled }, set: { value in model.editPreferences { $0[kind].enabled = value } })).labelsHidden().toggleStyle(.switch).accessibilityLabel("开启\(kind.title)")
                    }
                    HStack(spacing: 20) {
                        Text("提醒间隔").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Stepper(value: Binding(get: { model.preferences[kind].intervalMinutes }, set: { value in model.editPreferences { $0[kind].intervalMinutes = value } }), in: 1...180) { Text("每 \(model.preferences[kind].intervalMinutes) 分钟").font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 103, alignment: .leading) }.fixedSize()
                        ForEach([20, 30, 45, 60], id: \.self) { interval in
                            Button("\(interval) 分") { model.editPreferences { $0[kind].intervalMinutes = interval } }.buttonStyle(QuietButton())
                        }
                        Spacer()
                    }.disabled(!model.preferences[kind].enabled)
                    if kind != .water {
                        HStack(spacing: 20) {
                            Text("休息时长").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            BreakDurationPicker(kind: kind, duration: Binding(get: { model.preferences[kind].durationSeconds }, set: { value in model.editPreferences { $0[kind].durationSeconds = value } }))
                            Text("倒计时结束后确认，才会计入统计").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }.disabled(!model.preferences[kind].enabled)
                    }
                }.padding(23).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
            }
            RoutinePlanningView(model: model)
            Text("提示：每项提醒都可以稍后 5 分钟；暂停后恢复、电脑唤醒及新提醒时段开始时，间隔会重新计时。").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}

struct BreakDurationPicker: View {
    let kind: ReminderKind
    @Binding var duration: Int
    @State private var showingCustom = false

    var body: some View {
        Picker("\(kind.title)时长", selection: Binding(get: { duration }, set: { value in
            if value == -1 { showingCustom = true }
            else { duration = value }
        })) {
            ForEach(BreakDuration.presets, id: \.self) { seconds in
                Text(BreakDuration.label(seconds)).tag(seconds)
            }
            if !BreakDuration.presets.contains(duration) {
                Text("\(BreakDuration.label(duration))（自定义）").tag(duration)
            }
            Text("自定义…").tag(-1)
        }
        .labelsHidden().frame(width: 170)
        .sheet(isPresented: $showingCustom) {
            CustomBreakDurationView(kind: kind, duration: duration) { duration = $0 }
        }
    }
}

struct CustomBreakDurationView: View {
    let kind: ReminderKind
    let onSave: (Int) -> Void
    @State private var minutes: String
    @State private var seconds: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var minutesFocused: Bool

    init(kind: ReminderKind, duration: Int, onSave: @escaping (Int) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _minutes = State(initialValue: String(duration / 60))
        _seconds = State(initialValue: String(duration % 60))
    }

    private var value: Int? { BreakDuration.parse(minutes: minutes, seconds: seconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("自定义休息时长").font(.system(size: 20, weight: .semibold))
                Text("为\(kind.title)留出适合自己的时间。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 10) {
                TextField("分钟", text: $minutes).frame(width: 72).focused($minutesFocused)
                    .accessibilityLabel("自定义休息分钟数")
                Text("分钟")
                TextField("秒", text: $seconds).frame(width: 72)
                    .accessibilityLabel("自定义休息秒数")
                Text("秒")
            }.textFieldStyle(.roundedBorder).font(.system(size: 16)).monospacedDigit()
            Text(value == nil ? "请输入整数，秒数为 0–59，总时长为 10 秒至 10 分钟。" : "支持 10 秒至 10 分钟。例如：3 分钟 0 秒。")
                .font(.system(size: 11)).foregroundStyle(value == nil ? Palette.stretch : Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(value == nil)
            }
        }
        .padding(28).frame(width: 420).foregroundStyle(Palette.ink).background(Palette.background)
        .tint(Palette.green)
        .onAppear { minutesFocused = true }
        .onSubmit { save() }
    }

    private func save() {
        guard let value else { return }
        onSave(value)
        dismiss()
    }
}

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                metric("今日饮水", value: "\(model.today.waterML)", unit: "ml", symbol: "drop", color: Palette.water)
                metric("今日休息", value: "\(model.today.breakCount)", unit: "次", symbol: "leaf", color: Palette.eyes)
                metric("累计工作", value: "\(Int(model.today.workSeconds / 60))", unit: "分钟", symbol: "clock", color: Palette.stretch)
            }
            ReminderInsights(model: model)
            PeriodReviewView(model: model)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日最长一轮（估算）").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(minutesText(model.today.longestSittingSeconds)).font(.system(size: 24, weight: .light, design: .rounded))
                    Text("回顾今天连续使用电脑的最长时段").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Palette.line).frame(width: 1, height: 67)
                VStack(alignment: .leading, spacing: 10) {
                    Text("今天留给自己的时间").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text("\(model.today.breakSeconds / 60) 分 \(model.today.breakSeconds % 60) 秒").font(.system(size: 24, weight: .light, design: .rounded))
                    Text("只统计完成并确认的护眼与拉伸休息").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(24).background(Palette.sidebar).clipShape(RoundedRectangle(cornerRadius: 16))
            RecordManagementCard(model: model)
            TimingHistoryView(model: model)
            HStack { Text("使用与工作时长为应用运行期间的计时估算，暂停、休息与睡眠不累计。\n缓芽不使用摄像头或传感器识别坐姿；退出应用后不计时、不提醒。").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(5); Spacer(); Button { model.exportCSV() } label: { Label("导出 CSV", systemImage: "square.and.arrow.up") }.buttonStyle(QuietButton()) }
        }
    }
    func metric(_ name: String, value: String, unit: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text(name).font(.system(size: 12)).foregroundStyle(Palette.muted); Spacer(); Image(systemName: symbol).foregroundStyle(color) }
            HStack(alignment: .firstTextBaseline) { Text(value).font(.system(size: 31, weight: .light, design: .rounded)).monospacedDigit(); Text(unit).font(.system(size: 11)).foregroundStyle(Palette.muted) }
        }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("提醒方式", symbol: "bell") {
                settingRow("浮窗提醒", detail: "到时间在桌面弹出轻量提醒；关闭后使用 macOS 系统通知。") { Toggle("浮窗提醒", isOn: boolBinding(\.floatingReminder)).labelsHidden().toggleStyle(.switch) }
                Divider().overlay(Palette.line)
                settingRow("提示音", detail: "让每次小休息，都有一个轻轻的提示。") { Toggle("提示音", isOn: boolBinding(\.sound)).labelsHidden().toggleStyle(.switch) }
                Divider().overlay(Palette.line)
                settingRow("系统通知 · \(model.notificationStatus)", detail: model.preferences.floatingReminder ? "当前使用浮窗，可在这里开启系统通知备用。" : "使用系统通知需要授权；请在系统设置中允许提醒。") {
                    Button(model.notificationsAllowed ? "系统设置" : "允许通知") { if model.notificationStatus == "系统已关闭" || model.notificationsAllowed { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) } else { model.requestNotifications() } }.buttonStyle(QuietButton())
                }
                if !model.preferences.floatingReminder && !model.notificationsAllowed { Text("系统通知尚未允许，目前不会弹出定时提醒。可开启浮窗，或允许系统通知。").font(.system(size: 11)).foregroundStyle(Palette.stretch) }
                Button("预览一次提醒") { model.trigger(.eyes) }.buttonStyle(QuietButton())
            }
            settingsGroup("提醒时段", symbol: "clock") {
                if model.preferences.weeklyRoutineEnabled {
                    HStack { Text("已使用每周作息，每日时段规则暂不生效。").font(.system(size: 12)); Spacer(); Button("前往提醒计划") { model.page = "提醒计划" }.buttonStyle(QuietButton()) }
                }
                Group {
                settingRow("仅在指定时段提醒", detail: "时段外不提醒、不累计工作计时；结束时间不包含在内。") { Toggle("仅在指定时段提醒", isOn: boolBinding(\.workHoursOnly)).labelsHidden().toggleStyle(.switch) }
                if model.preferences.workHoursOnly {
                    HStack(spacing: 12) {
                        Text("每天").foregroundStyle(Palette.muted)
                        hourPicker(\.startHour)
                        Text("至").foregroundStyle(Palette.muted)
                        hourPicker(\.endHour)
                        Text(model.preferences.startHour == model.preferences.endHour ? "相同时间表示全天" : model.preferences.startHour > model.preferences.endHour ? "跨午夜时段" : "本机时区").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Spacer()
                    }
                }
                Divider().overlay(Palette.line)
                settingRow("周末休息", detail: "开启后，周六和周日全天不提醒。") { Toggle("周末休息", isOn: boolBinding(\.weekdaysOnly)).labelsHidden().toggleStyle(.switch) }
                }.disabled(model.preferences.weeklyRoutineEnabled)
            }
            rhythmSettings
            busySettings
            settingsGroup("动作与快捷操作", symbol: "keyboard") {
                settingRow("拉伸动作图卡", detail: "肩膀、手腕、走动每 20 秒自动切换，也可手动换一张。") {
                    Toggle("拉伸动作图卡", isOn: boolBinding(\.stretchCardsEnabled)).labelsHidden().toggleStyle(.switch)
                }
                Divider().overlay(Palette.line)
                settingRow("菜单栏显示倒计时", detail: "显示距离下次提醒的时间；暂停和休息时显示对应状态。") {
                    Toggle("菜单栏倒计时", isOn: boolBinding(\.showMenuCountdown)).labelsHidden().toggleStyle(.switch)
                }
                Divider().overlay(Palette.line)
                settingRow("全局快捷键 · \(model.shortcutStatus)", detail: "⌃⌥⌘W 记默认杯量；⌃⌥⌘R 开始拉伸休息。") {
                    Toggle("全局快捷键", isOn: boolBinding(\.globalShortcutsEnabled)).labelsHidden().toggleStyle(.switch).disabled(model.isPreview)
                }
                Text("快捷键默认关闭，只注册指定组合，不读取其他键盘输入。缓芽运行时可用；若组合被占用，会显示提示。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            settingsGroup("启动与后台", symbol: "power") {
                settingRow("登录时启动 · \(model.launchAtLoginStatus.description)", detail: "开启后，登录 Mac 自动在菜单栏运行，不弹出主窗口。") {
                    Toggle("登录时启动", isOn: Binding(get: { model.launchAtLoginStatus.isSelected }, set: { model.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch).disabled(model.isPreview)
                }
                if model.launchAtLoginStatus == .requiresApproval {
                    Button("前往系统登录项设置") { model.openLoginSettings() }.buttonStyle(QuietButton())
                }
                Text(model.isPreview ? "预览不会更改系统登录项；安装到应用程序后可开启。" : "关闭主窗口后仍在菜单栏运行，按 ⌘Q 完全退出。登录项状态以系统实际设置为准。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            settingsGroup("每日小目标", symbol: "flag") {
                HStack(spacing: 18) {
                    Text("每杯饮水").foregroundStyle(Palette.muted)
                    Stepper("\(model.preferences.waterML) ml", value: intBinding(\.waterML), in: 50...1000, step: 50).frame(width: 130)
                    Spacer()
                    Text("每日目标").foregroundStyle(Palette.muted)
                    Stepper("\(model.preferences.waterGoalML) ml", value: intBinding(\.waterGoalML), in: 250...6000, step: 250).frame(width: 145)
                }.font(.system(size: 12))
                Divider().overlay(Palette.line)
                HStack { Text("护眼 / 拉伸各项目标").font(.system(size: 12)).foregroundStyle(Palette.muted); Spacer(); Stepper("\(model.preferences.breakGoal) 次 / 天", value: intBinding(\.breakGoal), in: 1...30).frame(width: 145) }
                Divider().overlay(Palette.line)
                Text("菜单栏快捷杯量").font(.system(size: 12, weight: .medium))
                HStack(spacing: 20) {
                    ForEach(0..<3, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("快捷杯 \(index + 1)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            Stepper("\(model.preferences.waterPresets[index]) ml", value: Binding(get: { model.preferences.waterPresets[index] }, set: { value in model.editPreferences { $0.waterPresets[index] = value } }), in: 50...1000, step: 50).font(.system(size: 12)).frame(maxWidth: .infinity)
                        }
                    }
                }
                Text("目标仅用于记录进度，可按自己的习惯调整。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .top, spacing: 14) {
                BrandMark().frame(width: 35, height: 37)
                VStack(alignment: .leading, spacing: 6) {
                    Text("缓芽 · huǎn yá  ·  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")").font(.system(size: 13, weight: .medium))
                    Text("一个照顾自己的小小提醒。关闭窗口后仍在菜单栏运行，按 ⌘Q 完全退出。\n所有数据保存在 ~/Library/Application Support/RiseUp，不联网、不上传。\n电脑睡眠时不提醒，唤醒后重新计时；可选择登录时自动启动。").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(5)
                }
            }.padding(.vertical, 4)
        }
    }
    private var rhythmSettings: some View {
        settingsGroup("提醒节奏", symbol: "leaf") {
            settingRow("空闲自动暂停", detail: "持续没有键鼠操作时暂停计时，返回后重新安排提醒。") {
                Toggle("空闲自动暂停", isOn: boolBinding(\.idlePauseEnabled)).labelsHidden().toggleStyle(.switch)
            }
            if model.preferences.idlePauseEnabled {
                HStack {
                    Text("空闲多久后暂停").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Stepper("\(model.preferences.idlePauseMinutes) 分钟", value: intBinding(\.idlePauseMinutes), in: 1...30).font(.system(size: 12)).frame(width: 140)
                }
            }
            Text("只读取未操作时长，不记录按键内容。空闲或锁屏满 5 分钟会重置本轮估算，不增加休息次数；提醒的空闲暂停阈值仍按上方设置生效，锁屏始终暂停提醒。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Divider().overlay(Palette.line)
            settingRow("合并临近提醒", detail: "放在同一个面板中，喝水、护眼和拉伸仍分别确认。") {
                Toggle("合并临近提醒", isOn: boolBinding(\.mergeReminders)).labelsHidden().toggleStyle(.switch)
            }
            if model.preferences.mergeReminders {
                HStack {
                    Text("相差多久可以合并").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Picker("合并范围", selection: intBinding(\.mergeWindowSeconds)) {
                        Text("仅同时到期").tag(0)
                        ForEach([60, 120, 180, 300], id: \.self) { value in Text("\(value / 60) 分钟内").tag(value) }
                    }.labelsHidden().frame(width: 140)
                }
                Text("合并到最早一项的提醒时间，可能提前；选择稍后 5 分钟的项目不会被提前。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Divider().overlay(Palette.line)
            settingRow("休息前轻声预告", detail: "提前显示安静的小提示，给你一点收尾时间。") {
                Toggle("休息前预告", isOn: boolBinding(\.prewarningEnabled)).labelsHidden().toggleStyle(.switch)
            }
            if model.preferences.prewarningEnabled {
                HStack {
                    Text("提前多久预告").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Picker("预告时间", selection: intBinding(\.prewarningSeconds)) { ForEach([10, 15, 30, 60], id: \.self) { Text("\($0) 秒").tag($0) } }.labelsHidden().frame(width: 140)
                }
            }
        }
    }
    private var busySettings: some View {
        settingsGroup("忙碌模式", symbol: "moon") {
            Text(model.status).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
            BusyControls(model: model)
            Text("忙碌期间不弹提醒、不累计工作时间；结束后重新计时。忙碌结束不会解除手动暂停。退出缓芽后，本次忙碌倒计时不保留。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Divider().overlay(Palette.line)
            settingRow("在这些应用中暂停", detail: "指定应用在前台时暂停并保留剩余时间；切换离开后继续倒计时。") {
                Button("添加应用…") { model.chooseBusyApplication() }.buttonStyle(QuietButton())
            }
            ForEach(model.preferences.busyApplications) { app in
                HStack {
                    Image(systemName: "app").foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 3) { Text(app.name).font(.system(size: 12)); Text(app.bundleIdentifier).font(.system(size: 9)).foregroundStyle(Palette.muted) }
                    Spacer()
                    Button("移除") { model.editPreferences { $0.busyApplications.removeAll { $0.id == app.id } } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.green)
                }
            }
            Text(model.preferences.busyApplications.isEmpty ? "尚未添加应用。只读取前台应用标识，不读取窗口内容，不保存应用使用历史。" : "只读取前台应用标识；手动暂停、锁屏和工作时段规则仍然生效。").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
    func boolBinding(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> { Binding(get: { model.preferences[keyPath: key] }, set: { value in model.editPreferences { $0[keyPath: key] = value } }) }
    func intBinding(_ key: WritableKeyPath<Preferences, Int>) -> Binding<Int> { Binding(get: { model.preferences[keyPath: key] }, set: { value in model.editPreferences { $0[keyPath: key] = value } }) }
    func hourPicker(_ key: WritableKeyPath<Preferences, Int>) -> some View { Picker("时间", selection: intBinding(key)) { ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d:00", hour)).tag(hour) } }.labelsHidden().frame(width: 100) }
    func settingsGroup<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) { Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold)); content() }.padding(23).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
    }
    func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 18) { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer(); control() }
    }
}

struct BusyControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            ForEach([30, 60], id: \.self) { minutes in
                Button("忙碌 \(minutes) 分") { model.startBusy(minutes: minutes) }.buttonStyle(QuietButton())
            }
            if model.engine.busyUntil != nil {
                Button("结束忙碌") { model.endBusy() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.green)
            }
        }
    }
}

struct StretchGuide: View {
    @ObservedObject var model: AppModel
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            StretchFigure(card: model.stretchCard).frame(width: compact ? 56 : 78, height: compact ? 76 : 106).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.stretchCard.title).font(.system(size: compact ? 12 : 14, weight: .semibold))
                    Spacer(minLength: 3)
                    Button { model.cycleStretchCard() } label: { Image(systemName: "arrow.right.circle") }.buttonStyle(.plain).accessibilityLabel("换一个拉伸动作").help("手动切换，20 秒后继续自动切换")
                }.foregroundStyle(Palette.green)
                Text(model.stretchCard.instruction).font(.system(size: compact ? 10 : 11)).foregroundStyle(Palette.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Text("\(model.stretchCard.rawValue + 1) / 3 · 每 20 秒自动换一张").font(.system(size: 9)).foregroundStyle(Palette.stretch)
            }
        }.padding(compact ? 10 : 15).frame(maxWidth: .infinity).background(ReminderKind.stretch.wash).clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct StretchFigure: View {
    let card: StretchCard
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 80, y: size.height / 110)
            func stroke(_ points: [CGPoint], color: Color = Palette.green, width: CGFloat = 5) {
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: 29, y: 8, width: 19, height: 19)), with: .color(Palette.green))
            stroke([CGPoint(x: 39,y: 34), CGPoint(x: 39,y: 68)], width: 9)
            if card == .walk {
                stroke([CGPoint(x: 39,y: 39),CGPoint(x: 21,y: 49),CGPoint(x: 12,y: 40)])
                stroke([CGPoint(x: 39,y: 39),CGPoint(x: 54,y: 47),CGPoint(x: 67,y: 36)])
                stroke([CGPoint(x: 39,y: 67),CGPoint(x: 24,y: 82),CGPoint(x: 18,y: 102)])
                stroke([CGPoint(x: 39,y: 67),CGPoint(x: 51,y: 90),CGPoint(x: 67,y: 98)])
            } else {
                stroke([CGPoint(x: 39,y: 67),CGPoint(x: 26,y: 101)])
                stroke([CGPoint(x: 39,y: 67),CGPoint(x: 52,y: 101)])
                if card == .shoulders {
                    stroke([CGPoint(x: 39,y: 38),CGPoint(x: 20,y: 35),CGPoint(x: 12,y: 19)])
                    stroke([CGPoint(x: 39,y: 38),CGPoint(x: 58,y: 35),CGPoint(x: 67,y: 19)])
                    stroke([CGPoint(x: 15,y: 61),CGPoint(x: 15,y: 51),CGPoint(x: 11,y: 55)], color: Palette.stretch, width: 2)
                    stroke([CGPoint(x: 64,y: 61),CGPoint(x: 64,y: 51),CGPoint(x: 68,y: 55)], color: Palette.stretch, width: 2)
                } else {
                    stroke([CGPoint(x: 39,y: 37),CGPoint(x: 22,y: 51),CGPoint(x: 12,y: 46)])
                    stroke([CGPoint(x: 39,y: 37),CGPoint(x: 55,y: 51),CGPoint(x: 68,y: 46)])
                    context.stroke(Path(ellipseIn: CGRect(x: 1, y: 36, width: 19, height: 19)), with: .color(Palette.stretch), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    context.stroke(Path(ellipseIn: CGRect(x: 59, y: 36, width: 19, height: 19)), with: .color(Palette.stretch), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            stroke([CGPoint(x: 7,y: 107),CGPoint(x: 73,y: 107)], color: Palette.stretch.opacity(0.3), width: 1)
        }
    }
}

struct ReminderInsights: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(title: "今天的节奏", caption: "MAKE ROOM FOR A PAUSE")
            HStack(spacing: 0) {
                count("到期提醒", model.today.remindersDue)
                count("选择延后", model.today.remindersSnoozed)
                count("主动跳过", model.today.remindersSkipped)
            }
            Text("按项目计数，合并的三项计三次。延后可重复累计；跳过仅指主动点击跳过。锁屏、空闲、忙碌不记为忽略。").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
            Divider().overlay(Palette.line)
            HStack { Text("各时段工作量").font(.system(size: 12, weight: .medium)); Spacer(); Text("每格 1 小时 · 悬停查看详情").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            HourlyWorkChart(seconds: model.today.hourlyWorkSeconds, currentHour: Calendar.current.component(.hour, from: model.now))
            HStack { Text("00:00"); Spacer(); Text("06:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00"); Spacer(); Text("24:00") }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            Text("连续工作较久的时段 · 20 分钟起").font(.system(size: 12, weight: .medium))
            if model.longWorkPeriods.isEmpty {
                Text("今天还没有记录到连续工作 20 分钟的时段。").font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                ForEach(Array(model.longWorkPeriods.prefix(3))) { period in
                    HStack {
                        Text("\(period.start.formatted(date: .omitted, time: .shortened)) – \(period.end.formatted(date: .omitted, time: .shortened))").monospacedDigit()
                        Spacer()
                        Text(minutesText(period.seconds)).foregroundStyle(Palette.green)
                    }.font(.system(size: 12))
                }
            }
            Text("连续工作时段在休息、暂停、空闲或睡眠时结束；最多保留最近 1000 段明细。").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
        }.padding(24).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
    }
    private func count(_ title: String, _ number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted); Text("\(number)").font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HourlyWorkChart: View {
    let seconds: [Double]
    let currentHour: Int
    @State private var hoveredHour: Int?

    init(seconds: [Double], currentHour: Int, previewHour: Int? = nil) {
        self.seconds = seconds
        self.currentHour = currentHour
        _hoveredHour = State(initialValue: previewHour)
    }

    private func detail(_ hour: Int) -> HourlyWorkDetail {
        HourlyWorkDetail(hour: hour, seconds: seconds.indices.contains(hour) ? seconds[hour] : 0, currentHour: currentHour)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        let bucket = detail(hour)
                        let selected = hoveredHour == hour
                        RoundedRectangle(cornerRadius: 3)
                            .fill(selected || hour == currentHour ? Palette.green : Palette.green.opacity(bucket.isFuture ? 0.18 : 0.35))
                            .frame(height: max(3, min(72, bucket.seconds / 3600 * 72)))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 2.5)
                            .padding(.bottom, 4)
                            .frame(height: 80, alignment: .bottom)
                            .background(selected ? Palette.sidebar : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(bucket.rangeLabel)
                            .accessibilityValue(bucket.summary)
                    }
                }.padding(.top, 64)
                if let hour = hoveredHour {
                    let bucket = detail(hour)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(bucket.rangeLabel).monospacedDigit()
                            if hour == currentHour { Text("本小时").foregroundStyle(Palette.muted) }
                        }.font(.system(size: 10))
                        Text(bucket.summary).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(width: min(176, geometry.size.width), height: 56)
                    .foregroundStyle(Palette.green)
                    .background(Palette.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
                    .shadow(color: Palette.green.opacity(0.09), radius: 6, y: 2)
                    .position(x: HourlyWorkDetail.tooltipCenter(hour: hour, width: geometry.size.width, tooltipWidth: 176), y: 28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if location.y >= 64 {
                        hoveredHour = HourlyWorkDetail.hour(at: location.x, width: geometry.size.width)
                    }
                case .ended: hoveredHour = nil
                }
            }
        }
        .frame(height: 144)
        .onChange(of: currentHour) { _ in hoveredHour = nil }
        .onDisappear { hoveredHour = nil }
    }
}

struct WaterQuickButtons: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                let amount = model.preferences.waterPresets[index]
                Button { model.logWater(amount: amount) } label: {
                    Text("+ \(amount) ml").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(ReminderKind.water.wash).foregroundStyle(Palette.water)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("记录 \(amount) 毫升饮水")
            }
        }
    }
}

struct ReminderPopup: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
        VStack(spacing: model.reminderKinds.count > 1 ? 15 : 17) {
            HStack {
                Text("缓芽  /  huǎn yá").font(.system(size: 10, weight: .medium)).tracking(1.7).foregroundStyle(Palette.muted)
                Spacer()
                Button { model.snoozeCurrent() } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).accessibilityLabel("全部稍后 5 分钟")
            }
            if model.reminderKinds.count > 1 {
                VStack(spacing: 8) {
                    Text("一起，休息一下。").font(.custom("Songti SC", size: 27)).foregroundStyle(Palette.ink)
                    Text("提醒时间接近，放在一起了。每一项都分别记录。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(.vertical, 4)
                ForEach(model.reminderKinds) { kind in ReminderRow(model: model, kind: kind) }
                if model.canUndoWater { Button("撤销最近一杯饮水") { model.undoWater() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.water) }
            } else {
                singleReminder
            }
            Button(model.activeBreak == nil ? "全部 5 分钟后提醒" : "结束本次 · 不计入统计") { model.snoozeCurrent() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button(model.plannedReminder == nil ? "本次跳过 · 下个间隔再提醒" : "本次跳过 · 按原计划再提醒") { model.skipReminder() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(25).frame(width: 410)
        }.scrollIndicators(.hidden).frame(width: 410, height: model.reminderPanelHeight)
            .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(Palette.line)).preferredColorScheme(.light)
    }
    private var singleReminder: some View {
        let kind = model.currentReminder ?? .stretch
        return VStack(spacing: 17) {
            Image(systemName: kind.symbol).font(.system(size: 38, weight: .ultraLight)).foregroundStyle(kind.color).frame(width: 82, height: 82).background(kind.wash).clipShape(Circle()).padding(.top, 5)
            Text(model.activeBreak != nil ? (model.breakRemaining > 0 ? "这一刻，留给自己。" : "休息好了，真不错。") : model.reminderTitle(kind)).font(.custom("Songti SC", size: 28)).foregroundStyle(Palette.ink)
            Text(kind.message).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 330)
            if kind == .stretch && model.preferences.stretchCardsEnabled { StretchGuide(model: model) }
            if model.activeBreak != nil {
                Text(clockText(model.breakRemaining)).font(.system(size: 45, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Palette.green)
                Button("完成休息 ✓") { model.finishReminder() }.buttonStyle(PrimaryButton()).disabled(model.breakRemaining > 0).opacity(model.breakRemaining > 0 ? 0.4 : 1)
            } else if kind == .water {
                WaterQuickButtons(model: model).padding(.top, 4)
                Button("喝好了，记 \(model.preferences.waterML) ml") { model.logWater() }.buttonStyle(PrimaryButton())
            } else {
                Text("给自己 \(BreakDuration.label(model.reminderDuration(kind)))，慢慢来").font(.system(size: 11)).foregroundStyle(kind.color)
                Button("开始休息") { model.startBreak() }.buttonStyle(PrimaryButton())
            }
        }
    }
}

struct ReminderRow: View {
    @ObservedObject var model: AppModel
    let kind: ReminderKind
    private var running: Bool { model.activeBreak?.kind == kind }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: kind.symbol).font(.system(size: 18, weight: .light)).foregroundStyle(kind.color).frame(width: 32, height: 32).background(kind.wash).clipShape(RoundedRectangle(cornerRadius: 9))
                Text(model.reminderTitle(kind)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Button("跳过") { model.skipReminder(kind) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
                Button("稍后 5 分钟") { model.snooze(kind) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if kind == .water {
                WaterQuickButtons(model: model)
                Button("按默认杯量记录 · \(model.preferences.waterML) ml") { model.logWater() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.water)
            } else {
                if kind == .stretch && model.preferences.stretchCardsEnabled { StretchGuide(model: model, compact: true) }
                else { Text(kind.message).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2) }
                HStack {
                    if running {
                        Text(clockText(model.breakRemaining)).font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Palette.green)
                        Spacer()
                        Button("完成\(kind.short) ✓") { model.finishReminder(kind) }.buttonStyle(QuietButton()).disabled(model.breakRemaining > 0)
                    } else {
                        Button("开始 \(BreakDuration.label(model.reminderDuration(kind)))休息") { model.startBreak(kind) }.buttonStyle(QuietButton()).disabled(model.activeBreak != nil)
                        if model.activeBreak != nil { Text("当前休息完成后可开始").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                    }
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line))
    }
}

struct PrewarningView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "leaf").foregroundStyle(Palette.green)
                Text("还有 \(model.prewarningRemaining) 秒，休息一下").font(.system(size: 13, weight: .medium))
                Spacer()
                Button { model.dismissPrewarning() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("收起预告，保留到时提醒")
            }
            HStack {
                Text(model.prewarning?.title ?? "给自己一点时间收尾。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("现在休息 ↗") { model.takePrewarningNow() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
            }
        }.padding(19).frame(width: 360, height: 112).foregroundStyle(Palette.ink).background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Palette.line)).preferredColorScheme(.light)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) { BrandMark().frame(width: 31, height: 33); VStack(alignment: .leading, spacing: 3) { Text("缓芽 · huǎn yá").font(.system(size: 14, weight: .semibold)); Text(model.status).font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer() }
            HStack { Text(model.nextBatch.map { "下次\($0.title)" } ?? "下次提醒").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Text(model.countdown).font(.system(size: 25, weight: .light, design: .rounded)).monospacedDigit() }
            Divider()
            HStack { Label("\(model.today.waterML) ml", systemImage: "drop"); Spacer(); Label("休息 \(model.today.breakCount) 次", systemImage: "leaf") }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            WaterQuickButtons(model: model)
            if model.canUndoWater {
                Button("撤销最近一杯饮水") { model.undoWater() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.water)
            }
            HStack { Button("+ 默认杯量") { model.logWater() }.buttonStyle(QuietButton()); Button("起身休息") { model.quickRest() }.buttonStyle(QuietButton()) }
            BusyControls(model: model)
            HStack { Button(model.hasManualPause ? "继续提醒" : "暂停 15 分钟") { model.togglePause(minutes: 15) }.buttonStyle(.plain); Spacer(); Button("打开缓芽 ↗") { model.showMainWindow?() }.buttonStyle(.plain) }.font(.system(size: 11)).foregroundStyle(Palette.green)
            Divider()
            Button("退出缓芽  ⌘Q") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(20).frame(width: 303).foregroundStyle(Palette.ink).background(Palette.background).preferredColorScheme(.light)
    }
}
