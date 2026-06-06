-- =========================================================================
-- SUPABASE COMPLETE SETUP SCHEMA
-- Execute this script in your Supabase SQL Editor (https://supabase.com)
-- =========================================================================

-- Enable uuid-ossp extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PROFILES (Extends Supabase Auth users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email text UNIQUE NOT NULL,
  name text,
  role text DEFAULT 'sales' CHECK (role IN ('admin', 'sales', 'warehouse')),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 2. CUSTOMERS
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  phone text,
  address text,
  type text DEFAULT 'client', -- client, specialist, trader, or custom types
  balance numeric DEFAULT 0,
  total_purchases numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on customers
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- 3. PRODUCTS
CREATE TABLE IF NOT EXISTS public.products (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  sku text UNIQUE,
  barcode text,
  category text,
  stock numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  price_retail numeric DEFAULT 0,
  price_specialist numeric DEFAULT 0,
  price_dealer numeric DEFAULT 0,
  traderPrice numeric DEFAULT 0,
  specialistPrice numeric DEFAULT 0,
  clientPrice numeric DEFAULT 0,
  supplier text,
  expiry date,
  min_qty integer DEFAULT 10,
  image text,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 4. INVOICES
CREATE TABLE IF NOT EXISTS public.invoices (
  id text PRIMARY KEY,
  customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  customer_name text,
  customer_type text,
  customer_phone text,
  subtotal numeric DEFAULT 0,
  discount numeric DEFAULT 0,
  tax numeric DEFAULT 0,
  total numeric DEFAULT 0,
  paid numeric DEFAULT 0,
  remaining numeric DEFAULT 0,
  payment_method text,
  date date DEFAULT current_date,
  due_date date,
  status text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on invoices
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

-- 5. INVOICE ITEMS
CREATE TABLE IF NOT EXISTS public.invoice_items (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id text NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  product_id bigint REFERENCES public.products(id) ON DELETE SET NULL,
  name text,
  qty numeric NOT NULL CHECK (qty > 0),
  price numeric NOT NULL,
  total numeric NOT NULL,
  movement_type text DEFAULT 'sale' CHECK (movement_type IN ('sale', 'gift', 'waste')),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS on invoice_items
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;

-- 6. WASTE LOGS
CREATE TABLE IF NOT EXISTS public.waste_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id bigint NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  qty numeric NOT NULL CHECK (qty > 0),
  type text NOT NULL CHECK (type IN ('gift', 'waste')),
  cost numeric NOT NULL DEFAULT 0,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text
);

-- Enable RLS on waste_logs
ALTER TABLE public.waste_logs ENABLE ROW LEVEL SECURITY;

-- 7. CUSTOMER SPECIAL PRICES
CREATE TABLE IF NOT EXISTS public.customer_special_prices (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  product_id bigint NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  special_price numeric NOT NULL CHECK (special_price >= 0),
  min_qty integer DEFAULT 1 CHECK (min_qty >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, product_id)
);

-- Enable RLS on customer_special_prices
ALTER TABLE public.customer_special_prices ENABLE ROW LEVEL SECURITY;


-- =========================================================================
-- SECURITY CHECKS & HELPER FUNCTIONS FOR RLS
-- =========================================================================

-- Function to get the role of the current authenticated user
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text AS $$
DECLARE
  u_role text;
BEGIN
  SELECT role INTO u_role FROM public.profiles WHERE id = auth.uid();
  RETURN COALESCE(u_role, 'sales');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS Policies for Profiles
DROP POLICY IF EXISTS "Allow authenticated to view profiles" ON public.profiles;
CREATE POLICY "Allow authenticated to view profiles" ON public.profiles
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow users to update their own profile" ON public.profiles;
CREATE POLICY "Allow users to update their own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Allow admin to manage profiles" ON public.profiles;
CREATE POLICY "Allow admin to manage profiles" ON public.profiles
  FOR ALL TO authenticated USING (public.get_user_role() = 'admin');

-- RLS Policies for Products
DROP POLICY IF EXISTS "Allow authenticated to view products" ON public.products;
CREATE POLICY "Allow authenticated to view products" ON public.products
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin/warehouse to manage products" ON public.products;
CREATE POLICY "Allow admin/warehouse to manage products" ON public.products
  FOR ALL TO authenticated USING (public.get_user_role() IN ('admin', 'warehouse'));

-- RLS Policies for Customers
DROP POLICY IF EXISTS "Allow authenticated to view customers" ON public.customers;
CREATE POLICY "Allow authenticated to view customers" ON public.customers
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin/sales to manage customers" ON public.customers;
CREATE POLICY "Allow admin/sales to manage customers" ON public.customers
  FOR ALL TO authenticated USING (public.get_user_role() IN ('admin', 'sales'));

-- RLS Policies for Invoices & Invoice Items
DROP POLICY IF EXISTS "Allow authenticated to view invoices" ON public.invoices;
CREATE POLICY "Allow authenticated to view invoices" ON public.invoices
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin/sales to manage invoices" ON public.invoices;
CREATE POLICY "Allow admin/sales to manage invoices" ON public.invoices
  FOR ALL TO authenticated USING (public.get_user_role() IN ('admin', 'sales'));

DROP POLICY IF EXISTS "Allow authenticated to view invoice items" ON public.invoice_items;
CREATE POLICY "Allow authenticated to view invoice items" ON public.invoice_items
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin/sales to manage invoice items" ON public.invoice_items;
CREATE POLICY "Allow admin/sales to manage invoice items" ON public.invoice_items
  FOR ALL TO authenticated USING (public.get_user_role() IN ('admin', 'sales'));

-- RLS Policies for Waste Logs
DROP POLICY IF EXISTS "Allow authenticated to view waste logs" ON public.waste_logs;
CREATE POLICY "Allow authenticated to view waste logs" ON public.waste_logs
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin/warehouse to manage waste logs" ON public.waste_logs;
CREATE POLICY "Allow admin/warehouse to manage waste logs" ON public.waste_logs
  FOR ALL TO authenticated USING (public.get_user_role() IN ('admin', 'warehouse'));

-- RLS Policies for Customer Special Prices
DROP POLICY IF EXISTS "Allow authenticated to view special prices" ON public.customer_special_prices;
CREATE POLICY "Allow authenticated to view special prices" ON public.customer_special_prices
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin to manage special prices" ON public.customer_special_prices;
CREATE POLICY "Allow admin to manage special prices" ON public.customer_special_prices
  FOR ALL TO authenticated USING (public.get_user_role() = 'admin');



-- =========================================================================
-- DATABASE TRIGGERS
-- =========================================================================

-- A. Trigger to automatically sync profiles table when a user registers in auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, role)
  VALUES (
    new.id,
    new.email,
    COALESCE((new.raw_user_meta_data::jsonb)->>'name', (new.raw_user_meta_data::jsonb)->>'full_name', 'مستخدم جديد'),
    COALESCE((new.raw_user_meta_data::jsonb)->>'role', 'sales')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- B. Trigger to manage product stock automatically when an invoice item is sold, gifted, or wasted
CREATE OR REPLACE FUNCTION public.handle_invoice_item_stock()
RETURNS trigger AS $$
DECLARE
  p_cost numeric;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- If it's a regular sale, we directly subtract stock
    IF NEW.movement_type = 'sale' THEN
      UPDATE public.products
      SET stock = stock - NEW.qty
      WHERE id = NEW.product_id;
    -- If it's a gift or waste, we insert into waste_logs, which then triggers the stock decrement automatically!
    ELSIF NEW.movement_type IN ('gift', 'waste') THEN
      SELECT cost INTO p_cost FROM public.products WHERE id = NEW.product_id;
      INSERT INTO public.waste_logs (product_id, qty, type, cost, notes, created_by)
      VALUES (
        NEW.product_id,
        NEW.qty,
        NEW.movement_type,
        COALESCE(p_cost, 0) * NEW.qty,
        'مسجل تلقائياً من الفاتورة رقم: ' || NEW.invoice_id,
        (SELECT created_by FROM public.invoices WHERE id = NEW.invoice_id)
      );
    END IF;
    
    -- Update customer total purchases and balance if it's a sale
    IF NEW.movement_type = 'sale' THEN
      UPDATE public.customers
      SET total_purchases = total_purchases + NEW.total
      WHERE id = (SELECT customer_id FROM public.invoices WHERE id = NEW.invoice_id);
    END IF;
    
  ELSIF TG_OP = 'UPDATE' THEN
    -- Restore old qty stock
    IF OLD.movement_type = 'sale' THEN
      UPDATE public.products SET stock = stock + OLD.qty WHERE id = OLD.product_id;
    END IF;
    -- Subtract new qty stock
    IF NEW.movement_type = 'sale' THEN
      UPDATE public.products SET stock = stock - NEW.qty WHERE id = NEW.product_id;
    END IF;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Restore stock on deletion
    IF OLD.movement_type = 'sale' THEN
      UPDATE public.products SET stock = stock + OLD.qty WHERE id = OLD.product_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_invoice_item_stock
  AFTER INSERT OR UPDATE OR DELETE ON public.invoice_items
  FOR EACH ROW EXECUTE FUNCTION public.handle_invoice_item_stock();


-- C. Trigger to manage stock when waste logs are inserted or manipulated directly
CREATE OR REPLACE FUNCTION public.handle_waste_log_stock()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.products
    SET stock = stock - NEW.qty
    WHERE id = NEW.product_id;
  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.products SET stock = stock + OLD.qty WHERE id = OLD.product_id;
    UPDATE public.products SET stock = stock - NEW.qty WHERE id = NEW.product_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.products SET stock = stock + OLD.qty WHERE id = OLD.product_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_waste_log_stock
  AFTER INSERT OR UPDATE OR DELETE ON public.waste_logs
  FOR EACH ROW EXECUTE FUNCTION public.handle_waste_log_stock();

-- 8. APP SETTINGS (For Google Sheets backup email, etc)
CREATE TABLE IF NOT EXISTS public.app_settings (
  id text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on app_settings
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated to view settings" ON public.app_settings;
CREATE POLICY "Allow authenticated to view settings" ON public.app_settings
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin to manage settings" ON public.app_settings;
CREATE POLICY "Allow admin to manage settings" ON public.app_settings
  FOR ALL TO authenticated USING (public.get_user_role() = 'admin');

-- ============================================================
-- STORAGE SETUP
-- Execute this in Supabase SQL Editor to create the 'invoices' bucket
-- ============================================================

-- Create a bucket for invoices if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('invoices', 'invoices', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public access to the invoices bucket
CREATE POLICY "Public Access" ON storage.objects FOR SELECT USING (bucket_id = 'invoices');
CREATE POLICY "Authenticated Upload" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'invoices' AND auth.role() = 'authenticated');
