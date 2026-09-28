-- Supabase Advisors 対応:
-- auth.uid() を (select auth.uid()) にして行ごとの再評価を避ける（0003_auth_rls_initplan）
alter policy "Users can view their own records" on public.records
  using ((select auth.uid()) = user_id);
alter policy "Users can insert their own records" on public.records
  with check ((select auth.uid()) = user_id);
alter policy "Users can update their own records" on public.records
  using ((select auth.uid()) = user_id);
alter policy "Users can delete their own records" on public.records
  using ((select auth.uid()) = user_id);

-- search_path を固定する（0011_function_search_path_mutable）。now() は pg_catalog なので影響なし
alter function public.set_updated_at() set search_path = '';
