// Supabase Edge Function: bounty-payout
// Instant micro-payout of a released scout bounty: once the poster releases
// the escrow (release_bounty RPC flips the row to `completed`), this function
// pays the streamer via the Pi Platform API's App-to-User (A2U) flow:
//   POST /v2/payments — with a2u profession + recipient uid, then approve.
// The payout is idempotent: re-invoking a bounty that already has a
// released_payment_id returns the existing result instead of double-paying.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PI_API_KEY = Deno.env.get("PI_API_KEY") ?? Deno.env.get("PI_NETWORK_API_KEY");
const PI_API_BASE = Deno.env.get("PI_API_BASE") ?? "https://api.minepi.com/v2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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
    if (!PI_API_KEY) {
      return json({ error: "server_not_configured" }, 500);
    }
    const { bountyId } = await req.json();
    if (!bountyId) return json({ error: "bountyId is required" }, 400);

    // 1. Load the bounty (service role, bypasses RLS).
    const bountyRes = await fetch(
      `${SUPABASE_URL}/rest/v1/stream_bounties?id=eq.${bountyId}&select=*`,
      { headers: authHeaders() },
    );
    const bounties = await bountyRes.json();
    const bounty = (bounties as Record<string, unknown>[])[0];
    if (!bounty) return json({ error: "bounty_not_found" }, 404);
    if (bounty.status !== "completed") {
      return json(
        { error: "not_releasable", detail: `status=${bounty.status}` },
        409,
      );
    }

    // 2. Idempotency: already paid.
    if (bounty.released_payment_id) {
      return json({
        ok: true,
        alreadyPaid: true,
        paymentId: bounty.released_payment_id,
      });
    }

    // 3. Resolve the streamer's Pi uid (profiles.pi_uid).
    const streamerId = bounty.streamer_profile_id as string | null;
    if (!streamerId) {
      return json({ error: "no_streamer" }, 409);
    }
    const profRes = await fetch(
      `${SUPABASE_URL}/rest/v1/profiles?id=eq.${streamerId}&select=pi_uid,username`,
      { headers: authHeaders() },
    );
    const profs = await profRes.json();
    const profile = (profs as Record<string, unknown>[])[0];
    const piUid = profile?.pi_uid as string | null;
    if (!piUid) return json({ error: "streamer_has_no_pi_uid" }, 409);

    const amount = bounty.amount_pi as number;
    const memo = `Bounty payout: ${(bounty.title as string).slice(0, 60)}`;

    // 4. Create the A2U payment server-side.
    //    pi_uid is masked in the response per Pi docs; we echo our own copy.
    const createRes = await fetch(`${PI_API_BASE}/payments`, {
      method: "POST",
      headers: {
        Authorization: `Key ${PI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount,
        memo,
        metadata: { product: "bounty_payout", bounty_id: bountyId },
        recipient: { "user_uid": piUid },
        a2u_profession: "FOOTBALL_PLAYER",
      }),
    });
    const created = await createRes.json();
    if (!createRes.ok) {
      return json({ error: "a2u_create_failed", detail: created }, createRes.status);
    }
    const paymentId = created.identifier as string;

    // 5. Approve it (A2U requires server approval too).
    const approveRes = await fetch(
      `${PI_API_BASE}/payments/${paymentId}/approve`,
      {
        method: "POST",
        headers: {
          Authorization: `Key ${PI_API_KEY}`,
          "Content-Type": "application/json",
        },
      },
    );
    const approved = await approveRes.json();
    if (!approveRes.ok) {
      return json({ error: "a2u_approve_failed", detail: approved }, approveRes.status);
    }

    // 6. Record the payout against the bounty (idempotency anchor).
    await fetch(
      `${SUPABASE_URL}/rest/v1/stream_bounties?id=eq.${bountyId}`,
      {
        method: "PATCH",
        headers: { ...authHeaders(), "Content-Type": "application/json",
          Prefer: "return=minimal" },
        body: JSON.stringify({ released_payment_id: paymentId }),
      },
    );

    // 7. Mirror into pi_payments as the streamer's receipt (payout ledger).
    await fetch(`${SUPABASE_URL}/rest/v1/pi_payments`, {
      method: "POST",
      headers: { ...authHeaders(), "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({
        identifier: paymentId,
        user_uid: piUid,
        amount,
        memo,
        metadata: {
          product: "bounty_payout",
          bounty_id: bountyId,
          direction: "a2u_payout",
        },
        status: "approved",
        network: approved.network ?? "Pi Network",
      }),
    });

    return json({
      ok: true,
      paymentId,
      amount,
      streamer: profile?.username ?? piUid,
      note: "A2U payout approved — Pi settles to the streamer's wallet instantly",
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

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
