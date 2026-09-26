import 'dart:io';

import 'package:flutter/cupertino.dart';
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
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/ticket_mail_import_sheet.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_time_row.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';
import 'package:recolle/features/records/widgets/record_form/ticket_preview_picker.dart';
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
  });

  /// 指定時は編集モード。
  final Record? recordToEdit;

  /// 新規作成時にアーティスト欄へあらかじめ入れておく名前。
  final String? initialArtist;

  /// 新規作成時の種別。省略時はライブ。
  final RecordType? initialType;

  /// キーボード表示中でも、入力欄の下に出る候補リストまで見えるようにする余白。
  static const _fieldScrollPadding = EdgeInsets.fromLTRB(20, 24, 20, 160);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editingRecord = recordToEdit;
    final isEditMode = editingRecord != null;

    final startType = editingRecord?.type ?? initialType ?? RecordType.live;
    final initialDate = useMemoized(
      () => editingRecord?.date ?? DateTime.now(),
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
    final openTime = useState(editingRecord?.openTime);
    final startTime = useState(editingRecord?.startTime);
    final endTime = useState(editingRecord?.endTime);
    final songs = useState(initialSongs);
    final selectedImage = useState<File?>(null);
    final removeSavedImage = useState(false);
    final isSaving = useState(false);

    final titleController = useTextEditingController(
      text: editingRecord?.title,
    );
    final artistController = useTextEditingController(
      text: editingRecord?.artistOrAuthor ?? initialArtist,
    );
    final sourceController = useTextEditingController(
      text: editingRecord?.ticketSource,
    );
    final venueController = useTextEditingController(
      text: editingRecord?.venue,
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

    final title = titleController.text.trim();
    final artist = artistController.text.trim();
    final isLive = type.value == RecordType.live;
    final savedImageUrl = removeSavedImage.value
        ? null
        : editingRecord?.ticketImageUrl;

    final isDirty =
        type.value != startType ||
        date.value != initialDate ||
        openTime.value != editingRecord?.openTime ||
        startTime.value != editingRecord?.startTime ||
        endTime.value != editingRecord?.endTime ||
        selectedImage.value != null ||
        removeSavedImage.value ||
        !_sameList(songs.value, initialSongs) ||
        [
          for (final (i, c) in textControllers.indexed)
            c.text != initialTexts[i],
        ].any((changed) => changed);

    final missingLabels = [
      if (artist.isEmpty) type.value.creatorFieldLabel,
      if (title.isEmpty) type.value.titleFieldLabel,
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
      fill(artistController, info.artist, RecordFieldLimits.artistOrAuthor);
      fill(sourceController, info.ticketSource, RecordFieldLimits.ticketSource);
      if (info.date != null) date.value = info.date!;
      if (isLive) {
        fill(venueController, info.venue, RecordFieldLimits.venue);
        fill(seatController, info.seat, RecordFieldLimits.seat);
        if (info.ticketPrice != null &&
            info.ticketPrice! <= RecordFieldLimits.ticketPriceMax) {
          priceController.text = '${info.ticketPrice}';
        }
        if (info.openTime != null) openTime.value = info.openTime;
        if (info.startTime != null) startTime.value = info.startTime;
        if (info.endTime != null) endTime.value = info.endTime;
      }
      artistTypedSincePick.value = false;

      final filled = [
        if (info.title != null) type.value.titleFieldLabel,
        if (info.artist != null) type.value.creatorFieldLabel,
        if (info.date != null) isLive ? '公演日' : '日付',
        if (isLive && info.openTime != null) '開場',
        if (isLive && info.startTime != null) '開演',
        if (isLive && info.endTime != null) '終演',
        if (isLive && info.venue != null) '会場',
        if (isLive && info.seat != null) '座席',
        if (isLive && info.ticketPrice != null) 'チケット代',
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

      final setlist = isLive && songs.value.isNotEmpty
          ? songs.value.join('\n')
          : null;
      if (setlist != null && setlist.length > RecordFieldLimits.setlistTotal) {
        AppToast.error('セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。');
        return;
      }

      final price = int.tryParse(priceController.text.trim());
      if (isLive && price != null && price > RecordFieldLimits.ticketPriceMax) {
        AppToast.error('チケット代が大きすぎます。金額を確認してください。');
        return;
      }

      final open = openTime.value;
      final start = startTime.value;
      if (isLive &&
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
          artistOrAuthor: artist,
          date: date.value,
          ticketImageUrl: ticketImageUrl,
          ticketSource: nullIfEmpty(sourceController),
          venue: isLive ? nullIfEmpty(venueController) : null,
          seat: isLive ? nullIfEmpty(seatController) : null,
          ticketPrice: isLive ? price : null,
          openTime: isLive ? openTime.value : null,
          startTime: isLive ? startTime.value : null,
          endTime: isLive ? endTime.value : null,
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
        if (context.mounted) Navigator.of(context).pop(saved);
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
    final titleRow = FormTextRow(
      controller: titleController,
      placeholder: type.value.titleFieldLabel,
      maxLength: RecordFieldLimits.title,
      scrollPadding: _fieldScrollPadding,
    );

    final sourceRow = FormTextRow(
      controller: sourceController,
      placeholder: 'チケット取得元（e+、ローチケ など）',
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
              const SizedBox(height: 20),
              TicketPreviewPicker(
                type: type.value,
                title: title,
                artistOrAuthor: artist,
                date: date.value,
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
                  ...isLive ? [artistBlock, titleRow] : [titleRow, artistBlock],
                  RecordDateRow(
                    label: isLive ? '公演日' : '日付',
                    date: date.value,
                    onChanged: (d) => date.value = d,
                  ),
                  if (!isLive) sourceRow,
                ],
              ),
              if (isLive)
                FormSection(
                  header: '公演・チケット',
                  children: [
                    RecordTimeRow(
                      label: '開場',
                      time: openTime.value,
                      defaultTime:
                          _shift(startTime.value, -60) ??
                          const ClockTime(17, 0),
                      onChanged: (t) => openTime.value = t,
                    ),
                    RecordTimeRow(
                      label: '開演',
                      time: startTime.value,
                      defaultTime:
                          _shift(openTime.value, 60) ?? const ClockTime(18, 0),
                      onChanged: (t) => startTime.value = t,
                    ),
                    RecordTimeRow(
                      label: '終演',
                      time: endTime.value,
                      defaultTime:
                          _shift(startTime.value, 120) ??
                          const ClockTime(20, 0),
                      onChanged: (t) => endTime.value = t,
                    ),
                    FormTextRow(
                      controller: venueController,
                      placeholder: '会場',
                      maxLength: RecordFieldLimits.venue,
                      scrollPadding: _fieldScrollPadding,
                    ),
                    FormTextRow(
                      controller: seatController,
                      placeholder: '座席（アリーナ A5 12列 34番 など）',
                      maxLength: RecordFieldLimits.seat,
                      scrollPadding: _fieldScrollPadding,
                    ),
                    FormTextRow(
                      controller: priceController,
                      placeholder: 'チケット代',
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
              if (isLive)
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
                      initialSongs: songs.value,
                      artistName: artist,
                      date: date.value,
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
