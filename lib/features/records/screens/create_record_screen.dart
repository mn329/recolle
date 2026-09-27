import 'dart:async';
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
import 'package:recolle/core/utils/ticket_image_compress.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/confirm_dialog.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/data/work_search_client.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/record_form_view_model.dart';
import 'package:recolle/features/records/ticket_mail_parser.dart';
import 'package:recolle/features/records/widgets/record_form/acts_editor.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/form_text_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_creator_field.dart';
import 'package:recolle/features/records/widgets/record_form/record_date_row.dart';
import 'package:recolle/features/records/widgets/record_form/record_details_section.dart';
import 'package:recolle/features/records/widgets/record_form/record_title_field.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';
import 'package:recolle/features/records/widgets/record_form/ticket_preview_picker.dart';
import 'package:recolle/features/records/widgets/ticket_mail_import_sheet.dart';

/// 記録の作成・編集フォーム。保存したら [Record] を返して閉じる。
///
/// 通常は `openRecordEditor` から iOS のシートとして開く。
/// 入力内容と保存は [RecordFormViewModel] が持ち、この画面は表示と入力の受け渡しをする。
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
    final provider = recordFormProvider(
      RecordFormArgs(
        recordToEdit: recordToEdit,
        initialArtist: initialArtist,
        initialType: initialType,
        prefill: prefill,
      ),
    );
    final form = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final isEditMode = vm.isEditMode;

    final controllers = {
      for (final field in RecordTextField.values)
        field: useTextEditingController(text: form.text(field)),
    };
    // 候補やメールの取り込みで ViewModel が書き換えた欄を、入力欄にも反映する
    ref.listen(provider, (_, next) {
      for (final MapEntry(key: field, value: controller)
          in controllers.entries) {
        final text = next.text(field);
        if (controller.text == text) continue;
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });

    final artistFocusNode = useFocusNode();
    useListenable(artistFocusNode);
    // 候補から選んだ直後は同じ候補を出し直さない
    final artistTypedSincePick = useState(false);
    final titleFocusNode = useFocusNode();
    useListenable(titleFocusNode);
    final titlePicked = useState(false);

    final kind = form.type;
    final isLive = form.isLive;
    final isMultiAct = form.isMultiAct;
    final isFestival = form.isFestival;
    final missingLabels = form.missingLabels;

    void pickArtist(String name) {
      vm.pickArtist(name);
      artistTypedSincePick.value = false;
      artistFocusNode.unfocus();
    }

    void pickWork(WorkSuggestion work) {
      vm.pickWork(work);
      titlePicked.value = true;
      titleFocusNode.unfocus();
    }

    Future<void> pickConcert(ConcertCandidate candidate) async {
      titlePicked.value = true;
      titleFocusNode.unfocus();
      HapticFeedback.selectionClick();
      final filled = await vm.applyConcert(candidate);
      if (filled == null || !context.mounted) return;
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
      vm.setImage(compressed);
    }

    Future<void> importFromMail() async {
      FocusScope.of(context).unfocus();
      final info = await showTicketMailImportSheet(context);
      if (info == null || !context.mounted) return;
      final filled = vm.applyMailInfo(info);
      artistTypedSincePick.value = false;
      AppToast.show(
        '${filled.join('・')}を入力しました',
        icon: CupertinoIcons.envelope_open_fill,
      );
    }

    Future<void> save() async {
      FocusScope.of(context).unfocus();
      switch (await vm.save()) {
        case null:
          return;
        case RecordSaveInvalid(:final message) ||
            RecordSaveFailed(:final message):
          AppToast.error(message);
        case RecordSaveSucceeded(:final record, :final autoFavorited):
          HapticFeedback.mediumImpact();
          AppToast.show(
            isEditMode ? '記録を更新しました' : '記録を保存しました',
            icon: CupertinoIcons.checkmark_circle_fill,
          );
          if (context.mounted) Navigator.of(context).pop(record);
          unawaited(
            autoFavorited.then((added) {
              if (added.isEmpty) return;
              AppToast.show(
                '「${added.join('」「')}」をお気に入りに追加しました',
                icon: CupertinoIcons.star_fill,
              );
            }),
          );
      }
    }

    final creatorField = RecordCreatorField(
      type: kind,
      controller: controllers[RecordTextField.artist]!,
      focusNode: artistFocusNode,
      showSuggestions: artistFocusNode.hasFocus && artistTypedSincePick.value,
      onChanged: (value) {
        vm.updateText(RecordTextField.artist, value);
        artistTypedSincePick.value = true;
      },
      onPick: pickArtist,
      scrollPadding: _fieldScrollPadding,
    );
    final titleField = RecordTitleField(
      type: kind,
      label: form.titleLabel,
      controller: controllers[RecordTextField.title]!,
      focusNode: titleFocusNode,
      lookupArtist: form.lookupArtist,
      showSuggestions: titleFocusNode.hasFocus && !titlePicked.value,
      onChanged: (value) {
        vm.updateText(RecordTextField.title, value);
        titlePicked.value = false;
      },
      onPickConcert: pickConcert,
      onPickWork: pickWork,
      scrollPadding: _fieldScrollPadding,
    );

    return PopScope(
      canPop: !vm.isDirty && !form.isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || form.isSaving) return;
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
            if (form.isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: CupertinoActivityIndicator(),
              )
            else
              NavBarTextButton(
                label: isEditMode ? '保存' : '追加',
                isBold: true,
                onPressed: form.canSave ? save : null,
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
                value: kind,
                segments: {
                  for (final t in RecordType.values) t: t.japaneseLabel,
                },
                onChanged: vm.setType,
              ),
              if (isLive) ...[
                const SizedBox(height: 10),
                IosSegmentedControl<EventFormat>(
                  value: form.eventFormat,
                  segments: {for (final f in EventFormat.values) f: f.label},
                  onChanged: vm.changeFormat,
                ),
              ],
              const SizedBox(height: 20),
              TicketPreviewPicker(
                type: kind,
                title: form.title,
                artistOrAuthor: form.headline,
                date: form.date,
                endDate: isFestival ? form.endDate : null,
                localImage: form.selectedImage,
                remoteImageUrl: form.savedImageUrl,
                onPickImage: pickImage,
                onRemoveImage: vm.removeImage,
              ),
              FormSection(
                header: '基本情報',
                trailing: _MailImportButton(onPressed: importFromMail),
                footer: missingLabels.isEmpty
                    ? null
                    : '${missingLabels.join('と')}は必須です。',
                children: [
                  // ライブはアーティストから決めることが多く、候補や setlist.fm もそこから引く
                  if (isMultiAct)
                    titleField
                  else
                    ...isLive
                        ? [creatorField, titleField]
                        : [titleField, creatorField],
                  RecordDateRow(
                    label: isFestival ? '開催日' : (isLive ? '公演日' : '日付'),
                    icon: CupertinoIcons.calendar,
                    enLabel: 'DATE',
                    date: form.date,
                    onChanged: vm.changeDate,
                  ),
                  if (isFestival)
                    RecordDateRow(
                      label: '最終日',
                      icon: CupertinoIcons.calendar_badge_plus,
                      enLabel: 'LAST DAY',
                      date: form.endDate ?? form.date,
                      minimumDate: form.date,
                      onChanged: vm.setEndDate,
                    ),
                ],
              ),
              if (isMultiAct)
                FormSection(
                  header: '出演者',
                  trailing: form.namedActs.isEmpty
                      ? null
                      : _CountLabel('${form.namedActs.length}組'),
                  footer: '★ でお目当てを 1 組選ぶと、チケットの見出しになり、お気に入りにも追加されます。',
                  wrapInCard: false,
                  children: [
                    ActsEditor(
                      // 日数が変わったら日ごとの欄を作り直す
                      key: ValueKey((form.actsRevision, form.dayCount)),
                      initialActs: form.acts,
                      minimumActs: form.eventFormat == EventFormat.taiban
                          ? 2
                          : 1,
                      days: form.festivalDays,
                      scrollPadding: _fieldScrollPadding,
                      onChanged: vm.setActs,
                    ),
                  ],
                ),
              RecordDetailsSection(
                form: form,
                controllers: controllers,
                onTextChanged: vm.updateText,
                onOpenTimeChanged: vm.setOpenTime,
                onStartTimeChanged: vm.setStartTime,
                onEndTimeChanged: vm.setEndTime,
                scrollPadding: _fieldScrollPadding,
              ),
              if (isLive && !isMultiAct)
                FormSection(
                  header: 'セットリスト',
                  trailing: form.songs.isEmpty
                      ? null
                      : _CountLabel('${form.songs.length}曲'),
                  wrapInCard: false,
                  children: [
                    SetlistEditor(
                      key: ValueKey(form.setlistRevision),
                      initialSongs: form.songs,
                      artistName: form.artist,
                      scrollPadding: _fieldScrollPadding,
                      onChanged: vm.setSongs,
                    ),
                  ],
                ),
              if (isLive)
                FormSection(
                  header: 'MCメモ',
                  children: [
                    FormTextRow(
                      controller: controllers[RecordTextField.mcMemo]!,
                      placeholder: '印象に残った MC や演出',
                      maxLines: 6,
                      maxLength: RecordFieldLimits.mcMemo,
                      scrollPadding: _fieldScrollPadding,
                      onChanged: (value) =>
                          vm.updateText(RecordTextField.mcMemo, value),
                    ),
                  ],
                ),
              FormSection(
                header: '感想',
                children: [
                  FormTextRow(
                    controller: controllers[RecordTextField.impressions]!,
                    placeholder: 'あとで読み返したいことを自由に',
                    minLines: 5,
                    maxLines: 12,
                    maxLength: RecordFieldLimits.impressions,
                    scrollPadding: _fieldScrollPadding,
                    onChanged: (value) =>
                        vm.updateText(RecordTextField.impressions, value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailImportButton extends StatelessWidget {
  const _MailImportButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.envelope, size: 15, color: context.colors.accent),
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
    );
  }
}

/// セクション見出しの右に添える件数。
class _CountLabel extends StatelessWidget {
  const _CountLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
    );
  }
}
