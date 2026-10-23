import SwiftUI

struct PeriodReviewView: View {
    @ObservedObject var model: AppModel
    @State private var period = ReviewPeriod.week
    @State private var offset = 0
    @State private var metric = 1
    init(model: AppModel, period: ReviewPeriod = .week) { self.model = model; _period = State(initialValue: period) }
    private var review: PeriodReview { PeriodReview(kind: period, offset: offset, now: model.now, days: model.engine.saved.days) }
    private var activities: [ActivityEvent] { model.engine.saved.events.filter { $0.voidedAt == nil && ($0.recordDay ?? dayKey($0.date)) >= dayKey(review.start) && ($0.recordDay ?? dayKey($0.date)) < dayKey(review.end) } }
    private var away: [TimingEvent] { model.engine.saved.timingEvents.filter { $0.reason == .naturalAway && $0.date >= review.start && $0.date < review.end } }
    private func value(_ record: DayRecord) -> Double { metric == 0 ? Double(record.waterML) : metric == 1 ? Double(record.breakCount) : record.workSeconds / 60 }
    private var unit: String { metric == 0 ? "ml" : metric == 1 ? "次" : "分钟" }
    private var maximum: Double { max(1, review.records.compactMap { $0 }.map(value).max() ?? 1) }
    private var range: String {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd"
        return "\(f.string(from: review.start)) – \(f.string(from: review.end.addingTimeInterval(-1)))"
    }
    var body: some View {
        FeatureCard(title: "把小习惯放进更长的时间里", subtitle: "按周或月回看。空白表示没有记录，与已记录的零值分开显示。") {
            HStack(spacing: 12) {
                Picker("回顾周期", selection: $period) { ForEach(ReviewPeriod.allCases, id: \.self) { Text("按\($0.rawValue)").tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 136)
                    .onChange(of: period) { _ in offset = 0 }
                Spacer()
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(QuietButton()).accessibilityLabel("上一\(period.rawValue)")
                Text(range).font(.system(size: 11)).monospacedDigit().frame(minWidth: 190)
                Button { offset = min(0, offset + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(QuietButton()).disabled(offset == 0).accessibilityLabel("下一\(period.rawValue)")
                Button("本\(period.rawValue)") { offset = 0 }.buttonStyle(QuietButton()).disabled(offset == 0)
            }
            HStack(spacing: 24) {
                total("饮水", "\(review.total.waterML) ml")
                total("休息", "\(review.total.breakCount) 次")
                total("工作时长（估算）", minutesText(review.total.workSeconds))
                Spacer()
                Text("\(review.recordedDays) 天有记录").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 8)
            HStack {
                Text("每天的小进展").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("回顾指标", selection: $metric) { Text("饮水").tag(0); Text("休息").tag(1); Text("工作时长").tag(2) }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            HStack(alignment: .bottom, spacing: period == .week ? 18 : 4) {
                ForEach(review.dates.indices, id: \.self) { i in
                    let record = review.records[i]
                    let future = review.dates[i] > model.now
                    VStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: period == .week ? 5 : 3)
                            .fill(record == nil ? Palette.line : Palette.green.opacity(Calendar.current.isDate(review.dates[i], inSameDayAs: model.now) ? 1 : 0.35))
                            .frame(height: record.map { max(4, 90 * value($0) / maximum) } ?? 2)
                        Text(period == .week || i == 0 || (i + 1) % 5 == 0 ? "\(Calendar.current.component(.day, from: review.dates[i]))" : " ").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity).frame(height: 117, alignment: .bottom)
                        .help("\(dayKey(review.dates[i]))\n\(future ? "尚未到这一天" : record.map { "\(Int(value($0))) \(unit)" } ?? "没有记录")")
                        .accessibilityElement(children: .ignore).accessibilityLabel(dayKey(review.dates[i])).accessibilityValue(record.map { "\(Int(value($0))) \(unit)" } ?? "没有记录")
                }
            }
            comparison
            Divider().overlay(Palette.line)
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("休息记录的来源").font(.system(size: 12, weight: .medium))
                    Text("手动确认 \(activities.filter { $0.kind != .water && $0.origin == .confirmed }.count) 次 · 历史未标记 \(activities.filter { $0.kind != .water && $0.origin == nil }.count) 次").font(.system(size: 11))
                    Text("来源分类仅覆盖保留的明细，完整汇总以上方数字为准。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("自然离开电脑（估算）").font(.system(size: 12, weight: .medium))
                    Text("\(away.count) 段 · \(minutesText(away.reduce(0) { $0 + ($1.seconds ?? 0) }))").font(.system(size: 11))
                    Text("仅含保留的观测片段，不增加完成休息次数。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
    }
    private func total(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit() }
    }
    @ViewBuilder private var comparison: some View {
        if review.canCompare {
            let difference = value(review.comparableTotal) - value(review.previousTotal)
            VStack(alignment: .leading, spacing: 5) {
                Text("较上一\(period.rawValue)：\(difference > 0 ? "+" : "")\(Int(difference)) \(unit)").font(.system(size: 12, weight: .medium))
                Text("对比相同日序的 \(review.matchedDays) 个有记录完整日\(review.isCurrent ? "，截至昨天" : "")；两期任一侧未记录的日期不参与比较。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        } else {
            Text("还没有足够的对应完整日记录可作比较\(review.isCurrent ? "；今天尚未结束" : "")。").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}

struct RecordManagementCard: View {
    @ObservedObject var model: AppModel
    @State private var showing = false
    var body: some View {
        FeatureCard(title: "让记录更贴近实际", subtitle: "误记了一杯水，或休息时长填错了，可以更正或撤销。修改保留痕迹，汇总同步调整。") {
            HStack {
                Text("保留最近 1000 条活动明细；较早的每日汇总继续保留。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("管理记录") { showing = true }.buttonStyle(QuietButton())
            }
        }.sheet(isPresented: $showing) { ActivityRecordsView(model: model) }
    }
}

struct ActivityRecordsView: View {
    @ObservedObject var model: AppModel
    @State private var filter = "all"
    @State private var showVoided = false
    @State private var page = 0
    @State private var selected: ActivityEvent?
    @Environment(\.dismiss) private var dismiss
    var events: [ActivityEvent] { model.engine.saved.events.filter { (showVoided || $0.voidedAt == nil) && (filter == "all" || $0.kind.rawValue == filter) }.sorted { $0.date > $1.date } }
    var visible: [ActivityEvent] { Array(events.dropFirst(page * 12).prefix(12)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("活动记录").font(.system(size: 22, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction) }
            HStack {
                Picker("类型", selection: $filter) { Text("全部").tag("all"); ForEach(ReminderKind.allCases) { Text($0.short).tag($0.rawValue) } }.frame(width: 200)
                Spacer()
                Toggle("显示已撤销", isOn: $showVoided).toggleStyle(.checkbox)
            }.font(.system(size: 12))
            ScrollView {
                VStack(spacing: 0) {
                    if visible.isEmpty { Text("这里还没有符合条件的记录。").foregroundStyle(Palette.muted).padding(40) }
                    ForEach(visible) { event in
                        HStack(spacing: 14) {
                            Image(systemName: event.kind.symbol).foregroundStyle(event.kind.color).frame(width: 25)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(event.label ?? event.kind.title).fontWeight(.medium); Text(event.kind == .water ? "\(event.amount) ml" : BreakDuration.label(event.amount)).monospacedDigit(); if event.voidedAt != nil { Text("已撤销").foregroundStyle(Palette.stretch) } }
                                Text("\(event.date.formatted(date: .numeric, time: .shortened)) · \(event.origin == .confirmed ? "手动确认" : "历史来源未记录")\((event.revisions?.isEmpty == false) ? " · 已更正" : "")").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button(event.voidedAt == nil ? "更正" : "查看 / 恢复") { selected = event }.buttonStyle(QuietButton())
                        }.font(.system(size: 12)).padding(.vertical, 13)
                        Divider().overlay(Palette.line)
                    }
                }.padding(.trailing, 8)
            }.frame(height: 400)
            HStack {
                Text("\(events.count) 条明细 · 第 \(page + 1) / \(max(1, (events.count + 11) / 12)) 页").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("上一页") { page -= 1 }.buttonStyle(QuietButton()).disabled(page == 0)
                Button("下一页") { page += 1 }.buttonStyle(QuietButton()).disabled((page + 1) * 12 >= events.count)
            }
        }.padding(26).frame(width: 720).foregroundStyle(Palette.ink).background(Palette.background).tint(Palette.green)
            .onChange(of: filter) { _ in page = 0 }.onChange(of: showVoided) { _ in page = 0 }
            .onChange(of: events.count) { _ in page = min(page, max(0, (events.count - 1) / 12)) }
            .sheet(item: $selected) { event in ActivityCorrectionEditor(model: model, event: event) }
    }
}

struct ActivityCorrectionEditor: View {
    @ObservedObject var model: AppModel
    let event: ActivityEvent
    @State private var input: String
    @State private var confirmingVoid = false
    @State private var error = false
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, event: ActivityEvent) { self.model = model; self.event = event; _input = State(initialValue: String(event.amount)) }
    var amount: Int? { guard let value = Int(input), (event.kind == .water ? 50...1000 : 10...1800).contains(value) else { return nil }; return value }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(event.voidedAt == nil ? "更正记录" : "恢复记录").font(.system(size: 22, weight: .semibold))
            Text("\(event.label ?? event.kind.title) · 统计日期 \(event.recordDay ?? dayKey(event.date))").font(.system(size: 12)).foregroundStyle(Palette.muted)
            HStack { Text(event.kind == .water ? "饮水量" : "休息时长"); TextField("数值", text: $input).textFieldStyle(.roundedBorder).frame(width: 100).accessibilityLabel(event.kind == .water ? "更正饮水毫升数" : "更正休息秒数"); Text(event.kind == .water ? "毫升" : "秒") }
            Text(event.kind == .water ? "支持 50–1000 ml。只调整这条记录，不改变默认杯量。" : "支持 10–1800 秒（3 分钟为 180 秒）。不改变当前计时和默认休息时长。").font(.system(size: 11)).foregroundStyle(amount == nil ? Palette.stretch : Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let revisions = event.revisions, !revisions.isEmpty {
                Text("修改记录（最近 3 次）").font(.system(size: 11, weight: .medium))
                ForEach(Array(revisions.suffix(3).enumerated()), id: \.offset) { _, revision in
                    Text("\(revision.changedAt.formatted(date: .numeric, time: .shortened)) · 修改前：\(revision.wasVoided ? "已撤销" : "\(revision.previousAmount) \(event.kind == .water ? "ml" : "秒")")").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            if error { Text("未能修改：原汇总与明细不一致，未更改任何数据。").font(.system(size: 11)).foregroundStyle(Palette.stretch) }
            HStack {
                if event.voidedAt == nil { Button("撤销这条记录") { confirmingVoid = true }.buttonStyle(.plain).foregroundStyle(Palette.stretch) }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button(event.voidedAt == nil ? "保存修改" : "恢复") { if model.correctRecord(event.id, amount: amount) { dismiss() } else { error = true } }.buttonStyle(PrimaryButton()).disabled(amount == nil)
            }
        }.padding(28).frame(width: 500).foregroundStyle(Palette.ink).background(Palette.background).tint(Palette.green)
            .confirmationDialog("撤销后将从统计中扣除，之后仍可恢复。", isPresented: $confirmingVoid) { Button("撤销记录", role: .destructive) { if model.correctRecord(event.id, amount: nil) { dismiss() } else { error = true } } }
    }
}

struct TimingHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var showing = false
    var body: some View {
        FeatureCard(title: "计时为什么变化了", subtitle: "查看暂停、恢复与重置的原因。只保留时间和原因，不记录应用名称、窗口标题或屏幕内容。") {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.system(size: 13, weight: .medium))
                    if let event = model.engine.saved.timingEvents.first { Text("最近：\(event.reason.title)").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }
                Spacer()
                Button("查看计时记录") { showing = true }.buttonStyle(QuietButton())
            }
        }.sheet(isPresented: $showing) { TimingHistoryList(model: model) }
    }
}
struct TimingHistoryList: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss
    var events: [TimingEvent] { model.engine.saved.timingEvents }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("计时记录").font(.system(size: 22, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction) }
            Text("从这个版本起记录，最多保留最近 1000 条。自然离开仅在观测到返回后估算；睡眠和未观测的时间不补算。").font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if events.isEmpty { Text("暂时没有计时变化，之后可以来这里查看原因。").foregroundStyle(Palette.muted).padding(.vertical, 25) }
                    ForEach(Array(events.dropFirst(page * 30).prefix(30))) { event in
                        HStack(alignment: .top) {
                            Text(event.date.formatted(date: .numeric, time: .shortened)).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 145, alignment: .leading)
                            Text(event.reason.title).font(.system(size: 12))
                            Spacer()
                            if let seconds = event.seconds { Text(minutesText(seconds)).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        }
                        Divider().overlay(Palette.line)
                    }
                }.padding(.trailing, 8)
            }.frame(height: 400)
            HStack { Text("\(events.count) 条记录").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Button("上一页") { page -= 1 }.buttonStyle(QuietButton()).disabled(page == 0); Button("下一页") { page += 1 }.buttonStyle(QuietButton()).disabled((page + 1) * 30 >= events.count) }
        }.padding(26).frame(width: 690).foregroundStyle(Palette.ink).background(Palette.background)
    }
}
