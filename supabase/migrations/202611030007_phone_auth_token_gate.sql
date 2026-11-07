-- Auth-time access gate for TRUSTBET phone accounts.
-- Development branch only. Do not apply to production without review.
create or replace function public.trustbet_access_token_gate(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile record;
  v_uid uuid;
begin
  v_uid := (event->>'user_id')::uuid;
  select phone, account_approval_status, phone_login_locked_until
    into v_profile
    from public.profiles
   where id = v_uid;

  if found and v_profile.phone is not null then
    if coalesce(v_profile.account_approval_status, 'approved') <> 'approved' then
      return jsonb_build_object('error', jsonb_build_object(
        'http_code', 403, 'message', 'Your TRUSTBET account is awaiting approval or is not active.'
      ));
    end if;
    if v_profile.phone_login_locked_until is not null
       and v_profile.phone_login_locked_until > now() then
      return jsonb_build_object('error', jsonb_build_object(
        'http_code', 403, 'message', 'Phone login is temporarily locked. Please try again later.'
      ));
    end if;
  end if;
  return jsonb_build_object('claims', event->'claims');
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.trustbet_access_token_gate(jsonb) to supabase_auth_admin;
revoke execute on function public.trustbet_access_token_gate(jsonb) from public, anon, authenticated;
