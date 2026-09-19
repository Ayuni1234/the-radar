// Supabase Edge Function: pi-session
//
// STEP 2 of the Pi authentication flow, executed SERVER-SIDE (per the
// authentication guide: with any server-side code present, the exchange
// happens there — exactly once per sign-in, never in the browser too).
//
// 1. Exchanges the browser-obtained Pi accessToken with App Studio, which
//    verifies it against the Pi Platform. The uid/username App Studio
//    returns are the only identity this app trusts.
// 2. Provisions a Supabase auth user whose app_metadata.pi_uid IS that
//    verified uid (deterministic UUID via UUIDv5, so re-signing-in finds
//    the same user) and issues a one-time magic token.
// 3. Records the verified sign-in in public.pi_sessions.
//
// The client completes sign-in with `verifyOTP(...)` and gets a real
// Supabase session — so auth.uid() / app_metadata.pi_uid drive every RLS
// policy. No Pi API key is needed for the App Studio call.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const APP_STUDIO_LOGIN_URL =
  "https://backend.appstudio-u7cm9zhmha0ruwv8.piappengine.com/pi/auth/v1/login";

// RFC 4122 DNS namespace — public constant, used to derive a stable UUID
// for each verified Pi uid.
const UUID_NAMESPACE = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";

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
    const { accessToken } = await req.json();
    if (!accessToken) {
      return json({ error: "accessToken is required" }, 400);
    }

    // 1. Server-side App Studio exchange (the only trusted identity source).
    const exRes = await fetch(APP_STUDIO_LOGIN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ accessToken }),
    });
    if (!exRes.ok) {
      return json(
        { error: "app_studio_rejected", status: exRes.status },
        401,
      );
    }
    const verified = await exRes.json();
    const piUid: unknown = verified?.user?.uid;
    const piUsername: string = verified?.user?.username ?? "";
    const sessionToken: string = verified?.sessionToken ?? "";
    if (typeof piUid !== "string" || piUid.length === 0) {
      return json({ error: "app_studio_missing_uid" }, 502);
    }

    // 2. Provision the Supabase auth user keyed on the VERIFIED uid.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const email = `${piUid.toLowerCase()}@pi.users.radar`;
    const appMetadata = { provider: "pi", pi_uid: piUid };
    const password = crypto.randomUUID() + crypto.randomUUID();

    const { error: createErr } = await admin.auth.admin.createUser({
      // Deterministic id derived from the verified Pi uid (UUIDv5) — the
      // cast keeps compiles honest on runtimes that don't type the field.
      ...({ id: await uuidv5(piUid) } as object),
      email,
      password,
      email_confirm: true,
      app_metadata: appMetadata,
      user_metadata: { pi_username: piUsername },
    } as Parameters<typeof admin.auth.admin.createUser>[0]);

    if (createErr) {
      const msg = String(createErr.message);
      if (!msg.includes("already") && createErr.status !== 422) {
        return json({ error: "supabase_user_create_failed", detail: msg }, 500);
      }
      // Existing user: make sure the identity metadata is current.
      const { data: listed } = await admin.auth.admin.listUsers({
        page: 1,
        perPage: 1000,
      });
      const existing = listed?.users?.find((u) => u.email === email);
      if (!existing) {
        return json({ error: "supabase_user_lookup_failed" }, 500);
      }
      await admin.auth.admin.updateUserById(existing.id, {
        app_metadata: appMetadata,
        user_metadata: { pi_username: piUsername },
      });
    }

    // Issue a one-time token the client exchanges for a real session via
    // `auth.verifyOTP(...)` (magic-link OTP).
    const { data: link, error: linkErr } = await admin.auth.admin
      .generateLink({ type: "magiclink", email });
    if (linkErr || !link?.properties?.email_otp) {
      return json(
        { error: "supabase_generate_link_failed", detail: String(linkErr) },
        500,
      );
    }

    // 3. Audit the verified sign-in (service role, bypasses RLS).
    await admin.from("pi_sessions").insert({
      pi_uid: piUid,
      username: piUsername,
      session_token: sessionToken,
    });

    return json({
      ok: true,
      user: { uid: piUid, username: piUsername },
      sessionToken,
      magic: { email, token: link.properties.email_otp },
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

async function uuidv5(name: string): Promise<string> {
  const hex = UUID_NAMESPACE.replaceAll("-", "");
  const ns = new Uint8Array(hex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const payload = new TextEncoder().encode(name);
  const data = new Uint8Array(ns.length + payload.length);
  data.set(ns);
  data.set(payload, ns.length);

  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  digest[6] = (digest[6] & 0x0f) | 0x50; // version 5
  digest[8] = (digest[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = [...digest.slice(0, 16)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(
    16,
    20,
  )}-${h.slice(20, 32)}`;
}
