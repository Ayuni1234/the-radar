// Supabase Edge Function: pi-payment-complete
// Server-side completion for Pi U2A payments:
//   POST https://api.minepi.com/v2/payments/{id}/complete  { txid }
// Grants the purchased entitlement once the txid is verified by Pi.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PI_API_KEY = Deno.env.get("PI_API_KEY")!;
const PI_API_BASE = "https://api.minepi.com/v2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const { paymentId, txid, incomplete } = await req.json();
    if (!paymentId || !txid) {
      return json({ error: "paymentId and txid are required" }, 400);
    }

    // 1. Verify with Pi Platform API.
    const res = await fetch(`${PI_API_BASE}/payments/${paymentId}/complete`, {
      method: "POST",
      headers: {
        Authorization: `Key ${PI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ txid }),
    });
    const payment = await res.json();
    if (!res.ok) {
      return json({ error: "complete_failed", detail: payment }, res.status);
    }

    // 2. Mirror the payment.
    const admin = createAdminClient();
    await admin.from("pi_payments").upsert({
      identifier: payment.identifier,
      user_uid: payment.user_uid,
      amount: payment.amount,
      memo: payment.memo,
      metadata: payment.metadata ?? {},
      status: payment.status?.cancelled ? "cancelled" : "completed",
      txid,
      network: payment.network,
      completed_at: new Date().toISOString(),
    });

    // 3. Grant entitlement based on the product in payment metadata.
    const meta = (payment.metadata ?? {}) as Record<string, unknown>;
    const product = meta.product as string | undefined;
    if (product) {
      await admin.from("entitlements").upsert({
        user_uid: payment.user_uid,
        product,
        reference_id: (meta.reference_id as string) ?? null,
        expires_at: expiryFor(product),
      });
    }

    // Incomplete-payment recovery arrives here too (onIncompletePaymentFound).
    if (incomplete) {
      console.log(`Recovered incomplete payment ${payment.identifier}`);
    }

    return json({ ok: true, payment });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function expiryFor(product: string): string | null {
  const now = Date.now();
  const day = 24 * 60 * 60 * 1000;
  switch (product) {
    case "premium_search_30d":
      return new Date(now + 30 * day).toISOString();
    case "session_boost_48h":
      return new Date(now + 2 * day).toISOString();
    default:
      return null; // bounties don't expire
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function createAdminClient() {
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
