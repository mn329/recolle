-- 対バン・フェスの記録。ワンマンは従来どおり artist_or_author と setlist だけを使い、acts は空。
-- 対バン・フェスでは acts に出演者ごとのセトリを持ち、artist_or_author には一覧や検索で使う見出し
-- （お目当ての出演者を「／」でつないだもの）を入れる。
alter table public.records
  add column if not exists event_format text not null default 'oneman',
  add column if not exists end_date date,
  add column if not exists acts jsonb not null default '[]'::jsonb;

alter table public.records
  add constraint records_event_format_valid
    check (event_format in ('oneman', 'taiban', 'festival')),
  add constraint records_end_date_after_date
    check (end_date is null or end_date >= date),
  -- [{"artist": "...", "songs": ["..."], "is_main": true}, ...]
  add constraint records_acts_shape
    check (
      jsonb_typeof(acts) = 'array'
      and jsonb_array_length(acts) <= 100
      and pg_column_size(acts) <= 200000
    );

comment on column public.records.event_format is '公演の形式（oneman: ワンマン、taiban: 対バン、festival: フェス）';
comment on column public.records.end_date is '複数日にわたる公演（フェスの 2 日通しなど）の最終日。1 日だけなら null';
comment on column public.records.acts is '対バン・フェスの出演者（artist, songs, is_main）';
