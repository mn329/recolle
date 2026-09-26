import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/widgets/app_toast.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/data/favorite_artists_repository.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// お気に入りアーティストを検索して追加する、iOS のカード型シート。
Future<void> showAddFavoriteArtistSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return showCupertinoSheet<void>(
    context: context,
    builder: (_) => _AddFavoriteArtistSheet(initialQuery: initialQuery),
  );
}

class _AddFavoriteArtistSheet extends HookConsumerWidget {
  const _AddFavoriteArtistSheet({required this.initialQuery});

  final String initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController(text: initialQuery);
    final query = useValueListenable(controller).text;
    final isSaving = useState(false);
    final itunes = ref.watch(itunesClientProvider);
    final suggestions = useDebouncedSearch<ItunesArtist>(
      query,
      itunes.searchArtists,
    );
    final existingNames = {
      for (final f in ref.watch(favoriteArtistsProvider).asData?.value ?? [])
        normalizeArtistName(f.name),
    };

    Future<void> addArtist(String name, {int? itunesArtistId}) async {
      if (isSaving.value) return;
      if (name.trim().length > FavoriteArtistsRepository.maxNameLength) {
        AppToast.error(
          'アーティスト名は${FavoriteArtistsRepository.maxNameLength}文字以内にしてください',
        );
        return;
      }
      isSaving.value = true;
      final navigator = Navigator.of(context);
      try {
        String? artworkUrl;
        try {
          artworkUrl = await itunes.findArtistArtwork(name);
        } catch (e) {
          // アートワークは任意項目なので、取得失敗でも登録は続ける
          debugPrint('Artwork lookup failed for $name: $e');
        }
        await ref
            .read(favoriteArtistsProvider.notifier)
            .add(
              name: name,
              itunesArtistId: itunesArtistId,
              artworkUrl: artworkUrl,
            );
        HapticFeedback.lightImpact();
        navigator.pop();
        AppToast.show(
          '「${name.trim()}」をお気に入りに追加しました',
          icon: CupertinoIcons.star_fill,
        );
      } catch (e) {
        AppToast.error(toUserFriendlyMessage(e));
      } finally {
        if (context.mounted) isSaving.value = false;
      }
    }

    final trimmedQuery = query.trim();
    final artists = suggestions.data ?? const <ItunesArtist>[];
    final exactMatchInResults = artists.any(
      (a) => normalizeArtistName(a.name) == normalizeArtistName(trimmedQuery),
    );

    return CupertinoPageScaffold(
      backgroundColor: context.colors.card,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.colors.card,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          onPressed: () => Navigator.pop(context),
          child: Text(
            'キャンセル',
            style: TextStyle(color: context.colors.accent, fontSize: 17),
          ),
        ),
        middle: const Text('アーティストを追加'),
        trailing: isSaving.value ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: CupertinoSearchTextField(
                controller: controller,
                autofocus: true,
                placeholder: 'アーティスト名で検索',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                ),
                itemColor: context.colors.textSecondary,
                backgroundColor: context.colors.fill,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) addArtist(value);
                },
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  if (trimmedQuery.isNotEmpty && !exactMatchInResults)
                    _SuggestionRow(
                      icon: CupertinoIcons.plus_circle,
                      title: '「$trimmedQuery」を追加',
                      subtitle: '入力した名前のまま登録',
                      enabled:
                          !isSaving.value &&
                          !existingNames.contains(
                            normalizeArtistName(trimmedQuery),
                          ),
                      onTap: () => addArtist(trimmedQuery),
                    ),
                  if (suggestions.connectionState == ConnectionState.waiting &&
                      artists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CupertinoActivityIndicator(),
                    ),
                  if (suggestions.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Text(
                        toUserFriendlyMessage(suggestions.error),
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  for (final artist in artists)
                    _SuggestionRow(
                      icon: CupertinoIcons.person,
                      title: artist.name,
                      subtitle: artist.genre,
                      alreadyAdded: existingNames.contains(
                        normalizeArtistName(artist.name),
                      ),
                      enabled:
                          !isSaving.value &&
                          !existingNames.contains(
                            normalizeArtistName(artist.name),
                          ),
                      onTap: () =>
                          addArtist(artist.name, itunesArtistId: artist.id),
                    ),
                  if (trimmedQuery.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Apple Music のカタログから候補を表示します',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.enabled,
    this.subtitle,
    this.alreadyAdded = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool alreadyAdded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GroupedRow(
      leading: Icon(
        icon,
        size: 22,
        color: enabled ? context.colors.accent : context.colors.textDisabled,
      ),
      title: title,
      titleColor: enabled
          ? context.colors.textPrimary
          : context.colors.textDisabled,
      subtitle: subtitle,
      showChevron: false,
      additionalInfo: alreadyAdded
          ? Text(
              '登録済み',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
              ),
            )
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}
