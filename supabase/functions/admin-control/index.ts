import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey',
};

type Action = 'pause' | 'resume' | 'advance' | 'reset' | 'wipe_gyms' | 'wipe_fighters' | 'status';

interface AdminResult {
  action: Action;
  status: 'ok' | 'error' | 'unauthorized';
  message?: string;
  data?: unknown;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !anonKey || !serviceKey) {
      return new Response(
        JSON.stringify({ error: 'Server misconfigured: missing credentials.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Use the user's bearer token to verify they're an admin
    const authHeader = req.headers.get('Authorization') || '';
    const bearerToken = authHeader.replace(/^Bearer\s+/i, '');

    if (!bearerToken) {
      return new Response(
        JSON.stringify({ action: 'status', status: 'unauthorized', message: 'Missing auth token.' } satisfies AdminResult),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create a client as the user so the is_admin() RPC checks THEIR profile
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${bearerToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: isAdmin, error: adminError } = await userClient.rpc('is_admin');
    if (adminError || !isAdmin) {
      return new Response(
        JSON.stringify({ action: 'status', status: 'unauthorized', message: 'Admin privileges required.' } satisfies AdminResult),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse body
    let body: { action?: Action } = {};
    try {
      body = await req.json();
    } catch {
      // Empty body is fine for status-only requests
    }
    const action = (body.action || 'status') as Action;

    // Service-role client for privileged writes
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let result: AdminResult;

    switch (action) {
      case 'pause': {
        await admin.rpc('pause_world');
        result = { action, status: 'ok', message: 'World simulation paused.' };
        break;
      }
      case 'resume': {
        await admin.rpc('resume_world');
        result = { action, status: 'ok', message: 'World simulation resumed.' };
        break;
      }
      case 'advance': {
        const { data, error } = await admin.rpc('advance_week');
        if (error) throw new Error(`advance_week failed: ${error.message}`);
        result = { action, status: 'ok', data };
        break;
      }
      case 'reset': {
        const { data, error } = await admin.rpc('reset_world');
        if (error) throw new Error(`reset_world failed: ${error.message}`);
        result = { action, status: 'ok', message: 'World reset to Day 1.', data };
        break;
      }
      case 'wipe_gyms': {
        await admin.rpc('wipe_all_gyms');
        result = { action, status: 'ok', message: 'All gyms wiped.' };
        break;
      }
      case 'wipe_fighters': {
        await admin.rpc('wipe_all_fighters');
        result = { action, status: 'ok', message: 'All fighters wiped.' };
        break;
      }
      case 'status': {
        const { data: world, error } = await admin
          .from('world_state')
          .select('*')
          .eq('id', 1)
          .maybeSingle();
        if (error) throw new Error(`Failed to read world: ${error.message}`);
        result = { action, status: 'ok', data: world };
        break;
      }
      default:
        result = { action, status: 'error', message: `Unknown action: ${action}` };
    }

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('admin-control error:', message);
    return new Response(
      JSON.stringify({ status: 'error', error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
