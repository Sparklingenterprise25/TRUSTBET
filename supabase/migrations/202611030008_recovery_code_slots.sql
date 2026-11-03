-- Reserve three stable code positions per account so issuance can be retried safely.
-- Development branch only; review before applying.
alter table public.account_recovery_codes add column if not exists code_slot smallint;
with ranked as (
  select id, row_number() over (partition by user_id order by created_at, id) as n
  from public.account_recovery_codes
)
update public.account_recovery_codes c
set code_slot = ranked.n::smallint
from ranked
where ranked.id = c.id and ranked.n <= 3 and c.code_slot is null;
create unique index if not exists account_recovery_codes_user_slot_uq
  on public.account_recovery_codes(user_id, code_slot)
  where code_slot is not null;
alter table public.account_recovery_codes
  add constraint account_recovery_codes_slot_range
  check (code_slot is null or code_slot between 1 and 3);
