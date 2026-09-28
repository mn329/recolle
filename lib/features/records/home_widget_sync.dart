import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/record_timeline.dart';

/// iOS のウィジェット拡張と共有する App Group。Runner / RecolleWidget の entitlements と揃える。
const homeWidgetAppGroupId = 'group.com.ishidaminato.recolle';

/// ウィジェットの `kind`（Swift 側の構造体名）。
const _iOSWidgetName = 'RecolleWidget';
const _dataKey = 'upcoming_events';

/// ウィジェットに渡す件数。公演が過ぎてもアプリを開くまで次の公演へ進めるよう、数件先まで渡す。
const _maxEvents = 5;

/// ウィジェットに渡す「これから」の記録（近い順）。日時はエポックミリ秒で、開場・終演は未入力なら null。
List<Map<String, Object?>> upcomingEventsPayload(
  Iterable<Record> records,
  DateTime now,
) {
  return [
    for (final r in splitByDate(records, now).upcoming.take(_maxEvents))
      {
        'title': r.title,
        'artist': r.artistOrAuthor,
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
    await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
  } catch (e) {
    // ウィジェットは補助機能なので、失敗してもアプリの操作は止めない
    debugPrint('Home widget sync failed: $e');
  }
}
