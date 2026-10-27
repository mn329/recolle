-- 強制アップデートの最低バージョン。アプリは起動時と復帰時に読み、これより古ければ App Store へ誘導する。
-- 値はダッシュボード（service role）から変える。

create table public.app_config (
  id boolean primary key default true check (id),
  min_ios_version text not null check (min_ios_version ~ '^\d+(\.\d+){0,2}$')
);

comment on table public.app_config is 'アプリ全体の設定（1 行だけ）。min_ios_version より古い iOS アプリは使えなくする';

alter table public.app_config enable row level security;

-- 起動直後は匿名サインイン前のこともあるので anon にも読ませる。書き込みのポリシーは作らない
create policy "app_config は誰でも読める"
  on public.app_config for select
  to anon, authenticated
  using (true);

insert into public.app_config (min_ios_version) values ('1.0.0');
