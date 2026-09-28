import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/account/services/social_credential.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  test('Google のクライアント ID が空なら、Google のログインを出さない', () {
    dotenv.loadFromString(
      envString: 'GOOGLE_WEB_CLIENT_ID=\nGOOGLE_IOS_CLIENT_ID=',
    );

    expect(isGoogleSignInConfigured, isFalse);
    expect(availableSocialProviders, isNot(contains(SocialProvider.google)));
  });

  test('Google のクライアント ID があれば、Google のログインを出す', () {
    dotenv.loadFromString(
      envString:
          'GOOGLE_WEB_CLIENT_ID=1-web.apps.googleusercontent.com\n'
          'GOOGLE_IOS_CLIENT_ID=1-ios.apps.googleusercontent.com',
    );

    expect(isGoogleSignInConfigured, isTrue);
    expect(availableSocialProviders, contains(SocialProvider.google));
  });

  test('Apple のエラー 1000 は、端末の Apple アカウントを確かめるよう案内する', () {
    expect(
      appleSignInErrorMessage(AuthorizationErrorCode.unknown),
      contains('Apple アカウントにサインインしているか'),
    );
    for (final code in AuthorizationErrorCode.values) {
      expect(appleSignInErrorMessage(code), isNotEmpty);
    }
  });
}
