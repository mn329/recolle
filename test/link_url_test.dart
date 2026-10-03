import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/core/utils/link_url.dart';

void main() {
  test('http(s) の URL はそのまま、https:// を省いた入力は補う', () {
    expect(parseLinkUrl(' https://eplus.jp/a '), 'https://eplus.jp/a');
    expect(parseLinkUrl('http://example.com'), 'http://example.com');
    expect(parseLinkUrl('l-tike.com/concert/'), 'https://l-tike.com/concert/');
  });

  test('開けない URL や URL でない文字は読まない', () {
    expect(parseLinkUrl(''), isNull);
    expect(parseLinkUrl('チケットのページ'), isNull);
    expect(parseLinkUrl('javascript:alert(1)'), isNull);
    expect(parseLinkUrl('ftp://example.com/file'), isNull);
    expect(parseLinkUrl('localhost'), isNull);
  });
}
