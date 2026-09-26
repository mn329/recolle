import 'package:flutter/cupertino.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/core/widgets/ios_widgets.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';

/// 「すべて」とお気に入りアーティストを横に並べる絞り込みチップ。選択はアーティスト名で扱う。
///
/// お気に入りにないアーティストが選ばれているときは、そのチップを先頭に足す。
class FavoriteArtistChips extends StatelessWidget {
  const FavoriteArtistChips({
    super.key,
    required this.favorites,
    required this.selectedName,
    required this.onSelected,
  });

  static const double height = 44;

  final List<FavoriteArtist> favorites;
  final String? selectedName;

  /// 選んだアーティスト名。「すべて」や選択中のチップをもう一度押したら null。
  final ValueChanged<String?> onSelected;

  /// チップを出すか。お気に入りがなく、何も選んでいなければ出さない。
  static bool isVisible(List<FavoriteArtist> favorites, String? selectedName) =>
      favorites.isNotEmpty || selectedName != null;

  @override
  Widget build(BuildContext context) {
    final selected = selectedName;
    final artists = [
      if (selected != null &&
          !favorites.any((f) => _sameArtist(f.name, selected)))
        (name: selected, artworkUrl: null as String?),
      for (final f in favorites) (name: f.name, artworkUrl: f.artworkUrl),
    ];
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        itemCount: artists.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return CapsuleChip(
              label: 'すべて',
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final artist = artists[index - 1];
          final isSelected =
              selected != null && _sameArtist(artist.name, selected);
          return CapsuleChip(
            label: artist.name,
            selected: isSelected,
            avatar: ArtistAvatar(
              name: artist.name,
              artworkUrl: artist.artworkUrl,
              size: 22,
            ),
            onTap: () => onSelected(isSelected ? null : artist.name),
          );
        },
      ),
    );
  }

  static bool _sameArtist(String a, String b) =>
      normalizeArtistName(a) == normalizeArtistName(b);
}
