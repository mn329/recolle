import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:recolle/core/constants/field_limits.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/widgets/music_suggestions.dart';
import 'package:recolle/features/records/widgets/record_form/form_row_parts.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/records/widgets/record_form/setlist_editor.dart';

/// 並び替えや削除をしても入力欄の状態を取り違えないための、出演者の安定キー。
class _ActDraft {
  const _ActDraft({required this.id, required this.act});

  final String id;
  final RecordAct act;
}

/// 対バン・フェスの出演者の入力欄。出演者ごとにお目当ての印とセトリを持つ。
///
/// [days] が 2 日以上なら、日ごとに出演者を分けて入力する。
class ActsEditor extends HookWidget {
  const ActsEditor({
    super.key,
    required this.initialActs,
    required this.onChanged,
    this.minimumActs = 1,
    this.days = const [],
    this.scrollPadding = const EdgeInsets.all(20),
  });

  /// DB の制約と揃える。
  static const int maxActs = 100;

  final List<RecordAct> initialActs;
  final ValueChanged<List<RecordAct>> onChanged;

  /// 最初から出しておく入力欄の数（対バンは 2 組）。
  final int minimumActs;

  /// 複数日のフェスの各日。1 日だけなら空。
  final List<DateTime> days;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final idCounter = useRef(0);
    _ActDraft draft(RecordAct act) =>
        _ActDraft(id: 'act_${idCounter.value++}', act: act);

    final drafts = useState<List<_ActDraft>>(
      useMemoized(() {
        final initial = initialActs.map(draft).toList();
        if (days.length > 1) {
          // 出演者のいない日にも 1 組分の欄を用意する
          final filledDays = {for (final a in initialActs) a.day ?? 1};
          return [
            ...initial,
            for (var day = 1; day <= days.length; day++)
              if (!filledDays.contains(day))
                draft(RecordAct(artist: '', day: day)),
          ];
        }
        return [
          ...initial,
          for (var i = initial.length; i < minimumActs; i++)
            draft(const RecordAct(artist: '')),
        ];
      }),
    );
    // 追加した出演者の名前欄にだけフォーカスを当てる
    final autofocusId = useState<String?>(null);
    final multiDay = days.length > 1;
    int dayOf(RecordAct act) => (act.day ?? 1).clamp(1, days.length);

    void commit(List<_ActDraft> next) {
      drafts.value = next;
      onChanged([for (final d in next) d.act]);
    }

    void update(String id, RecordAct Function(RecordAct) change) => commit([
      for (final d in drafts.value)
        if (d.id == id) _ActDraft(id: d.id, act: change(d.act)) else d,
    ]);

    void add({int? day}) {
      if (drafts.value.length >= maxActs) return;
      HapticFeedback.selectionClick();
      final added = draft(RecordAct(artist: '', day: day));
      autofocusId.value = added.id;
      commit([...drafts.value, added]);
    }

    void remove(String id) {
      HapticFeedback.selectionClick();
      commit([
        for (final d in drafts.value)
          if (d.id != id) d,
      ]);
    }

    List<Widget> cards(List<_ActDraft> group) => [
      for (final (index, d) in group.indexed)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
          child: _ActCard(
            key: ValueKey(d.id),
            act: d.act,
            order: index + 1,
            autofocus: autofocusId.value == d.id,
            canRemove: drafts.value.length > 1,
            scrollPadding: scrollPadding,
            onArtistChanged: (name) =>
                update(d.id, (a) => a.copyWith(artist: name)),
            onMainToggled: () {
              HapticFeedback.selectionClick();
              update(d.id, (a) => a.copyWith(isMain: !a.isMain));
            },
            onSongsChanged: (songs) =>
                update(d.id, (a) => a.copyWith(songs: songs)),
            onRemove: () => remove(d.id),
          ),
        ),
    ];

    final canAdd = drafts.value.length < maxActs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!multiDay) ...[
          ...cards(drafts.value),
          if (canAdd) _AddActButton(label: '出演者を追加', onPressed: add),
        ] else
          for (var day = 1; day <= days.length; day++) ...[
            _DayHeading(day: day, date: days[day - 1], isFirst: day == 1),
            ...cards([
              for (final d in drafts.value)
                if (dayOf(d.act) == day) d,
            ]),
            if (canAdd)
              _AddActButton(
                label: '$day日目の出演者を追加',
                onPressed: () => add(day: day),
              ),
          ],
      ],
    );
  }
}

/// 複数日のフェスの「DAY 1　8月1日 (土)」の見出し。
class _DayHeading extends StatelessWidget {
  const _DayHeading({
    required this.day,
    required this.date,
    required this.isFirst,
  });

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  final int day;
  final DateTime date;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, isFirst ? 0 : 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'DAY $day',
            style: AppFonts.displayStyle(
              fontSize: 20,
              color: colors.accent,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$day日目　${date.month}月${date.day}日 (${_weekdays[date.weekday - 1]})',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AddActButton extends StatelessWidget {
  const _AddActButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 12),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.plus_circle_fill, size: 20, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActCard extends StatefulWidget {
  const _ActCard({
    super.key,
    required this.act,
    required this.order,
    required this.autofocus,
    required this.canRemove,
    required this.scrollPadding,
    required this.onArtistChanged,
    required this.onMainToggled,
    required this.onSongsChanged,
    required this.onRemove,
  });

  final RecordAct act;

  /// 出演順（1 始まり）。
  final int order;
  final bool autofocus;
  final bool canRemove;
  final EdgeInsets scrollPadding;
  final ValueChanged<String> onArtistChanged;
  final VoidCallback onMainToggled;
  final ValueChanged<List<String>> onSongsChanged;
  final VoidCallback onRemove;

  @override
  State<_ActCard> createState() => _ActCardState();
}

class _ActCardState extends State<_ActCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.act.artist,
  );
  final FocusNode _focusNode = FocusNode();

  /// 候補から選んだ直後は同じ候補を出し直さない。
  bool _typedSincePick = false;
  bool _setlistOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pick(String name) {
    _controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    widget.onArtistChanged(name);
    setState(() => _typedSincePick = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final act = widget.act;
    final songCount = act.songs.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: colors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormRowHighlight(
              active: _focusNode.hasFocus,
              child: _buildNameRow(context),
            ),
            if (_focusNode.hasFocus && _typedSincePick)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ArtistSuggestions(
                  query: _controller.text,
                  onPick: (a) => _pick(a.name),
                ),
              ),
            const FormDivider(),
            CupertinoButton(
              padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
              minimumSize: const Size(0, 44),
              pressedOpacity: 0.6,
              onPressed: () => setState(() => _setlistOpen = !_setlistOpen),
              child: Row(
                children: [
                  const FormRowIcon(CupertinoIcons.music_note_list),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'セットリスト',
                      style: TextStyle(fontSize: 15, color: colors.textPrimary),
                    ),
                  ),
                  Text(
                    songCount == 0 ? '未入力' : '$songCount曲',
                    style: TextStyle(fontSize: 15, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _setlistOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            // カードの中でセトリを開閉し、出演者とセトリをひとまとまりに見せる
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _setlistOpen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FormDivider(),
                        SetlistEditor(
                          initialSongs: act.songs,
                          artistName: act.artist.trim(),
                          scrollPadding: widget.scrollPadding,
                          embedded: true,
                          onChanged: widget.onSongsChanged,
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameRow(BuildContext context) {
    final colors = context.colors;
    final act = widget.act;
    return Row(
      children: [
        CupertinoButton(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          minimumSize: const Size(44, 44),
          onPressed: widget.onMainToggled,
          child: Icon(
            act.isMain ? CupertinoIcons.star_fill : CupertinoIcons.star,
            size: 21,
            color: act.isMain ? colors.accent : colors.textDisabled,
            semanticLabel: act.isMain ? 'お目当てを外す' : 'お目当てにする',
          ),
        ),
        Expanded(
          child: CupertinoTextField(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: '${widget.order}組目の出演者',
            maxLength: RecordFieldLimits.artistOrAuthor,
            textInputAction: TextInputAction.done,
            scrollPadding: widget.scrollPadding,
            clearButtonMode: OverlayVisibilityMode.editing,
            decoration: null,
            padding: const EdgeInsets.symmetric(vertical: 13),
            cursorColor: colors.accent,
            style: TextStyle(fontSize: 16, color: colors.textPrimary),
            placeholderStyle: TextStyle(
              fontSize: 16,
              color: colors.textDisabled,
            ),
            onChanged: (text) {
              widget.onArtistChanged(text);
              if (!_typedSincePick) setState(() => _typedSincePick = true);
            },
          ),
        ),
        if (widget.canRemove)
          CupertinoButton(
            padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
            minimumSize: const Size(44, 44),
            onPressed: widget.onRemove,
            child: Icon(
              CupertinoIcons.minus_circle_fill,
              size: 21,
              color: colors.destructive,
              semanticLabel: '出演者を削除',
            ),
          )
        else
          const SizedBox(width: 14),
      ],
    );
  }
}
