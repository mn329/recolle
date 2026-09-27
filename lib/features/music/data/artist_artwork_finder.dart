import 'package:flutter/foundation.dart';
import 'package:recolle/features/music/data/deezer_client.dart';
import 'package:recolle/features/music/data/itunes_client.dart';

/// アーティストのアートワークを探す。
///
/// Deezer のアーティスト画像を優先し、なければ iTunes の代表アルバムのジャケットで代用する。
class ArtistArtworkFinder {
  const ArtistArtworkFinder({
    required DeezerClient deezer,
    required ItunesClient itunes,
  }) : _deezer = deezer,
       _itunes = itunes;

  final DeezerClient _deezer;
  final ItunesClient _itunes;

  Future<String?> find(String artistName) async {
    final image = await findArtistImage(artistName);
    return image ?? await _itunes.findArtistArtwork(artistName);
  }

  /// アルバムジャケットでの代用はせず、アーティスト画像だけを探す。
  /// Deezer が失敗しても呼び出し側の処理は止めたくないので、失敗時も null を返す。
  Future<String?> findArtistImage(String artistName) async {
    try {
      return await _deezer.findArtistImage(artistName);
    } catch (e) {
      debugPrint('Deezer artist image lookup failed for $artistName: $e');
      return null;
    }
  }

  /// [url] が iTunes のアルバムジャケット（アーティスト画像の代用）か。
  static bool isAlbumArtworkFallback(String url) =>
      Uri.tryParse(url)?.host.endsWith('mzstatic.com') ?? false;
}
