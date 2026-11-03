-- TRUSTBET: atomic phone-account approval and welcome bonus credit.
-- Development branch only. Called only by the admin Edge Function using service_role.
-- This does not touch existing approved users or their balances.

create or replace function public.trustbet_admin_approve_phone_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile public.profiles%rowtype;
  v_before numeric;
  v_after numeric;
  v_tracking text;
begin
  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Account not found';
  end if;

  if v_profile.phone is null then
    raise exception 'This is not a phone-number account';
  end if;

  if v_profile.account_approval_status = 'rejected' then
    raise exception 'Rejected accounts cannot be approved';
  end if;

  if v_profile.account_approval_status = 'approved' then
    return jsonb_build_object(
      'success', true,
      'already_approved', true,
      'bonus_credited', v_profile.welcome_bonus_credited
    );
  end if;

  v_before := coalesce(v_profile.virtual_balance, 0);
  v_after := v_before;

  if not coalesce(v_profile.welcome_bonus_credited, false) then
    v_after := v_before + 9000;
    update public.profiles
      set account_approval_status = 'approved',
          account_approved_at = now(),
          account_rejected_at = null,
          virtual_balance = v_after,
          bonus_balance = coalesce(bonus_balance, 0) + 9000,
          welcome_bonus_credited = true
    where id = p_user_id;

    v_tracking := 'WELCOME-' || upper(replace(gen_random_uuid()::text, '-', ''));
    insert into public.wallet_transactions
      (user_id, transaction_type, amount, balance_before, balance_after, description, tracking_code)
    values
      (p_user_id, 'bonus', 9000, v_before, v_after,
       'One-time welcome bonus after account approval', v_tracking);
  else
    update public.profiles
      set account_approval_status = 'approved',
          account_approved_at = now(),
          account_rejected_at = null
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'already_approved', false,
    'bonus_credited', not coalesce(v_profile.welcome_bonus_credited, false),
    'bonus_amount', case when coalesce(v_profile.welcome_bonus_credited, false) then 0 else 9000 end
  );
end;
$function$;

revoke all on function public.trustbet_admin_approve_phone_account(uuid) from public, anon, authenticated;
grant execute on function public.trustbet_admin_approve_phone_account(uuid) to service_role;

create or replace function public.trustbet_admin_reject_phone_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_phone text;
begin
  select phone into v_phone
  from public.profiles
  where id = p_user_id
  for update;

  if not found then raise exception 'Account not found'; end if;
  if v_phone is null then raise exception 'This is not a phone-number account'; end if;

  update public.profiles
    set account_approval_status = 'rejected',
        account_rejected_at = now(),
        account_approved_at = null
  where id = p_user_id
    and account_approval_status = 'pending';

  if not found then raise exception 'Only pending accounts can be rejected'; end if;

  return jsonb_build_object('success', true);
end;
$function$;

revoke all on function public.trustbet_admin_reject_phone_account(uuid) from public, anon, authenticated;
grant execute on function public.trustbet_admin_reject_phone_account(uuid) to service_role;
