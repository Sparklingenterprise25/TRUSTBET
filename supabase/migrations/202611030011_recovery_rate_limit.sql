-- Rate-limit public recovery attempts by a one-way identifier hash.
-- Branch-only; test against a disposable staging project before any production use.
create table if not exists public.account_recovery_rate_limits (
  identifier_hash text primary key,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  constraint account_recovery_rate_limits_attempt_count_check check (attempt_count >= 0)
);
alter table public.account_recovery_rate_limits enable row level security;

create or replace function public.trustbet_allow_recovery_attempt(
  p_identifier_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_started timestamptz;
  v_count integer;
begin
  if p_identifier_hash is null or length(p_identifier_hash) <> 64 then
    return false;
  end if;

  insert into public.account_recovery_rate_limits(identifier_hash, window_started_at, attempt_count)
  values (p_identifier_hash, now(), 1)
  on conflict (identifier_hash) do update
    set window_started_at = case
          when public.account_recovery_rate_limits.window_started_at < now() - interval '15 minutes'
          then now()
          else public.account_recovery_rate_limits.window_started_at
        end,
        attempt_count = case
          when public.account_recovery_rate_limits.window_started_at < now() - interval '15 minutes'
          then 1
          else public.account_recovery_rate_limits.attempt_count + 1
        end
  returning window_started_at, attempt_count into v_started, v_count;

  return v_count <= 5;
end;
$$;

revoke all on function public.trustbet_allow_recovery_attempt(text) from public, anon, authenticated;
grant execute on function public.trustbet_allow_recovery_attempt(text) to service_role;
