-- Keep notifications strictly private to their recipient account.
DROP POLICY IF EXISTS "Admins manage user notifications" ON public.user_notifications;
DROP POLICY IF EXISTS "Users view own notifications" ON public.user_notifications;
CREATE POLICY "Accounts view own notifications"
  ON public.user_notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.notify_admin_accounts(p_title text,p_message text,p_type text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  INSERT INTO public.user_notifications(user_id,title,message,notification_type)
  SELECT id,p_title,p_message,p_type FROM public.profiles WHERE role='admin';
END;
$$;
REVOKE ALL ON FUNCTION public.notify_admin_accounts(text,text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.notify_deposit_request_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  INSERT INTO public.user_notifications(user_id,title,message,notification_type)
  VALUES(NEW.user_id,'Deposit request submitted','Your deposit request of ₦'||NEW.amount::text||' has been submitted and is awaiting review.','deposit');
  PERFORM public.notify_admin_accounts('New deposit request','A deposit request of ₦'||NEW.amount::text||' is awaiting review.','deposit');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_deposit_request_created() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.notify_withdrawal_request_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  INSERT INTO public.user_notifications(user_id,title,message,notification_type)
  VALUES(NEW.user_id,'Withdrawal request submitted','Your withdrawal request of ₦'||NEW.amount::text||' has been submitted and is awaiting review.','withdrawal');
  PERFORM public.notify_admin_accounts('New withdrawal request','A withdrawal request of ₦'||NEW.amount::text||' is awaiting review.','withdrawal');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_withdrawal_request_created() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.notify_wallet_transaction_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_label text; v_description text;
BEGIN
  IF NEW.transaction_type IN ('deposit','withdrawal','bet','payout','win') THEN RETURN NEW; END IF;
  v_label:=CASE NEW.transaction_type WHEN 'bonus' THEN 'Bonus credit' WHEN 'bonus credit' THEN 'Bonus credit' WHEN 'adjustment' THEN 'Compensation credit' ELSE initcap(replace(NEW.transaction_type,'_',' ')) END;
  v_description:=COALESCE(NULLIF(trim(NEW.description),''),v_label);
  INSERT INTO public.user_notifications(user_id,title,message,notification_type)
  VALUES(NEW.user_id,v_label,v_label||' of ₦'||NEW.amount::text||' has been added to your wallet. '||v_description,'transaction');
  PERFORM public.notify_admin_accounts('Wallet transaction recorded',v_label||' of ₦'||NEW.amount::text||' was recorded. '||v_description,'transaction');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_wallet_transaction_created() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.notify_admin_bet_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_game_name text;
BEGIN
  SELECT name INTO v_game_name FROM public.games WHERE id=NEW.game_id;
  PERFORM public.notify_admin_accounts('Bet transaction recorded','A bet of ₦'||NEW.bet_amount::text||' was recorded for '||COALESCE(v_game_name,NEW.game_id,'a game')||'.','bet');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_admin_bet_created() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS trg_notify_deposit_request_created ON public.deposit_requests;
CREATE TRIGGER trg_notify_deposit_request_created AFTER INSERT ON public.deposit_requests
FOR EACH ROW EXECUTE FUNCTION public.notify_deposit_request_created();

DROP TRIGGER IF EXISTS trg_notify_withdrawal_request_created ON public.withdrawal_requests;
CREATE TRIGGER trg_notify_withdrawal_request_created AFTER INSERT ON public.withdrawal_requests
FOR EACH ROW EXECUTE FUNCTION public.notify_withdrawal_request_created();

DROP TRIGGER IF EXISTS trg_notify_wallet_transaction_created ON public.wallet_transactions;
CREATE TRIGGER trg_notify_wallet_transaction_created AFTER INSERT ON public.wallet_transactions
FOR EACH ROW EXECUTE FUNCTION public.notify_wallet_transaction_created();

DROP TRIGGER IF EXISTS trg_notify_admin_bet_created ON public.demo_bets;
CREATE TRIGGER trg_notify_admin_bet_created AFTER INSERT ON public.demo_bets
FOR EACH ROW EXECUTE FUNCTION public.notify_admin_bet_created();
