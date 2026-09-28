import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// iOS のウィジェット拡張と共有する App Group。Runner / RecolleWidget の entitlements と揃える。
const homeWidgetAppGroupId = 'group.com.ishidaminato.recolle';

/// ウィジェットの `kind`（Swift 側の各 Widget の kind）。全予定・ライブ・映画・その他の 4 種。
const _iOSWidgetKinds = [
  'RecolleWidget',
  'RecolleLiveWidget',
  'RecolleMovieWidget',
  'RecolleOtherWidget',
];
const _dataKey = 'upcoming_events';

/// 種類ごとにウィジェットへ渡す件数。公演が過ぎてもアプリを開くまで次の公演へ進めるよう、数件先まで渡す。
/// 種類ごとに数えるのは、ライブが多くても映画・その他のウィジェットが空にならないようにするため。
const _maxEventsPerType = 5;

/// ウィジェットに渡す「これから」の記録（近い順）。日時はエポックミリ秒で、開場・終演は未入力なら null。
List<Map<String, Object?>> upcomingEventsPayload(
  Iterable<Record> records,
  DateTime now,
) {
  final counts = <RecordType, int>{};
  final selected = <Record>[];
  for (final r in splitByDate(records, now).upcoming) {
    final count = (counts[r.type] ?? 0) + 1;
    counts[r.type] = count;
    if (count <= _maxEventsPerType) selected.add(r);
  }
  return [
    for (final r in selected)
      {
        'title': r.title,
        'artist': r.artistOrAuthor,
        'type': r.type.name,
        'startsAt': r.startsAt.millisecondsSinceEpoch,
        'hasStartTime': r.startTime != null,
        'opensAt': r.opensAt?.millisecondsSinceEpoch,
        'endsAt': r.endsAt?.millisecondsSinceEpoch,
        'venue': r.venue,
        'isLive': r.type == RecordType.live,
        'startLabel': r.type.startTimeLabel,
        'endLabel': r.type.endTimeLabel,
        'inProgressLabel': r.type.inProgressLabel,
      },
  ];
}

/// 記録が変わるたびに呼び、ホーム画面ウィジェットの表示を更新する。iOS 以外では何もしない。
Future<void> syncHomeWidget(Iterable<Record> records) async {
  if (kIsWeb || !Platform.isIOS) return;
  try {
    await HomeWidget.setAppGroupId(homeWidgetAppGroupId);
    await HomeWidget.saveWidgetData<String>(
      _dataKey,
      jsonEncode(upcomingEventsPayload(records, DateTime.now())),
    );
    for (final kind in _iOSWidgetKinds) {
      await HomeWidget.updateWidget(iOSName: kind);
    }
  } catch (e) {
    // ウィジェットは補助機能なので、失敗してもアプリの操作は止めない
    debugPrint('Home widget sync failed: $e');
  }
}
