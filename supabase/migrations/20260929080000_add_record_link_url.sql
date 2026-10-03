alter table public.records
  add column if not exists link_url text;

-- アプリは http(s) の URL だけを開くので、それ以外は入れさせない
alter table public.records
  add constraint records_link_url_format check (
    link_url is null
    or (char_length(link_url) <= 2000 and link_url ~* '^https?://')
  );

comment on column public.records.link_url is '公演ページ・チケットのページなど、あとで開きたいリンク（http(s) の URL）';
