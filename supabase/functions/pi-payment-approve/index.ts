// Supabase Edge Function: pi-payment-approve
// Server-side approval for Pi U2A payments (POST https://api.minepi.com/v2/payments/{id}/approve)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Server-to-server Platform API key (Dashboard → App → Developer Portal).
// Fail with a clear 500 instead of crashing on a missing secret.
const PI_API_KEY = Deno.env.get("PI_API_KEY") ?? Deno.env.get("PI_NETWORK_API_KEY");
// Single Platform API base for both networks (per pi-platform-docs).
// The PI_API_BASE override exists only as an ops escape hatch (e.g. a proxy).
const PI_API_BASE =
  Deno.env.get("PI_API_BASE") ?? "https://api.minepi.com/v2";

// CORS preflight must allow every header the Supabase Dart/JS clients send
// (notably x-client-info and apikey) or browsers block the real request.
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { paymentId } = await req.json();
    if (!paymentId) {
      return json({ error: "paymentId is required" }, 400);
    }
    if (!PI_API_KEY) {
      return json(
        { error: "server_not_configured", detail: "PI_API_KEY secret is not set (supabase secrets set PI_API_KEY=...)" },
        500,
      );
    }

    const res = await fetch(`${PI_API_BASE}/payments/${paymentId}/approve`, {
      method: "POST",
      headers: { Authorization: `Key ${PI_API_KEY}` },
    });
    const payment = await res.json();

    if (!res.ok) {
      return json({ error: "approve_failed", detail: payment }, res.status);
    }

    // Record approval in the backend mirror.
    const admin = createAdminClient();
    await admin.from("pi_payments").upsert({
      identifier: payment.identifier,
      user_uid: payment.user_uid,
      amount: payment.amount,
      memo: payment.memo,
      metadata: payment.metadata ?? {},
      status: "approved",
      network: payment.network,
    });

    return json({ ok: true, payment });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function createAdminClient() {
  // Lazy import keeps cold-start light; service role key never leaves the server.
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return {
    from: (table: string) => ({
      upsert: async (row: Record<string, unknown>) => {
        await fetch(`${url}/rest/v1/${table}`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${key}`,
            apikey: key,
            "Content-Type": "application/json",
            Prefer: "resolution=merge-duplicates",
          },
          body: JSON.stringify(row),
        });
      },
    }),
  };
}
