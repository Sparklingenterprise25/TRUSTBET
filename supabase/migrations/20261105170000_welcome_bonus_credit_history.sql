-- Display welcome bonuses as credits in wallet history.
-- Existing welcome bonus rows are corrected, and both email and phone
-- onboarding paths create future welcome bonus entries as credits.
-- Front-end code already renders transaction types containing "credit" in green.

update public.wallet_transactions
set transaction_type = 'bonus credit'
where transaction_type = 'bonus'
  and amount = 9000
  and lower(description) in (
    'one-time welcome bonus',
    'one-time welcome bonus after account approval'
  );

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_first_name text;
  v_last_name text;
  v_full_name text;
  v_phone text;
  v_is_phone boolean;
  v_pending boolean;
begin
  v_phone := nullif(trim(coalesce(new.phone, new.raw_user_meta_data->>'phone')), '');
  v_is_phone := v_phone is not null;

  v_first_name := upper(trim(coalesce(new.raw_user_meta_data->>'first_name', '')));
  v_last_name := upper(trim(coalesce(new.raw_user_meta_data->>'last_name', '')));

  if v_is_phone then
    if v_first_name !~ '^[A-Z]+$' or v_last_name !~ '^[A-Z]+$' then
      raise exception 'Phone registrations require alphabetic FIRST NAME and LAST NAME.';
    end if;
  end if;

  v_full_name := upper(trim(coalesce(
    nullif(concat_ws(' ', nullif(v_first_name, ''), nullif(v_last_name, '')), ''),
    nullif(new.raw_user_meta_data->>'full_name', ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), '')
  )));
  v_pending := v_is_phone;

  insert into public.profiles (
    id,email,phone,first_name,last_name,full_name,account_approval_status,
    account_approval_requested_at,account_approved_at,
    virtual_balance,cash_balance,bonus_balance,
    legacy_unclassified_balance,welcome_bonus_credited,welcome_bonus_used
  ) values (
    new.id,new.email,v_phone,
    case when v_is_phone then v_first_name else null end,
    case when v_is_phone then v_last_name else null end,
    v_full_name,
    case when v_pending then 'pending' else 'approved' end,
    case when v_pending then now() else null end,
    case when v_pending then null else now() end,
    case when v_pending then 0 else 9000 end,
    0,
    case when v_pending then 0 else 9000 end,
    0,
    not v_pending,
    false
  ) on conflict (id) do nothing;

  if found and not v_pending then
    insert into public.wallet_transactions
      (user_id,transaction_type,amount,balance_before,balance_after,description)
    values (new.id,'bonus credit',9000,0,9000,'One-time welcome bonus');
  end if;
  return new;
end;
$function$;

create or replace function public.trustbet_admin_approve_phone_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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

  if not found then raise exception 'Account not found'; end if;
  if v_profile.phone is null then raise exception 'This is not a phone-number account'; end if;
  if v_profile.account_approval_status = 'rejected' then raise exception 'Rejected accounts cannot be approved'; end if;

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

    -- tracking_code is varchar(24): prefix (8) + UUID fragment (16) = 24.
    v_tracking := 'WELCOME-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 16));

    insert into public.wallet_transactions(
      user_id, transaction_type, amount, balance_before, balance_after, description, tracking_code
    )
    values (
      p_user_id, 'bonus credit', 9000, v_before, v_after,
      'One-time welcome bonus after account approval', v_tracking
    );
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
