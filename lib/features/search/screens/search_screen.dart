import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/content_switcher.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/music/widgets/preview_play_button.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/search/search_logic.dart';
import 'package:recolle/core/widgets/app_background.dart';

enum _Scope { records, artists, songs }

/// 記録・アーティスト・曲の横断検索。
class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final query = useValueListenable(controller).text;
    final scope = useState(_Scope.records);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: CupertinoSearchTextField(
            controller: controller,
            autofocus: true,
            placeholder: 'ライブ・アーティスト・曲',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
            itemColor: context.colors.textSecondary,
            backgroundColor: context.colors.fill,
          ),
          actions: [
            NavBarTextButton(
              label: 'キャンセル',
              onPressed: () => Navigator.pop(context),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: IosSegmentedControl<_Scope>(
                value: scope.value,
                segments: const {
                  _Scope.records: '記録',
                  _Scope.artists: 'アーティスト',
                  _Scope.songs: '曲',
                },
                onChanged: (s) => scope.value = s,
              ),
            ),
          ),
        ),
        body: ContentSwitcher(
          contentKey: scope.value,
          child: switch (scope.value) {
            _Scope.records => _RecordResults(query: query),
            _Scope.artists => _ArtistResults(query: query),
            _Scope.songs => _SongResults(query: query),
          },
        ),
      ),
    );
  }
}

EdgeInsets _listPadding(BuildContext context) =>
    EdgeInsets.only(top: 8, bottom: 32 + MediaQuery.paddingOf(context).bottom);

class _RecordResults extends ConsumerWidget {
  const _RecordResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return const IosEmptyState(
        icon: CupertinoIcons.tickets,
        message:
            'タイトル・アーティスト・セトリの曲・MC メモ・感想から探せます。スペースで区切ると、すべての言葉を含む記録に絞り込めます（例: YOASOBI アイドル）。',
      );
    }
    final recordsAsync = ref.watch(recordsProvider);
    // 読み込み前に「結果なし」と出さない
    if (recordsAsync.isLoading && !recordsAsync.hasValue) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    final records = recordsAsync.asData?.value ?? const [];
    final hits = searchRecords(records, query);
    if (hits.isEmpty) {
      return IosEmptyState(
        icon: CupertinoIcons.search,
        title: '結果なし',
        message: '「${query.trim()}」に一致する記録はありません',
      );
    }
    return ListView.builder(
      padding: _listPadding(context),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecordTicketTile(record: hit.record),
            if (hit.snippet != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${hit.matchLabel}  ',
                        style: TextStyle(color: context.colors.accent),
                      ),
                      TextSpan(text: hit.snippet),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ArtistResults extends HookConsumerWidget {
  const _ArtistResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider).asData?.value ?? const [];
    final favorites =
        ref.watch(favoriteArtistsProvider).asData?.value ??
        const <FavoriteArtist>[];
    final local = searchLocalArtists(
      records: records,
      favorites: favorites,
      query: query,
    );
    final itunes = ref.watch(itunesClientProvider);
    final remote = useDebouncedSearch<ItunesArtist>(
      query,
      (q) => itunes.searchArtists(q, limit: 10),
      minLength: 2,
    );
    final localKeys = {for (final a in local) normalizeArtistName(a.name)};
    final remoteArtists = (remote.data ?? const <ItunesArtist>[])
        .where((a) => !localKeys.contains(normalizeArtistName(a.name)))
        .toList();

    void open(String name, {int? itunesArtistId, String? artworkUrl}) {
      Navigator.push(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => ArtistDetailScreen(
            artistName: name,
            itunesArtistId: itunesArtistId,
            artworkUrl: artworkUrl,
          ),
        ),
      );
    }

    if (local.isEmpty && query.trim().length < 2) {
      return const IosEmptyState(
        icon: CupertinoIcons.person_2,
        message: 'アーティスト名を入力すると、まだ記録していないアーティストも探せます。',
      );
    }

    return ListView(
      padding: _listPadding(context),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (local.isNotEmpty) ...[
          SectionTitle(
            'YOUR ARTISTS',
            query.trim().isEmpty ? 'あなたのアーティスト' : '記録・お気に入りから',
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          ),
          for (final a in local)
            MediaListTile(
              leading: ArtistAvatar(
                name: a.name,
                artworkUrl: a.favorite?.artworkUrl,
                size: 46,
              ),
              title: a.name,
              subtitle: '${a.recordCount}件の記録',
              trailing: a.favorite == null
                  ? null
                  : Icon(
                      CupertinoIcons.star_fill,
                      size: 18,
                      color: context.colors.accent,
                    ),
              onTap: () => open(
                a.name,
                itunesArtistId: a.favorite?.itunesArtistId,
                artworkUrl: a.favorite?.artworkUrl,
              ),
            ),
        ],
        if (query.trim().length >= 2) ...[
          const SectionTitle(
            'MORE ARTISTS',
            'ほかのアーティスト',
            padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
          ),
          _RemoteState(snapshot: remote, isEmpty: remoteArtists.isEmpty),
          for (final a in remoteArtists)
            MediaListTile(
              leading: ArtistAvatar(name: a.name, size: 46),
              title: a.name,
              subtitle: a.genre,
              onTap: () => open(a.name, itunesArtistId: a.id),
            ),
        ],
      ],
    );
  }
}

class _SongResults extends HookConsumerWidget {
  const _SongResults({required this.query});

  final String query;

  static const _maxLocalSongs = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider).asData?.value ?? const [];
    final local = searchLocalSongs(
      records,
      query,
    ).take(_maxLocalSongs).toList();
    final itunes = ref.watch(itunesClientProvider);
    final remote = useDebouncedSearch<ItunesSong>(
      query,
      (q) => itunes.searchSongs(artistName: '', term: q, limit: 10),
      minLength: 2,
    );
    final remoteSongs = remote.data ?? const <ItunesSong>[];

    void openSong(String artistName, String title, {ItunesSong? song}) {
      Navigator.push(
        context,
        CupertinoPageRoute<void>(
          builder: (_) => SongDetailScreen(
            artistName: artistName,
            title: title,
            song: song,
          ),
        ),
      );
    }

    if (local.isEmpty && query.trim().length < 2) {
      return const IosEmptyState(
        icon: CupertinoIcons.music_note_list,
        message: 'ライブで聴いた曲（セトリ）と、配信されている曲から探せます。',
      );
    }

    return ListView(
      padding: _listPadding(context),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (local.isNotEmpty) ...[
          SectionTitle(
            'HEARD LIVE',
            query.trim().isEmpty ? 'よく聴いた曲' : 'ライブで聴いた曲',
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          ),
          for (final s in local)
            MediaListTile(
              leading: SizedBox.square(
                dimension: 46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.card,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Icon(
                    CupertinoIcons.tickets_fill,
                    color: context.colors.accent,
                    size: 22,
                  ),
                ),
              ),
              title: s.title,
              subtitle:
                  '${s.artistName}・最後に聴いた日 ${formatJapaneseDate(s.lastHeard)}',
              trailing: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text(
                  '×${s.timesHeard}',
                  style: AppFonts.monoStyle(
                    fontSize: 13,
                    color: context.colors.accent,
                  ),
                ),
              ),
              onTap: () => openSong(s.artistName, s.title),
            ),
        ],
        if (query.trim().length >= 2) ...[
          const SectionTitle(
            'MORE SONGS',
            '配信されている曲',
            padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
          ),
          _RemoteState(snapshot: remote, isEmpty: remoteSongs.isEmpty),
          for (final s in remoteSongs)
            MediaListTile(
              leading: ArtistAvatar(
                name: s.title,
                artworkUrl: s.artworkUrl,
                size: 46,
                borderRadius: BorderRadius.circular(6),
              ),
              title: s.title,
              subtitle: s.artistName,
              trailing: PreviewPlayButton(previewUrl: s.previewUrl, size: 34),
              onTap: () => openSong(s.artistName, s.title, song: s),
            ),
        ],
      ],
    );
  }
}

/// iTunes 検索の読み込み中・エラー・該当なしの表示。結果があるときは何も出さない。
class _RemoteState extends StatelessWidget {
  const _RemoteState({required this.snapshot, required this.isEmpty});

  final AsyncSnapshot<Object?> snapshot;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final String? message;
    if (snapshot.hasError) {
      message = toUserFriendlyMessage(snapshot.error);
    } else if (snapshot.connectionState == ConnectionState.waiting ||
        (snapshot.connectionState == ConnectionState.none)) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: CupertinoActivityIndicator(),
      );
    } else if (isEmpty) {
      message = '見つかりませんでした';
    } else {
      message = null;
    }
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Text(
        message,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
      ),
    );
  }
}
