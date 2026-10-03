import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:recolle/core/utils/error_messages.dart';
import 'package:recolle/core/utils/user_facing_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Edge Function を呼び、応答の本文を返す。
///
/// supabase_flutter の通信は既定でタイムアウトしないので [timeout] で区切る。失敗はすべて [UserFacingException] にする。
/// 関数が返したエラー（本文の `error` のコードと HTTP ステータス）は [messageForError] で文言にする。
Future<Object?> invokeEdgeFunction(
  FunctionsClient functions,
  String name, {
  required Map<String, dynamic> body,
  required String Function(Object? code, int status) messageForError,
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final res = await functions.invoke(name, body: body).timeout(timeout);
    return res.data;
  } on FunctionException catch (e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    throw UserFacingException(messageForError(code, e.status));
  } on TimeoutException {
    throw const UserFacingException('サーバーの応答がありませんでした。電波の良い場所でもう一度お試しください。');
  } catch (e) {
    // 接続できない（SocketException / ClientException）、応答が JSON でない など
    debugPrint('Edge Function $name failed: $e');
    throw UserFacingException(toUserFriendlyMessage(e));
  }
}
