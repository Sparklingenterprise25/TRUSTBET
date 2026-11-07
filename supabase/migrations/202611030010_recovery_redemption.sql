-- TRUSTBET recovery-code redemption support.
-- Branch-only migration. Review and test in an isolated Supabase staging project.
-- A short claim lease prevents two simultaneous requests redeeming the same code.

alter table public.account_recovery_codes
  add column if not exists claimed_at timestamptz,
  add column if not exists claim_token uuid;

create index if not exists account_recovery_codes_claimed_idx
  on public.account_recovery_codes (claimed_at)
  where used_at is null;

create or replace function public.trustbet_claim_recovery_code(
  p_user_id uuid,
  p_code_hash text,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_user_id is null or p_code_hash is null or p_claim_token is null then
    return false;
  end if;

  select id into v_id
  from public.account_recovery_codes
  where user_id = p_user_id
    and code_hash = p_code_hash
    and used_at is null
    and (claimed_at is null or claimed_at < now() - interval '10 minutes')
  for update;

  if not found then
    return false;
  end if;

  update public.account_recovery_codes
  set claimed_at = now(), claim_token = p_claim_token
  where id = v_id;

  return true;
end;
$$;

create or replace function public.trustbet_finish_recovery_code(
  p_user_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.account_recovery_codes
  set used_at = now(), used_for = 'password_reset',
      claimed_at = null, claim_token = null
  where user_id = p_user_id
    and claim_token = p_claim_token
    and used_at is null;
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$$;

create or replace function public.trustbet_release_recovery_code(
  p_user_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.account_recovery_codes
  set claimed_at = null, claim_token = null
  where user_id = p_user_id
    and claim_token = p_claim_token
    and used_at is null;
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$$;

revoke all on function public.trustbet_claim_recovery_code(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.trustbet_finish_recovery_code(uuid,uuid) from public, anon, authenticated;
revoke all on function public.trustbet_release_recovery_code(uuid,uuid) from public, anon, authenticated;
grant execute on function public.trustbet_claim_recovery_code(uuid,text,uuid) to service_role;
grant execute on function public.trustbet_finish_recovery_code(uuid,uuid) to service_role;
grant execute on function public.trustbet_release_recovery_code(uuid,uuid) to service_role;
