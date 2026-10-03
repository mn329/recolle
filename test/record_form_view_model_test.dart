import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/constants/ticket_image_settings.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_view_model.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class _FakeRepository implements RecordsRepository {
  final inserted = <Map<String, dynamic>>[];
  final updated = <(String, Map<String, dynamic>)>[];
  final uploaded = <File>[];
  final deletedImages = <String>[];

  /// 指定すると、記録の保存でこの例外を投げる。
  Object? saveError;

  Record _toRecord(String id, Map<String, dynamic> row) =>
      Record.fromJson({...row, 'id': id});

  @override
  Future<Record> insertRecord(Map<String, dynamic> row) async {
    if (saveError case final error?) throw error;
    inserted.add(row);
    return _toRecord('new', row);
  }

  @override
  Future<Record> updateRecord(String id, Map<String, dynamic> row) async {
    updated.add((id, row));
    return _toRecord(id, row);
  }

  @override
  Future<String> uploadTicketImage({
    required String userId,
    required File file,
  }) async {
    uploaded.add(file);
    return 'https://storage/${file.path}';
  }

  @override
  Future<void> deleteTicketImages(List<String> urls) async =>
      deletedImages.addAll(urls);

  @override
  Future<void> deleteRecord(String id) async {}
}

class _RecordingFavorites extends FavoriteArtistsNotifier {
  final added = <String>[];

  @override
  Future<List<FavoriteArtist>> build() async => const [];

  @override
  Future<FavoriteArtist> add({
    required String name,
    int? itunesArtistId,
  }) async {
    added.add(name);
    return FavoriteArtist(id: name, name: name, createdAt: DateTime(2026));
  }
}

class _FakeItunesClient extends ItunesClient {
  _FakeItunesClient(this.japaneseTitles);

  final Map<String, String> japaneseTitles;

  @override
  Future<Map<String, String>> localizeSongTitles({
    required String artistName,
    required List<String> titles,
    int maxIndividualLookups = 6,
  }) async => {
    for (final t in titles)
      if (japaneseTitles[t] case final ja?) t: ja,
  };
}

final _user = User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

typedef _Harness = ({
  ProviderContainer container,
  RecordFormViewModel vm,
  _FakeRepository repository,
  _RecordingFavorites favorites,
});

Future<_Harness> _harness({
  RecordFormArgs args = const RecordFormArgs(),
  Map<String, String> japaneseTitles = const {},
  bool signedIn = true,
}) async {
  final repository = _FakeRepository();
  final favorites = _RecordingFavorites();
  final container = ProviderContainer(
    overrides: [
      authUserProvider.overrideWith(
        (ref) => Stream.value(signedIn ? _user : null),
      ),
      recordsRepositoryProvider.overrideWithValue(repository),
      recordsProvider.overrideWith((ref) => Stream.value(const [])),
      favoriteArtistsProvider.overrideWith(() => favorites),
      itunesClientProvider.overrideWithValue(_FakeItunesClient(japaneseTitles)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(recordFormProvider(args), (_, _) {});
  await container.read(favoriteArtistsProvider.future);
  return (
    container: container,
    vm: container.read(recordFormProvider(args).notifier),
    repository: repository,
    favorites: favorites,
  );
}

void main() {
  group('入力の検証', () {
    test('必須項目が揃うまでは保存できず、足りない項目を返す', () async {
      final h = await _harness();

      expect(h.vm.state.missingLabels, ['アーティスト', '公演名・ツアー名']);
      expect(h.vm.state.canSave, isFalse);
      expect(await h.vm.save(), isNull);

      h.vm.updateText(RecordTextField.artist, 'YOASOBI');
      h.vm.updateText(RecordTextField.title, 'ZEPP TOUR');
      expect(h.vm.state.canSave, isTrue);
    });

    test('料金が上限を超えるときは保存しない', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'YOASOBI');
      h.vm.updateText(RecordTextField.title, 'TOUR');
      h.vm.updateText(
        RecordTextField.price,
        '${RecordFieldLimits.ticketPriceMax + 1}',
      );

      final result = await h.vm.save();

      expect(result, isA<RecordSaveInvalid>());
      expect((result! as RecordSaveInvalid).message, contains('チケット代'));
      expect(h.repository.inserted, isEmpty);
    });

    test('開場が開演より遅いときは保存しない', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'YOASOBI');
      h.vm.updateText(RecordTextField.title, 'TOUR');
      h.vm.setOpenTime(const ClockTime(19, 0));
      h.vm.setStartTime(const ClockTime(18, 0));

      final result = await h.vm.save();

      expect((result! as RecordSaveInvalid).message, '開場は開演より前の時刻にしてください。');
    });

    test('日をまたぐ公演は、開場が開演より遅い時刻でも保存できる', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'YOASOBI');
      h.vm.updateText(RecordTextField.title, 'COUNTDOWN');
      h.vm.setOpenTime(const ClockTime(23, 30));
      h.vm.setStartTime(const ClockTime(0, 30));

      final result = await h.vm.save();

      expect(result, isNot(isA<RecordSaveInvalid>()));
      expect(h.repository.inserted, hasLength(1));
    });

    test('URL として読めないリンクは保存せず、https:// を省いたリンクは補って保存する', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'YOASOBI');
      h.vm.updateText(RecordTextField.title, 'TOUR');
      h.vm.updateText(RecordTextField.link, 'チケットのページ');

      final invalid = await h.vm.save();
      expect((invalid! as RecordSaveInvalid).message, contains('リンク'));
      expect(h.repository.inserted, isEmpty);

      h.vm.updateText(RecordTextField.link, 'eplus.jp/sf/detail/123');
      await h.vm.save();
      expect(
        h.repository.inserted.single['link_url'],
        'https://eplus.jp/sf/detail/123',
      );
    });
  });

  group('形式の切り替え', () {
    test('対バンにすると、アーティストとセトリをお目当ての出演者として引き継ぐ', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'sumika');
      h.vm.setSongs(const ['Lovers']);

      h.vm.changeFormat(EventFormat.taiban);

      expect(h.vm.state.acts, const [
        RecordAct(artist: 'sumika', songs: ['Lovers'], isMain: true),
      ]);
      expect(h.vm.state.actsRevision, 1);
      expect(h.vm.state.missingLabels, ['イベント名・対バン名']);
    });

    test('ワンマンに戻すと、お目当ての出演者をアーティストとセトリに戻す', () async {
      final h = await _harness();
      h.vm.changeFormat(EventFormat.festival);
      h.vm.setActs(const [
        RecordAct(artist: 'sumika'),
        RecordAct(artist: 'Vaundy', songs: ['怪獣の花唄'], isMain: true),
      ]);
      h.vm.setEndDate(h.vm.state.date.add(const Duration(days: 1)));

      h.vm.changeFormat(EventFormat.oneman);

      expect(h.vm.state.artist, 'Vaundy');
      expect(h.vm.state.songs, ['怪獣の花唄']);
      expect(h.vm.state.setlistRevision, 1);
      expect(h.vm.state.endDate, isNull);
    });
  });

  test('メールの取り込みは長すぎる値を切り詰め、入力した項目名を返す', () async {
    final h = await _harness();
    final longTitle = 'A' * (RecordFieldLimits.title + 10);

    final filled = h.vm.applyMailInfo(
      TicketMailInfo(
        title: longTitle,
        artist: 'YOASOBI',
        date: DateTime(2026, 5, 3),
        ticketSource: 'ローチケ',
        seat: 'アリーナ A5',
        ticketPrice: 9800,
        openTime: const ClockTime(17, 0),
      ),
    );

    expect(h.vm.state.title.length, RecordFieldLimits.title);
    expect(h.vm.state.artist, 'YOASOBI');
    expect(h.vm.state.date, DateTime(2026, 5, 3));
    expect(h.vm.state.text(RecordTextField.price), '9800');
    expect(h.vm.state.openTime, const ClockTime(17, 0));
    expect(filled, ['公演名・ツアー名', 'アーティスト', '公演日', '開場', '座席', 'チケット代', '取得元']);
  });

  group('公演の候補', () {
    test('日本語化したセトリを入れる', () async {
      final h = await _harness(japaneseTitles: const {'Hikoutei': '飛行艇'});
      h.vm.updateText(RecordTextField.artist, 'King Gnu');

      final filled = await h.vm.applyConcert(
        ConcertCandidate(
          title: 'ARENA TOUR',
          source: ConcertCandidateSource.setlistFm,
          date: DateTime(2025, 5, 3),
          venue: '東京ドーム',
          songs: const ['Hikoutei', '白日'],
        ),
      );

      expect(h.vm.state.songs, ['飛行艇', '白日']);
      expect(h.vm.state.setlistRevision, 1);
      expect(filled, ['公演名・ツアー名', '公演日', '会場', 'セットリスト']);
    });

    test('入力済みのセトリは上書きしない', () async {
      final h = await _harness();
      h.vm.updateText(RecordTextField.artist, 'King Gnu');
      h.vm.setSongs(const ['一途']);

      final filled = await h.vm.applyConcert(
        const ConcertCandidate(
          title: 'ARENA TOUR',
          source: ConcertCandidateSource.setlistFm,
          songs: ['白日'],
        ),
      );

      expect(h.vm.state.songs, ['一途']);
      expect(filled, ['公演名・ツアー名']);
    });

    test('過去の記録からは公演名だけを入れる', () async {
      final h = await _harness();

      await h.vm.applyConcert(
        const ConcertCandidate(
          title: 'HALL TOUR',
          source: ConcertCandidateSource.record,
          venue: '日本武道館',
        ),
      );

      expect(h.vm.state.title, 'HALL TOUR');
      expect(h.vm.state.text(RecordTextField.venue), isEmpty);
    });
  });

  group('保存', () {
    test('対バンは見出しにお目当てを入れて新規登録し、お気に入りに追加する', () async {
      final h = await _harness();
      h.vm.changeFormat(EventFormat.taiban);
      h.vm.setActs(const [
        RecordAct(artist: 'sumika', isMain: true),
        RecordAct(artist: 'Vaundy'),
        RecordAct(artist: '  '),
      ]);
      h.vm.updateText(RecordTextField.title, '対バン');

      final result = await h.vm.save();

      final success = result! as RecordSaveSucceeded;
      expect(success.record.artistOrAuthor, 'sumika');
      expect(success.record.acts.map((a) => a.artist), ['sumika', 'Vaundy']);
      expect(h.repository.inserted.single['user_id'], 'u1');
      expect(await success.autoFavorited, ['sumika']);
      expect(h.favorites.added, ['sumika']);
      expect(h.vm.state.isSaving, isFalse);
    });

    test('フェスは最終日を残し、日数を超える出演日は範囲内に丸める', () async {
      final h = await _harness();
      h.vm.changeFormat(EventFormat.festival);
      h.vm.changeDate(DateTime(2026, 8, 1));
      h.vm.setEndDate(DateTime(2026, 8, 2));
      h.vm.setActs(const [
        RecordAct(artist: 'サカナクション', isMain: true, day: 3),
        RecordAct(artist: 'sumika'),
      ]);
      h.vm.updateText(RecordTextField.title, 'ROCK IN JAPAN');

      final saved = (await h.vm.save())! as RecordSaveSucceeded;

      expect(saved.record.endDate, DateTime(2026, 8, 2));
      expect(saved.record.acts.map((a) => a.day), [2, 1]);
    });

    test('編集では更新し、新しく選んだ画像だけをアップロードして後ろに足す', () async {
      final record = Record(
        id: 'r1',
        type: RecordType.movie,
        title: 'ルックバック',
        artistOrAuthor: '押山清高',
        date: DateTime(2026, 11, 3),
        ticketImageUrls: const ['https://storage/old.jpg'],
        seat: 'G-12',
      );
      final h = await _harness(args: RecordFormArgs(recordToEdit: record));
      h.vm.addImages([File('a.jpg'), File('b.jpg')]);

      final saved = (await h.vm.save())! as RecordSaveSucceeded;

      expect(h.repository.inserted, isEmpty);
      expect(h.repository.updated.single.$1, 'r1');
      expect(h.repository.uploaded.map((f) => f.path), ['a.jpg', 'b.jpg']);
      expect(saved.record.ticketImageUrls, [
        'https://storage/old.jpg',
        'https://storage/a.jpg',
        'https://storage/b.jpg',
      ]);
      expect(
        h.repository.updated.single.$2['ticket_image_url'],
        'https://storage/old.jpg',
      );
      expect(h.repository.deletedImages, isEmpty);
      expect(saved.record.seat, 'G-12');
      expect(await saved.autoFavorited, isEmpty);
    });

    test('外した保存済みの画像は、保存できたらストレージから消す', () async {
      final record = Record(
        id: 'r1',
        type: RecordType.movie,
        title: 'ルックバック',
        artistOrAuthor: '押山清高',
        date: DateTime(2026, 11, 3),
        ticketImageUrls: const [
          'https://storage/1.jpg',
          'https://storage/2.jpg',
        ],
      );
      final h = await _harness(args: RecordFormArgs(recordToEdit: record));
      h.vm.removeImageAt(0);

      final saved = (await h.vm.save())! as RecordSaveSucceeded;

      expect(saved.record.ticketImageUrls, ['https://storage/2.jpg']);
      expect(h.repository.deletedImages, ['https://storage/1.jpg']);
    });

    test('記録の保存に失敗したら、アップロードした画像を消して元の画像は残す', () async {
      final h = await _harness(
        args: const RecordFormArgs(initialArtist: 'YOASOBI'),
      );
      h.vm.updateText(RecordTextField.title, 'TOUR');
      h.vm.addImages([File('a.jpg')]);
      h.repository.saveError = Exception('network');

      final result = await h.vm.save();

      expect(result, isA<RecordSaveFailed>());
      expect(h.repository.deletedImages, ['https://storage/a.jpg']);
      expect(h.vm.state.images, [PickedTicketImage(File('a.jpg'))]);
    });

    test('保存の応答がないときは画像を残し、保存し直すと同じ ID・同じ画像で保存する', () async {
      final h = await _harness(
        args: const RecordFormArgs(initialArtist: 'YOASOBI'),
      );
      h.vm.updateText(RecordTextField.title, 'TOUR');
      h.vm.addImages([File('a.jpg')]);
      h.repository.saveError = const RecordWriteUncertain();

      final first = await h.vm.save();

      expect(
        (first! as RecordSaveFailed).message,
        const RecordWriteUncertain().userMessage,
      );
      expect(h.repository.deletedImages, isEmpty);
      expect(h.vm.state.images, [
        const SavedTicketImage('https://storage/a.jpg'),
      ]);

      h.repository.saveError = null;
      final second = await h.vm.save();

      expect(second, isA<RecordSaveSucceeded>());
      expect(h.repository.uploaded.map((f) => f.path), ['a.jpg']);
      expect(h.repository.inserted.single['ticket_image_urls'], [
        'https://storage/a.jpg',
      ]);
      expect(h.repository.inserted.single['id'], isA<String>());
    });

    test('新しい記録は、保存するたびに同じ ID を使う', () async {
      final h = await _harness(
        args: const RecordFormArgs(initialArtist: 'YOASOBI'),
      );
      h.vm.updateText(RecordTextField.title, 'TOUR');

      await h.vm.save();
      await h.vm.save();

      final ids = h.repository.inserted.map((row) => row['id']).toSet();
      expect(ids, hasLength(1));
      expect(ids.single, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('ログインしていなければ保存しない', () async {
      final h = await _harness(
        args: const RecordFormArgs(initialArtist: 'YOASOBI'),
        signedIn: false,
      );
      h.vm.updateText(RecordTextField.title, 'TOUR');

      final result = await h.vm.save();

      expect((result! as RecordSaveInvalid).message, 'ログインしてください');
      expect(h.repository.inserted, isEmpty);
      expect(h.vm.state.isSaving, isFalse);
    });
  });

  group('チケット画像', () {
    test('上限を超えて選んだ分は足さない', () async {
      final h = await _harness();
      h.vm.addImages([for (var i = 0; i < 4; i++) File('$i.jpg')]);
      h.vm.addImages([File('4.jpg'), File('5.jpg')]);

      expect(h.vm.state.images, hasLength(TicketImageSettings.maxCount));
      expect(h.vm.state.remainingImageSlots, 0);
      expect(h.vm.state.images.last, PickedTicketImage(File('4.jpg')));
    });

    test('表紙にした画像を先頭へ移し、ほかの並びは保つ', () async {
      final h = await _harness();
      h.vm.addImages([File('a.jpg'), File('b.jpg'), File('c.jpg')]);

      h.vm.makeCover(2);

      expect(h.vm.state.images, [
        PickedTicketImage(File('c.jpg')),
        PickedTicketImage(File('a.jpg')),
        PickedTicketImage(File('b.jpg')),
      ]);
      expect(h.vm.isDirty, isTrue);
    });
  });

  group('isDirty', () {
    test('変えたら true、元に戻したら false', () async {
      final h = await _harness();
      expect(h.vm.isDirty, isFalse);

      h.vm.updateText(RecordTextField.impressions, 'よかった');
      expect(h.vm.isDirty, isTrue);

      h.vm.updateText(RecordTextField.impressions, '');
      expect(h.vm.isDirty, isFalse);
    });

    test('編集で開いただけなら false', () async {
      final h = await _harness(
        args: RecordFormArgs(
          recordToEdit: Record(
            id: 'r1',
            type: RecordType.live,
            title: 'TOUR',
            artistOrAuthor: 'YOASOBI',
            date: DateTime(2026, 9, 1),
            setlist: 'アイドル\n祝福',
          ),
        ),
      );

      expect(h.vm.state.songs, ['アイドル', '祝福']);
      expect(h.vm.isDirty, isFalse);
    });
  });
}
