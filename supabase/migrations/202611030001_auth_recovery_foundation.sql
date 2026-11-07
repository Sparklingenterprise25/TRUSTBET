-- TRUSTBET authentication and recovery groundwork.
-- DEVELOPMENT BRANCH ONLY. Do not run against production until reviewed and approved.
-- Existing accounts remain approved; only new phone registrations will be marked pending
-- by the later, reviewed signup-flow change.

alter table public.profiles
  add column if not exists phone text,
  add column if not exists account_approval_status text not null default 'approved',
  add column if not exists account_approval_requested_at timestamptz,
  add column if not exists account_approved_at timestamptz,
  add column if not exists account_rejected_at timestamptz,
  add column if not exists phone_login_failed_attempts integer not null default 0,
  add column if not exists phone_login_locked_until timestamptz,
  add column if not exists phone_login_lock_stage integer not null default 0;

alter table public.profiles
  drop constraint if exists profiles_account_approval_status_check;
alter table public.profiles
  add constraint profiles_account_approval_status_check
  check (account_approval_status in ('approved','pending','rejected'));

alter table public.profiles
  drop constraint if exists profiles_phone_login_failed_attempts_check;
alter table public.profiles
  add constraint profiles_phone_login_failed_attempts_check
  check (phone_login_failed_attempts >= 0);

alter table public.profiles
  drop constraint if exists profiles_phone_login_lock_stage_check;
alter table public.profiles
  add constraint profiles_phone_login_lock_stage_check
  check (phone_login_lock_stage between 0 and 3);

create unique index if not exists profiles_phone_unique
  on public.profiles (phone)
  where phone is not null;

-- Only server-side Edge Functions should read or mutate these tables.
create table if not exists public.account_recovery_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text not null,
  code_ciphertext text not null,
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_for text,
  unique (user_id, code_hash)
);

create index if not exists account_recovery_codes_user_unused_idx
  on public.account_recovery_codes (user_id, created_at)
  where used_at is null;

create table if not exists public.account_recovery_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  account_identifier_hash text not null,
  requested_at timestamptz not null default now(),
  status text not null default 'awaiting_code',
  pending_password_ciphertext text,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  review_note text,
  constraint account_recovery_requests_status_check
    check (status in ('awaiting_code','code_ready','completed','approved','rejected'))
);

create index if not exists account_recovery_requests_recent_idx
  on public.account_recovery_requests (account_identifier_hash, requested_at desc);

-- RLS is enabled now; explicit service-role-only policies are added in the
-- security migration after policy inventory and endpoint authorization review.
alter table public.account_recovery_codes enable row level security;
alter table public.account_recovery_requests enable row level security;
