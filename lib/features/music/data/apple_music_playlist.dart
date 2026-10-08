import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';

@immutable
class AppleMusicPlaylistResult {
  const AppleMusicPlaylistResult({this.url});

  /// 作ったプレイリストを開く URL。取れないこともある。
  final Uri? url;
}

/// Apple Music のライブラリにプレイリストを作る。iOS の MusicKit（`AppDelegate.swift`）を呼ぶ。
///
/// 使う人の Apple Music への加入と iOS 16 以降が必要。
class AppleMusicPlaylistService {
  AppleMusicPlaylistService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('recolle/apple_music');

  final MethodChannel _channel;

  /// この端末で使えるか（iOS のアプリだけ）。iOS のバージョンは作るときに確かめる。
  static bool get isAvailable => !kIsWeb && Platform.isIOS;

  Future<AppleMusicPlaylistResult> createPlaylist({
    required String name,
    required List<int> songIds,
    String? description,
  }) async {
    final Map<String, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<String, Object?>(
        'createPlaylist',
        {
          'name': name,
          'songIds': [for (final id in songIds) '$id'],
          'description': ?description,
        },
      );
    } on PlatformException catch (e) {
      if (e.code == 'failed') debugPrint('Apple Music playlist failed: $e');
      throw UserFacingException(messageForError(e.code));
    } on MissingPluginException {
      throw UserFacingException(messageForError('unsupported_os'));
    }
    final url = reply?['url'];
    return AppleMusicPlaylistResult(
      url: url is String ? Uri.tryParse(url) : null,
    );
  }

  @visibleForTesting
  static String messageForError(String code) => switch (code) {
    'unsupported_os' => 'プレイリストの作成には iOS 16 以降が必要です。',
    'denied' => 'Apple Music へのアクセスが許可されていません。設定アプリの「recolle」から許可してください。',
    'no_subscription' => 'プレイリストの作成には Apple Music への加入が必要です。',
    'not_found' => 'Apple Music で曲が見つかりませんでした。',
    _ => 'プレイリストを作成できませんでした。',
  };
}
