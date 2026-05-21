// Supabase Edge Function (Deno) - insert_waste_protected
// Deploy via `supabase functions deploy insert_waste_protected`

import { serve } from 'std/server';

// Read environment variables for Supabase URL/Key or use built-in service_role
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

serve(async (req) => {
  try {
    const supabaseAccessToken = req.headers.get('authorization')?.replace('Bearer ', '') || '';
    const body = await req.json();
    const { product_id, qty, type, notes } = body;

    if (!supabaseAccessToken) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
    }

    // verify user role by calling Supabase /auth/user or profiles table using service key
    // We'll use service role to query profiles safely
    const profileRes = await fetch(`${SUPABASE_URL}/rest/v1/profiles?select=role&id=eq.${encodeURIComponent(body.user_id || '')}`, {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY || '',
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY || ''}`,
        'Content-Type': 'application/json'
      }
    });

    if (!profileRes.ok) {
      return new Response(JSON.stringify({ error: 'Failed to fetch profile' }), { status: 500 });
    }

    const profiles = await profileRes.json();
    const role = profiles?.[0]?.role || null;
    if (type === 'waste' && role !== 'admin') {
      return new Response(JSON.stringify({ error: 'Only admin can insert waste' }), { status: 403 });
    }

    // Insert into waste_logs using service role key
    const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/waste_logs`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY || '',
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY || ''}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation'
      },
      body: JSON.stringify([{ product_id, qty, type, notes, created_by: body.user_id }])
    });

    const insertData = await insertRes.json();
    if (!insertRes.ok) {
      return new Response(JSON.stringify({ error: insertData }), { status: 500 });
    }

    // Optionally deduct stock and insert invoice_item can be handled by DB trigger.

    return new Response(JSON.stringify({ data: insertData }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
