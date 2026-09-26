-- ライブの開場・終演時刻（開演は start_time）。日付やタイムゾーンは date 列と端末側で扱う。
alter table public.records
  add column if not exists open_time time,
  add column if not exists end_time time;
