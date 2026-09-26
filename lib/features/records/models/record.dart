enum RecordType { live, movie, book, other }

extension RecordTypeUi on RecordType {
  /// タブやチップなどに表示する日本語ラベル。
  String get japaneseLabel {
    switch (this) {
      case RecordType.live:
        return 'ライブ';
      case RecordType.movie:
        return '映画';
      case RecordType.book:
        return '本';
      case RecordType.other:
        return 'その他';
    }
  }

  /// 入力フォームでの [Record.title] の呼び方。
  String get titleFieldLabel => switch (this) {
    RecordType.live => '公演名・ツアー名',
    RecordType.movie => '作品名',
    RecordType.book => '書名',
    RecordType.other => 'タイトル',
  };

  /// 入力フォームでの [Record.artistOrAuthor] の呼び方。
  String get creatorFieldLabel => switch (this) {
    RecordType.live => 'アーティスト',
    RecordType.movie => '監督・出演',
    RecordType.book => '著者',
    RecordType.other => '出演・作者',
  };

  /// 日時・会場・チケットなどをまとめた入力欄の見出し。
  String get detailsSectionLabel => switch (this) {
    RecordType.live => '公演・チケット',
    RecordType.movie => '上映・チケット',
    RecordType.book => '購入情報',
    RecordType.other => '日時・チケット',
  };

  /// 開場時刻を持つか。
  bool get hasOpenTime => this == RecordType.live;

  /// 開始・終了時刻を持つか。本は日時の決まった催しではないので持たない。
  bool get hasSchedule => this != RecordType.book;

  String get startTimeLabel => switch (this) {
    RecordType.live => '開演',
    RecordType.movie => '上映開始',
    RecordType.book || RecordType.other => '開始',
  };

  String get endTimeLabel => switch (this) {
    RecordType.live => '終演',
    RecordType.movie => '上映終了',
    RecordType.book || RecordType.other => '終了',
  };

  /// 開始から終了までの間の呼び方。
  String get inProgressLabel => switch (this) {
    RecordType.live => '公演中',
    RecordType.movie => '上映中',
    RecordType.book || RecordType.other => '開催中',
  };

  /// [Record.venue] の呼び方。null なら入力欄を出さない。
  String? get venueLabel => switch (this) {
    RecordType.live => '会場',
    RecordType.movie => '映画館',
    RecordType.book => null,
    RecordType.other => '会場・場所',
  };

  /// [Record.seat] の入力例つきの呼び方。null なら入力欄を出さない。
  String? get seatPlaceholder => switch (this) {
    RecordType.live => '座席（アリーナ A5 12列 34番 など）',
    RecordType.movie => '座席（G-12 など）',
    RecordType.book || RecordType.other => null,
  };

  /// [Record.ticketPrice] の呼び方。
  String get priceLabel => this == RecordType.book ? '価格' : 'チケット代';

  /// [Record.ticketSource] の呼び方。
  String get sourceLabel => this == RecordType.book ? '購入先' : 'チケット取得元';

  String get sourcePlaceholder => switch (this) {
    RecordType.live => 'チケット取得元（e+、ローチケ など）',
    RecordType.movie => 'チケット取得元（劇場窓口、アプリ など）',
    RecordType.book => '購入先（書店、電子書籍ストア など）',
    RecordType.other => 'チケット取得元',
  };
}

/// 開演時刻などの「時:分」。日付やタイムゾーンを持たない。
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// DB の time 型（"18:00:00"）や "18:00" を読む。形式が違えば null。
  static ClockTime? tryParse(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (m == null) return null;
    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return ClockTime(hour, minute);
  }

  /// "18:00" の形。
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) =>
      (hour * 60 + minute) - (other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class Record {
  final String id;
  final RecordType type;
  final String title;
  final String artistOrAuthor;
  final DateTime date;
  final String ticketImageUrl;
  final String? ticketSource; // e+, LawTicket, etc.
  final String? setlist;
  final String? mcMemo;
  final String? impressions;
  final String? venue;
  final String? seat;

  /// チケット代・本の価格（円）。
  final int? ticketPrice;

  /// 開場時刻。未入力なら null。
  final ClockTime? openTime;

  /// 開演時刻。未入力なら null。
  final ClockTime? startTime;

  /// 終演時刻。未入力なら null。開演より前の時刻なら翌日（オールナイトなど）とみなす。
  final ClockTime? endTime;

  const Record({
    required this.id,
    required this.type,
    required this.title,
    required this.artistOrAuthor,
    required this.date,
    required this.ticketImageUrl,
    this.ticketSource,
    this.setlist,
    this.mcMemo,
    this.impressions,
    this.venue,
    this.seat,
    this.ticketPrice,
    this.openTime,
    this.startTime,
    this.endTime,
  });

  String get typeLabel => type.japaneseLabel;

  DateTime _at(ClockTime time, {int dayOffset = 0}) => DateTime(
    date.year,
    date.month,
    date.day + dayOffset,
    time.hour,
    time.minute,
  );

  /// 開演日時（端末のローカル時刻）。開演時刻が未入力ならその日の始まり。
  DateTime get startsAt => _at(startTime ?? const ClockTime(0, 0));

  /// 開場日時。未入力なら null。
  DateTime? get opensAt => openTime == null ? null : _at(openTime!);

  /// 終演日時。未入力なら null。
  DateTime? get endsAt {
    final end = endTime;
    if (end == null) return null;
    final start = startTime;
    return _at(
      end,
      dayOffset: start != null && end.compareTo(start) < 0 ? 1 : 0,
    );
  }

  factory Record.fromJson(Map<String, dynamic> json) {
    return Record(
      id: json['id'] as String,
      type: RecordType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecordType.other,
      ),
      title: json['title'] as String,
      artistOrAuthor: json['artist_or_author'] as String,
      date: DateTime.parse(json['date'] as String),
      ticketImageUrl: json['ticket_image_url'] as String? ?? '',
      ticketSource: json['ticket_source'] as String?,
      setlist: json['setlist'] as String?,
      mcMemo: json['mc_memo'] as String?,
      impressions: json['impressions'] as String?,
      venue: json['venue'] as String?,
      seat: json['seat'] as String?,
      ticketPrice: (json['ticket_price'] as num?)?.toInt(),
      openTime: ClockTime.tryParse(json['open_time'] as String?),
      startTime: ClockTime.tryParse(json['start_time'] as String?),
      endTime: ClockTime.tryParse(json['end_time'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // id is usually generated by DB on insert, but included if updating
      // 'id': id,
      'type': type.name,
      'title': title,
      'artist_or_author': artistOrAuthor,
      'date': date.toIso8601String(),
      'ticket_image_url': ticketImageUrl,
      'ticket_source': ticketSource,
      'setlist': setlist,
      'mc_memo': mcMemo,
      'impressions': impressions,
      'venue': venue,
      'seat': seat,
      'ticket_price': ticketPrice,
      'open_time': openTime?.format(),
      'start_time': startTime?.format(),
      'end_time': endTime?.format(),
    };
  }
}
