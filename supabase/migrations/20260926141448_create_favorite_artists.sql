-- お気に入りアーティスト。記録の artist_or_author とは名前で緩く紐づける（外部キーにはしない）。
create table public.favorite_artists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  itunes_artist_id bigint,
  artwork_url text check (artwork_url is null or artwork_url ~ '^https://'),
  created_at timestamptz not null default now(),
  constraint favorite_artists_user_name_key unique (user_id, name)
);

comment on table public.favorite_artists is 'ユーザーのお気に入りアーティスト';
comment on column public.favorite_artists.itunes_artist_id is 'iTunes Search API の artistId（任意）';
comment on column public.favorite_artists.artwork_url is 'iTunes から取得したアートワーク URL（任意）';

alter table public.favorite_artists enable row level security;

create policy "Users can view their own favorite artists"
  on public.favorite_artists for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert their own favorite artists"
  on public.favorite_artists for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own favorite artists"
  on public.favorite_artists for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own favorite artists"
  on public.favorite_artists for delete
  to authenticated
  using ((select auth.uid()) = user_id);
