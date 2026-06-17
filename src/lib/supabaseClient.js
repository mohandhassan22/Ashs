import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://placeholder.supabase.co';
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'placeholder';
const supabaseServiceKey = import.meta.env.VITE_SUPABASE_SERVICE_ROLE_KEY || '';

if (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY) {
  console.warn('⚠️ VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY is not set. Please restart Vite if you just added the .env file.');
}

function _create() {
  return createClient(supabaseUrl, supabaseKey);
}

const g = typeof globalThis !== 'undefined' ? globalThis : (typeof window !== 'undefined' ? window : {});

if (!g.__supabaseClient) {
  g.__supabaseClient = _create();
}

export const supabase = g.__supabaseClient;

// Admin client with service role key — used for user management (create/delete)
export const supabaseAdmin = supabaseServiceKey
  ? createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })
  : null;
