-- TRUSTBET wallet request limits: server-side enforcement.
-- Development branch only. Do not apply to production without explicit approval.
create or replace function public.trustbet_enforce_wallet_request_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_min numeric;
  v_max numeric := 5000000;
  v_day_start timestamptz;
  v_total numeric;
begin
  if TG_TABLE_NAME = 'deposit_requests' then
    v_min := 500;
  elsif TG_TABLE_NAME = 'withdrawal_requests' then
    v_min := 20000;
  else
    raise exception 'Unsupported wallet request table';
  end if;

  if NEW.amount is null or NEW.amount < v_min or NEW.amount > v_max
     or NEW.amount <> trunc(NEW.amount) then
    raise exception 'Request amount must be between ₦% and ₦%.', v_min, v_max;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(NEW.user_id::text || ':' || TG_TABLE_NAME, 0));
  v_day_start := date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';

  execute format(
    'select coalesce(sum(amount),0) from public.%I where user_id = $1 and created_at >= $2 and created_at < $3',
    TG_TABLE_NAME
  ) into v_total using NEW.user_id, v_day_start, v_day_start + interval '1 day';

  if v_total + NEW.amount > v_max then
    raise exception 'Daily wallet request limit exceeded. Maximum: ₦%.', v_max;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trustbet_deposit_request_limits on public.deposit_requests;
create trigger trustbet_deposit_request_limits
before insert on public.deposit_requests
for each row execute function public.trustbet_enforce_wallet_request_limits();

drop trigger if exists trustbet_withdrawal_request_limits on public.withdrawal_requests;
create trigger trustbet_withdrawal_request_limits
before insert on public.withdrawal_requests
for each row execute function public.trustbet_enforce_wallet_request_limits();

revoke all on function public.trustbet_enforce_wallet_request_limits() from public, anon, authenticated;
