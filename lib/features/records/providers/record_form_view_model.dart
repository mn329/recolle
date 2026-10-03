import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/account/providers/auth_providers.dart';
import 'package:recolle/features/favorites/auto_favorite.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/setlist_localization.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/data/records_local_cache.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_state.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:uuid/uuid.dart';

export 'package:recolle/features/records/providers/record_form_state.dart';

final recordFormProvider = NotifierProvider.autoDispose
    .family<RecordFormViewModel, RecordFormState, RecordFormArgs>(
      RecordFormViewModel.new,
    );

/// [RecordFormViewModel.save] の結果。
sealed class RecordSaveResult {
  const RecordSaveResult();
}

/// 入力内容に問題があり、保存しなかった。
class RecordSaveInvalid extends RecordSaveResult {
  const RecordSaveInvalid(this.message);

  final String message;
}

class RecordSaveSucceeded extends RecordSaveResult {
  const RecordSaveSucceeded(this.record, {required this.autoFavorited});

  final Record record;

  /// 自動でお気に入りに追加できたアーティスト。
  /// 画像の検索で保存の完了を待たせないよう、保存とは別に進める。
  final Future<List<String>> autoFavorited;
}

class RecordSaveFailed extends RecordSaveResult {
  const RecordSaveFailed(this.message);

  final String message;
}

/// 記録の作成・編集フォームの ViewModel。
///
/// トーストや画面遷移は View の役目なので、操作の結果（入力した項目名など）を返すだけにする。
class RecordFormViewModel extends Notifier<RecordFormState> {
  RecordFormViewModel(this._args);

  final RecordFormArgs _args;
  late RecordFormState _initial;

  /// 新しい記録の ID。保存に失敗して保存し直しても同じ記録になるよう、フォームを開いている間は固定する。
  final _newRecordId = const Uuid().v4();

  @override
  RecordFormState build() {
    // 保存時に読むログイン中のユーザーを、読み込み済みのまま保つ。
    // watch だとトークン更新のたびに入力内容が初期化されるので listen にする。
    ref.listen(authUserProvider, (_, _) {});
    return _initial = RecordFormState.initial(_args);
  }

  bool get isEditMode => _args.recordToEdit != null;

  /// 開いたときから入力内容が変わったか。
  bool get isDirty => state.hasChangesFrom(_initial);

  void setType(RecordType type) => state = state.copyWith(type: type);

  void updateText(RecordTextField field, String value) =>
      state = state.withTexts({field: value});

  void setSongs(List<String> songs) => state = state.copyWith(songs: songs);

  void setActs(List<RecordAct> acts) => state = state.copyWith(acts: acts);

  void setOpenTime(ClockTime? time) => state = state.copyWith(openTime: time);

  void setStartTime(ClockTime? time) => state = state.copyWith(startTime: time);

  void setEndTime(ClockTime? time) => state = state.copyWith(endTime: time);

  void changeDate(DateTime date) {
    final end = state.endDate;
    state = state.copyWith(
      date: date,
      endDate: end != null && !end.isAfter(date) ? null : end,
    );
  }

  /// 開催日以前を選んだら、1 日だけの公演に戻す。
  void setEndDate(DateTime date) =>
      state = state.copyWith(endDate: date.isAfter(state.date) ? date : null);

  /// 入力済みのアーティストとセトリは、形式を変えても引き継ぐ。
  void changeFormat(EventFormat next) {
    final current = state;
    final previous = current.eventFormat;
    if (next == previous) return;

    var updated = current;
    if (next.hasMultipleActs && !previous.hasMultipleActs) {
      if (current.namedActs.isEmpty &&
          (current.artist.isNotEmpty || current.songs.isNotEmpty)) {
        updated = updated.copyWith(
          acts: [
            RecordAct(
              artist: current.artist,
              songs: current.songs,
              isMain: true,
            ),
          ],
          actsRevision: current.actsRevision + 1,
        );
      }
    } else if (!next.hasMultipleActs && previous.hasMultipleActs) {
      final lead = current.leadAct;
      if (current.artist.isEmpty && lead != null) {
        updated = updated.withTexts({RecordTextField.artist: lead.artist});
        if (current.songs.isEmpty && lead.songs.isNotEmpty) {
          updated = updated.copyWith(
            songs: lead.songs,
            setlistRevision: current.setlistRevision + 1,
          );
        }
      }
    }
    updated = updated.copyWith(eventFormat: next);
    if (next != EventFormat.festival) updated = updated.copyWith(endDate: null);
    state = updated;
  }

  void pickArtist(String name) =>
      state = state.withTexts({RecordTextField.artist: name});

  /// 映画・本の候補から、題名と監督・著者を入れる。
  void pickWork(WorkSuggestion work) {
    final creator = work.creator;
    state = state.withTexts({
      RecordTextField.title: _fit(work.title, RecordFieldLimits.title),
      if (creator != null && creator.length <= RecordFieldLimits.artistOrAuthor)
        RecordTextField.artist: creator,
    });
  }

  /// 公演の候補を取り込み、入力した項目名を返す。
  /// 取り込み中に画面が閉じられたら null。
  ///
  /// 入力済みのセトリは上書きしない。曲名の日本語化を待つ間に手で入れた曲も同様。
  Future<List<String>?> applyConcert(ConcertCandidate candidate) async {
    final before = state;
    final kind = before.type;
    final filled = [before.titleLabel];
    state = state.withTexts({
      RecordTextField.title: _fit(candidate.title, RecordFieldLimits.title),
    });

    if (candidate.fillsDetails) {
      if (candidate.date case final d?) {
        changeDate(d);
        filled.add('公演日');
      }
      if (candidate.venue case final v? when before.hasVenue) {
        state = state.withTexts({
          RecordTextField.venue: _fit(v, RecordFieldLimits.venue),
        });
        filled.add(kind.venueLabel!);
      }
      if (candidate.openTime case final t? when kind.hasOpenTime) {
        state = state.copyWith(openTime: t);
        filled.add('開場');
      }
      if (candidate.startTime case final t? when kind.hasSchedule) {
        state = state.copyWith(startTime: t);
        filled.add(kind.startTimeLabel);
      }
    }

    final lead = before.leadAct;
    final isMultiAct = before.isMultiAct;
    final targetEmpty = isMultiAct
        ? lead != null && lead.songs.isEmpty
        : state.songs.isEmpty;
    if (!candidate.fillsDetails || candidate.songs.isEmpty || !targetEmpty) {
      return filled;
    }

    final localized = await localizeSetlistSongs(
      ref.read(itunesClientProvider),
      artistName: before.lookupArtist,
      songs: candidate.songs,
    );
    if (!ref.mounted) return null;
    if (localized.join('\n').length > RecordFieldLimits.setlistTotal) {
      return filled;
    }

    final current = state;
    if (isMultiAct && lead != null) {
      final index = current.acts.indexWhere(
        (a) => a.artist.trim() == lead.artist && a.songs.isEmpty,
      );
      if (index >= 0) {
        state = current.copyWith(
          acts: [
            for (final (i, a) in current.acts.indexed)
              i == index ? a.copyWith(songs: localized) : a,
          ],
          actsRevision: current.actsRevision + 1,
        );
        filled.add('${lead.artist}のセットリスト');
      }
    } else if (!isMultiAct && current.songs.isEmpty) {
      state = current.copyWith(
        songs: localized,
        setlistRevision: current.setlistRevision + 1,
      );
      filled.add('セットリスト');
    }
    return filled;
  }

  /// チケットのメールから読み取った項目を入れ、入力した項目名を返す。
  List<String> applyMailInfo(TicketMailInfo info) {
    final current = state;
    final kind = current.type;
    final texts = <RecordTextField, String>{};
    void fill(RecordTextField field, String? value, int maxLength) {
      if (value != null) texts[field] = _fit(value, maxLength);
    }

    var updated = current;
    fill(RecordTextField.title, info.title, RecordFieldLimits.title);
    if (current.isMultiAct) {
      final name = _fit(
        info.artist?.trim() ?? '',
        RecordFieldLimits.artistOrAuthor,
      );
      if (name.isNotEmpty && current.namedActs.every((a) => a.artist != name)) {
        updated = updated.copyWith(
          acts: [
            ...current.namedActs,
            // お目当てはすでに決まっていれば、そのままにする
            RecordAct(
              artist: name,
              isMain: !current.namedActs.any((a) => a.isMain),
            ),
          ],
          actsRevision: current.actsRevision + 1,
        );
      }
    } else {
      fill(
        RecordTextField.artist,
        info.artist,
        RecordFieldLimits.artistOrAuthor,
      );
    }
    fill(
      RecordTextField.source,
      info.ticketSource,
      RecordFieldLimits.ticketSource,
    );

    final priceFits =
        info.ticketPrice != null &&
        info.ticketPrice! <= RecordFieldLimits.ticketPriceMax;
    final useOpen = kind.hasOpenTime && info.openTime != null;
    final useStart = kind.hasSchedule && info.startTime != null;
    final useEnd = kind.hasSchedule && info.endTime != null;
    final useVenue = current.hasVenue && info.venue != null;
    final useSeat = current.hasSeat && info.seat != null;
    if (useVenue) {
      fill(RecordTextField.venue, info.venue, RecordFieldLimits.venue);
    }
    if (useSeat) fill(RecordTextField.seat, info.seat, RecordFieldLimits.seat);
    if (priceFits) texts[RecordTextField.price] = '${info.ticketPrice}';
    fill(RecordTextField.link, info.linkUrl, RecordFieldLimits.linkUrl);

    updated = updated.withTexts(texts);
    if (useOpen) updated = updated.copyWith(openTime: info.openTime);
    if (useStart) updated = updated.copyWith(startTime: info.startTime);
    if (useEnd) updated = updated.copyWith(endTime: info.endTime);
    state = updated;
    if (info.date case final d?) changeDate(d);

    return [
      if (info.title != null) current.titleLabel,
      if (info.artist != null)
        current.isMultiAct ? '出演者' : kind.creatorFieldLabel,
      if (info.date != null) current.isLive ? '公演日' : '日付',
      if (useOpen) '開場',
      if (useStart) kind.startTimeLabel,
      if (useEnd) kind.endTimeLabel,
      if (useVenue) kind.venueLabel!,
      if (useSeat) '座席',
      if (priceFits) kind.priceLabel,
      if (info.ticketSource != null) '取得元',
      if (info.linkUrl != null) 'リンク',
    ];
  }

  /// 選んだ画像を後ろに足す。上限を超える分は捨てる。
  void addImages(List<File> files) {
    final room = state.remainingImageSlots;
    if (room == 0 || files.isEmpty) return;
    state = state.copyWith(
      images: [
        ...state.images,
        for (final file in files.take(room)) PickedTicketImage(file),
      ],
    );
  }

  void removeImageAt(int index) =>
      state = state.copyWith(images: [...state.images]..removeAt(index));

  /// [index] の画像を先頭（一覧に出す表紙）へ移す。
  void makeCover(int index) {
    if (index == 0) return;
    final images = [...state.images];
    images.insert(0, images.removeAt(index));
    state = state.copyWith(images: images);
  }

  /// 記録を保存する。保存できない状態（必須項目の不足・保存中）なら null。
  Future<RecordSaveResult?> save() async {
    final form = state;
    if (!form.canSave) return null;
    final error = form.validate();
    if (error != null) return RecordSaveInvalid(error);

    state = state.copyWith(isSaving: true);
    try {
      final userId = (await ref.read(authUserProvider.future))?.id;
      if (userId == null) return const RecordSaveInvalid('ログインしてください');

      final repo = ref.read(recordsRepositoryProvider);
      final favoritesNotifier = ref.read(favoriteArtistsProvider.notifier);
      final favorites = ref.read(favoriteArtistsProvider).asData?.value;

      final uploaded = <String>[];
      final Record saved;
      try {
        final ticketImageUrls = await Future.wait([
          for (final image in form.images)
            switch (image) {
              SavedTicketImage(:final url) => Future.value(url),
              PickedTicketImage(:final file) =>
                repo.uploadTicketImage(userId: userId, file: file).then((url) {
                  uploaded.add(url);
                  return url;
                }),
            },
        ]);
        final editing = _args.recordToEdit;
        final record = form.toRecord(
          id: editing?.id ?? _newRecordId,
          ticketImageUrls: ticketImageUrls,
        );
        try {
          saved = editing != null
              ? await repo.updateRecord(editing.id, record.toJson())
              : await repo.insertRecord({
                  ...record.toJson(),
                  'id': _newRecordId,
                  'user_id': userId,
                });
        } on RecordWriteUncertain {
          // 記録がこれらの画像を指して保存されているかもしれないので消さない。
          // 保存し直したときに同じ画像を使うよう、アップロード済みとしてフォームに持たせる
          if (ref.mounted) {
            state = state.copyWith(
              images: [
                for (final url in ticketImageUrls) SavedTicketImage(url),
              ],
            );
          }
          uploaded.clear();
          rethrow;
        }
      } catch (_) {
        // 記録に結び付かなかった画像をストレージに残さない
        _deleteImagesQuietly(repo, uploaded);
        rethrow;
      }
      _deleteImagesQuietly(repo, form.removedImageUrls(_initial));
      // キャッシュが古いままだと、再読み込みの先頭で保存前の一覧が一瞬出る
      await RecordsLocalCache()
          .upsert(userId, saved)
          .timeout(const Duration(seconds: 2))
          .catchError((Object e) {
            debugPrint('Records cache update failed: $e');
          });
      if (ref.mounted) ref.invalidate(recordsProvider);

      final editing = _args.recordToEdit;
      final names = favorites == null
          ? const <String>[]
          : artistsToAutoFavorite(
              saved,
              previous: editing,
              favorites: favorites,
            );
      return RecordSaveSucceeded(
        saved,
        autoFavorited: names.isEmpty
            ? Future.value(const <String>[])
            : addAutoFavorites(
                names,
                add: (name) => favoritesNotifier.add(name: name),
              ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error saving record: $e\n$stackTrace');
      return RecordSaveFailed(toUserFriendlyMessage(e));
    } finally {
      if (ref.mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// 画像の片付けは、失敗しても保存の結果は変えずにログだけ残す。
  static void _deleteImagesQuietly(RecordsRepository repo, List<String> urls) {
    if (urls.isEmpty) return;
    unawaited(
      repo.deleteTicketImages(urls).catchError((Object e, StackTrace st) {
        debugPrint('Failed to delete ticket images: $e\n$st');
      }),
    );
  }

  static String _fit(String value, int maxLength) =>
      value.length > maxLength ? value.substring(0, maxLength) : value;
}
