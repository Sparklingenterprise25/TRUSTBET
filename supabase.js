import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://gzhxsdwhrrphbrjcnytj.supabase.co';

const SUPABASE_ANON_KEY = 'sb_publishable_ziI0kZ7KGO04M2GkuIoQXw_KSf95rN9';

export const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);
