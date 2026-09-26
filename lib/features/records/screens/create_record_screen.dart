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
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_row.dart';
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 110,
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
                  FormTextRow(
                    controller: sourceController,
                    placeholder: 'チケット取得元（e+、ローチケ など）',
                    maxLength: RecordFieldLimits.ticketSource,
                    scrollPadding: _fieldScrollPadding,
                  ),
                ],
              ),
              if (isLive)
                FormSection(
                  header: 'セットリスト',
                  trailing: songs.value.isEmpty
                      ? null
                      : Text(
                          '${songs.value.length}曲',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
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
}
