class FavoriteArtist {
  const FavoriteArtist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.itunesArtistId,
    this.artworkUrl,
  });

  factory FavoriteArtist.fromJson(Map<String, dynamic> json) {
    return FavoriteArtist(
      id: json['id'] as String,
      name: json['name'] as String,
      itunesArtistId: (json['itunes_artist_id'] as num?)?.toInt(),
      artworkUrl: json['artwork_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String name;
  final int? itunesArtistId;
  final String? artworkUrl;
  final DateTime createdAt;

  FavoriteArtist copyWith({String? artworkUrl}) => FavoriteArtist(
    id: id,
    name: name,
    createdAt: createdAt,
    itunesArtistId: itunesArtistId,
    artworkUrl: artworkUrl ?? this.artworkUrl,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'itunes_artist_id': itunesArtistId,
    'artwork_url': artworkUrl,
    'created_at': createdAt.toIso8601String(),
  };
}
