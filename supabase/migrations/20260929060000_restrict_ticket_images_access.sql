-- 誰でも ticket-images の全ユーザーの画像を一覧・取得できてしまうため外す。
-- 自分の画像は "Allow view own folder images" で引き続き取得できる。
-- バケットが公開のあいだは公開 URL（/object/public/...）はポリシーを通らないので、
-- 公開 URL で表示している旧版アプリもこのまま表示できる。
drop policy if exists "Allow public viewing" on storage.objects;

-- アプリは長辺 1920px の JPEG に圧縮して上げる（圧縮に失敗したときは選んだ画像のまま）。
update storage.buckets
set
  file_size_limit = 10 * 1024 * 1024,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
where id = 'ticket-images';
