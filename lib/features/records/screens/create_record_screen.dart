import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/constants/ticket_image_settings.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/utils/ticket_image_compress.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/detail_screen.dart';
import 'package:recolle/features/records/widgets/number_date_picker_sheet.dart';
import 'package:recolle/features/records/widgets/record_form_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 並び替え時に [ReorderableListView] 用の安定キーとなる行。
class _SetlistLine {
  const _SetlistLine({required this.id, required this.text});

  final String id;
  final String text;
}

class CreateRecordScreen extends HookConsumerWidget {
  const CreateRecordScreen({super.key, this.recordToEdit});

  /// 指定時は編集モード。保存後は更新された [Record] を [Navigator.pop] で返す。
  final Record? recordToEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordToEdit = this.recordToEdit;
    final editingRecord = recordToEdit;
    final isEditMode = editingRecord != null;

    // State
    final setlistIdCounter = useRef(1);
    final selectedType = useState<RecordType>(
      recordToEdit?.type ?? RecordType.live,
    );
    final date = useState<DateTime>(recordToEdit?.date ?? DateTime.now());
    final setlistLines = useState<List<_SetlistLine>>(() {
      final s = recordToEdit?.setlist;
      if (s == null || s.isEmpty) return <_SetlistLine>[];
      return s
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(
            (t) => _SetlistLine(id: 'sl_${setlistIdCounter.value++}', text: t),
          )
          .toList(growable: false);
    }());
    final selectedImage = useState<File?>(null);
    final isLoading = useState(false);

    // Controllers
    final titleController = useTextEditingController(text: recordToEdit?.title);
    final artistController = useTextEditingController(
      text: recordToEdit?.artistOrAuthor,
    );
    final sourceController = useTextEditingController(
      text: recordToEdit?.ticketSource,
    );
    final currentSongController = useTextEditingController();
    final mcMemoController = useTextEditingController(
      text: recordToEdit?.mcMemo,
    );
    final impressionsController = useTextEditingController(
      text: recordToEdit?.impressions,
    );

    final scrollController = useScrollController();
    final currentSongFocusNode = useFocusNode();
    final addSetlistSectionKey = useMemoized(GlobalKey.new);

    void tryAddSongToSetlist() {
      final line = currentSongController.text.trim();
      if (line.isEmpty) return;
      if (line.length > RecordFieldLimits.setlistSongLine) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('曲名は最大${RecordFieldLimits.setlistSongLine}文字までです。'),
          ),
        );
        return;
      }
      final candidate = [
        ...setlistLines.value.map((e) => e.text),
        line,
      ].join('\n');
      if (candidate.length > RecordFieldLimits.setlistTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。',
            ),
          ),
        );
        return;
      }
      final newLine = _SetlistLine(
        id: 'sl_${setlistIdCounter.value++}',
        text: line,
      );
      setlistLines.value = [...setlistLines.value, newLine];
      currentSongController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final target = addSetlistSectionKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: 1,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
        if (currentSongFocusNode.canRequestFocus) {
          currentSongFocusNode.requestFocus();
        }
      });
    }

    Future<void> pickImage() async {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: TicketImageSettings.maxPickDimension,
        maxHeight: TicketImageSettings.maxPickDimension,
        imageQuality: TicketImageSettings.pickImageQuality,
      );

      if (pickedFile != null) {
        final raw = File(pickedFile.path);
        selectedImage.value = await compressTicketImageForUpload(raw);
      }
    }

    Future<void> saveRecord() async {
      if (isLoading.value) return;

      final title = titleController.text.trim();
      final artist = artistController.text.trim();
      if (title.isEmpty || artist.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('タイトルとアーティスト名は必須です')));
        return;
      }

      if (title.length > RecordFieldLimits.title ||
          artist.length > RecordFieldLimits.artistOrAuthor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('タイトルまたはアーティスト名が文字数上限を超えています。')),
        );
        return;
      }

      final sourceTrimmed = sourceController.text.trim();
      if (sourceTrimmed.length > RecordFieldLimits.ticketSource) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('取得元は最大${RecordFieldLimits.ticketSource}文字までです。'),
          ),
        );
        return;
      }

      final setlistJoined = setlistLines.value.isEmpty
          ? null
          : setlistLines.value.map((e) => e.text).join('\n');
      if (setlistJoined != null &&
          setlistJoined.length > RecordFieldLimits.setlistTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'セットリスト全体は最大${RecordFieldLimits.setlistTotal}文字までです。',
            ),
          ),
        );
        return;
      }

      final mcTrimmed = mcMemoController.text.trim();
      final impressionsTrimmed = impressionsController.text.trim();
      if (mcTrimmed.length > RecordFieldLimits.mcMemo ||
          impressionsTrimmed.length > RecordFieldLimits.impressions) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MCメモまたは感想が文字数上限を超えています。')),
        );
        return;
      }

      isLoading.value = true;

      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('ログインしてください')));
          }
          isLoading.value = false;
          return;
        }

        final repo = ref.read(recordsRepositoryProvider);

        String ticketImageUrl = recordToEdit?.ticketImageUrl ?? '';
        if (selectedImage.value != null) {
          debugPrint('Uploading ticket image…');
          ticketImageUrl = await repo.uploadTicketImage(
            userId: userId,
            file: selectedImage.value!,
          );
          debugPrint('Image uploaded, URL: $ticketImageUrl');
        }

        final record = Record(
          id: recordToEdit?.id ?? '',
          type: selectedType.value,
          title: title,
          artistOrAuthor: artist,
          date: date.value,
          ticketImageUrl: ticketImageUrl,
          ticketSource: sourceTrimmed.isEmpty ? null : sourceTrimmed,
          setlist: setlistJoined == null || setlistJoined.isEmpty
              ? null
              : setlistJoined,
          mcMemo: mcTrimmed.isEmpty ? null : mcTrimmed,
          impressions: impressionsTrimmed.isEmpty ? null : impressionsTrimmed,
        );

        if (editingRecord != null) {
          final updated = await repo.updateRecord(
            editingRecord.id,
            record.toJson(),
          );
          debugPrint('Record updated: ${updated.id}');
          if (context.mounted) {
            ref.invalidate(recordsProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('記録を更新しました'),
                backgroundColor: AppColors.gold,
              ),
            );
            Navigator.of(context).pop(updated);
          }
        } else {
          final recordData = record.toJson();
          recordData['user_id'] = userId;

          debugPrint('Inserting record: $recordData');

          final newRecord = await repo.insertRecord(recordData);
          debugPrint('Record inserted: ${newRecord.id}');

          if (context.mounted) {
            ref.invalidate(recordsProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('記録を保存しました'),
                backgroundColor: AppColors.gold,
              ),
            );
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => DetailScreen(record: newRecord),
              ),
            );
          }
        }
      } catch (e, stackTrace) {
        debugPrint('Error saving record: $e');
        debugPrint('Stack trace: $stackTrace');
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(toUserFriendlyMessage(e))));
        }
      } finally {
        isLoading.value = false;
      }
    }

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final fieldScrollPadding = EdgeInsets.fromLTRB(
      20,
      24,
      20,
      keyboardInset + 120,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isEditMode ? '編集' : '新規登録'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (isLoading.value)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.gold,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: saveRecord,
              child: const Text(
                '保存',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Genre Selection
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: RecordType.values.map((type) {
                  final isSelected = selectedType.value == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      label: Text(
                        type.japaneseLabel,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.black
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) selectedType.value = type;
                      },
                      selectedColor: AppColors.gold,
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : AppColors.textDisabled,
                        ),
                      ),
                      // Remove checkmark
                      showCheckmark: false,
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            // 2. Image Placeholder
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.textDisabled.withValues(alpha: 0.3),
                ),
              ),
              child: InkWell(
                onTap: pickImage,
                borderRadius: BorderRadius.circular(16),
                child: selectedImage.value != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final dpr = MediaQuery.devicePixelRatioOf(context);
                            return Image.file(
                              selectedImage.value!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              cacheHeight: (constraints.maxHeight * dpr).round(),
                            );
                          },
                        ),
                      )
                    : (recordToEdit?.ticketImageUrl.isNotEmpty ?? false)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return DecodedNetworkImage(
                              url: recordToEdit!.ticketImageUrl,
                              logicalWidth: constraints.maxWidth,
                              logicalHeight: constraints.maxHeight,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      size: 48,
                                      color: AppColors.gold.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '画像を読み込めません',
                                      style: TextStyle(
                                        color: AppColors.textSecondary
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 48,
                            color: AppColors.gold.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'チケット画像を追加',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // 3. Basic Info Form
            RecordFormTextField(
              controller: titleController,
              label: 'タイトル',
              icon: Icons.title,
              maxLength: RecordFieldLimits.title,
              scrollPadding: fieldScrollPadding,
            ),
            const SizedBox(height: 16),
            RecordFormTextField(
              controller: artistController,
              label: 'アーティスト / 作者',
              icon: Icons.person_outline,
              maxLength: RecordFieldLimits.artistOrAuthor,
              scrollPadding: fieldScrollPadding,
            ),
            const SizedBox(height: 16),

            // Date Picker (Custom Number Picker)
            InkWell(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.surface,
                  builder: (BuildContext context) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height / 3 + 50,
                      child: Column(
                        children: [
                          // Toolbar with Done button
                          Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.textDisabled.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    '決定',
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Picker
                          Expanded(
                            child: NumberDatePickerSheet(
                              initialDate: date.value,
                              onDateChanged: (newDate) {
                                date.value = newDate;
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.textDisabled.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: AppColors.gold,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatJapaneseDate(
                        date.value,
                        includeWeekday: true,
                        padMonthDay: true,
                      ),
                      style: AppFonts.monoStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            RecordFormTextField(
              controller: sourceController,
              label: '取得元 (e+, Amazon等)',
              icon: Icons.confirmation_number_outlined,
              maxLength: RecordFieldLimits.ticketSource,
              scrollPadding: fieldScrollPadding,
            ),

            const SizedBox(height: 32),

            // 4. Detailed Info (Conditional)
            if (selectedType.value == RecordType.live) ...[
              const Text(
                'レポート',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Setlist UI
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.queue_music_rounded,
                      color: AppColors.gold,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'セットリスト',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '左のつまみをドラッグして並び替え',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // List of songs（編集・並び替え）
              if (setlistLines.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    onReorder: (oldIndex, newIndex) {
                      final items = [...setlistLines.value];
                      if (newIndex > oldIndex) newIndex--;
                      final moved = items.removeAt(oldIndex);
                      items.insert(newIndex, moved);
                      setlistLines.value = items;
                    },
                    children: [
                      ...setlistLines.value.asMap().entries.map((entry) {
                        final i = entry.key;
                        final line = entry.value;
                        final lineId = line.id;
                        final isLast = i == setlistLines.value.length - 1;
                        return Padding(
                          key: ValueKey(lineId),
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                          child: _SetlistSongRow(
                            scrollPadding: fieldScrollPadding,
                            indexOneBased: i + 1,
                            line: line,
                            onTextChanged: (newText) {
                              setlistLines.value = [
                                for (final e in setlistLines.value)
                                  if (e.id == lineId)
                                    _SetlistLine(id: lineId, text: newText)
                                  else
                                    e,
                              ];
                            },
                            onDelete: () {
                              setlistLines.value = setlistLines.value
                                  .where((e) => e.id != lineId)
                                  .toList();
                            },
                            dragIndex: i,
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // Add Song Input
              DecoratedBox(
                key: addSetlistSectionKey,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        color: AppColors.gold.withValues(alpha: 0.85),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: currentSongController,
                          focusNode: currentSongFocusNode,
                          maxLength: RecordFieldLimits.setlistSongLine,
                          scrollPadding: fieldScrollPadding,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: '曲名を追加',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            counterText: '',
                          ),
                          onSubmitted: (_) => tryAddSongToSetlist(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        onPressed: tryAddSongToSetlist,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.gold.withValues(
                            alpha: 0.22,
                          ),
                          foregroundColor: AppColors.gold,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '追加',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              RecordFormTextField(
                controller: mcMemoController,
                label: 'MCメモ',
                icon: Icons.mic_none,
                maxLines: 3,
                maxLength: RecordFieldLimits.mcMemo,
                scrollPadding: fieldScrollPadding,
              ),
              const SizedBox(height: 16),
            ],

            RecordFormTextField(
              controller: impressionsController,
              label: '感想',
              icon: Icons.edit_note,
              maxLines: 5,
              maxLength: RecordFieldLimits.impressions,
              scrollPadding: fieldScrollPadding,
            ),

            SizedBox(height: 40 + keyboardInset),
          ],
        ),
      ),
    );
  }
}

class _SetlistSongRow extends StatefulWidget {
  const _SetlistSongRow({
    required this.scrollPadding,
    required this.indexOneBased,
    required this.line,
    required this.onTextChanged,
    required this.onDelete,
    required this.dragIndex,
  });

  final EdgeInsets scrollPadding;
  final int indexOneBased;
  final _SetlistLine line;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onDelete;
  final int dragIndex;

  @override
  State<_SetlistSongRow> createState() => _SetlistSongRowState();
}

class _SetlistSongRowState extends State<_SetlistSongRow>
    with SingleTickerProviderStateMixin {
  static const double _deleteRevealWidth = 92;

  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late AnimationController _slideController;
  late Animation<double> _slideOffset;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line.text);
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _slideOffset = Tween<double>(begin: 0, end: _deleteRevealWidth).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _SetlistSongRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line.id != oldWidget.line.id) {
      _slideController.value = 0;
      _controller.dispose();
      _controller = TextEditingController(text: widget.line.text);
      return;
    }
    if (!_focusNode.hasFocus && widget.line.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.line.text,
        selection: TextSelection.collapsed(offset: widget.line.text.length),
      );
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleDeleteReveal() {
    if (_slideController.isCompleted) {
      _slideController.reverse();
    } else {
      _slideController.forward();
    }
  }

  void _confirmDelete() {
    _slideController.reverse();
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: _deleteRevealWidth,
            child: Material(
              color: const Color(0xFFB71C1C),
              child: InkWell(
                onTap: _confirmDelete,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '削除',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _slideOffset,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_slideOffset.value, 0),
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Tooltip(
                        message: 'ドラッグして並び替え',
                        waitDuration: const Duration(milliseconds: 400),
                        child: ReorderableDragStartListener(
                          index: widget.dragIndex,
                          child: Material(
                            color: AppColors.surface.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.75,
                                ),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.35),
                              width: 0.6,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${widget.indexOneBased}',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          scrollPadding: widget.scrollPadding,
                          maxLength: RecordFieldLimits.setlistSongLine,
                          maxLines: 2,
                          minLines: 1,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.35,
                          ),
                          strutStyle: const StrutStyle(
                            fontSize: 15,
                            height: 1.35,
                            forceStrutHeight: true,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '曲名',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.42,
                              ),
                              fontSize: 15,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surface.withValues(
                              alpha: 0.65,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(11),
                              borderSide: BorderSide(
                                color: AppColors.textDisabled.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(11),
                              borderSide: BorderSide(
                                color: AppColors.textDisabled.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(11),
                              borderSide: BorderSide(
                                color: AppColors.gold.withValues(alpha: 0.75),
                                width: 1.2,
                              ),
                            ),
                          ),
                          onChanged: widget.onTextChanged,
                        ),
                      ),
                      const SizedBox(width: 4),
                      ListenableBuilder(
                        listenable: _slideController,
                        builder: (context, _) {
                          return Tooltip(
                            message: _slideController.isCompleted
                                ? '閉じる'
                                : '削除パネルを表示',
                            waitDuration: const Duration(milliseconds: 400),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              icon: Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 22,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                              style: IconButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                              ),
                              onPressed: _toggleDeleteReveal,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
