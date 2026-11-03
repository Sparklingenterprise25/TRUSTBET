-- TRUSTBET recovery-code administration and server-side lockout groundwork.
-- Development branch only. No production database changes.

alter table public.account_recovery_requests
  add column if not exists account_phone text,
  add column if not exists request_ip_hash text;

create index if not exists account_recovery_requests_phone_recent_idx
  on public.account_recovery_requests (account_phone, requested_at desc)
  where account_phone is not null;

-- Serialize and record password failures on the profile row.
create or replace function public.trustbet_record_phone_login_failure(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile public.profiles%rowtype;
  v_attempts integer;
  v_stage integer;
  v_lock interval;
begin
  select * into v_profile from public.profiles where id=p_user_id for update;
  if not found then return jsonb_build_object('locked',false); end if;
  if v_profile.phone_login_locked_until is not null and v_profile.phone_login_locked_until > now() then
    return jsonb_build_object('locked',true,'until',v_profile.phone_login_locked_until);
  end if;

  v_attempts := coalesce(v_profile.phone_login_failed_attempts,0)+1;
  v_stage := coalesce(v_profile.phone_login_lock_stage,0);
  v_lock := null;

  if v_attempts >= 5 then
    v_stage := least(v_stage+1,3);
    v_lock := case v_stage
      when 1 then interval '15 minutes'
      when 2 then interval '1 hour'
      else interval '24 hours'
    end;
    v_attempts := 0;
  end if;

  update public.profiles
    set phone_login_failed_attempts=v_attempts,
        phone_login_lock_stage=v_stage,
        phone_login_locked_until=case when v_lock is null then null else now()+v_lock end
  where id=p_user_id;

  return jsonb_build_object(
    'locked',v_lock is not null,
    'lock_stage',v_stage,
    'locked_until',case when v_lock is null then null else now()+v_lock end
  );
end;
$function$;

create or replace function public.trustbet_reset_phone_login_failures(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $function$
  update public.profiles
  set phone_login_failed_attempts=0,
      phone_login_lock_stage=0,
      phone_login_locked_until=null
  where id=p_user_id;
$function$;

revoke all on function public.trustbet_record_phone_login_failure(uuid) from public,anon,authenticated;
revoke all on function public.trustbet_reset_phone_login_failures(uuid) from public,anon,authenticated;
grant execute on function public.trustbet_record_phone_login_failure(uuid) to service_role;
grant execute on function public.trustbet_reset_phone_login_failures(uuid) to service_role;
