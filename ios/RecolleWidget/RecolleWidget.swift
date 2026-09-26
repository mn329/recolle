import SwiftUI
import WidgetKit

/// アプリ（home_widget）が App Group に書き込む「これから」の記録。
struct UpcomingEvent: Decodable {
  let title: String
  let artist: String
  let startsAt: Double
  let hasStartTime: Bool
  let venue: String?
  let isLive: Bool

  var date: Date { Date(timeIntervalSince1970: startsAt / 1000) }
}

private let appGroupId = "group.com.ishidaminato.recolle"
private let dataKey = "upcoming_events"

struct EventEntry: TimelineEntry {
  let date: Date
  let event: UpcomingEvent?
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> EventEntry {
    EventEntry(
      date: Date(),
      event: UpcomingEvent(
        title: "ARENA TOUR 2026",
        artist: "Artist",
        startsAt: Date().addingTimeInterval(86400 * 12).timeIntervalSince1970 * 1000,
        hasStartTime: true,
        venue: "さいたまスーパーアリーナ",
        isLive: true
      )
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (EventEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
  }

  /// 公演が当日を過ぎたら次の公演へ切り替わるよう、各公演の翌日 0 時にもエントリを置く。
  func getTimeline(in context: Context, completion: @escaping (Timeline<EventEntry>) -> Void) {
    let now = Date()
    let calendar = Calendar.current
    var dates = [now]
    for event in loadEvents() {
      if let nextDay = calendar.date(
        byAdding: .day, value: 1, to: calendar.startOfDay(for: event.date)),
        nextDay > now
      {
        dates.append(nextDay)
      }
    }
    let entries = dates.sorted().map { entry(at: $0) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func entry(at date: Date) -> EventEntry {
    let today = Calendar.current.startOfDay(for: date)
    let next = loadEvents().first { Calendar.current.startOfDay(for: $0.date) >= today }
    return EventEntry(date: date, event: next)
  }

  private func loadEvents() -> [UpcomingEvent] {
    guard
      let json = UserDefaults(suiteName: appGroupId)?.string(forKey: dataKey),
      let data = json.data(using: .utf8),
      let events = try? JSONDecoder().decode([UpcomingEvent].self, from: data)
    else { return [] }
    return events.sorted { $0.startsAt < $1.startsAt }
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
    let isToday = Calendar.current.isDate(event.date, inSameDayAs: entry.date)
    let days =
      Calendar.current.dateComponents(
        [.day],
        from: Calendar.current.startOfDay(for: entry.date),
        to: Calendar.current.startOfDay(for: event.date)
      ).day ?? 0

    return VStack(alignment: .leading, spacing: 4) {
      Text(event.isLive ? "次の公演まで" : "次の予定まで")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Palette.accent)

      if isToday {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("今日")
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(Palette.accent)
          if event.hasStartTime && event.date > entry.date {
            // 開演まではシステムが秒単位で進めてくれる
            Text(event.date, style: .timer)
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
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
    var parts = [event.artist, formatter.string(from: event.date)]
    if family != .systemSmall, let venue = event.venue { parts.append(venue) }
    return parts.joined(separator: "・")
  }

  private var emptyView: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("RECOLLE")
        .font(.system(size: 16, weight: .heavy))
        .foregroundStyle(Palette.accent)
      Spacer(minLength: 0)
      Text("これからの予定はありません")
        .font(.caption.weight(.semibold))
      Text("公演を記録するとカウントダウンが表示されます")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct RecolleWidget: Widget {
  let kind = "RecolleWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      RecolleWidgetView(entry: entry)
    }
    .configurationDisplayName("次の公演")
    .description("次のライブまでの日数を表示します。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct RecolleWidgetBundle: WidgetBundle {
  var body: some Widget {
    RecolleWidget()
  }
}
