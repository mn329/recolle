import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/constants/ticket_image_settings.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/ticket_image_compress.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/auto_favorite.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/setlist_localization.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/data/place_search_client.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/ticket_mail_import_sheet.dart';
import 'package:recolle/features/records/widgets/record_form/acts_editor.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_time_row.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';
import 'package:recolle/features/records/widgets/record_form/ticket_preview_picker.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 記録の作成・編集フォーム。保存したら [Record] を返して閉じる。
///
/// 通常は `openRecordEditor` から iOS のシートとして開く。
class CreateRecordScreen extends HookConsumerWidget {
  const CreateRecordScreen({
    super.key,
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

  /// キーボード表示中でも、入力欄の下に出る候補リストまで見えるようにする余白。
  static const _fieldScrollPadding = EdgeInsets.fromLTRB(20, 24, 20, 160);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editingRecord = recordToEdit;
    final isEditMode = editingRecord != null;
    final draft = isEditMode ? null : prefill;

    final startType = editingRecord?.type ?? initialType ?? RecordType.live;
    final initialDate = useMemoized(
      () => editingRecord?.date ?? draft?.date ?? DateTime.now(),
    );
    final initialSongs = useMemoized(
      () => (editingRecord?.setlist ?? '')
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );

    final type = useState(startType);
    final date = useState(initialDate);
    final startFormat = editingRecord?.eventFormat ?? EventFormat.oneman;
    final eventFormat = useState(startFormat);
    final initialEndDate = editingRecord?.endDate;
    final endDate = useState(initialEndDate);
    final initialActs = editingRecord?.acts ?? const <RecordAct>[];
    final acts = useState(initialActs);
    // 形式の切り替えや候補の取り込みで出演者を差し替えたときに、出演者欄を作り直す
    final actsEditorGeneration = useState(0);
    final initialOpenTime = editingRecord?.openTime ?? draft?.openTime;
    final initialStartTime = editingRecord?.startTime ?? draft?.startTime;
    final initialEndTime = editingRecord?.endTime ?? draft?.endTime;
    final openTime = useState(initialOpenTime);
    final startTime = useState(initialStartTime);
    final endTime = useState(initialEndTime);
    final songs = useState(initialSongs);
    final selectedImage = useState<File?>(null);
    final removeSavedImage = useState(false);
    final isSaving = useState(false);

    final titleController = useTextEditingController(
      text: editingRecord?.title ?? draft?.title,
    );
    final artistController = useTextEditingController(
      text: editingRecord?.artistOrAuthor ?? draft?.artist ?? initialArtist,
    );
    final sourceController = useTextEditingController(
      text: editingRecord?.ticketSource ?? draft?.ticketSource,
    );
    final venueController = useTextEditingController(
      text: editingRecord?.venue ?? draft?.venue,
    );
    final seatController = useTextEditingController(text: editingRecord?.seat);
    final priceController = useTextEditingController(
      text: editingRecord?.ticketPrice?.toString(),
    );
    final mcMemoController = useTextEditingController(
      text: editingRecord?.mcMemo,
    );
    final impressionsController = useTextEditingController(
      text: editingRecord?.impressions,
    );
    final textControllers = [
      titleController,
      artistController,
      sourceController,
      venueController,
      seatController,
      priceController,
      mcMemoController,
      impressionsController,
    ];
    final initialTexts = useMemoized(
      () => [for (final c in textControllers) c.text],
    );
    useListenable(useMemoized(() => Listenable.merge(textControllers)));

    final artistFocusNode = useFocusNode();
    useListenable(artistFocusNode);
    // 候補から選んだ直後は同じ候補を出し直さない
    final artistTypedSincePick = useState(false);
    final titleFocusNode = useFocusNode();
    useListenable(titleFocusNode);
    final titlePicked = useState(false);
    final venueFocusNode = useFocusNode();
    useListenable(venueFocusNode);
    final venuePicked = useState(false);
    // 候補から取り込んだセトリを反映するため、セトリ欄を作り直す
    final setlistEditorGeneration = useState(0);

    final title = titleController.text.trim();
    final artist = artistController.text.trim();
    final isLive = type.value == RecordType.live;
    final kind = type.value;
    final isMultiAct = isLive && eventFormat.value.hasMultipleActs;
    final isFestival = isLive && eventFormat.value == EventFormat.festival;
    final namedActs = [
      for (final a in acts.value)
        if (a.artist.trim().isNotEmpty) a.copyWith(artist: a.artist.trim()),
    ];
    final leadAct =
        namedActs.where((a) => a.isMain).firstOrNull ?? namedActs.firstOrNull;
    // 対バン・フェスではお目当て（いなければ先頭）の出演者で公演名の候補やセトリを引く
    final headline = isMultiAct ? Record.headlineFor(namedActs) : artist;
    final lookupArtist = isMultiAct ? leadAct?.artist ?? '' : artist;
    final dayCount = isFestival
        ? Record.dayCountBetween(date.value, endDate.value)
        : 1;
    final festivalDays = [
      if (dayCount > 1)
        for (var i = 0; i < dayCount; i++)
          DateTime(date.value.year, date.value.month, date.value.day + i),
    ];
    final titleLabel = isMultiAct
        ? 'イベント名・${eventFormat.value.label}名'
        : kind.titleFieldLabel;
    final hasVenue = kind.venueLabel != null;
    final hasSeat = kind.seatPlaceholder != null;
    final savedImageUrl = removeSavedImage.value
        ? null
        : editingRecord?.ticketImageUrl;

    final isDirty =
        type.value != startType ||
        date.value != initialDate ||
        eventFormat.value != startFormat ||
        endDate.value != initialEndDate ||
        !listEquals(acts.value, initialActs) ||
        openTime.value != initialOpenTime ||
        startTime.value != initialStartTime ||
        endTime.value != initialEndTime ||
        selectedImage.value != null ||
        removeSavedImage.value ||
        !_sameList(songs.value, initialSongs) ||
        [
          for (final (i, c) in textControllers.indexed)
            c.text != initialTexts[i],
        ].any((changed) => changed);

    final missingLabels = [
      if (isMultiAct && namedActs.isEmpty)
        '出演者'
      else if (!isMultiAct && artist.isEmpty)
        type.value.creatorFieldLabel,
      if (title.isEmpty) titleLabel,
    ];
    final canSave = missingLabels.isEmpty && !isSaving.value;

    void pickArtist(String name) {
      artistController.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
      artistTypedSincePick.value = false;
      artistFocusNode.unfocus();
    }

    void pickWork(WorkSuggestion work) {
      final picked = work.title.length > RecordFieldLimits.title
          ? work.title.substring(0, RecordFieldLimits.title)
          : work.title;
      titleController.value = TextEditingValue(
        text: picked,
        selection: TextSelection.collapsed(offset: picked.length),
      );
      final creator = work.creator;
      if (creator != null &&
          creator.length <= RecordFieldLimits.artistOrAuthor) {
        artistController.text = creator;
      }
      titlePicked.value = true;
      titleFocusNode.unfocus();
    }

    void pickPlace(PlaceSuggestion place) {
      final picked = place.name.length > RecordFieldLimits.venue
          ? place.name.substring(0, RecordFieldLimits.venue)
          : place.name;
      venueController.value = TextEditingValue(
        text: picked,
        selection: TextSelection.collapsed(offset: picked.length),
      );
      venuePicked.value = true;
      venueFocusNode.unfocus();
    }

    void changeFormat(EventFormat next) {
      final previous = eventFormat.value;
      if (next == previous) return;
      // 入力済みのアーティストとセトリは、形式を変えても引き継ぐ
      if (next.hasMultipleActs && !previous.hasMultipleActs) {
        if (namedActs.isEmpty &&
            (artist.isNotEmpty || songs.value.isNotEmpty)) {
          acts.value = [
            RecordAct(artist: artist, songs: songs.value, isMain: true),
          ];
          actsEditorGeneration.value++;
        }
      } else if (!next.hasMultipleActs && previous.hasMultipleActs) {
        final lead = leadAct;
        if (artist.isEmpty && lead != null) {
          artistController.text = lead.artist;
          if (songs.value.isEmpty && lead.songs.isNotEmpty) {
            songs.value = lead.songs;
            setlistEditorGeneration.value++;
          }
        }
      }
      if (next != EventFormat.festival) endDate.value = null;
      eventFormat.value = next;
    }

    void changeDate(DateTime d) {
      date.value = d;
      final end = endDate.value;
      if (end != null && !end.isAfter(d)) endDate.value = null;
    }

    Future<void> pickConcert(ConcertCandidate c) async {
      final title = c.title.length > RecordFieldLimits.title
          ? c.title.substring(0, RecordFieldLimits.title)
          : c.title;
      titleController.value = TextEditingValue(
        text: title,
        selection: TextSelection.collapsed(offset: title.length),
      );
      titlePicked.value = true;
      titleFocusNode.unfocus();

      final filled = [titleLabel];
      if (c.fillsDetails) {
        if (c.date case final d?) {
          changeDate(d);
          filled.add('公演日');
        }
        if (c.venue case final v? when hasVenue) {
          venueController.text = v.length > RecordFieldLimits.venue
              ? v.substring(0, RecordFieldLimits.venue)
              : v;
          filled.add(kind.venueLabel!);
        }
        if (c.openTime case final t? when kind.hasOpenTime) {
          openTime.value = t;
          filled.add('開場');
        }
        if (c.startTime case final t? when kind.hasSchedule) {
          startTime.value = t;
          filled.add(kind.startTimeLabel);
        }
      }
      HapticFeedback.selectionClick();

      // 入力済みのセトリは上書きしない
      final lead = leadAct;
      final targetEmpty = isMultiAct
          ? lead != null && lead.songs.isEmpty
          : songs.value.isEmpty;
      if (c.fillsDetails && c.songs.isNotEmpty && targetEmpty) {
        final localized = await localizeSetlistSongs(
          ref.read(itunesClientProvider),
          artistName: lookupArtist,
          songs: c.songs,
        );
        if (!context.mounted) return;
        final fits =
            localized.join('\n').length <= RecordFieldLimits.setlistTotal;
        // 日本語化を待つ間に手で入れた曲も上書きしない
        if (fits && isMultiAct && lead != null) {
          final index = acts.value.indexWhere(
            (a) => a.artist.trim() == lead.artist && a.songs.isEmpty,
          );
          if (index >= 0) {
            acts.value = [
              for (final (i, a) in acts.value.indexed)
                i == index ? a.copyWith(songs: localized) : a,
            ];
            actsEditorGeneration.value++;
            filled.add('${lead.artist}のセットリスト');
          }
        } else if (fits && !isMultiAct && songs.value.isEmpty) {
          songs.value = localized;
          setlistEditorGeneration.value++;
          filled.add('セットリスト');
        }
      }
      AppToast.show(
        '${filled.join('・')}を入力しました',
        icon: CupertinoIcons.checkmark_circle_fill,
      );
    }

    Future<void> pickImage() async {
      FocusScope.of(context).unfocus();
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: TicketImageSettings.maxPickDimension,
        maxHeight: TicketImageSettings.maxPickDimension,
        imageQuality: TicketImageSettings.pickImageQuality,
      );
      if (picked == null) return;
      final compressed = await compressTicketImageForUpload(File(picked.path));
      if (!context.mounted) return;
      selectedImage.value = compressed;
      removeSavedImage.value = false;
    }

    void removeImage() {
      selectedImage.value = null;
      removeSavedImage.value = true;
    }

    Future<void> importFromMail() async {
      FocusScope.of(context).unfocus();
      final info = await showTicketMailImportSheet(context);
      if (info == null || !context.mounted) return;

      void fill(TextEditingController c, String? value, int maxLength) {
        if (value == null) return;
        c.text = value.length > maxLength
            ? value.substring(0, maxLength)
            : value;
      }

      fill(titleController, info.title, RecordFieldLimits.title);
      if (isMultiAct) {
        final name = info.artist?.trim() ?? '';
        final truncated = name.length > RecordFieldLimits.artistOrAuthor
            ? name.substring(0, RecordFieldLimits.artistOrAuthor)
            : name;
        if (truncated.isNotEmpty &&
            namedActs.every((a) => a.artist != truncated)) {
          acts.value = [
            ...namedActs,
            RecordAct(artist: truncated, isMain: true),
          ];
          actsEditorGeneration.value++;
        }
      } else {
        fill(artistController, info.artist, RecordFieldLimits.artistOrAuthor);
      }
      fill(sourceController, info.ticketSource, RecordFieldLimits.ticketSource);
      if (info.date != null) changeDate(info.date!);
      final priceFits =
          info.ticketPrice != null &&
          info.ticketPrice! <= RecordFieldLimits.ticketPriceMax;
      final useOpen = kind.hasOpenTime && info.openTime != null;
      final useStart = kind.hasSchedule && info.startTime != null;
      final useEnd = kind.hasSchedule && info.endTime != null;
      final useVenue = hasVenue && info.venue != null;
      final useSeat = hasSeat && info.seat != null;
      if (useVenue) fill(venueController, info.venue, RecordFieldLimits.venue);
      if (useSeat) fill(seatController, info.seat, RecordFieldLimits.seat);
      if (priceFits) priceController.text = '${info.ticketPrice}';
      if (useOpen) openTime.value = info.openTime;
      if (useStart) startTime.value = info.startTime;
      if (useEnd) endTime.value = info.endTime;
      artistTypedSincePick.value = false;

      final filled = [
        if (info.title != null) titleLabel,
        if (info.artist != null) isMultiAct ? '出演者' : kind.creatorFieldLabel,
        if (info.date != null) isLive ? '公演日' : '日付',
        if (useOpen) '開場',
        if (useStart) kind.startTimeLabel,
        if (useEnd) kind.endTimeLabel,
        if (useVenue) kind.venueLabel!,
        if (useSeat) '座席',
        if (priceFits) kind.priceLabel,
        if (info.ticketSource != null) '取得元',
      ];
      AppToast.show(
        '${filled.join('・')}を入力しました',
        icon: CupertinoIcons.envelope_open_fill,
      );
    }

    Future<void> save() async {
      if (!canSave) return;
      FocusScope.of(context).unfocus();

      final setlist = isLive && !isMultiAct && songs.value.isNotEmpty
          ? songs.value.join('\n')
          : null;
      if (setlist != null && setlist.length > RecordFieldLimits.setlistTotal) {
        AppToast.error('セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。');
        return;
      }

      final price = int.tryParse(priceController.text.trim());
      if (price != null && price > RecordFieldLimits.ticketPriceMax) {
        AppToast.error('${kind.priceLabel}が大きすぎます。金額を確認してください。');
        return;
      }

      final open = openTime.value;
      final start = startTime.value;
      if (kind.hasOpenTime &&
          open != null &&
          start != null &&
          open.compareTo(start) > 0) {
        AppToast.error('開場は開演より前の時刻にしてください。');
        return;
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        AppToast.error('ログインしてください');
        return;
      }

      isSaving.value = true;
      try {
        final repo = ref.read(recordsRepositoryProvider);
        final image = selectedImage.value;
        final ticketImageUrl = image != null
            ? await repo.uploadTicketImage(userId: userId, file: image)
            : savedImageUrl ?? '';

        String? nullIfEmpty(TextEditingController c) {
          final text = c.text.trim();
          return text.isEmpty ? null : text;
        }

        final record = Record(
          id: editingRecord?.id ?? '',
          type: type.value,
          title: title,
          artistOrAuthor: headline,
          date: date.value,
          eventFormat: isLive ? eventFormat.value : EventFormat.oneman,
          endDate: isFestival && (endDate.value?.isAfter(date.value) ?? false)
              ? endDate.value
              : null,
          acts: isMultiAct
              ? [
                  for (final a in namedActs)
                    a.withDay(
                      dayCount > 1 ? (a.day ?? 1).clamp(1, dayCount) : null,
                    ),
                ]
              : const [],
          ticketImageUrl: ticketImageUrl,
          ticketSource: nullIfEmpty(sourceController),
          venue: hasVenue ? nullIfEmpty(venueController) : null,
          seat: hasSeat ? nullIfEmpty(seatController) : null,
          ticketPrice: price,
          openTime: kind.hasOpenTime ? openTime.value : null,
          startTime: kind.hasSchedule ? startTime.value : null,
          endTime: kind.hasSchedule ? endTime.value : null,
          setlist: setlist,
          mcMemo: isLive ? nullIfEmpty(mcMemoController) : null,
          impressions: nullIfEmpty(impressionsController),
        );

        final saved = editingRecord != null
            ? await repo.updateRecord(editingRecord.id, record.toJson())
            : await repo.insertRecord({...record.toJson(), 'user_id': userId});
        ref.invalidate(recordsProvider);
        HapticFeedback.mediumImpact();
        AppToast.show(
          isEditMode ? '記録を更新しました' : '記録を保存しました',
          icon: CupertinoIcons.checkmark_circle_fill,
        );
        final favoritesNotifier = ref.read(favoriteArtistsProvider.notifier);
        final itunes = ref.read(itunesClientProvider);
        final favorites = ref.read(favoriteArtistsProvider).asData?.value;
        if (context.mounted) Navigator.of(context).pop(saved);
        if (favorites != null) {
          final names = artistsToAutoFavorite(
            saved,
            previous: editingRecord,
            favorites: favorites,
          );
          // 画面を閉じた後に追加する（画像の検索で保存の完了を待たせないため）
          if (names.isNotEmpty) {
            unawaited(
              addAutoFavorites(
                names,
                add: (name, artworkUrl) =>
                    favoritesNotifier.add(name: name, artworkUrl: artworkUrl),
                findArtwork: itunes.findArtistArtwork,
              ).then((added) {
                if (added.isEmpty) return;
                AppToast.show(
                  '「${added.join('」「')}」をお気に入りに追加しました',
                  icon: CupertinoIcons.star_fill,
                );
              }),
            );
          }
        }
      } catch (e, stackTrace) {
        debugPrint('Error saving record: $e\n$stackTrace');
        AppToast.error(toUserFriendlyMessage(e));
      } finally {
        if (context.mounted) isSaving.value = false;
      }
    }

    final artistBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextRow(
          controller: artistController,
          focusNode: artistFocusNode,
          placeholder: type.value.creatorFieldLabel,
          icon: switch (type.value) {
            RecordType.live => CupertinoIcons.music_mic,
            RecordType.book => CupertinoIcons.pencil,
            RecordType.movie || RecordType.other => CupertinoIcons.person_2,
          },
          enLabel: type.value.creatorFieldEnLabel,
          maxLength: RecordFieldLimits.artistOrAuthor,
          scrollPadding: _fieldScrollPadding,
          onChanged: (_) => artistTypedSincePick.value = true,
        ),
        // iTunes のカタログとお気に入りは音楽のみなので、ライブのときだけ出す
        if (isLive && artistFocusNode.hasFocus && artistTypedSincePick.value)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ArtistSuggestions(
              query: artistController.text,
              onPick: (a) => pickArtist(a.name),
            ),
          ),
        if (isLive)
          FavoriteArtistQuickPick(
            currentArtist: artistController.text,
            onPick: (a) => pickArtist(a.name),
          ),
      ],
    );
    final titleRow = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextRow(
          controller: titleController,
          focusNode: titleFocusNode,
          placeholder: titleLabel,
          icon: switch (type.value) {
            RecordType.live => CupertinoIcons.music_note_2,
            RecordType.movie => CupertinoIcons.film,
            RecordType.book => CupertinoIcons.book,
            RecordType.other => CupertinoIcons.star,
          },
          enLabel: 'TITLE',
          maxLength: RecordFieldLimits.title,
          scrollPadding: _fieldScrollPadding,
          onChanged: (_) => titlePicked.value = false,
        ),
        if (isLive &&
            lookupArtist.isNotEmpty &&
            titleFocusNode.hasFocus &&
            !titlePicked.value)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ConcertSuggestions(
              artist: lookupArtist,
              query: titleController.text,
              onPick: pickConcert,
            ),
          ),
        if ((kind == RecordType.movie || kind == RecordType.book) &&
            titleFocusNode.hasFocus &&
            !titlePicked.value)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: WorkSuggestions(
              key: ValueKey(kind),
              type: kind,
              query: titleController.text,
              onPick: pickWork,
            ),
          ),
      ],
    );

    final sourceRow = FormTextRow(
      controller: sourceController,
      placeholder: kind.sourcePlaceholder,
      icon: kind == RecordType.book
          ? CupertinoIcons.bag
          : CupertinoIcons.tickets,
      enLabel: kind.sourceEnLabel,
      maxLength: RecordFieldLimits.ticketSource,
      scrollPadding: _fieldScrollPadding,
    );

    return PopScope(
      canPop: !isDirty && !isSaving.value,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || isSaving.value) return;
        final discard = await showActionSheet<bool>(
          context,
          message: isEditMode ? '編集内容は保存されません。' : '入力した内容は保存されません。',
          actions: [
            SheetAction(
              label: isEditMode ? '変更を破棄' : '記録を破棄',
              value: true,
              isDestructive: true,
            ),
          ],
          cancelText: '編集を続ける',
        );
        if (discard == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 124,
          leading: Align(
            alignment: Alignment.centerLeft,
            child: NavBarTextButton(
              label: 'キャンセル',
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          title: Text(isEditMode ? '記録を編集' : '新規記録'),
          actions: [
            if (isSaving.value)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: CupertinoActivityIndicator(),
              )
            else
              NavBarTextButton(
                label: isEditMode ? '保存' : '追加',
                isBold: true,
                onPressed: canSave ? save : null,
              ),
          ],
        ),
        // ListView だと画面外に出たセトリ入力欄が破棄されフォーカスを失うため、一括で組み立てる
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IosSegmentedControl<RecordType>(
                value: type.value,
                segments: {
                  for (final t in RecordType.values) t: t.japaneseLabel,
                },
                onChanged: (t) => type.value = t,
              ),
              if (isLive) ...[
                const SizedBox(height: 10),
                IosSegmentedControl<EventFormat>(
                  value: eventFormat.value,
                  segments: {for (final f in EventFormat.values) f: f.label},
                  onChanged: changeFormat,
                ),
              ],
              const SizedBox(height: 20),
              TicketPreviewPicker(
                type: type.value,
                title: title,
                artistOrAuthor: headline,
                date: date.value,
                endDate: isFestival ? endDate.value : null,
                localImage: selectedImage.value,
                remoteImageUrl: savedImageUrl,
                onPickImage: pickImage,
                onRemoveImage: removeImage,
              ),
              FormSection(
                header: '基本情報',
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: importFromMail,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.envelope,
                        size: 15,
                        color: context.colors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'メールから入力',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                footer: missingLabels.isEmpty
                    ? null
                    : '${missingLabels.join('と')}は必須です。',
                children: [
                  // ライブはアーティストから決めることが多く、候補や setlist.fm もそこから引く
                  if (isMultiAct)
                    titleRow
                  else
                    ...isLive
                        ? [artistBlock, titleRow]
                        : [titleRow, artistBlock],
                  RecordDateRow(
                    label: isFestival ? '開催日' : (isLive ? '公演日' : '日付'),
                    icon: CupertinoIcons.calendar,
                    enLabel: 'DATE',
                    date: date.value,
                    onChanged: changeDate,
                  ),
                  if (isFestival)
                    RecordDateRow(
                      label: '最終日',
                      icon: CupertinoIcons.calendar_badge_plus,
                      enLabel: 'LAST DAY',
                      date: endDate.value ?? date.value,
                      minimumDate: date.value,
                      onChanged: (d) =>
                          endDate.value = d.isAfter(date.value) ? d : null,
                    ),
                ],
              ),
              if (isMultiAct)
                FormSection(
                  header: '出演者',
                  trailing: namedActs.isEmpty
                      ? null
                      : Text(
                          '${namedActs.length}組',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                  footer: '★ でお目当てを 1 組選ぶと、チケットの見出しになり、お気に入りにも追加されます。',
                  wrapInCard: false,
                  children: [
                    ActsEditor(
                      // 日数が変わったら日ごとの欄を作り直す
                      key: ValueKey((actsEditorGeneration.value, dayCount)),
                      initialActs: acts.value,
                      minimumActs: eventFormat.value == EventFormat.taiban
                          ? 2
                          : 1,
                      days: festivalDays,
                      scrollPadding: _fieldScrollPadding,
                      onChanged: (next) => acts.value = next,
                    ),
                  ],
                ),
              FormSection(
                header: kind.detailsSectionLabel,
                children: [
                  if (kind.hasOpenTime)
                    RecordTimeRow(
                      label: '開場',
                      icon: CupertinoIcons.clock,
                      enLabel: 'OPEN',
                      time: openTime.value,
                      defaultTime:
                          _shift(startTime.value, -60) ??
                          const ClockTime(17, 0),
                      onChanged: (t) => openTime.value = t,
                    ),
                  if (kind.hasSchedule) ...[
                    RecordTimeRow(
                      label: kind.startTimeLabel,
                      icon: CupertinoIcons.play_circle,
                      enLabel: 'START',
                      time: startTime.value,
                      defaultTime:
                          _shift(openTime.value, 60) ?? const ClockTime(18, 0),
                      onChanged: (t) => startTime.value = t,
                    ),
                    RecordTimeRow(
                      label: kind.endTimeLabel,
                      icon: CupertinoIcons.stop_circle,
                      enLabel: 'END',
                      time: endTime.value,
                      defaultTime:
                          _shift(startTime.value, 120) ??
                          const ClockTime(20, 0),
                      onChanged: (t) => endTime.value = t,
                    ),
                  ],
                  if (hasVenue)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FormTextRow(
                          controller: venueController,
                          focusNode: venueFocusNode,
                          placeholder: kind.venueLabel!,
                          icon: CupertinoIcons.location,
                          enLabel: kind.venueEnLabel,
                          maxLength: RecordFieldLimits.venue,
                          scrollPadding: _fieldScrollPadding,
                          onChanged: (_) => venuePicked.value = false,
                        ),
                        if (venueFocusNode.hasFocus && !venuePicked.value)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: PlaceSuggestions(
                              query: venueController.text,
                              onPick: pickPlace,
                            ),
                          ),
                      ],
                    ),
                  if (hasSeat)
                    FormTextRow(
                      controller: seatController,
                      placeholder: kind.seatPlaceholder!,
                      icon: CupertinoIcons.square_grid_2x2,
                      enLabel: 'SEAT',
                      maxLength: RecordFieldLimits.seat,
                      scrollPadding: _fieldScrollPadding,
                    ),
                  FormTextRow(
                    controller: priceController,
                    placeholder: kind.priceLabel,
                    icon: CupertinoIcons.money_yen,
                    enLabel: 'PRICE',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        '${RecordFieldLimits.ticketPriceMax}'.length,
                      ),
                    ],
                    suffix: '円',
                    scrollPadding: _fieldScrollPadding,
                  ),
                  sourceRow,
                ],
              ),
              if (isLive && !isMultiAct)
                FormSection(
                  header: 'セットリスト',
                  trailing: songs.value.isEmpty
                      ? null
                      : Text(
                          '${songs.value.length}曲',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                  wrapInCard: false,
                  children: [
                    SetlistEditor(
                      key: ValueKey(setlistEditorGeneration.value),
                      initialSongs: songs.value,
                      artistName: artist,
                      scrollPadding: _fieldScrollPadding,
                      onChanged: (next) => songs.value = next,
                    ),
                  ],
                ),
              if (isLive)
                FormSection(
                  header: 'MCメモ',
                  children: [
                    FormTextRow(
                      controller: mcMemoController,
                      placeholder: '印象に残った MC や演出',
                      maxLines: 6,
                      maxLength: RecordFieldLimits.mcMemo,
                      scrollPadding: _fieldScrollPadding,
                    ),
                  ],
                ),
              FormSection(
                header: '感想',
                children: [
                  FormTextRow(
                    controller: impressionsController,
                    placeholder: 'あとで読み返したいことを自由に',
                    minLines: 5,
                    maxLines: 12,
                    maxLength: RecordFieldLimits.impressions,
                    scrollPadding: _fieldScrollPadding,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 未設定の時刻行を開いたときの初期値に使う。開演の 1 時間前を開場、2 時間後を終演とする。
  static ClockTime? _shift(ClockTime? time, int minutes) {
    if (time == null) return null;
    final total = (time.hour * 60 + time.minute + minutes) % (24 * 60);
    return ClockTime(total ~/ 60, total % 60);
  }
}
