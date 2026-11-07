alter table public.profiles
  add column if not exists dashboard_display_name text;

comment on column public.profiles.dashboard_display_name is
  'Admin-managed homepage welcome name override; null uses the email-derived default.';
