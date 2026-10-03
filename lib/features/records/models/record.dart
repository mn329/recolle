import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/records/models/setlist_entry.dart';

export 'package:recolle/features/records/models/setlist_entry.dart';

enum RecordType { live, movie, book, other }

/// ライブの形式。対バン・フェスは出演者（[RecordAct]）ごとにセトリを持つ。
enum EventFormat {
  oneman,
  taiban,
  festival;

  String get label => switch (this) {
    EventFormat.oneman => 'ワンマン',
    EventFormat.taiban => '対バン',
    EventFormat.festival => 'フェス',
  };

  bool get hasMultipleActs => this != EventFormat.oneman;

  static EventFormat fromName(String? name) => EventFormat.values.firstWhere(
    (e) => e.name == name,
    orElse: () => EventFormat.oneman,
  );
}

/// 改行区切りのセトリを曲名の一覧にする。空行は除く。
List<String> splitSetlist(String? setlist) => [
  for (final line in (setlist ?? '').split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// 対バン・フェスの出演者 1 組と、その出演者のセトリ。
class RecordAct {
  const RecordAct({
    required this.artist,
    this.songs = const [],
    this.isMain = false,
    this.day,
  });

  final String artist;

  /// セトリの行。曲のほか、アンコールなどの区切りと MC の行も含む（[SetlistEntry]）。
  final List<String> songs;

  /// 区切り・MC を除いた曲名。
  List<String> get songTitles => setlistSongTitles(songs);

  /// お目当ての出演者か。
  final bool isMain;

  /// 複数日のフェスで出演した日（1 始まり）。1 日だけの公演では null。
  final int? day;

  RecordAct copyWith({String? artist, List<String>? songs, bool? isMain}) =>
      RecordAct(
        artist: artist ?? this.artist,
        songs: songs ?? this.songs,
        isMain: isMain ?? this.isMain,
        day: day,
      );

  RecordAct withDay(int? day) =>
      RecordAct(artist: artist, songs: songs, isMain: isMain, day: day);

  factory RecordAct.fromJson(Map<String, dynamic> json) => RecordAct(
    artist: (json['artist'] as String? ?? '').trim(),
    songs: [
      for (final song in json['songs'] as List<dynamic>? ?? const [])
        if (song is String && song.trim().isNotEmpty) song.trim(),
    ],
    isMain: json['is_main'] as bool? ?? false,
    day: (json['day'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'artist': artist,
    'songs': songs,
    'is_main': isMain,
    if (day != null) 'day': day,
  };

  @override
  bool operator ==(Object other) =>
      other is RecordAct &&
      other.artist == artist &&
      other.isMain == isMain &&
      other.day == day &&
      _sameStrings(other.songs, songs);

  @override
  int get hashCode => Object.hash(artist, isMain, day, Object.hashAll(songs));
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

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

  /// 自由入力に切り替えたときの [Record.ticketSource] の入力例つきの呼び方。
  String get sourcePlaceholder => switch (this) {
    RecordType.live || RecordType.other => 'チケット取得元（e+、ローチケ など）',
    RecordType.movie => 'チケット取得元（劇場窓口、ムビチケ など）',
    RecordType.book => '購入先（書店、Amazon など）',
  };

  /// 入力行の上に添える、チケット風の英字の項目名。
  String get creatorFieldEnLabel => switch (this) {
    RecordType.live => 'ARTIST',
    RecordType.book => 'AUTHOR',
    RecordType.movie || RecordType.other => 'CAST',
  };

  String get venueEnLabel => this == RecordType.movie ? 'THEATER' : 'VENUE';

  String get sourceEnLabel => this == RecordType.book ? 'STORE' : 'TICKET';
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

  /// [minutes] 分ずらした時刻。日をまたいだら 0:00〜23:59 に折り返す。
  ClockTime shiftedBy(int minutes) {
    final total = (hour * 60 + minute + minutes) % (24 * 60);
    return ClockTime(total ~/ 60, total % 60);
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

  /// チケット画像の公開 URL。先頭が一覧に出す表紙。
  final List<String> ticketImageUrls;
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

  final EventFormat eventFormat;

  /// 複数日にわたる公演の最終日。1 日だけなら null。
  final DateTime? endDate;

  /// 対バン・フェスの出演者。ワンマンや他の種別では空で、[artistOrAuthor] と [setlist] を使う。
  final List<RecordAct> acts;

  /// 公演ページ・チケットのページなど、あとで開きたいリンク（http(s) の URL）。
  final String? linkUrl;

  const Record({
    required this.id,
    required this.type,
    required this.title,
    required this.artistOrAuthor,
    required this.date,
    this.ticketImageUrls = const [],
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
    this.eventFormat = EventFormat.oneman,
    this.endDate,
    this.acts = const [],
    this.linkUrl,
  });

  /// 出演者の一覧の見出しに収める文字数。
  static const int headlineMaxLength = 300;

  /// 対バン・フェスの [artistOrAuthor] に入れる見出し。
  ///
  /// お目当てがいればその出演者、いなければ全員を「／」でつなぐ（[artistMatches] が分割できる区切り）。
  /// 長すぎるときは入る分だけにして「ほか」を付ける。
  static String headlineFor(List<RecordAct> acts) {
    final named = acts.where((a) => a.artist.trim().isNotEmpty).toList();
    final mains = named.where((a) => a.isMain).toList();
    final names = [
      for (final a in mains.isEmpty ? named : mains) a.artist.trim(),
    ];
    final all = names.join(' ／ ');
    if (all.length <= headlineMaxLength) return all;
    const suffix = ' ほか';
    var result = '';
    for (final name in names) {
      final next = result.isEmpty ? name : '$result ／ $name';
      if (next.length + suffix.length > headlineMaxLength) break;
      result = next;
    }
    return result.isEmpty
        ? '${names.first.substring(0, headlineMaxLength - suffix.length)}$suffix'
        : '$result$suffix';
  }

  /// 出演者ごとのセトリ。ワンマンなどは [artistOrAuthor] 1 組として返す。
  List<RecordAct> get performances => acts.isNotEmpty
      ? acts
      : [
          RecordAct(
            artist: artistOrAuthor,
            songs: splitSetlist(setlist),
            isMain: true,
          ),
        ];

  /// [artist] が出演しているか（コラボ表記の記録も含む）。
  bool features(String artist) =>
      performances.any((a) => artistMatches(a.artist, artist));

  /// [artist] が演奏した曲。
  List<String> songsBy(String artist) => [
    for (final a in performances)
      if (artistMatches(a.artist, artist)) ...a.songTitles,
  ];

  /// 一覧に出す表紙の画像。画像がなければ null。
  String? get coverImageUrl => ticketImageUrls.firstOrNull;

  /// 公演の最終日。1 日だけの公演なら [date]。
  DateTime get lastDate => endDate ?? date;

  bool get isMultiDay => endDate != null && endDate!.isAfter(date);

  /// 開催日数（1 日だけなら 1）。
  int get dayCount => dayCountBetween(date, endDate);

  /// [start] から [end] までの日数。[end] が null か [start] 以前なら 1。
  static int dayCountBetween(DateTime start, DateTime? end) {
    if (end == null) return 1;
    final days = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return days < 1 ? 1 : days + 1;
  }

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

  /// 終演日時（複数日なら最終日の終演）。未入力なら null。
  DateTime? get endsAt {
    final end = endTime;
    if (end == null) return null;
    final start = startTime;
    final overnight = start != null && end.compareTo(start) < 0 ? 1 : 0;
    return _at(end, dayOffset: lastDate.difference(date).inDays + overnight);
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
      ticketImageUrls: _ticketImageUrlsFromJson(json),
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
      eventFormat: EventFormat.fromName(json['event_format'] as String?),
      endDate: switch (json['end_date']) {
        final String d => DateTime.parse(d),
        _ => null,
      },
      acts: [
        for (final act in json['acts'] as List<dynamic>? ?? const [])
          if (act is Map<String, dynamic>) RecordAct.fromJson(act),
      ],
      linkUrl: json['link_url'] as String?,
    );
  }

  /// 複数枚の列が空なら、列を足す前の 1 枚だけの列を読む。
  static List<String> _ticketImageUrlsFromJson(Map<String, dynamic> json) {
    final urls = [
      for (final url in json['ticket_image_urls'] as List<dynamic>? ?? const [])
        if (url is String && url.isNotEmpty) url,
    ];
    if (urls.isNotEmpty) return urls;
    final legacy = json['ticket_image_url'] as String? ?? '';
    return legacy.isEmpty ? const [] : [legacy];
  }

  Map<String, dynamic> toJson() {
    return {
      // id is usually generated by DB on insert, but included if updating
      // 'id': id,
      'type': type.name,
      'title': title,
      'artist_or_author': artistOrAuthor,
      'date': date.toIso8601String(),
      'ticket_image_urls': ticketImageUrls,
      // 旧版アプリは 1 枚目だけを読む
      'ticket_image_url': coverImageUrl ?? '',
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
      'event_format': eventFormat.name,
      'end_date': endDate?.toIso8601String(),
      'acts': [for (final a in acts) a.toJson()],
      'link_url': linkUrl,
    };
  }
}
