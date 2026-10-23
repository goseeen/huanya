import SwiftUI
import AppKit

struct FeatureCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            content
        }.padding(23).frame(maxWidth: .infinity, alignment: .leading).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
    }
}

struct RoutinePlanningView: View {
    @ObservedObject var model: AppModel
    @State private var editingRoutine = false
    @State private var editingPlan: PlannedBreak?
    var body: some View {
        VStack(spacing: 20) {
            FeatureCard(title: "按自己的作息来", subtitle: "午休留白、周末休息，或给不同工作日安排不同的时段。") {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.preferences.routineSummary).font(.system(size: 13, weight: .medium))
                        Text(model.preferences.weeklyRoutineEnabled ? "时段外不提醒，也不累计工作时间。" : "当前使用设置中的每日时段规则。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("编辑每周作息") { editingRoutine = true }.buttonStyle(QuietButton())
                }
                if model.preferences.weeklyRoutineEnabled {
                    ForEach(model.preferences.weeklyRoutine.filter(\.enabled)) { day in
                        HStack { Text(day.title).frame(width: 44, alignment: .leading); Text(day.windows.sorted { $0.start < $1.start }.map(\.label).joined(separator: "  /  ")); Spacer() }.font(.system(size: 11)).monospacedDigit()
                    }
                    Button("改用每日时段规则") { model.editPreferences { $0.weeklyRoutineEnabled = false } }.buttonStyle(.plain).foregroundStyle(Palette.muted).font(.system(size: 11))
                }
            }
            FeatureCard(title: "小休息之间，留一次长休息", subtitle: "每完成几次起身拉伸，下一次多休息一会儿。仍需确认完成；跳过不推进次数。") {
                HStack {
                    Toggle("穿插长休息", isOn: Binding(get: { model.preferences.longBreak.enabled }, set: { value in model.editPreferences { $0.longBreak.enabled = value } })).toggleStyle(.switch)
                    Spacer()
                    Stepper("每 \(model.preferences.longBreak.every) 次拉伸", value: Binding(get: { model.preferences.longBreak.every }, set: { value in model.editPreferences { $0.longBreak.every = value } }), in: 2...12).fixedSize()
                    Stepper("长休息 \(model.preferences.longBreak.durationSeconds / 60) 分钟", value: Binding(get: { model.preferences.longBreak.durationSeconds / 60 }, set: { value in model.editPreferences { $0.longBreak.durationSeconds = value * 60 } }), in: 1...30).fixedSize().padding(.leading, 12)
                }.font(.system(size: 12))
                if model.preferences.longBreak.enabled {
                    Text("本轮已完成 \(model.engine.saved.stretchCycle) 次拉伸；第 \(model.preferences.longBreak.every) 次为长休息。修改这项规则会重新开始一轮。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            FeatureCard(title: "给一天留几个固定的空隙", subtitle: "例如午间走走、下午远眺。固定提醒独立于工作时段，仍遵守暂停、忙碌、指定应用和锁屏规则。") {
                if model.preferences.plannedBreaks.isEmpty {
                    Text("还没有固定提醒。添加一项，给每天一个休息的约定。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                ForEach(model.preferences.plannedBreaks) { plan in
                    HStack(spacing: 14) {
                        Toggle(plan.name, isOn: Binding(get: { model.preferences.plannedBreaks.first(where: { $0.id == plan.id })?.enabled ?? false }, set: { value in model.editPreferences { p in if let i = p.plannedBreaks.firstIndex(where: { $0.id == plan.id }) { p.plannedBreaks[i].enabled = value } } })).labelsHidden().toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name).font(.system(size: 13, weight: .medium))
                            Text("\(WorkWindow.clock(plan.minute)) · \(plan.weekdays.sorted().map { WeekdayRoutine(weekday: $0).title }.joined(separator: "、")) · \(BreakDuration.label(plan.durationSeconds))").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("编辑") { editingPlan = plan }.buttonStyle(QuietButton())
                    }
                }
                HStack {
                    Button { editingPlan = PlannedBreak() } label: { Label("添加固定提醒", systemImage: "plus") }.buttonStyle(QuietButton()).disabled(model.preferences.plannedBreaks.count >= 20)
                    Text("已有休息时不叠加；错过超过 1 分钟不补发。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
        .sheet(isPresented: $editingRoutine) { WeeklyRoutineEditor(model: model) }
        .sheet(item: $editingPlan) { plan in PlannedBreakEditor(model: model, plan: plan) }
    }
}

struct MinutePicker: View {
    let title: String
    @Binding var minute: Int
    var allowsMidnightEnd = false
    private var date: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60))! }, set: { minute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        HStack(spacing: 4) {
            if minute == 1440 { Text("24:00").monospacedDigit().frame(width: 94); Button("更改") { minute = 23 * 60 }.buttonStyle(.plain).font(.system(size: 10)) }
            else {
                DatePicker(title, selection: date, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 110).accessibilityLabel(title)
                if allowsMidnightEnd { Button("至午夜") { minute = 1440 }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(Palette.muted).help("将结束时间设为当天午夜") }
            }
        }
    }
}

struct WeeklyRoutineEditor: View {
    @ObservedObject var model: AppModel
    @State private var draft: [WeekdayRoutine]
    @State private var enabled: Bool
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel) { self.model = model; _draft = State(initialValue: model.preferences.weeklyRoutine); _enabled = State(initialValue: model.preferences.weeklyRoutineEnabled) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每周作息").font(.system(size: 22, weight: .semibold))
            Text("留出午休，给不同的日子不同的节奏。时间以本机时区为准，结束时间不包含在内。").font(.system(size: 11)).foregroundStyle(Palette.muted)
            Toggle("使用每周作息", isOn: $enabled).toggleStyle(.switch)
            HStack {
                Text("从模板开始").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Button("工作日 · 午休一小时") { draft = WeekdayRoutine.standard; enabled = true }.buttonStyle(QuietButton())
                Button("工作日 · 弹性下午") { draft = WeekdayRoutine.standard.map { var d = $0; d.windows = [WorkWindow(start: 13 * 60, end: 18 * 60), WorkWindow(start: 19 * 60, end: 21 * 60)]; return d }; enabled = true }.buttonStyle(QuietButton())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach($draft) { $day in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle(day.title, isOn: $day.enabled).toggleStyle(.checkbox).frame(width: 75, alignment: .leading)
                                if !day.enabled { Text("休息日").foregroundStyle(Palette.muted) }
                                Spacer()
                                if day.enabled {
                                    Button("复制到工作日") { let windows = day.windows; for i in draft.indices where (2...6).contains(draft[i].weekday) { draft[i].enabled = true; draft[i].windows = windows.map { WorkWindow(start: $0.start, end: $0.end) } } }.buttonStyle(.plain).font(.system(size: 10))
                                    Button("添加时段") { day.windows.append(WorkWindow(start: 19 * 60, end: 21 * 60)) }.buttonStyle(.plain).disabled(day.windows.count >= 4).font(.system(size: 10))
                                }
                            }
                            if day.enabled {
                                ForEach($day.windows) { $window in
                                    HStack(spacing: 12) {
                                        MinutePicker(title: "\(day.title)开始时间", minute: $window.start)
                                        Text("至").foregroundStyle(Palette.muted)
                                        MinutePicker(title: "\(day.title)结束时间", minute: $window.end, allowsMidnightEnd: true)
                                        Spacer()
                                        Button { day.windows.removeAll { $0.id == window.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("删除\(day.title)的这个时段")
                                    }.padding(.leading, 22)
                                }
                            }
                        }
                        Divider().overlay(Palette.line)
                    }
                }.padding(.trailing, 8)
            }.frame(height: 365)
            Text(enabled ? (WeekdayRoutine.error(draft) ?? "每一天最多 4 个时段；跨午夜请分别设置在相邻两天。") : "保存后使用设置中的每日时段规则；每周作息会保留。").font(.system(size: 11)).foregroundStyle(WeekdayRoutine.error(draft) != nil && enabled ? Palette.stretch : Palette.muted)
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction); Button("保存作息") { model.editPreferences { $0.weeklyRoutine = draft; $0.weeklyRoutineEnabled = enabled }; dismiss() }.buttonStyle(PrimaryButton()).disabled(enabled && WeekdayRoutine.error(draft) != nil) }
        }.padding(26).frame(width: 680).foregroundStyle(Palette.ink).background(Palette.background).tint(Palette.green)
    }
}

struct PlannedBreakEditor: View {
    @ObservedObject var model: AppModel
    @State var plan: PlannedBreak
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var isExisting: Bool { model.preferences.plannedBreaks.contains { $0.id == plan.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isExisting ? "编辑固定提醒" : "添加固定提醒").font(.system(size: 22, weight: .semibold))
            TextField("例如：午间走走", text: $plan.name).textFieldStyle(.roundedBorder).accessibilityLabel("提醒名称")
            HStack {
                Text("提醒时间"); MinutePicker(title: "提醒时间", minute: $plan.minute); Spacer()
                Picker("休息类型", selection: $plan.kind) { Text("起身活动").tag(ReminderKind.stretch); Text("护眼休息").tag(ReminderKind.eyes) }.frame(width: 175)
            }
            HStack(spacing: 11) {
                ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                    Toggle(WeekdayRoutine(weekday: day).title, isOn: Binding(get: { plan.weekdays.contains(day) }, set: { value in if value { plan.weekdays.append(day) } else { plan.weekdays.removeAll { $0 == day } } })).toggleStyle(.checkbox)
                }
            }.font(.system(size: 11))
            Stepper("休息 \(BreakDuration.label(plan.durationSeconds))", value: Binding(get: { max(1, plan.durationSeconds / 60) }, set: { plan.durationSeconds = $0 * 60 }), in: 1...30).fixedSize()
            Text(plan.error ?? "按所选日期的本地时间提醒。独立于工作时段；暂停、睡眠等期间不会补发很久前的提醒。").font(.system(size: 11)).foregroundStyle(plan.error == nil ? Palette.muted : Palette.stretch).fixedSize(horizontal: false, vertical: true)
            HStack {
                if isExisting { Button("删除提醒") { deleting = true }.buttonStyle(.plain).foregroundStyle(Palette.stretch) }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存") { model.editPreferences { p in p.plannedBreaks.removeAll { $0.id == plan.id }; p.plannedBreaks.append(plan) }; dismiss() }.buttonStyle(PrimaryButton()).disabled(plan.error != nil)
            }
        }.padding(28).frame(width: 620).foregroundStyle(Palette.ink).background(Palette.background).tint(Palette.green)
            .confirmationDialog("删除这个固定提醒？", isPresented: $deleting) { Button("删除", role: .destructive) { model.editPreferences { $0.plannedBreaks.removeAll { $0.id == plan.id } }; dismiss() } }
    }
}
