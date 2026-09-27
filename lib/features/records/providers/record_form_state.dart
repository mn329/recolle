import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';

/// 記録フォームのテキスト入力欄。
enum RecordTextField {
  title,
  artist,
  source,
  venue,
  seat,
  price,
  mcMemo,
  impressions,
}

/// 記録フォームを開くときの初期値。
@immutable
class RecordFormArgs {
  const RecordFormArgs({
    this.recordToEdit,
    this.initialArtist,
    this.initialType,
    this.prefill,
  });

  /// 指定時は編集モード。
  final Record? recordToEdit;

  /// 新規作成時にアーティスト欄へあらかじめ入れておく名前。
  final String? initialArtist;

  /// 新規作成時の種別。省略時はライブ。
  final RecordType? initialType;

  /// 新規作成時にあらかじめ入れておく公演の情報（公演検索の結果など）。
  final TicketMailInfo? prefill;

  @override
  bool operator ==(Object other) =>
      other is RecordFormArgs &&
      other.recordToEdit == recordToEdit &&
      other.initialArtist == initialArtist &&
      other.initialType == initialType &&
      other.prefill == prefill;

  @override
  int get hashCode =>
      Object.hash(recordToEdit, initialArtist, initialType, prefill);
}

/// 記録フォームの入力内容。
@immutable
class RecordFormState {
  const RecordFormState({
    required this.type,
    required this.eventFormat,
    required this.date,
    required this.texts,
    this.endDate,
    this.acts = const [],
    this.openTime,
    this.startTime,
    this.endTime,
    this.songs = const [],
    this.selectedImage,
    this.removeSavedImage = false,
    this.existingImageUrl,
    this.isSaving = false,
    this.actsRevision = 0,
    this.setlistRevision = 0,
  });

  factory RecordFormState.initial(RecordFormArgs args, {DateTime? now}) {
    final editing = args.recordToEdit;
    final draft = editing == null ? args.prefill : null;
    return RecordFormState(
      type: editing?.type ?? args.initialType ?? RecordType.live,
      eventFormat: editing?.eventFormat ?? EventFormat.oneman,
      date: editing?.date ?? draft?.date ?? now ?? DateTime.now(),
      endDate: editing?.endDate,
      acts: editing?.acts ?? const [],
      openTime: editing?.openTime ?? draft?.openTime,
      startTime: editing?.startTime ?? draft?.startTime,
      endTime: editing?.endTime ?? draft?.endTime,
      songs: splitSetlist(editing?.setlist),
      texts: Map.unmodifiable({
        RecordTextField.title: editing?.title ?? draft?.title ?? '',
        RecordTextField.artist:
            editing?.artistOrAuthor ??
            draft?.artist ??
            args.initialArtist ??
            '',
        RecordTextField.source:
            editing?.ticketSource ?? draft?.ticketSource ?? '',
        RecordTextField.venue: editing?.venue ?? draft?.venue ?? '',
        RecordTextField.seat: editing?.seat ?? '',
        RecordTextField.price: editing?.ticketPrice?.toString() ?? '',
        RecordTextField.mcMemo: editing?.mcMemo ?? '',
        RecordTextField.impressions: editing?.impressions ?? '',
      }),
      existingImageUrl: editing?.ticketImageUrl,
    );
  }

  final RecordType type;
  final EventFormat eventFormat;
  final DateTime date;

  /// フェスの最終日。1 日だけなら null。
  final DateTime? endDate;

  /// 対バン・フェスの出演者（名前が空の入力途中の欄も含む）。
  final List<RecordAct> acts;
  final ClockTime? openTime;
  final ClockTime? startTime;
  final ClockTime? endTime;

  /// ワンマンのセトリ。
  final List<String> songs;
  final Map<RecordTextField, String> texts;

  /// 新しく選んだチケット画像。
  final File? selectedImage;

  /// 編集中の記録に保存済みの画像を外すか。
  final bool removeSavedImage;

  /// 編集中の記録に保存済みの画像。
  final String? existingImageUrl;
  final bool isSaving;

  /// 出演者・セトリを入力欄の外から差し替えたときに増やす。
  /// 入力欄は自分の内容を持つので、これが変わったら作り直してもらう。
  final int actsRevision;
  final int setlistRevision;

  String text(RecordTextField field) => texts[field] ?? '';

  String get title => text(RecordTextField.title).trim();
  String get artist => text(RecordTextField.artist).trim();

  bool get isLive => type == RecordType.live;
  bool get isMultiAct => isLive && eventFormat.hasMultipleActs;
  bool get isFestival => isLive && eventFormat == EventFormat.festival;
  bool get hasVenue => type.venueLabel != null;
  bool get hasSeat => type.seatPlaceholder != null;

  List<RecordAct> get namedActs => [
    for (final a in acts)
      if (a.artist.trim().isNotEmpty) a.copyWith(artist: a.artist.trim()),
  ];

  /// お目当て（いなければ先頭）の出演者。
  RecordAct? get leadAct {
    final named = namedActs;
    return named.where((a) => a.isMain).firstOrNull ?? named.firstOrNull;
  }

  /// チケットや一覧に出す見出し。
  String get headline => isMultiAct ? Record.headlineFor(namedActs) : artist;

  /// 公演名の候補やセトリを引くアーティスト。
  String get lookupArtist => isMultiAct ? leadAct?.artist ?? '' : artist;

  int get dayCount => isFestival ? Record.dayCountBetween(date, endDate) : 1;

  /// 複数日のフェスの各日。1 日だけなら空。
  List<DateTime> get festivalDays => [
    if (dayCount > 1)
      for (var i = 0; i < dayCount; i++)
        DateTime(date.year, date.month, date.day + i),
  ];

  String get titleLabel =>
      isMultiAct ? 'イベント名・${eventFormat.label}名' : type.titleFieldLabel;

  String? get savedImageUrl => removeSavedImage ? null : existingImageUrl;

  List<String> get missingLabels => [
    if (isMultiAct && namedActs.isEmpty)
      '出演者'
    else if (!isMultiAct && artist.isEmpty)
      type.creatorFieldLabel,
    if (title.isEmpty) titleLabel,
  ];

  bool get canSave => missingLabels.isEmpty && !isSaving;

  String? get _setlist =>
      isLive && !isMultiAct && songs.isNotEmpty ? songs.join('\n') : null;

  int? get _price => int.tryParse(text(RecordTextField.price).trim());

  /// 保存できない理由。保存できるなら null。
  String? validate() {
    if (missingLabels.isNotEmpty) return '${missingLabels.join('と')}は必須です。';
    final setlist = _setlist;
    if (setlist != null && setlist.length > RecordFieldLimits.setlistTotal) {
      return 'セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。';
    }
    final price = _price;
    if (price != null && price > RecordFieldLimits.ticketPriceMax) {
      return '${type.priceLabel}が大きすぎます。金額を確認してください。';
    }
    final open = openTime;
    final start = startTime;
    if (type.hasOpenTime &&
        open != null &&
        start != null &&
        open.compareTo(start) > 0) {
      return '開場は開演より前の時刻にしてください。';
    }
    return null;
  }

  /// 入力内容を保存用の [Record] にする。種別で使わない項目は捨てる。
  Record toRecord({required String id, required String ticketImageUrl}) {
    String? nullIfEmpty(RecordTextField field) {
      final value = text(field).trim();
      return value.isEmpty ? null : value;
    }

    final days = dayCount;
    return Record(
      id: id,
      type: type,
      title: title,
      artistOrAuthor: headline,
      date: date,
      eventFormat: isLive ? eventFormat : EventFormat.oneman,
      endDate: isFestival && (endDate?.isAfter(date) ?? false) ? endDate : null,
      acts: isMultiAct
          ? [
              for (final a in namedActs)
                a.withDay(days > 1 ? (a.day ?? 1).clamp(1, days) : null),
            ]
          : const [],
      ticketImageUrl: ticketImageUrl,
      ticketSource: nullIfEmpty(RecordTextField.source),
      venue: hasVenue ? nullIfEmpty(RecordTextField.venue) : null,
      seat: hasSeat ? nullIfEmpty(RecordTextField.seat) : null,
      ticketPrice: _price,
      openTime: type.hasOpenTime ? openTime : null,
      startTime: type.hasSchedule ? startTime : null,
      endTime: type.hasSchedule ? endTime : null,
      setlist: _setlist,
      mcMemo: isLive ? nullIfEmpty(RecordTextField.mcMemo) : null,
      impressions: nullIfEmpty(RecordTextField.impressions),
    );
  }

  /// [initial] から入力内容が変わったか（閉じるときに破棄を確認するため）。
  bool hasChangesFrom(RecordFormState initial) =>
      type != initial.type ||
      date != initial.date ||
      eventFormat != initial.eventFormat ||
      endDate != initial.endDate ||
      !listEquals(acts, initial.acts) ||
      openTime != initial.openTime ||
      startTime != initial.startTime ||
      endTime != initial.endTime ||
      selectedImage != null ||
      removeSavedImage ||
      !listEquals(songs, initial.songs) ||
      !mapEquals(texts, initial.texts);

  static const _unset = Object();

  /// null にできる項目は、省略すると現在の値のまま、null を渡すと消す。
  RecordFormState copyWith({
    RecordType? type,
    EventFormat? eventFormat,
    DateTime? date,
    Object? endDate = _unset,
    List<RecordAct>? acts,
    Object? openTime = _unset,
    Object? startTime = _unset,
    Object? endTime = _unset,
    List<String>? songs,
    Map<RecordTextField, String>? texts,
    Object? selectedImage = _unset,
    bool? removeSavedImage,
    bool? isSaving,
    int? actsRevision,
    int? setlistRevision,
  }) => RecordFormState(
    type: type ?? this.type,
    eventFormat: eventFormat ?? this.eventFormat,
    date: date ?? this.date,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
    acts: acts ?? this.acts,
    openTime: identical(openTime, _unset)
        ? this.openTime
        : openTime as ClockTime?,
    startTime: identical(startTime, _unset)
        ? this.startTime
        : startTime as ClockTime?,
    endTime: identical(endTime, _unset) ? this.endTime : endTime as ClockTime?,
    songs: songs ?? this.songs,
    texts: texts ?? this.texts,
    selectedImage: identical(selectedImage, _unset)
        ? this.selectedImage
        : selectedImage as File?,
    removeSavedImage: removeSavedImage ?? this.removeSavedImage,
    existingImageUrl: existingImageUrl,
    isSaving: isSaving ?? this.isSaving,
    actsRevision: actsRevision ?? this.actsRevision,
    setlistRevision: setlistRevision ?? this.setlistRevision,
  );

  /// [values] の欄だけ書き換える。
  RecordFormState withTexts(Map<RecordTextField, String> values) =>
      copyWith(texts: Map.unmodifiable({...texts, ...values}));
}
