-- ユーザーが選んだお気に入りアーティストの画像。
-- 自動取得の artwork_url とは別の列にして、自動の置き換えに上書きされないようにする。
-- null のときは artwork_url（なければ頭文字）を表示する。
alter table public.favorite_artists
  add column custom_image_url text
  check (custom_image_url is null or custom_image_url ~ '^https://');

comment on column public.favorite_artists.custom_image_url is
  'ユーザーが選んだ画像の URL（ticket-images バケットの <user_id>/artist_*）。null なら artwork_url を使う';
