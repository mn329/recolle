import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/components/record_ticket_list.dart';
import 'package:recolle/core/network/connectivity_provider.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/utils/artist_name_match.dart';
import 'package:recolle/features/favorites/models/favorite_artist.dart';
import 'package:recolle/features/favorites/widgets/artist_avatar.dart';
import 'package:recolle/features/records/providers/records_provider.dart';
import 'package:recolle/features/records/screens/create_record_screen.dart';

/// お気に入りアーティストの記録一覧。
class ArtistRecordsScreen extends ConsumerWidget {
  const ArtistRecordsScreen({super.key, required this.artist});

  final FavoriteArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = (ref.watch(recordsProvider).asData?.value ?? const [])
        .where((r) => artistMatches(r.artistOrAuthor, artist.name))
        .toList();
    final readOnlyOffline = ref.watch(isOfflineReadOnlyProvider);
    final firstDate = records.isEmpty ? null : records.last.date;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(artist.name.toUpperCase()),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add,
              color: readOnlyOffline ? AppColors.textDisabled : AppColors.gold,
            ),
            tooltip: 'このアーティストの記録を追加',
            onPressed: readOnlyOffline
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateRecordScreen(initialArtist: artist.name),
                      fullscreenDialog: true,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Hero(
                  tag: 'favorite-artist-${artist.id}',
                  child: ArtistAvatar(
                    name: artist.name,
                    artworkUrl: artist.artworkUrl,
                    size: 88,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.displayStyle(
                          fontSize: 28,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${records.length} RECORDS',
                        style: AppFonts.monoStyle(
                          fontSize: 13,
                          color: AppColors.gold,
                        ),
                      ),
                      if (firstDate != null)
                        Text(
                          'SINCE ${firstDate.year}.${firstDate.month.toString().padLeft(2, '0')}',
                          style: AppFonts.monoStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RecordTicketList(
              records: records,
              emptyMessage: 'まだ記録がありません。\n右上の＋から追加できます。',
            ),
          ),
        ],
      ),
    );
  }
}
