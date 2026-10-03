import SwiftUI
import WidgetKit

/// アプリの RecordType と同じ値。
enum EventType: String, Decodable {
  case live, movie, book, other
}

/// アプリ（home_widget）が App Group に書き込む「これから」の記録。
struct UpcomingEvent: Decodable {
  let title: String
  let artist: String
  /// 種類を渡すようになる前のデータでは nil。
  let type: EventType?
  let startsAt: Double
  let hasStartTime: Bool
  let opensAt: Double?
  let endsAt: Double?
  /// 最終日の翌日 0 時。古いデータでは nil。
  let finishesAt: Double?
  let venue: String?
  let isLive: Bool
  let startLabel: String?
  let endLabel: String?
  let inProgressLabel: String?

  var date: Date { Date(timeIntervalSince1970: startsAt / 1000) }
  var openDate: Date? { opensAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
  var endDate: Date? { endsAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

  var resolvedType: EventType { type ?? (isLive ? .live : .other) }

  /// 開始時刻が未入力のときの見出しに使う呼び方。
  var noun: String {
    switch resolvedType {
    case .live: return "公演"
    case .movie: return "上映"
    case .book, .other: return "予定"
    }
  }

  /// 終演時刻があれば終演で、なければ日付が変わった時点で終わったとみなす（アプリの splitByDate と同じ）。
  func isFinished(at now: Date) -> Bool {
    if let end = endDate { return end <= now }
    if let finishesAt { return Date(timeIntervalSince1970: finishesAt / 1000) <= now }
    let calendar = Calendar.current
    return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
  }

  var startName: String { startLabel ?? "開演" }

  /// 当日の、まだ来ていない最初の区切り（開場・開演・終演）。
  func nextMilestone(after now: Date) -> (label: String, date: Date)? {
    let end = endLabel ?? "終演"
    let inProgress = inProgressLabel ?? "公演中"
    if let open = openDate, open > now { return ("開場まで", open) }
    if hasStartTime, date > now { return ("\(startName)まで", date) }
    if let endDate, endDate > now {
      // 開始時刻が未入力（その他の予定など）だと始まったかどうか分からないので「開催中」とは言わない
      return (hasStartTime ? "\(inProgress)・\(end)まで" : "\(end)まで", endDate)
    }
    return nil
  }

  /// 前日のうち、開始まで 24 時間を切ってからは時間・分で残りを見せる。
  func showsHoursCountdown(at now: Date) -> Bool {
    hasStartTime && date > now && date.timeIntervalSince(now) <= hoursCountdownWindow
  }

  /// 開始までの残りを「日・時間」に切り捨てたもの。開始時刻が未入力なら nil。
  func remainingDaysAndHours(at now: Date) -> (days: Int, hours: Int)? {
    guard hasStartTime, date > now else { return nil }
    let totalHours = Int(date.timeIntervalSince(now) / hour)
    return (totalHours / 24, totalHours % 24)
  }

  /// 表示から外れる時刻。終演があれば終演、なければ最終日の翌日 0 時（isFinished と同じ基準）。
  var finishDate: Date? {
    if let endDate { return endDate }
    if let finishesAt { return Date(timeIntervalSince1970: finishesAt / 1000) }
    let calendar = Calendar.current
    return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
  }
}

private let hour: TimeInterval = 60 * 60
private let hoursCountdownWindow: TimeInterval = 24 * hour

/// 一度に作るタイムラインの期間。表示の差し替えは 1 時間ごとだが、作り直し（1 日の回数に上限がある）は
/// この期間ごとに 1 回で済む。
private let timelineHorizonDays = 3

private let appGroupId = "group.com.ishidaminato.recolle"
private let dataKey = "upcoming_events"

/// ウィジェットごとに表示する記録の種類。
enum WidgetCategory {
  case all, live, movie, other

  /// アプリの home_widget_sync.dart の _iOSWidgetKinds と揃える。
  var kind: String {
    switch self {
    case .all: return "RecolleWidget"
    case .live: return "RecolleLiveWidget"
    case .movie: return "RecolleMovieWidget"
    case .other: return "RecolleOtherWidget"
    }
  }

  var displayName: String {
    switch self {
    case .all: return "次の予定"
    case .live: return "次のライブ"
    case .movie: return "次の映画"
    case .other: return "次のその他の予定"
    }
  }

  var description: String {
    switch self {
    case .all: return "すべての予定のうち、一番近いものまでの残り時間を表示します。"
    case .live: return "次のライブまでの残り時間を表示します。"
    case .movie: return "次の映画の上映開始までの残り時間を表示します。"
    case .other: return "次のその他の予定までの残り時間を表示します。"
    }
  }

  func includes(_ event: UpcomingEvent) -> Bool {
    switch self {
    case .all: return true
    case .live: return event.resolvedType == .live
    case .movie: return event.resolvedType == .movie
    case .other: return event.resolvedType == .other
    }
  }

  var emptyTitle: String {
    switch self {
    case .live: return "これからの公演はありません"
    case .movie: return "これからの上映はありません"
    case .all, .other: return "これからの予定はありません"
    }
  }

  var emptyMessage: String {
    switch self {
    case .all: return "予定を記録するとカウントダウンが表示されます"
    case .live: return "ライブを記録するとカウントダウンが表示されます"
    case .movie: return "映画を記録するとカウントダウンが表示されます"
    case .other: return "その他の予定を記録するとカウントダウンが表示されます"
    }
  }

  /// ウィジェットギャラリーに出す見本。
  var sampleEvent: UpcomingEvent {
    let startsAt = Date().addingTimeInterval(86400 * 12 + 3600 * 5).timeIntervalSince1970 * 1000
    switch self {
    case .all, .live:
      return UpcomingEvent(
        title: "ARENA TOUR 2026", artist: "Artist", type: .live, startsAt: startsAt,
        hasStartTime: true, opensAt: nil, endsAt: nil, finishesAt: nil, venue: "さいたまスーパーアリーナ",
        isLive: true, startLabel: "開演", endLabel: "終演", inProgressLabel: "公演中")
    case .movie:
      return UpcomingEvent(
        title: "作品名", artist: "監督・出演", type: .movie, startsAt: startsAt,
        hasStartTime: true, opensAt: nil, endsAt: nil, finishesAt: nil, venue: "映画館",
        isLive: false, startLabel: "上映開始", endLabel: "上映終了", inProgressLabel: "上映中")
    case .other:
      return UpcomingEvent(
        title: "イベント", artist: "", type: .other, startsAt: startsAt,
        hasStartTime: true, opensAt: nil, endsAt: nil, finishesAt: nil, venue: "会場",
        isLive: false, startLabel: "開始", endLabel: "終了", inProgressLabel: "開催中")
    }
  }
}

struct EventEntry: TimelineEntry {
  let date: Date
  let category: WidgetCategory
  let event: UpcomingEvent?
}

struct Provider: TimelineProvider {
  let category: WidgetCategory

  func placeholder(in context: Context) -> EventEntry {
    EventEntry(date: Date(), category: category, event: category.sampleEvent)
  }

  func getSnapshot(in context: Context, completion: @escaping (EventEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
  }

  /// 毎日 0 時（日数の減少・当日への切り替え）、表示中の公演の開始から数えた 1 時間ごと（「◯日◯時間」の更新）、
  /// 開場・開演・終演、各公演の翌日 0 時にエントリを置く。最後のエントリ（期間末の 0 時）で作り直す。
  func getTimeline(in context: Context, completion: @escaping (Timeline<EventEntry>) -> Void) {
    let now = Date()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let midnights = (1...timelineHorizonDays).compactMap {
      calendar.date(byAdding: .day, value: $0, to: today)
    }
    guard let horizon = midnights.last else {
      completion(Timeline(entries: [entry(at: now)], policy: .atEnd))
      return
    }

    var dates = Set([now] + midnights)
    // 1 時間ごとの区切りは、その公演が表示されている間（前の公演が終わってから）だけ置けば足りる
    var shownFrom = now
    for event in loadEvents() where !event.isFinished(at: now) {
      if event.hasStartTime {
        let hoursBeforeHorizon = Int((event.date.timeIntervalSince(horizon) / hour).rounded(.up))
        let nearestHours = max(Int(hoursCountdownWindow / hour), hoursBeforeHorizon)
        var mark = event.date.addingTimeInterval(-Double(nearestHours) * hour)
        while mark > shownFrom {
          dates.insert(mark)
          mark.addTimeInterval(-hour)
        }
      }
      let candidates: [Date?] = [event.openDate, event.hasStartTime ? event.date : nil, event.finishDate]
      for case let date? in candidates where date > now && date < horizon {
        dates.insert(date)
      }
      guard let finish = event.finishDate, finish < horizon else { break }
      shownFrom = max(shownFrom, finish)
    }
    let entries = dates.sorted().map { entry(at: $0) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func entry(at date: Date) -> EventEntry {
    let next = loadEvents().first { !$0.isFinished(at: date) }
    return EventEntry(date: date, category: category, event: next)
  }

  private func loadEvents() -> [UpcomingEvent] {
    guard
      let json = UserDefaults(suiteName: appGroupId)?.string(forKey: dataKey),
      let data = json.data(using: .utf8),
      let events = try? JSONDecoder().decode([UpcomingEvent].self, from: data)
    else { return [] }
    return events.filter(category.includes).sorted { $0.startsAt < $1.startsAt }
  }
}

/// アプリのシャンパンゴールドのパレットに合わせた色。
private enum Palette {
  static let accent = Color(
    light: Color(red: 0x9A / 255, green: 0x74 / 255, blue: 0x33 / 255),
    dark: Color(red: 0xE6 / 255, green: 0xC8 / 255, blue: 0x8F / 255))
  static let background = Color(
    light: Color(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEE / 255),
    dark: Color(red: 0x1D / 255, green: 0x1B / 255, blue: 0x18 / 255))
}

extension Color {
  fileprivate init(light: Color, dark: Color) {
    self.init(
      UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
  }
}

struct RecolleWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: EventEntry

  var body: some View {
    Group {
      if let event = entry.event {
        eventView(event)
      } else {
        emptyView
      }
    }
    .containerBackground(Palette.background, for: .widget)
  }

  private func eventView(_ event: UpcomingEvent) -> some View {
    // 当日かどうかと、開始時刻が未入力の予定の日数は、カレンダー上の日付差で数える
    let days =
      Calendar.current.dateComponents(
        [.day],
        from: Calendar.current.startOfDay(for: entry.date),
        to: Calendar.current.startOfDay(for: event.date)
      ).day ?? 0
    // 日付をまたぐ公演（オールナイトなど）は、翌日も終演までは当日として扱う
    let isToday = days <= 0

    let milestone = isToday ? event.nextMilestone(after: entry.date) : nil
    let showsHours = !isToday && event.showsHoursCountdown(at: entry.date)
    let label =
      milestone?.label ?? (event.hasStartTime ? "\(event.startName)まで" : "次の\(event.noun)まで")

    return VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Palette.accent)

      if showsHours {
        // 「11時間32分」の形でシステムが自動更新する。拡張の言語設定に左右されないよう日本語に固定
        Text(event.date, style: .relative)
          .font(.system(size: 26, weight: .heavy))
          .foregroundStyle(Palette.accent)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .environment(\.locale, Locale(identifier: "ja_JP"))
      } else if let milestone {
        // 区切りの時刻までシステムが秒単位で進めてくれる
        Text(milestone.date, style: .timer)
          .font(.system(size: 30, weight: .heavy, design: .monospaced))
          .foregroundStyle(Palette.accent)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      } else if isToday {
        Text("今日")
          .font(.system(size: 30, weight: .heavy))
          .foregroundStyle(Palette.accent)
      } else if let remaining = event.remainingDaysAndHours(at: entry.date) {
        (Text("\(remaining.days)")
          .font(.system(size: 34, weight: .heavy))
          .foregroundStyle(Palette.accent)
          + Text("日 ").font(.subheadline.weight(.bold))
          + Text("\(remaining.hours)")
          .font(.system(size: 34, weight: .heavy))
          .foregroundStyle(Palette.accent)
          + Text("時間").font(.subheadline.weight(.bold)))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(days)")
            .font(.system(size: 38, weight: .heavy))
            .foregroundStyle(Palette.accent)
          Text("日")
            .font(.subheadline.weight(.bold))
        }
      }

      Spacer(minLength: 0)

      Text(event.title)
        .font(.subheadline.weight(.bold))
        .lineLimit(family == .systemSmall ? 2 : 1)
      Text(subtitle(event))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(family == .systemSmall ? 1 : 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func subtitle(_ event: UpcomingEvent) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = event.hasStartTime ? "M/d(E) H:mm" : "M/d(E)"
    // その他の予定は出演・作者が空のことがある
    var parts = [event.artist, formatter.string(from: event.date)].filter { !$0.isEmpty }
    if family != .systemSmall, let venue = event.venue, !venue.isEmpty { parts.append(venue) }
    return parts.joined(separator: "・")
  }

  private var emptyView: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("RECOLLE")
        .font(.system(size: 16, weight: .heavy))
        .foregroundStyle(Palette.accent)
      Spacer(minLength: 0)
      Text(entry.category.emptyTitle)
        .font(.caption.weight(.semibold))
      Text(entry.category.emptyMessage)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private func configuration(for category: WidgetCategory) -> some WidgetConfiguration {
  StaticConfiguration(kind: category.kind, provider: Provider(category: category)) { entry in
    RecolleWidgetView(entry: entry)
  }
  .configurationDisplayName(category.displayName)
  .description(category.description)
  .supportedFamilies([.systemSmall, .systemMedium])
}

/// すべての予定のうち一番近いもの。kind は最初のウィジェットのまま据え置き、配置済みのものを引き継ぐ。
struct RecolleWidget: Widget {
  var body: some WidgetConfiguration { configuration(for: .all) }
}

struct RecolleLiveWidget: Widget {
  var body: some WidgetConfiguration { configuration(for: .live) }
}

struct RecolleMovieWidget: Widget {
  var body: some WidgetConfiguration { configuration(for: .movie) }
}

struct RecolleOtherWidget: Widget {
  var body: some WidgetConfiguration { configuration(for: .other) }
}

@main
struct RecolleWidgetBundle: WidgetBundle {
  var body: some Widget {
    RecolleWidget()
    RecolleLiveWidget()
    RecolleMovieWidget()
    RecolleOtherWidget()
  }
}
