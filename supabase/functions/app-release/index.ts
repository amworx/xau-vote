// Publishes the latest app release manifest for the in-app updater.
//
// The updater compares this against the version installed on the device and
// streams the APK. Two rules make this safe rather than an arbitrary remote
// code execution path:
//
//  1. Public READ is allowed (the app has no account), so there is no INSERT
//     policy. Rows can only be written with the service role.
//  2. The response always carries the stored `sha256`. Dart verifies the
//     downloaded bytes against it and discards a mismatch, so a tampered APK or
//     a corrupted transfer can never reach the installer.
//
// Serves JSON, not the APK itself: the APK lives in Storage so this function
// stays cheap and can be cached.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

const JSON_HEADERS = {
  ...CORS,
  'Content-Type': 'application/json; charset=utf-8',
  // A release manifest must never be served from a stale cache, or a fixed
  // update check would keep offering a build the user already installed.
  'Cache-Control': 'no-store',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: JSON_HEADERS,
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${Deno.env.get('SUPABASE_ANON_KEY') ?? ''}` } } },
    );

    // The RLS SELECT policy is what authorises this read.
    const { data, error } = await supabase
      .from('app_releases')
      .select('version, version_code, apk_url, sha256, size_bytes, notes, created_at')
      .order('version_code', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) throw error;

    if (!data) {
      return new Response(
        JSON.stringify({ error: 'no release published' }),
        { status: 404, headers: JSON_HEADERS },
      );
    }

    return new Response(
      JSON.stringify({
        version: data.version,
        versionCode: data.version_code,
        apkUrl: data.apk_url,
        sha256: data.sha256,
        sizeBytes: data.size_bytes,
        notes: data.notes,
        publishedAt: data.created_at,
      }),
      { status: 200, headers: JSON_HEADERS },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err?.message ?? err) }),
      { status: 500, headers: JSON_HEADERS },
    );
  }
});