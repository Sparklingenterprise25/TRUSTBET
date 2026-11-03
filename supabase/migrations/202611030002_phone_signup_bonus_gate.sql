-- TRUSTBET phone signup behavior.
-- Development branch only. Review before applying anywhere.
-- Existing email signup keeps its current one-time welcome bonus behavior.
-- Phone signups are created pending with zero balances; approval will credit once
-- through a separately authenticated admin Edge Function.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_full_name text;
  v_phone text;
  v_is_phone boolean;
  v_status text;
begin
  v_full_name := upper(trim(coalesce(
    nullif(new.raw_user_meta_data->>'full_name', ''),
    nullif(
      concat_ws(' ',
        nullif(trim(new.raw_user_meta_data->>'first_name'), ''),
        nullif(trim(new.raw_user_meta_data->>'last_name'), '')
      ), ''
    ),
    nullif(split_part(coalesce(new.email, ''), '@', 1), '')
  )));

  v_phone := nullif(trim(coalesce(
    new.phone,
    new.raw_user_meta_data->>'phone'
  )), '');
  v_is_phone := v_phone is not null;
  v_status := case when v_is_phone then 'pending' else 'approved' end;

  insert into public.profiles (
    id, email, phone, full_name, account_approval_status,
    account_approval_requested_at, account_approved_at,
    virtual_balance, cash_balance, bonus_balance,
    legacy_unclassified_balance, welcome_bonus_credited,
    welcome_bonus_used
  )
  values (
    new.id, new.email, v_phone, v_full_name, v_status,
    case when v_is_phone then now() else null end,
    case when v_is_phone then null else now() end,
    case when v_is_phone then 0 else 9000 end,
    0,
    case when v_is_phone then 0 else 9000 end,
    0,
    not v_is_phone,
    false
  )
  on conflict (id) do nothing;

  if found and not v_is_phone then
    insert into public.wallet_transactions
      (user_id, transaction_type, amount, balance_before, balance_after, description)
    values
      (new.id, 'bonus', 9000, 0, 9000, 'One-time welcome bonus');
  end if;

  return new;
end;
$function$;
