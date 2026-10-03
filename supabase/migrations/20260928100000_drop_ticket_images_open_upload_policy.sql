-- バケット内のどこにでも置けてしまうため外す。自分のフォルダへのアップロードは
-- "Allow upload to own folder" が許可している。
drop policy if exists "Allow authenticated uploads" on storage.objects;
