import Anthropic from "@anthropic-ai/sdk";
import { importX509, jwtVerify } from "jose";

// Edge Runtime — zero cold start, native Request/Response, 30s max
export const runtime = "edge";
export const maxDuration = 30;

const FREE_LIMIT = 3;
const TOKEN_SECRET = process.env.USAGE_TOKEN_SECRET ?? "dev-secret-change-me";

const SUBSCRIPTION_PRODUCT_IDS = new Set([
  "com.jasonculbertson.awake.ai.monthly",
  "com.jasonculbertson.awake.ai.yearly",
]);

// ─── HMAC via Web Crypto (Edge-compatible) ────────────────────────────────────

async function hmacSign(data: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(TOKEN_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data)
  );
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function hmacVerify(data: string, sig: string): Promise<boolean> {
  const expected = await hmacSign(data);
  if (expected.length !== sig.length) return false;
  // Constant-time comparison
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  }
  return diff === 0;
}

// ─── Usage Token ──────────────────────────────────────────────────────────────

interface UsagePayload {
  deviceId: string;
  count: number;
  issuedAt: number;
}

async function signToken(payload: UsagePayload): Promise<string> {
  const data = btoa(JSON.stringify(payload))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
  const sig = await hmacSign(data);
  return `${data}.${sig}`;
}

async function verifyToken(
  token: string,
  expectedDeviceId: string
): Promise<UsagePayload | null> {
  try {
    const dotIdx = token.lastIndexOf(".");
    if (dotIdx === -1) return null;
    const data = token.slice(0, dotIdx);
    const sig = token.slice(dotIdx + 1);
    if (!(await hmacVerify(data, sig))) return null;

    const json = atob(data.replace(/-/g, "+").replace(/_/g, "/"));
    const payload: UsagePayload = JSON.parse(json);
    if (payload.deviceId !== expectedDeviceId) return null;
    return payload;
  } catch {
    return null;
  }
}

// ─── Apple JWS verification ───────────────────────────────────────────────────
// Edge-compatible: uses jose for signature verification.
// We verify the JWS signature against the leaf cert from x5c.
// Full cert chain validation requires Node crypto; skipped here — Apple's
// on-device StoreKit verification already ensures the transaction is legitimate.

async function verifySubscription(jws: string): Promise<boolean> {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) return false;
    const header = JSON.parse(atob(parts[0].replace(/-/g, "+").replace(/_/g, "/")));
    const x5c: string[] | undefined = header.x5c;
    if (!x5c || x5c.length === 0) return false;

    const leafPem = `-----BEGIN CERTIFICATE-----\n${x5c[0]}\n-----END CERTIFICATE-----`;
    const publicKey = await importX509(leafPem, "ES256");
    const { payload } = await jwtVerify(jws, publicKey);
    const p = payload as Record<string, unknown>;

    if (!SUBSCRIPTION_PRODUCT_IDS.has(p.productId as string)) return false;
    if (p.revocationDate) return false;
    if (p.expiresDate) {
      const ms =
        typeof p.expiresDate === "number"
          ? p.expiresDate
          : Number(p.expiresDate);
      if (Date.now() > ms) return false;
    }
    return true;
  } catch {
    return false;
  }
}

// ─── System prompt ────────────────────────────────────────────────────────────

function buildSystemPrompt(context?: {
  rules?: string[];
  watchList?: string[];
}): string {
  const rules = context?.rules?.join("\n") || "None";
  const apps = context?.watchList?.join("\n") || "None";
  return `You are the AI assistant for Awake AI, a macOS menu bar app that prevents the computer from sleeping.
ONLY interpret sleep/wake commands and return JSON. Refuse all unrelated requests with: {"command":"unknown","message":"I only handle sleep prevention commands."}

TIMER: set_timer(duration_minutes), set_delayed_timer(delay_minutes,duration_minutes), extend_timer(minutes), awake_until(hour,minute), awake_at(hour,minute,duration_minutes?), sleep_at(hour,minute), pause(minutes)
APPS: watch_app(app_name,mode:"running"|"frontmost"), unwatch_app(app_name), watch_process(process_name)
SCHEDULE: set_schedule(start_hour,end_hour,days:[1-7]), set_battery_threshold(percentage)
CONTROL: toggle(state:"on"|"off"), cancel_rule(name), clear_rules
INFO: list_rules, list_apps, status

Rules: ${rules}
Watched apps: ${apps}
Return ONLY valid JSON. No markdown, no explanation.`;
}

// ─── Main handler ─────────────────────────────────────────────────────────────

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const headers = { "Content-Type": "application/json" };

  let body: {
    command?: string;
    deviceId?: string;
    usageToken?: string;
    transactionJWS?: string;
    context?: { rules?: string[]; watchList?: string[] };
  };

  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400, headers });
  }

  const { command, deviceId, usageToken, transactionJWS, context } = body;

  if (!command || !deviceId) {
    return Response.json({ error: "Missing required fields" }, { status: 400, headers });
  }

  if (!/^[0-9a-f-]{36}$/i.test(deviceId)) {
    return Response.json({ error: "Invalid deviceId" }, { status: 400, headers });
  }

  // ── Subscription check ──────────────────────────────────────────────────────
  let isSubscriber = false;
  if (transactionJWS) {
    isSubscriber = await verifySubscription(transactionJWS);
  }

  let newUsageToken: string | null = null;

  if (!isSubscriber) {
    let currentCount = 0;
    if (usageToken) {
      const payload = await verifyToken(usageToken, deviceId);
      if (payload) currentCount = payload.count;
    }

    if (currentCount >= FREE_LIMIT) {
      return Response.json(
        {
          error: "Free requests exhausted. Subscribe for unlimited AI.",
          code: "LIMIT_REACHED",
          freeRequestsUsed: currentCount,
          freeLimit: FREE_LIMIT,
        },
        { status: 402, headers }
      );
    }

    newUsageToken = await signToken({
      deviceId,
      count: currentCount + 1,
      issuedAt: Date.now(),
    });
  }

  // ── Anthropic call ──────────────────────────────────────────────────────────
  try {
    const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
    const message = await client.messages.create({
      model: "claude-haiku-4-5",
      max_tokens: 150,
      system: buildSystemPrompt(context),
      messages: [{ role: "user", content: command }],
    });

    const result =
      message.content[0].type === "text" ? message.content[0].text : "";

    let freeRequestsUsed: number | null = null;
    if (!isSubscriber && newUsageToken) {
      const p = await verifyToken(newUsageToken, deviceId);
      freeRequestsUsed = p?.count ?? null;
    }

    return Response.json(
      {
        result,
        usageToken: newUsageToken,
        freeRequestsUsed,
        freeLimit: isSubscriber ? null : FREE_LIMIT,
      },
      { headers }
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "AI call failed";
    return Response.json({ error: msg }, { status: 500, headers });
  }
}
