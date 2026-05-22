-- ============================================================
-- SQL SCRIPT FOR ALL TABLES
-- Includes all core tables for Ash Pure ERP
-- ============================================================

-- 1. PROFILES (Auth users for admin/sales)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email text UNIQUE NOT NULL,
  name text,
  role text DEFAULT 'sales' CHECK (role IN ('admin', 'sales')),
  created_at timestamptz DEFAULT now()
);

-- 2. CUSTOMERS
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  phone text,
  address text,
  type text DEFAULT 'client' CHECK (type IN ('client', 'specialist', 'trader')),
  balance numeric DEFAULT 0,
  total_purchases numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 3. PRODUCTS
CREATE TABLE IF NOT EXISTS public.products (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  sku text,
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

-- 5. INVOICE ITEMS
CREATE TABLE IF NOT EXISTS public.invoice_items (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id text NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  product_id bigint NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  name text,
  qty numeric NOT NULL,
  price numeric NOT NULL,
  total numeric NOT NULL,
  movement_type text DEFAULT 'sale',
  created_at timestamptz DEFAULT now()
);

-- 6. WASTE LOGS (for waste and gifts)
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

-- 8. APP SETTINGS
CREATE TABLE IF NOT EXISTS public.app_settings (
  id text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz DEFAULT now()
);
