-- TRUSTBET wallet request limits: update the existing server-side trigger functions.
-- Development branch only. Do not apply to production without explicit approval.
create or replace function public.enforce_daily_deposit_request_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_start timestamptz;
  v_total numeric;
begin
  if auth.uid() is null or new.user_id <> auth.uid() then
    raise exception 'You can only submit deposit requests for your own account.';
  end if;
  if new.amount is null or new.amount <> trunc(new.amount)
     or new.amount < 500 or new.amount > 5000000 then
    raise exception 'Deposit amount must be between ₦500 and ₦5,000,000.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text || ':deposit', 0));
  v_start := ((now() at time zone 'Africa/Lagos')::date::timestamp at time zone 'Africa/Lagos');
  select coalesce(sum(amount),0) into v_total
  from public.deposit_requests
  where user_id = new.user_id
    and created_at >= v_start
    and created_at < v_start + interval '1 day';
  if v_total + new.amount > 5000000 then
    raise exception 'Daily deposit limit of ₦5,000,000 exceeded.';
  end if;
  return new;
end;
$function$;

create or replace function public.enforce_daily_withdrawal_request_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_start timestamptz;
  v_total numeric;
begin
  if auth.uid() is null or new.user_id <> auth.uid() then
    raise exception 'You can only submit withdrawal requests for your own account.';
  end if;
  if new.amount is null or new.amount <> trunc(new.amount)
     or new.amount < 20000 or new.amount > 5000000 then
    raise exception 'Withdrawal amount must be between ₦20,000 and ₦5,000,000.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text || ':withdrawal', 0));
  v_start := ((now() at time zone 'Africa/Lagos')::date::timestamp at time zone 'Africa/Lagos');
  select coalesce(sum(amount),0) into v_total
  from public.withdrawal_requests
  where user_id = new.user_id
    and created_at >= v_start
    and created_at < v_start + interval '1 day';
  if v_total + new.amount > 5000000 then
    raise exception 'Daily withdrawal limit of ₦5,000,000 exceeded.';
  end if;
  return new;
end;
$function$;
