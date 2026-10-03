-- チケット画像を公開 URL で取れないようにする。
-- アプリは認証つきの窓口（/object/authenticated/...）から本人のトークンで取得する。
-- 公開 URL で表示している旧版アプリでは画像が出なくなるため、新しい版が行き渡ってから適用する。
update storage.buckets
set public = false
where id = 'ticket-images';

comment on column public.records.ticket_image_urls is 'チケット画像の場所（先頭が一覧に出す表紙）。/object/public/... 形式だがバケットは非公開で、アプリはパスを取り出して認証つきで取得する';
