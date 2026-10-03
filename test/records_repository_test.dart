import 'package:flutter_test/flutter_test.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ticketImageStoragePath', () {
    test('公開 URL からバケット内のパスを取り出す', () {
      expect(
        RecordsRepository.ticketImageStoragePath(
          'https://example.supabase.co/storage/v1/object/public/ticket-images/user-1/123_ticket.jpg',
        ),
        'user-1/123_ticket.jpg',
      );
    });

    test('ほかのバケットや URL でないものは null', () {
      expect(
        RecordsRepository.ticketImageStoragePath(
          'https://example.supabase.co/storage/v1/object/public/avatars/user-1/a.jpg',
        ),
        isNull,
      );
      expect(
        RecordsRepository.ticketImageStoragePath(
          'https://example.supabase.co/storage/v1/object/public/ticket-images/',
        ),
        isNull,
      );
      expect(RecordsRepository.ticketImageStoragePath(''), isNull);
    });
  });

  group('ticketImageRequest', () {
    final storage = SupabaseStorageClient(
      'https://example.supabase.co/storage/v1',
      {'apikey': 'anon-key', 'Authorization': 'Bearer user-token'},
    );

    test('チケット画像は認証つきの窓口から、ログイン中のトークンを付けて取る', () {
      final request = RecordsRepository.ticketImageRequest(
        'https://example.supabase.co/storage/v1/object/public/ticket-images/user-1/123_ticket.jpg',
        storage: storage,
      );

      expect(
        request.url,
        'https://example.supabase.co/storage/v1/object/authenticated/ticket-images/user-1/123_ticket.jpg',
      );
      expect(request.headers, containsPair('apikey', 'anon-key'));
      expect(
        request.headers,
        containsPair('Authorization', 'Bearer user-token'),
      );
    });

    test('ファイル名に URL で使えない文字があっても取れる URL にする', () {
      final request = RecordsRepository.ticketImageRequest(
        'https://example.supabase.co/storage/v1/object/public/ticket-images/user-1/1_%E3%83%81%E3%82%B1%E3%83%83%E3%83%88%20a.jpg',
        storage: storage,
      );

      expect(
        request.url,
        'https://example.supabase.co/storage/v1/object/authenticated/ticket-images/user-1/1_%E3%83%81%E3%82%B1%E3%83%83%E3%83%88%20a.jpg',
      );
    });

    test('チケット画像でない URL は、Supabase に触れずそのまま返す', () {
      final request = RecordsRepository.ticketImageRequest(
        'https://is1-ssl.mzstatic.com/image/thumb/a.jpg',
      );

      expect(request.url, 'https://is1-ssl.mzstatic.com/image/thumb/a.jpg');
      expect(request.headers, isNull);
    });
  });
}
