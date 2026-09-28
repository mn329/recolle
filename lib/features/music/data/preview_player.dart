import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';

/// iTunes の 30 秒試聴を再生する。同時に鳴るのは 1 曲だけ。
class PreviewPlayer extends ChangeNotifier {
  PreviewPlayer() {
    _subscriptions.addAll([
      _player.playerStateStream.listen(_onPlayerState),
      _player.positionStream.listen((p) {
        _position = p;
        notifyListeners();
      }),
      _player.durationStream.listen((d) {
        _duration = d;
        notifyListeners();
      }),
    ]);
  }

  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _sessionConfigured = false;

  Uri? _currentUrl;
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  Uri? get currentUrl => _currentUrl;
  bool isPlaying(Uri url) => _currentUrl == url && _playing;
  bool isLoading(Uri url) => _currentUrl == url && _loading;

  /// [url] を再生中なら 0〜1 の進み具合、そうでなければ 0。
  double progressOf(Uri url) {
    final total = _duration;
    if (_currentUrl != url || total == null || total == Duration.zero) return 0;
    return (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<void> toggle(Uri url) async {
    if (_currentUrl == url) {
      _playing ? await _player.pause() : await _player.play();
      return;
    }
    await _configureSession();
    _currentUrl = url;
    _position = Duration.zero;
    _duration = null;
    _loading = true;
    notifyListeners();
    try {
      await _player.setUrl(url.toString());
      // play() は再生が終わるまで完了しないので待たない
      unawaited(_player.play());
    } on PlayerException catch (e) {
      _reset();
      throw UserFacingException('試聴を再生できませんでした (${e.code})。');
    } on PlayerInterruptedException {
      // 読み込み中に別の曲へ切り替えられた。新しい曲の処理が続くので何もしない
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _reset();
  }

  void _onPlayerState(PlayerState state) {
    _playing = state.playing;
    _loading =
        state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering;
    if (state.processingState == ProcessingState.completed) {
      unawaited(_player.stop());
      _reset();
      return;
    }
    notifyListeners();
  }

  void _reset() {
    _currentUrl = null;
    _playing = false;
    _loading = false;
    _position = Duration.zero;
    _duration = null;
    notifyListeners();
  }

  /// マナーモード中でも音楽アプリと同じように鳴らす。
  Future<void> _configureSession() async {
    if (_sessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _sessionConfigured = true;
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
