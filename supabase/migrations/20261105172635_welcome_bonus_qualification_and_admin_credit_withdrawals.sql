DO $$
DECLARE
  v_bad record;
BEGIN
  FOR v_bad IN
    WITH grants AS (
      SELECT user_id,
             COALESCE(sum(amount) FILTER (WHERE transaction_type='bonus'),0) AS admin_bonus,
             COALESCE(sum(amount) FILTER (WHERE transaction_type='adjustment'),0) AS admin_compensation
      FROM public.wallet_transactions
      WHERE transaction_type IN ('bonus','adjustment')
      GROUP BY user_id
    )
    SELECT p.id, p.bonus_balance, p.virtual_balance, p.cash_balance,
           COALESCE(g.admin_bonus,0) AS admin_bonus,
           COALESCE(g.admin_compensation,0) AS admin_compensation,
           (COALESCE(p.virtual_balance,0)-COALESCE(p.cash_balance,0)-COALESCE(p.bonus_balance,0)) AS unclassified_gap
    FROM public.profiles p
    JOIN grants g ON g.user_id=p.id
    WHERE COALESCE(p.bonus_balance,0) + 0.001 < COALESCE(g.admin_bonus,0)
       OR abs((COALESCE(p.virtual_balance,0)-COALESCE(p.cash_balance,0)-COALESCE(p.bonus_balance,0))-COALESCE(g.admin_compensation,0)) > 0.01
  LOOP
    RAISE EXCEPTION 'Cannot safely reclassify admin credits for profile %: bonus balance or compensation ledger does not reconcile', v_bad.id;
  END LOOP;
END $$;

WITH grants AS (
  SELECT user_id,
         COALESCE(sum(amount) FILTER (WHERE transaction_type='bonus'),0) AS admin_bonus,
         COALESCE(sum(amount) FILTER (WHERE transaction_type='adjustment'),0) AS admin_compensation
  FROM public.wallet_transactions
  WHERE transaction_type IN ('bonus','adjustment')
  GROUP BY user_id
)
UPDATE public.profiles p
SET cash_balance = COALESCE(p.cash_balance,0) + g.admin_bonus + g.admin_compensation,
    bonus_balance = COALESCE(p.bonus_balance,0) - g.admin_bonus
FROM grants g
WHERE p.id=g.user_id
  AND (g.admin_bonus <> 0 OR g.admin_compensation <> 0);

CREATE OR REPLACE FUNCTION public.admin_issue_wallet_credit(
  p_user_id uuid,
  p_amount numeric,
  p_credit_type text,
  p_message text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_before numeric;
  v_after numeric;
  v_tracking text;
  v_transaction_type text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Select a user'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> trunc(p_amount) THEN
    RAISE EXCEPTION 'Amount must be a positive whole number';
  END IF;
  IF p_credit_type NOT IN ('bonus','compensation') THEN
    RAISE EXCEPTION 'Invalid credit type';
  END IF;
  IF length(trim(coalesce(p_message,''))) = 0 THEN
    RAISE EXCEPTION 'Customer message is required';
  END IF;

  v_transaction_type := CASE WHEN p_credit_type='compensation' THEN 'adjustment' ELSE 'bonus' END;
  SELECT * INTO v_profile FROM public.profiles WHERE id=p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'User account not found'; END IF;

  v_before := COALESCE(v_profile.virtual_balance,0);
  v_after := v_before+p_amount;

  UPDATE public.profiles
  SET virtual_balance=v_after,
      cash_balance=COALESCE(cash_balance,0)+p_amount
  WHERE id=p_user_id;

  v_tracking := 'ADMIN-'||upper(replace(gen_random_uuid()::text,'-',''));
  INSERT INTO public.wallet_transactions
    (user_id,transaction_type,amount,balance_before,balance_after,description,tracking_code)
  VALUES
    (p_user_id,v_transaction_type,p_amount,v_before,v_after,trim(p_message),v_tracking);

  RETURN jsonb_build_object('success',true,'balance',v_after,'amount',p_amount,
    'type',p_credit_type,'transaction_type',v_transaction_type,'tracking_code',v_tracking);
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_withdrawal(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
  v_request public.withdrawal_requests%ROWTYPE;
  v_before numeric;
  v_after numeric;
  v_cash_before numeric;
  v_bonus_before numeric;
  v_qualified boolean := false;
  v_eligible_bonus numeric := 0;
  v_eligible_total numeric := 0;
  v_cash_deduction numeric := 0;
  v_bonus_deduction numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT * INTO v_request
  FROM public.withdrawal_requests
  WHERE id=p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal request not found'; END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'This withdrawal request has already been processed';
  END IF;

  SELECT virtual_balance,cash_balance,bonus_balance
  INTO v_before,v_cash_before,v_bonus_before
  FROM public.profiles
  WHERE id=v_request.user_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'User profile not found'; END IF;

  SELECT
    COALESCE((SELECT sum(d.amount) FROM public.deposit_requests d
              WHERE d.user_id=v_request.user_id AND lower(d.status)='approved'),0) >= 30000
    AND EXISTS (SELECT 1 FROM public.demo_bets b WHERE b.user_id=v_request.user_id)
  INTO v_qualified;

  IF v_qualified THEN
    v_eligible_bonus := COALESCE(v_bonus_before,0);
  END IF;
  v_eligible_total := COALESCE(v_cash_before,0)+v_eligible_bonus;

  IF v_eligible_total < 20000 THEN
    RAISE EXCEPTION 'Withdrawal requires at least ₦20,000 in eligible wallet funds';
  END IF;
  IF v_eligible_total < v_request.amount THEN
    RAISE EXCEPTION 'Insufficient eligible wallet funds for this withdrawal';
  END IF;

  v_cash_deduction := LEAST(COALESCE(v_cash_before,0),v_request.amount);
  v_bonus_deduction := v_request.amount-v_cash_deduction;

  UPDATE public.profiles
  SET cash_balance=COALESCE(cash_balance,0)-v_cash_deduction,
      bonus_balance=COALESCE(bonus_balance,0)-v_bonus_deduction,
      virtual_balance=COALESCE(virtual_balance,0)-v_request.amount
  WHERE id=v_request.user_id
  RETURNING virtual_balance INTO v_after;

  UPDATE public.withdrawal_requests
  SET status='approved',reviewed_by=auth.uid(),reviewed_at=now()
  WHERE id=p_request_id;

  INSERT INTO public.wallet_transactions
    (user_id,transaction_type,amount,balance_before,balance_after,reference_id,description)
  VALUES
    (v_request.user_id,'withdrawal',v_request.amount,v_before,v_after,p_request_id,
     CASE WHEN v_bonus_deduction>0
       THEN 'Withdrawal approved from eligible cash and qualified welcome bonus funds'
       ELSE 'Withdrawal approved from eligible wallet funds' END);

  INSERT INTO public.user_notifications(user_id,title,message,notification_type)
  VALUES(v_request.user_id,'Withdrawal approved',
    'Your withdrawal request of ₦'||v_request.amount||' was approved.','withdrawal');
END;
$function$;
