/// 各ストリーミングサービスへのリンク。
///
/// Spotify / YouTube Music は無料・キー不要で使える検索 API がないため、
/// 検索結果ページの URL を開く（アプリが入っていればユニバーサルリンクでアプリが開く）。
enum StreamingService { appleMusic, spotify, youtubeMusic }

extension StreamingServiceUi on StreamingService {
  String get label => switch (this) {
    StreamingService.appleMusic => 'Apple Music',
    StreamingService.spotify => 'Spotify',
    StreamingService.youtubeMusic => 'YouTube Music',
  };

  /// [directUrl] は iTunes が返す正規 URL（Apple Music のみ）。なければ [query] で検索する。
  Uri link({required String query, Uri? directUrl}) {
    final q = query.trim();
    return switch (this) {
      StreamingService.appleMusic =>
        directUrl ?? Uri.https('music.apple.com', '/jp/search', {'term': q}),
      // pathSegments なら "AC/DC" の / も区切りにならずエンコードされる
      StreamingService.spotify => Uri(
        scheme: 'https',
        host: 'open.spotify.com',
        pathSegments: ['search', q],
      ),
      StreamingService.youtubeMusic => Uri.https(
        'music.youtube.com',
        '/search',
        {'q': q},
      ),
    };
  }
}
