/// そのままユーザーに見せてよい日本語メッセージを持つ例外。
///
/// [toUserFriendlyMessage] は、この型なら [userMessage] をそのまま返す。
class UserFacingException implements Exception {
  const UserFacingException(this.userMessage);

  final String userMessage;

  @override
  String toString() => 'UserFacingException: $userMessage';
}
