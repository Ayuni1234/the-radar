// Supabase Edge Function: pi-payment-complete
// Server-side completion for Pi U2A payments:
//   POST https://api.minepi.com/v2/payments/{id}/complete  { txid }
// Grants the purchased entitlement once the txid is verified by Pi.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PI_API_KEY = Deno.env.get("PI_API_KEY") ?? Deno.env.get("PI_NETWORK_API_KEY");
// Single Platform API base for both networks (per pi-platform-docs).
const PI_API_BASE =
  Deno.env.get("PI_API_BASE") ?? "https://api.minepi.com/v2";

// Same CORS rule as pi-session / pi-payment-approve: allow every header the
// Supabase clients send or browsers reject the preflight silently.
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
    const { paymentId, txid, incomplete } = await req.json();
    if (!paymentId) {
      return json({ error: "paymentId is required" }, 400);
    }
    if (!PI_API_KEY) {
      return json(
        { error: "server_not_configured", detail: "PI_API_KEY secret is not set (supabase secrets set PI_API_KEY=...)" },
        500,
      );
    }

    // Incomplete-payment recovery (onIncompletePaymentFound): the client may
    // not know the txid yet — look it up from the Platform API instead of
    // rejecting, so an interrupted payment is always completed, never lost.
    let finalTxid = txid;
    if (!finalTxid && incomplete) {
      const lookup = await fetch(`${PI_API_BASE}/payments/${paymentId}`, {
        headers: { Authorization: `Key ${PI_API_KEY}` },
      });
      if (!lookup.ok) {
        return json({ error: "payment_lookup_failed", detail: await lookup.text() }, 502);
      }
      const dto = await lookup.json();
      finalTxid = dto?.transaction?.txid;
      if (!finalTxid) {
        // No on-chain transaction yet: mirror as created and wait — the SDK
        // will re-fire completion once the user's tx lands.
        const admin = createAdminClient();
        await admin.from("pi_payments").upsert({
          identifier: dto.identifier,
          user_uid: dto.user_uid,
          amount: dto.amount,
          memo: dto.memo,
          metadata: dto.metadata ?? {},
          status: dto.status?.cancelled ? "cancelled" : "created",
          network: dto.network,
        });
        return json({ ok: true, payment: dto, note: "no txid yet; payment mirrored as pending" });
      }
    }
    if (!finalTxid) {
      return json({ error: "txid is required" }, 400);
    }

    // 1. Verify with Pi Platform API.
    const res = await fetch(`${PI_API_BASE}/payments/${paymentId}/complete`, {
      method: "POST",
      headers: {
        Authorization: `Key ${PI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ txid: finalTxid }),
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
      txid: finalTxid,
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

      // Boost products: stamp the target event's boosted_until so it pins
      // above non-boosted events on the radar and discovery feeds.
      const BOOST_PRODUCTS = new Set(["session_boost_48h", "event_spotlight_7d"]);
      if (BOOST_PRODUCTS.has(product) && meta.reference_id) {
        await admin
          .from("radar_events")
          .update({ boosted_until: expiryFor(product) })
          .eq("id", meta.reference_id as string);
      }
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
    case "event_spotlight_7d":
      return new Date(now + 7 * day).toISOString();
    case "profile_spotlight_14d":
      return new Date(now + 14 * day).toISOString();
    default:
      return null; // bounties don't expire
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
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
