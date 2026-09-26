import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/records/widgets/record_form/form_section.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/data/setlistfm_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/records/concert_candidates.dart';
import 'package:recolle/features/records/models/record.dart';
import 'package:recolle/features/records/providers/records_provider.dart';

/// お気に入りアーティストをワンタップで入力するチップ列。未登録なら何も出さない。
class FavoriteArtistQuickPick extends ConsumerWidget {
  const FavoriteArtistQuickPick({
    super.key,
    required this.currentArtist,
    required this.onPick,
  });

  final String currentArtist;
  final ValueChanged<FavoriteArtist> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    if (favorites.isEmpty) return const SizedBox.shrink();

    final current = normalizeArtistName(currentArtist);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final artist = favorites[index];
          return CapsuleChip(
            label: artist.name,
            selected: normalizeArtistName(artist.name) == current,
            avatar: ArtistAvatar(
              name: artist.name,
              artworkUrl: artist.artworkUrl,
              size: 22,
            ),
            onTap: () => onPick(artist),
          );
        },
      ),
    );
  }
}

/// iTunes のアーティスト候補。[query] が空なら何も出さない。
class ArtistSuggestions extends HookConsumerWidget {
  const ArtistSuggestions({
    super.key,
    required this.query,
    required this.onPick,
  });

  final String query;
  final ValueChanged<ItunesArtist> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itunes = ref.watch(itunesClientProvider);
    final snapshot = useDebouncedSearch<ItunesArtist>(
      query,
      (q) => itunes.searchArtists(q, limit: 5),
      minLength: 2,
    );
    final normalizedQuery = normalizeArtistName(query);
    final artists = (snapshot.data ?? const <ItunesArtist>[])
        .where((a) => normalizeArtistName(a.name) != normalizedQuery)
        .toList();

    return _SuggestionPanel(
      snapshot: snapshot,
      isEmpty: artists.isEmpty,
      children: [
        for (final artist in artists)
          _SuggestionRow(
            icon: CupertinoIcons.person,
            title: artist.name,
            subtitle: artist.genre,
            onTap: () => onPick(artist),
          ),
      ],
    );
  }
}

/// セトリ入力中の曲名候補。アーティスト名で絞り込む。
class SongSuggestions extends HookConsumerWidget {
  const SongSuggestions({
    super.key,
    required this.artistName,
    required this.query,
    required this.alreadyAdded,
    required this.onPick,
  });

  final String artistName;
  final String query;

  /// 既にセトリにある曲は候補から外す。
  final Iterable<String> alreadyAdded;
  final ValueChanged<ItunesSong> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itunes = ref.watch(itunesClientProvider);
    final snapshot = useDebouncedSearch<ItunesSong>(
      query,
      (q) => itunes.searchSongs(artistName: artistName, term: q),
    );
    final added = {for (final t in alreadyAdded) normalizeArtistName(t)};
    final songs = (snapshot.data ?? const <ItunesSong>[])
        .where((s) => !added.contains(normalizeArtistName(s.title)))
        .toList();

    return _SuggestionPanel(
      snapshot: snapshot,
      isEmpty: songs.isEmpty,
      children: [
        for (final song in songs)
          _SuggestionRow(
            leading: song.artworkUrl == null
                ? null
                : ArtistAvatar(
                    name: song.title,
                    artworkUrl: song.artworkUrl,
                    size: 32,
                    borderRadius: BorderRadius.circular(4),
                  ),
            icon: CupertinoIcons.music_note,
            title: song.title,
            subtitle: song.artistName,
            onTap: () => onPick(song),
          ),
      ],
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.snapshot,
    required this.isEmpty,
    required this.children,
  });

  final AsyncSnapshot<Object?> snapshot;
  final bool isEmpty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Widget? content;
    if (snapshot.hasError) {
      content = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          toUserFriendlyMessage(snapshot.error),
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      );
    } else if (!isEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const FormDivider(indent: 56),
            child,
          ],
        ],
      );
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      content = const Padding(
        padding: EdgeInsets.all(12),
        child: CupertinoActivityIndicator(),
      );
    } else {
      content = null;
    }

    return _SuggestionCard(child: content);
  }
}

/// 候補リストの枠。[child] が null なら何も出さない（出し入れはアニメーションする）。
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: context.colors.cardPressed,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
    );
  }
}

/// 公演名欄の候補。今後の公演（公演検索）・setlist.fm の直近の公演・自分の過去の記録から出す。
///
/// 公演検索は Gemini の無料枠を使うので、この画面か他の画面で検索済みのときだけ自動で出し、
/// それ以外は「これからの公演を探す」を押してから読む。
class ConcertSuggestions extends HookConsumerWidget {
  const ConcertSuggestions({
    super.key,
    required this.artist,
    required this.query,
    required this.onPick,
  });

  final String artist;
  final String query;
  final ValueChanged<ConcertCandidate> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = concertDiscoveryProvider(artist);
    final discoveryRequested = useState(ref.exists(discovery));
    final scrollController = useScrollController();
    final upcoming = discoveryRequested.value ? ref.watch(discovery) : null;
    final setlists = ref.watch(recentSetlistsProvider(artist));
    final setlistFm = ref.watch(setlistFmClientProvider);
    // 直近の公演にないツアーも、入力した名前で setlist.fm から探す
    final searched = useDebouncedSearch<SetlistSummary>(
      query,
      (q) =>
          setlistFm.search(artistName: artist, tourName: q, includeEmpty: true),
      delay: const Duration(milliseconds: 600),
      minLength: 2,
    );
    final records =
        ref.watch(recordsProvider).asData?.value ?? const <Record>[];

    final candidates = buildConcertCandidates(
      query: query,
      artist: artist,
      upcoming: upcoming?.asData?.value.concerts ?? const [],
      setlists: setlists.asData?.value ?? const [],
      searchedSetlists: searched.data ?? const [],
      records: records,
    );
    final errors = {
      if (upcoming?.error case final e?) toUserFriendlyMessage(e),
      if (setlists.error case final e?) toUserFriendlyMessage(e),
      if (searched.error case final e?) toUserFriendlyMessage(e),
    };
    final isLoading =
        setlists.isLoading ||
        (upcoming?.isLoading ?? false) ||
        searched.connectionState == ConnectionState.waiting;

    final footer = <Widget>[
      if (isLoading)
        const Padding(
          padding: EdgeInsets.all(12),
          child: CupertinoActivityIndicator(),
        )
      else if (!discoveryRequested.value)
        _SuggestionRow(
          icon: CupertinoIcons.search,
          title: 'これからの公演を探す',
          subtitle: '生成 AI が公式サイトなどから今後の公演を集めます',
          onTap: () => discoveryRequested.value = true,
        ),
      for (final message in errors)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
          ),
        ),
    ];

    if (candidates.isEmpty && footer.isEmpty) {
      return const _SuggestionCard(child: null);
    }
    return _SuggestionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidates.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              // 作成画面はドラッグでキーボードを閉じるため、候補のスクロールを伝えると
              // 公演名欄のフォーカスが外れて候補ごと消えてしまう
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: CupertinoScrollbar(
                  controller: scrollController,
                  child: ListView.separated(
                    controller: scrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const FormDivider(indent: 56),
                    itemBuilder: (context, i) {
                      final c = candidates[i];
                      return _SuggestionRow(
                        icon: switch (c.source) {
                          ConcertCandidateSource.upcoming =>
                            CupertinoIcons.sparkles,
                          ConcertCandidateSource.setlistFm =>
                            CupertinoIcons.music_note_list,
                          ConcertCandidateSource.record => CupertinoIcons.clock,
                        },
                        title: c.title,
                        subtitle: _subtitle(c),
                        onTap: () => onPick(c),
                      );
                    },
                  ),
                ),
              ),
            ),
          for (final (i, row) in footer.indexed) ...[
            if (i > 0 || candidates.isNotEmpty) const FormDivider(indent: 56),
            row,
          ],
        ],
      ),
    );
  }

  /// 候補がおよそ 4 件半見える高さ。途中で切れて見えることで、スクロールできると分かる。
  static const _maxListHeight = 260.0;

  static String _subtitle(ConcertCandidate c) {
    final date = c.date;
    return [
      if (c.source == ConcertCandidateSource.record) '過去の記録',
      if (date != null) formatJapaneseDate(date, includeWeekday: true),
      ?c.venue,
      ?c.city,
    ].join(' · ');
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      pressedOpacity: 0.5,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            leading ??
                Icon(
                  icon,
                  size: 20,
                  color: context.colors.accent.withValues(alpha: 0.8),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.arrow_up_left,
              size: 16,
              color: context.colors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
