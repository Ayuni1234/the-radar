// Supabase Edge Function: market-checkout
//
// PitchMarket gear purchase — the checkout half of the fee-split flow.
//
//   1. The buyer pays the listing's FULL price through the normal U2A flow
//      (Pi.createPayment, product = `market_gear_purchase`,
//      reference_id = listing id). The client then invokes this function
//      with the paymentId + txid.
//   2. This function verifies the payment against the Pi Platform API and
//      asserts the amount/metadata match the listing (no client-trust).
//   3. It computes the split — a small platform maintenance fee (default
//      5%) is kept by the treasury wallet, and the core amount is routed
//      to the merchant via the A2U API (POST /v2/payments with
//      `recipient.user_uid` = the shop's verified pi_uid), then approved
//      server-side.
//   4. On success it decrements stock (deactivating the listing at zero)
//      and writes one receipt row per leg into `pi_payments`.
//
// Idempotent: re-invoking with the same paymentId settles once (the
// buyer-payment receipt carries the settlement in its metadata, and the
// merchant payout reuses the stored payout id).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PI_API_KEY = Deno.env.get("PI_API_KEY") ?? Deno.env.get("PI_NETWORK_API_KEY");
const PI_API_BASE = Deno.env.get("PI_API_BASE") ?? "https://api.minepi.com/v2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Platform maintenance cut, as a fraction of the listing price. Ops-tunable
// via secret (e.g. `supabase secrets set MARKET_FEE_RATE=0.07`).
const MARKET_FEE_RATE = (() => {
  const raw = Number(Deno.env.get("MARKET_FEE_RATE") ?? "0.05");
  return Number.isFinite(raw) && raw >= 0 && raw <= 0.5 ? raw : 0.05;
})();

// Where the maintenance fee settles (Platform → Developer Portal wallet).
const TREASURY_PI_UID =
  Deno.env.get("MARKET_TREASURY_PI_UID") ?? "platform-treasury";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ListingRow {
  id: string;
  shop_id: string;
  title: string;
  price_pi: string | number;
  stock_quantity: number;
  is_active: boolean;
}

interface ShopRow {
  id: string;
  owner_id: string;
  shop_name: string;
  pi_uid: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    if (!PI_API_KEY) {
      return json({ error: "server_not_configured", detail: "PI_API_KEY secret is not set" }, 500);
    }
    const { paymentId, txid } = await req.json();
    if (!paymentId) return json({ error: "paymentId is required" }, 400);
    if (!txid) return json({ error: "txid is required" }, 400);

    const auth = authHeaders();

    // 0. Idempotency: has this buyer payment already been settled?
    const existing = await fetch(
      `${SUPABASE_URL}/rest/v1/pi_payments?identifier=eq.${encodeURIComponent(paymentId)}&select=*`,
      { headers: auth },
    );
    const existingRows = (await existing.json()) as Record<string, unknown>[];
    const prior = existingRows[0];
    if (prior?.status === "completed" && (prior.metadata as Record<string, unknown>)?.market_settled) {
      // Self-heal: if a previous run died between marking the receipt settled
      // and writing the payout legs, backfill them from the stored metadata
      // (idempotent — same identifiers, merge-duplicates). Keeps the ledger
      // complete for the buyer order history and merchant sales summary.
      const m = (prior.metadata ?? {}) as Record<string, unknown>;
      const payoutId = typeof m.merchant_payout_id === "string" ? m.merchant_payout_id : null;
      const merchantUid = typeof m.merchant_pi_uid === "string" ? m.merchant_pi_uid : null;
      const merchantAmount = Number(m.merchant_amount);
      const fee = Number(m.platform_fee ?? 0);
      const title = typeof m.listing_title === "string" ? m.listing_title : "gear";
      if (payoutId && merchantUid && Number.isFinite(merchantAmount)) {
        await upsertPayment({
          identifier: payoutId,
          user_uid: merchantUid,
          amount: merchantAmount,
          memo: `PitchMarket sale: ${title}`.slice(0, 60),
          metadata: {
            product: "market_merchant_payout",
            direction: "a2u_payout",
            listing_title: title,
            gross_amount: Number(m.gross_amount ?? prior.amount),
            platform_fee: fee,
            shop_id: m.shop_id,
          },
          status: "approved",
        });
        if (fee > 0) {
          await upsertPayment({
            identifier: `fee-${prior.identifier}`,
            user_uid: TREASURY_PI_UID,
            amount: fee,
            memo: `PitchMarket maintenance fee — ${title}`.slice(0, 60),
            metadata: {
              product: "market_platform_fee",
              direction: "treasury",
              listing_title: title,
              buyer_payment_id: prior.identifier,
            },
            status: "approved",
          });
        }
      }
      return json({
        ok: true,
        alreadySettled: true,
        listingId: (prior.metadata as Record<string, unknown>)?.reference_id,
        merchantPayoutId: payoutId ?? null,
      });
    }

    // 1. Verify the buyer payment with the Pi Platform API.
    const getRes = await fetch(`${PI_API_BASE}/payments/${paymentId}`, {
      headers: { Authorization: `Key ${PI_API_KEY}` },
    });
    if (!getRes.ok) {
      return json({ error: "payment_lookup_failed", detail: await getRes.text() }, 502);
    }
    const payment = await getRes.json();
    const meta = (payment.metadata ?? {}) as Record<string, unknown>;
    if (payment.status?.cancelled || payment.status?.user_cancelled) {
      return json({ error: "payment_cancelled" }, 409);
    }
    if (meta.product !== "market_gear_purchase" || !meta.reference_id) {
      return json({ error: "not_a_market_payment" }, 409);
    }

    // 2. Load the listing + its shop (service role, bypasses RLS).
    const listingId = String(meta.reference_id);
    const listing = await one<ListingRow>(
      `${SUPABASE_URL}/rest/v1/market_listings?id=eq.${listingId}&select=*`,
    );
    if (!listing) return json({ error: "listing_not_found" }, 404);
    const shop = await one<ShopRow>(
      `${SUPABASE_URL}/rest/v1/market_shops?id=eq.${listing.shop_id}&select=id,owner_id,shop_name,pi_uid`,
    );
    if (!shop) return json({ error: "shop_not_found" }, 404);
    if (!shop.pi_uid) return json({ error: "shop_has_no_pi_uid" }, 409);

    // 3. Server-side price check: the Pi amount must match the listing.
    const price = Number(listing.price_pi);
    const paid = Number(payment.amount);
    if (!(price > 0) || Math.abs(paid - price) > 0.0001) {
      return json({ error: "amount_mismatch", expected: price, paid }, 409);
    }
    if (!listing.is_active || listing.stock_quantity <= 0) {
      return json({ error: "out_of_stock" }, 409);
    }

    // Buyer must not buy from their own shop.
    if (payment.user_uid && payment.user_uid === shop.pi_uid) {
      return json({ error: "self_purchase" }, 409);
    }

    // 4. Compute the split.
    const fee = Math.round(price * MARKET_FEE_RATE * 10000) / 10000;
    const merchantAmount = Math.round((price - fee) * 10000) / 10000;

    // 5. Mirror the verified buyer payment as completed. The `market_settled`
    //    marker is intentionally NOT written yet — it lands only after the
    //    merchant payout succeeds, so a failed payout leaves the receipt
    //    unsettled and a retry re-attempts the payout (never skips it).
    await upsertPayment({
      identifier: payment.identifier,
      user_uid: payment.user_uid,
      amount: price,
      memo: payment.memo ?? `PitchMarket — ${listing.title}`,
      metadata: {
        ...meta,
        product: "market_gear_purchase",
        reference_id: listing.id,
        listing_title: listing.title,
        shop_id: shop.id,
        merchant_pi_uid: shop.pi_uid,
      },
      status: "completed",
      txid,
      network: payment.network,
      completed_at: new Date().toISOString(),
    });

    // 6. Route the core amount to the merchant via A2U (create + approve).
    //    Pi masks pi_uid in A2U responses; we echo our own stored copy.
    const payoutMemo = `PitchMarket sale: ${listing.title}`.slice(0, 60);
    const createRes = await fetch(`${PI_API_BASE}/payments`, {
      method: "POST",
      headers: {
        Authorization: `Key ${PI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: merchantAmount,
        memo: payoutMemo,
        metadata: {
          product: "market_merchant_payout",
          listing_id: listing.id,
          buyer_payment_id: payment.identifier,
        },
        recipient: { "user_uid": shop.pi_uid },
        a2u_profession: "FOOTBALL_PLAYER",
      }),
    });
    const created = await createRes.json();
    if (!createRes.ok) {
      // Stock is NOT decremented on payout failure — the settlement marker
      // is absent, so a retry re-attempts the payout first.
      return json({ error: "merchant_payout_create_failed", detail: created }, 502);
    }
    const payoutId = created.identifier as string;
    const approveRes = await fetch(`${PI_API_BASE}/payments/${payoutId}/approve`, {
      method: "POST",
      headers: {
        Authorization: `Key ${PI_API_KEY}`,
        "Content-Type": "application/json",
      },
    });
    const approved = await approveRes.json();
    if (!approveRes.ok) {
      return json({ error: "merchant_payout_approve_failed", detail: approved }, 502);
    }

    // 7. Mark the receipt settled — both payout legs exist from here on, so
    //    re-invocation with the same paymentId short-circuits.
    await upsertPayment({
      identifier: payment.identifier,
      user_uid: payment.user_uid,
      amount: price,
      memo: payment.memo ?? `PitchMarket — ${listing.title}`,
      metadata: {
        ...meta,
        product: "market_gear_purchase",
        reference_id: listing.id,
        market_settled: true,
        listing_title: listing.title,
        shop_id: shop.id,
        merchant_pi_uid: shop.pi_uid,
        merchant_amount: merchantAmount,
        platform_fee: fee,
        merchant_payout_id: payoutId,
      },
      status: "completed",
      txid,
      network: payment.network,
      completed_at: new Date().toISOString(),
    });

    // 8. Decrement stock atomically; deactivate at zero. `stock > 0` in the
    //    filter guards the concurrent-buyer race at the database level.
    const stockRes = await fetch(
      `${SUPABASE_URL}/rest/v1/market_listings?id=eq.${listing.id}&stock_quantity=gt.0`,
      {
        method: "PATCH",
        headers: { ...auth, "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify({
          stock_quantity: listing.stock_quantity - 1,
          is_active: listing.stock_quantity - 1 > 0 ? listing.is_active : false,
        }),
      },
    );
    const stockRows = (await stockRes.json()) as ListingRow[];
    if (!stockRes.ok || stockRows.length === 0) {
      // Concurrent buyer won the race — refund path / ops review.
      return json({ error: "stock_conflict", detail: "another buyer claimed the last unit" }, 409);
    }

    // 9. Receipts: merchant payout leg + treasury fee leg.
    await upsertPayment({
      identifier: payoutId,
      user_uid: shop.pi_uid,
      amount: merchantAmount,
      memo: payoutMemo,
      metadata: {
        product: "market_merchant_payout",
        direction: "a2u_payout",
        listing_id: listing.id,
        buyer_payment_id: payment.identifier,
        shop_id: shop.id,
        // Sales-summary enrichment: lets the merchant reconstruct their
        // gross/fee/net economics from their own payout receipts (RLS).
        gross_amount: price,
        platform_fee: fee,
        listing_title: listing.title,
      },
      status: "approved",
      network: approved.network ?? payment.network,
    });
    if (fee > 0) {
      await upsertPayment({
        identifier: `fee-${payment.identifier}`,
        user_uid: TREASURY_PI_UID,
        amount: fee,
        memo: `PitchMarket maintenance fee — ${listing.title}`.slice(0, 60),
        metadata: {
          product: "market_platform_fee",
          direction: "treasury",
          listing_id: listing.id,
          buyer_payment_id: payment.identifier,
        },
        status: "approved",
        network: payment.network,
      });
    }

    return json({
      ok: true,
      listingId: listing.id,
      remainingStock: stockRows[0].stock_quantity,
      split: { total: price, merchantAmount, platformFee: fee, merchantPayoutId: payoutId },
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

async function one<T>(url: string): Promise<T | null> {
  const res = await fetch(url, { headers: authHeaders() });
  const rows = (await res.json()) as T[];
  return rows.length > 0 ? rows[0] : null;
}

async function upsertPayment(row: Record<string, unknown>): Promise<void> {
  await fetch(`${SUPABASE_URL}/rest/v1/pi_payments`, {
    method: "POST",
    headers: {
      ...authHeaders(),
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates",
    },
    body: JSON.stringify(row),
  });
}

function authHeaders(): Record<string, string> {
  return {
    Authorization: `Bearer ${SERVICE_KEY}`,
    apikey: SERVICE_KEY,
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
