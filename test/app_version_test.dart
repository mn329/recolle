import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/app_update/app_version.dart';

void main() {
  group('parseAppVersion', () {
    test('3 桁までの数字を読み、足りない桁は 0 にする', () {
      expect(parseAppVersion('1.2.3'), [1, 2, 3]);
      expect(parseAppVersion('1.2'), [1, 2, 0]);
      expect(parseAppVersion('2'), [2, 0, 0]);
      expect(parseAppVersion(' 1.10.0 '), [1, 10, 0]);
    });

    test('形式が不正なら null', () {
      expect(parseAppVersion(''), isNull);
      expect(parseAppVersion('1.2.x'), isNull);
      expect(parseAppVersion('1.2.3.4'), isNull);
      expect(parseAppVersion('1..2'), isNull);
      expect(parseAppVersion('1.1.4+29'), isNull);
    });
  });

  group('isOlderThan', () {
    test('最低バージョンより古いときだけ true', () {
      expect(isOlderThan('1.1.3', '1.1.4'), isTrue);
      expect(isOlderThan('1.9.9', '2.0.0'), isTrue);
      expect(isOlderThan('1.1.4', '1.1.4'), isFalse);
      expect(isOlderThan('1.1.5', '1.1.4'), isFalse);
      expect(isOlderThan('1.10.0', '1.9.0'), isFalse);
    });

    test('桁数が違っても比べられる', () {
      expect(isOlderThan('1.1', '1.1.0'), isFalse);
      expect(isOlderThan('1.1', '1.1.1'), isTrue);
    });

    test('どちらかが読めないときは止めない', () {
      expect(isOlderThan('1.0.0', 'abc'), isFalse);
      expect(isOlderThan('', '9.9.9'), isFalse);
    });
  });
}
