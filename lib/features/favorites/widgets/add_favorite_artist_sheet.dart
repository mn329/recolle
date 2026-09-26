import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:recolle/core/hooks/use_debounced_search.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/features/favorites/data/favorite_artists_repository.dart';
import 'package:recolle/features/favorites/providers/favorite_artists_provider.dart';
import 'package:recolle/features/music/data/itunes_client.dart';
import 'package:recolle/features/music/providers/music_providers.dart';

/// お気に入りアーティストを検索して追加するボトムシート。
Future<void> showAddFavoriteArtistSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
      isSaving.value = true;
      final messenger = ScaffoldMessenger.of(context);
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
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('「${name.trim()}」をお気に入りに追加しました')),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(toUserFriendlyMessage(e))),
        );
      } finally {
        if (context.mounted) isSaving.value = false;
      }
    }

    final trimmedQuery = query.trim();
    final artists = suggestions.data ?? const <ItunesArtist>[];
    final exactMatchInResults = artists.any(
      (a) => normalizeArtistName(a.name) == normalizeArtistName(trimmedQuery),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: FavoriteArtistsRepository.maxNameLength,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'アーティスト名で検索',
                  prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                  counterText: '',
                  suffixIcon: isSaving.value
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.gold,
                            ),
                          ),
                        )
                      : null,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) addArtist(value);
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (trimmedQuery.isNotEmpty && !exactMatchInResults)
                    _SuggestionTile(
                      icon: Icons.add_circle_outline,
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
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                  if (suggestions.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Text(
                        toUserFriendlyMessage(suggestions.error),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  for (final artist in artists)
                    _SuggestionTile(
                      icon: Icons.person_outline,
                      title: artist.name,
                      subtitle: artist.genre,
                      trailingLabel:
                          existingNames.contains(
                            normalizeArtistName(artist.name),
                          )
                          ? '登録済み'
                          : null,
                      enabled:
                          !isSaving.value &&
                          !existingNames.contains(
                            normalizeArtistName(artist.name),
                          ),
                      onTap: () =>
                          addArtist(artist.name, itunesArtistId: artist.id),
                    ),
                  if (trimmedQuery.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Apple Music のカタログから候補を表示します',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textDisabled,
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

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.enabled,
    this.subtitle,
    this.trailingLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(
        icon,
        color: enabled ? AppColors.gold : AppColors.textDisabled,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
      trailing: trailingLabel == null
          ? null
          : Text(
              trailingLabel!,
              style: const TextStyle(
                color: AppColors.textDisabled,
                fontSize: 12,
              ),
            ),
      onTap: onTap,
    );
  }
}
