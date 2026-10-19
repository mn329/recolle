class FavoriteArtist {
  const FavoriteArtist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.itunesArtistId,
    this.artworkUrl,
    this.customImageUrl,
  });

  factory FavoriteArtist.fromJson(Map<String, dynamic> json) {
    return FavoriteArtist(
      id: json['id'] as String,
      name: json['name'] as String,
      itunesArtistId: (json['itunes_artist_id'] as num?)?.toInt(),
      artworkUrl: json['artwork_url'] as String?,
      customImageUrl: json['custom_image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String name;
  final int? itunesArtistId;

  /// iTunes などから自動で取得したアーティスト写真。
  final String? artworkUrl;

  /// ユーザーが選んだ画像。自動取得の [artworkUrl] とは別に持ち、自動の置き換えに上書きされない。
  final String? customImageUrl;
  final DateTime createdAt;

  /// 画面に出す画像。ユーザーが選んだ画像があればそれを、なければ自動取得の写真を使う。
  String? get displayArtworkUrl => customImageUrl ?? artworkUrl;

  /// [customImageUrl] は、渡さなければそのまま。null を渡すと独自画像を外す。
  FavoriteArtist copyWith({
    String? artworkUrl,
    Object? customImageUrl = _keep,
  }) => FavoriteArtist(
    id: id,
    name: name,
    createdAt: createdAt,
    itunesArtistId: itunesArtistId,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    customImageUrl: identical(customImageUrl, _keep)
        ? this.customImageUrl
        : customImageUrl as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'itunes_artist_id': itunesArtistId,
    'artwork_url': artworkUrl,
    'custom_image_url': customImageUrl,
    'created_at': createdAt.toIso8601String(),
  };

  static const _keep = Object();
}
