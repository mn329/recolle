import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/constants/ticket_image_settings.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/ticket_image_compress.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_field.dart';
import 'package:recolle/features/records/widgets/record_form/record_type_selector.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';
import 'package:recolle/features/records/widgets/record_form/ticket_preview_picker.dart';
import 'package:recolle/features/records/widgets/record_form_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateRecordScreen extends HookConsumerWidget {
  const CreateRecordScreen({super.key, this.recordToEdit, this.initialArtist});

  /// 指定時は編集モード。保存後は更新された [Record] を [Navigator.pop] で返す。
  final Record? recordToEdit;

  /// 新規作成時にアーティスト欄へあらかじめ入れておく名前。
  final String? initialArtist;

  /// キーボード表示中でも、入力欄の下に出る候補リストまで見えるようにする余白。
  static const _fieldScrollPadding = EdgeInsets.fromLTRB(20, 24, 20, 160);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editingRecord = recordToEdit;
    final isEditMode = editingRecord != null;

    final initialType = editingRecord?.type ?? RecordType.live;
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

    final type = useState(initialType);
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
    final initialTexts = useMemoized(
      () => [
        titleController.text,
        artistController.text,
        sourceController.text,
        mcMemoController.text,
        impressionsController.text,
      ],
    );
    final textControllers = [
      titleController,
      artistController,
      sourceController,
      mcMemoController,
      impressionsController,
    ];
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
        type.value != initialType ||
        date.value != initialDate ||
        selectedImage.value != null ||
        removeSavedImage.value ||
        !_sameList(songs.value, initialSongs) ||
        [
          for (final (i, c) in textControllers.indexed)
            c.text != initialTexts[i],
        ].any((changed) => changed);

    final missingLabels = [
      if (title.isEmpty) type.value.titleFieldLabel,
      if (artist.isEmpty) type.value.creatorFieldLabel,
    ];

    void showMessage(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

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
      if (isSaving.value || missingLabels.isNotEmpty) return;
      FocusScope.of(context).unfocus();

      final setlist = isLive && songs.value.isNotEmpty
          ? songs.value.join('\n')
          : null;
      if (setlist != null && setlist.length > RecordFieldLimits.setlistTotal) {
        showMessage('セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。');
        return;
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        showMessage('ログインしてください');
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

        if (editingRecord != null) {
          final updated = await repo.updateRecord(
            editingRecord.id,
            record.toJson(),
          );
          if (!context.mounted) return;
          ref.invalidate(recordsProvider);
          showMessage('記録を更新しました');
          Navigator.of(context).pop(updated);
        } else {
          final inserted = await repo.insertRecord({
            ...record.toJson(),
            'user_id': userId,
          });
          if (!context.mounted) return;
          ref.invalidate(recordsProvider);
          showMessage('記録を保存しました');
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => DetailScreen(record: inserted),
            ),
          );
        }
      } catch (e, stackTrace) {
        debugPrint('Error saving record: $e\n$stackTrace');
        if (context.mounted) showMessage(toUserFriendlyMessage(e));
      } finally {
        if (context.mounted) isSaving.value = false;
      }
    }

    final artistField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecordFormTextField(
          controller: artistController,
          focusNode: artistFocusNode,
          label: type.value.creatorFieldLabel,
          icon: isLive ? Icons.person_outline : Icons.people_outline,
          maxLength: RecordFieldLimits.artistOrAuthor,
          scrollPadding: _fieldScrollPadding,
          onChanged: (_) => artistTypedSincePick.value = true,
        ),
        // iTunes のカタログとお気に入りは音楽のみなので、ライブのときだけ出す
        if (isLive && artistFocusNode.hasFocus && artistTypedSincePick.value)
          ArtistSuggestions(
            query: artistController.text,
            onPick: (a) => pickArtist(a.name),
          ),
        if (isLive)
          FavoriteArtistQuickPick(
            currentArtist: artistController.text,
            onPick: (a) => pickArtist(a.name),
          ),
      ],
    );
    final titleField = RecordFormTextField(
      controller: titleController,
      label: type.value.titleFieldLabel,
      icon: Icons.local_activity_outlined,
      maxLength: RecordFieldLimits.title,
      scrollPadding: _fieldScrollPadding,
    );

    return PopScope(
      canPop: !isDirty && !isSaving.value,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || isSaving.value) return;
        final discard = await showConfirmDialog(
          context,
          title: isEditMode ? '編集を破棄しますか？' : '入力内容を破棄しますか？',
          message: '保存していない変更は失われます。',
          okText: '破棄する',
          cancelText: '編集を続ける',
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(isEditMode ? 'EDIT RECORD' : 'NEW RECORD'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '閉じる',
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        // ListView だと画面外に出たセトリ入力欄が破棄されフォーカスを失うため、一括で組み立てる
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordTypeSelector(
                selected: type.value,
                onChanged: (t) => type.value = t,
              ),
              const SizedBox(height: 24),
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
                title: 'BASICS',
                japaneseLabel: '基本情報',
                children: [
                  // ライブはアーティストから決めることが多く、候補や setlist.fm もそこから引く
                  ...isLive
                      ? [artistField, const SizedBox(height: 12), titleField]
                      : [titleField, const SizedBox(height: 12), artistField],
                  const SizedBox(height: 12),
                  RecordDateField(
                    label: isLive ? '公演日' : '日付',
                    date: date.value,
                    onChanged: (d) => date.value = d,
                  ),
                  const SizedBox(height: 12),
                  RecordFormTextField(
                    controller: sourceController,
                    label: 'チケット取得元',
                    hintText: 'e+、ローチケ、Amazon など',
                    icon: Icons.confirmation_number_outlined,
                    maxLength: RecordFieldLimits.ticketSource,
                    scrollPadding: _fieldScrollPadding,
                  ),
                ],
              ),
              if (isLive)
                FormSection(
                  title: 'SETLIST',
                  japaneseLabel: 'セットリスト',
                  trailing: songs.value.isEmpty
                      ? null
                      : Text(
                          '${songs.value.length}曲',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
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
              FormSection(
                title: 'NOTES',
                japaneseLabel: 'メモ',
                children: [
                  if (isLive) ...[
                    RecordFormTextField(
                      controller: mcMemoController,
                      label: 'MCメモ',
                      hintText: '印象に残った MC や演出',
                      icon: Icons.mic_none,
                      maxLines: 4,
                      maxLength: RecordFieldLimits.mcMemo,
                      scrollPadding: _fieldScrollPadding,
                    ),
                    const SizedBox(height: 12),
                  ],
                  RecordFormTextField(
                    controller: impressionsController,
                    label: '感想',
                    hintText: 'あとで読み返したいことを自由に',
                    icon: Icons.edit_note,
                    maxLines: 8,
                    maxLength: RecordFieldLimits.impressions,
                    scrollPadding: _fieldScrollPadding,
                  ),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: _SaveBar(
          label: missingLabels.isNotEmpty
              ? '${missingLabels.join('と')}を入力してください'
              : isEditMode
              ? '変更を保存'
              : '記録を保存',
          enabled: missingLabels.isEmpty,
          isSaving: isSaving.value,
          onPressed: save,
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

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.enabled,
    required this.isSaving,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.textDisabled.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              // 保存中も有効色のままスピナーを見せる（二重保存は save 側で弾く）
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColors.surfaceLight,
                disabledForegroundColor: AppColors.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.black,
                      ),
                    )
                  : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}
