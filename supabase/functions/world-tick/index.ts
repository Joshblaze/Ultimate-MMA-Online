import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey',
};

interface TickResult {
  status: string;
  tick?: number;
  date?: { year: number; month: number; week: number; day: number };
  retired?: number;
  signed?: number;
  events_processed?: number;
  fights_simulated?: number;
  offers_generated?: number;
  purses_paid?: number;
  error?: string;
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
    // Use service role to bypass RLS — this function runs the world tick
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceKey) {
      return new Response(
        JSON.stringify({ error: 'Server misconfigured: missing credentials.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Check if world is paused BEFORE calling advance_week (the RPC also returns 'paused' but this saves a round trip)
    const { data: world, error: worldError } = await supabase
      .from('world_state')
      .select('is_paused, tick_count, current_year, current_week, current_month, current_day')
      .eq('id', 1)
      .maybeSingle();

    if (worldError) {
      throw new Error(`Failed to read world state: ${worldError.message}`);
    }

    if (!world) {
      return new Response(
        JSON.stringify({ error: 'World not initialized. Reset the world from the admin panel.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (world.is_paused) {
      const result: TickResult = { status: 'paused' };
      return new Response(JSON.stringify(result), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Run the weekly tick
    const { data: tickData, error: tickError } = await supabase.rpc('advance_week');

    if (tickError) {
      throw new Error(`Tick RPC failed: ${tickError.message}`);
    }

    const result: TickResult = (tickData && typeof tickData === 'object')
      ? tickData as TickResult
      : { status: 'unknown' };

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('world-tick error:', message);
    return new Response(
      JSON.stringify({ status: 'error', error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
