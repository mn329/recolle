import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Auth のセッションを購読するProvider。
/// - 初回は現在のセッションを即時 emit
/// - 以降は auth state change を反映
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession;
  await for (final state in auth.onAuthStateChange) {
    yield state.session;
  }
});

/// 現在ログイン中のユーザー（匿名含む）を購読するProvider。
final authUserProvider = StreamProvider<User?>((ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentUser;
  await for (final state in auth.onAuthStateChange) {
    yield state.session?.user;
  }
});
