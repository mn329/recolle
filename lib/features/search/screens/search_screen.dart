import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/components/record_ticket_card.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/japanese_date_format.dart';
import 'package:recolle/core/widgets/section_title.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';
import 'package:recolle/features/music/screens/artist_detail_screen.dart';
import 'package:recolle/features/music/screens/song_detail_screen.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/search/search_logic.dart';

/// 記録・アーティスト・曲の横断検索。
class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final query = useValueListenable(controller).text;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            cursorColor: AppColors.gold,
            decoration: InputDecoration(
              hintText: 'ライブ・アーティスト・曲を検索',
              hintStyle: const TextStyle(color: AppColors.textDisabled),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'クリア',
                      onPressed: controller.clear,
                    ),
            ),
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: '記録'),
              Tab(text: 'アーティスト'),
              Tab(text: '曲'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RecordResults(query: query),
            _ArtistResults(query: query),
            _SongResults(query: query),
          ],
        ),
      ),
    );
  }
}

class _RecordResults extends ConsumerWidget {
  const _RecordResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return const _Hint(
        icon: Icons.confirmation_number_outlined,
        text: 'タイトル・アーティスト・セトリの曲・MCメモ・感想から探せます。\nスペース区切りで絞り込み（例: YOASOBI アイドル）',
      );
    }
    final records = ref.watch(recordsProvider).asData?.value ?? const [];
    final hits = searchRecords(records, query);
    if (hits.isEmpty) {
      return const _Hint(icon: Icons.search_off, text: '一致する記録はありません');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecordTicketCard(
              record: hit.record,
              onTap: () => openRecordDetail(context, hit.record),
            ),
            if (hit.snippet != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${hit.matchLabel}  ',
                        style: const TextStyle(color: AppColors.gold),
                      ),
                      TextSpan(text: hit.snippet),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
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
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen(
            artistName: name,
            itunesArtistId: itunesArtistId,
            artworkUrl: artworkUrl,
          ),
        ),
      );
    }

    if (local.isEmpty && query.trim().length < 2) {
      return const _Hint(
        icon: Icons.person_search_outlined,
        text: 'アーティスト名を入力すると Apple Music のカタログからも探します',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (local.isNotEmpty) ...[
          SectionTitle(
            'YOUR ARTISTS',
            query.trim().isEmpty ? 'あなたのアーティスト' : '記録・お気に入りから',
          ),
          for (final a in local)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: ArtistAvatar(
                name: a.name,
                artworkUrl: a.favorite?.artworkUrl,
                size: 44,
              ),
              title: Text(
                a.name,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                '${a.recordCount} RECORDS',
                style: AppFonts.monoStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: a.favorite == null
                  ? null
                  : const Icon(Icons.star_rounded, color: AppColors.gold),
              onTap: () => open(
                a.name,
                itunesArtistId: a.favorite?.itunesArtistId,
                artworkUrl: a.favorite?.artworkUrl,
              ),
            ),
        ],
        if (query.trim().length >= 2) ...[
          const SectionTitle(
            'APPLE MUSIC',
            'カタログから',
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          ),
          _RemoteState(snapshot: remote, isEmpty: remoteArtists.isEmpty),
          for (final a in remoteArtists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: ArtistAvatar(name: a.name, size: 44),
              title: Text(
                a.name,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: a.genre == null
                  ? null
                  : Text(
                      a.genre!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
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

    if (local.isEmpty && query.trim().length < 2) {
      return const _Hint(
        icon: Icons.library_music_outlined,
        text: 'ライブで聴いた曲（セトリ）と Apple Music のカタログから探せます',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (local.isNotEmpty) ...[
          SectionTitle(
            'HEARD LIVE',
            query.trim().isEmpty ? 'よく聴いた曲' : 'ライブで聴いた曲',
          ),
          for (final s in local)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(
                Icons.confirmation_number_rounded,
                color: AppColors.gold,
              ),
              title: Text(
                s.title,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                '${s.artistName} · 最後に聴いた日 ${formatJapaneseDate(s.lastHeard)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              trailing: Text(
                '×${s.timesHeard}',
                style: AppFonts.monoStyle(fontSize: 13, color: AppColors.gold),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    artistName: s.artistName,
                    title: s.title,
                  ),
                ),
              ),
            ),
        ],
        if (query.trim().length >= 2) ...[
          const SectionTitle(
            'APPLE MUSIC',
            'カタログから',
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          ),
          _RemoteState(snapshot: remote, isEmpty: remoteSongs.isEmpty),
          for (final s in remoteSongs)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: ArtistAvatar(
                name: s.title,
                artworkUrl: s.artworkUrl,
                size: 44,
                borderRadius: BorderRadius.circular(6),
              ),
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                s.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    artistName: s.artistName,
                    title: s.title,
                    song: s,
                  ),
                ),
              ),
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
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.gold,
            ),
          ),
        ),
      );
    } else if (isEmpty) {
      message = '見つかりませんでした';
    } else {
      message = null;
    }
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textDisabled, fontSize: 13),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.gold.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
