-- ============================================================
-- SQL SCRIPT FOR AUTOMATIC GOOGLE SHEETS SYNC VIA WEBHOOKS
-- Execute this script in your Supabase SQL Editor
-- ============================================================

-- Enable the pg_net extension if not enabled
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Helper function to trigger sync-google-sheets Edge Function
CREATE OR REPLACE FUNCTION public.trigger_google_sheets_sync()
RETURNS trigger AS $$
DECLARE
  payload jsonb;
  supabase_url text;
  anon_key text;
  req_url text;
BEGIN
  -- Get Supabase config from environment (or replace with your actual values if they are empty)
  supabase_url := current_setting('request.headers', true)::jsonb->>'x-forwarded-proto' || '://' || current_setting('request.headers', true)::jsonb->>'host';
  
  -- Alternatively, fallback to project URL if known, or hardcode it
  -- SELECT value INTO supabase_url FROM public.app_settings WHERE id = 'supabase_url'; 
  
  -- Construct request body
  payload := jsonb_build_object(
    'table', TG_TABLE_NAME,
    'type', TG_OP,
    'record', row_to_json(NEW)
  );

  -- Perform asynchronous HTTP POST request to the Edge Function
  -- Note: We use the local/remote project URL. In production, replace with your actual API endpoint if needed.
  -- IMPORTANT: Replace the URL with your actual project's Edge Function URL
  -- Example: https://[YOUR-PROJECT-ID].supabase.co/functions/v1/sync-google-sheets
  PERFORM net.http_post(
    url := 'https://[REPLACE-WITH-YOUR-PROJECT-ID].supabase.co/functions/v1/sync-google-sheets',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', '[REPLACE-WITH-YOUR-ANON-KEY]' -- Replace with your actual VITE_SUPABASE_ANON_KEY
    ),
    body := payload::text
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. TRIGGER FOR PRODUCTS
CREATE OR REPLACE TRIGGER on_product_change_sync
  AFTER INSERT OR UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.trigger_google_sheets_sync();

-- 2. TRIGGER FOR CUSTOMERS
CREATE OR REPLACE TRIGGER on_customer_change_sync
  AFTER INSERT OR UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.trigger_google_sheets_sync();

-- 3. TRIGGER FOR INVOICES
CREATE OR REPLACE TRIGGER on_invoice_change_sync
  AFTER INSERT OR UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.trigger_google_sheets_sync();
