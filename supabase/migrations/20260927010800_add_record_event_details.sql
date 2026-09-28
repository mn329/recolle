alter table public.records
  add column if not exists venue text,
  add column if not exists seat text,
  add column if not exists ticket_price integer,
  add column if not exists start_time time;

alter table public.records
  add constraint records_venue_length check (venue is null or char_length(venue) <= 200),
  add constraint records_seat_length check (seat is null or char_length(seat) <= 100),
  add constraint records_ticket_price_range check (ticket_price is null or ticket_price between 0 and 10000000);

comment on column public.records.ticket_price is 'チケット代（円）';
comment on column public.records.start_time is '開演時刻（公演地の現地時刻）';
