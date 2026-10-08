alter table public.records
  add column if not exists ticket_image_urls text[] not null default '{}';

alter table public.records
  add constraint records_ticket_image_urls_count check (cardinality(ticket_image_urls) <= 5);

update public.records
set ticket_image_urls = array[ticket_image_url]
where ticket_image_url is not null
  and ticket_image_url <> ''
  and cardinality(ticket_image_urls) = 0;

comment on column public.records.ticket_image_urls is 'チケット画像の公開 URL（先頭が一覧に出す表紙）';
comment on column public.records.ticket_image_url is '旧版アプリ向け。ticket_image_urls の先頭を入れる';
