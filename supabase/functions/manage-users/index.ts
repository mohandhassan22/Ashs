import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ""
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ""
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing Supabase environment variables on server.")
    }

    // Create client with service role for admin privileges
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    })

    // Get Auth Token from Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No authorization header provided' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const token = authHeader.replace('Bearer ', '')
    
    // Verify caller user
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid user session token', details: userError }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Query profiles to check if the caller is an Admin
    const { data: callerProfile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    if (profileError || !callerProfile || callerProfile.role !== 'admin') {
      return new Response(JSON.stringify({
        error: 'Forbidden: Only administrators can manage users',
        caller: {
          userId: user.id,
          role: callerProfile?.role ?? null,
          profileError: profileError ? String((profileError as any).message || profileError) : null,
        }
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Parse request body
    const { action, email, password, name, role, userId } = await req.json()

    if (action === 'createUser') {
      if (!email || !password || !name || !role) {
        return new Response(JSON.stringify({ error: 'Missing required fields: email, password, name, role' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      // Create auth user
      const { data: newAuthUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, role }
      })

      if (createError) {
        console.error('Auth creation error:', createError);
        return new Response(JSON.stringify({
          error: 'Failed to create user',
          details: {
            message: createError.message,
            name: (createError as any).name,
            status: (createError as any).status,
            statusText: (createError as any).statusText,
            code: (createError as any).code,
            hint: 'Check if email already exists, password requirements, and that role/name are valid'
          },
          request: { action, email, hasPassword: !!password, name, role, userId }
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      // Create profile entry if user was created successfully
      if (newAuthUser?.user) {
        const { error: profileError } = await supabaseAdmin
          .from('profiles')
          .insert({
            id: newAuthUser.user.id,
            email: email,
            name: name,
            role: role
          });
        
        if (profileError) {
          console.error('Profile creation error:', profileError);
          // Try update if insert fails (profile might exist)
          await supabaseAdmin
            .from('profiles')
            .update({ role, name, email })
            .eq('id', newAuthUser.user.id);
        }
      }

      return new Response(JSON.stringify({ message: 'User created successfully', user: newAuthUser.user }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    else if (action === 'updateUser') {
      if (!userId) {
        return new Response(JSON.stringify({ error: 'Missing userId parameter' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      const updateData: any = {
        user_metadata: { name, role }
      }
      if (email) updateData.email = email
      if (password) updateData.password = password

      // Update auth user
      const { data: updatedAuthUser, error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
        userId,
        updateData
      )

      if (updateError) {
        return new Response(JSON.stringify({ error: updateError.message }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      // Update public.profiles table row
      const updateProfile: any = {}
      if (name) updateProfile.name = name
      if (role) updateProfile.role = role
      if (email) updateProfile.email = email

      const { error: profileUpError } = await supabaseAdmin
        .from('profiles')
        .update(updateProfile)
        .eq('id', userId)

      if (profileUpError) {
        return new Response(JSON.stringify({ error: 'User updated, but failed to sync profiles table', details: profileUpError.message }), {
          status: 207,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      return new Response(JSON.stringify({ message: 'User updated successfully', user: updatedAuthUser.user }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    else if (action === 'deleteUser') {
      if (!userId) {
        return new Response(JSON.stringify({ error: 'Missing userId parameter' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      // Delete auth user (cascades to profile)
      const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userId)

      if (deleteError) {
        return new Response(JSON.stringify({ error: deleteError.message }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      return new Response(JSON.stringify({ message: 'User deleted successfully' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    else {
      return new Response(JSON.stringify({ error: 'Invalid or unsupported action' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
