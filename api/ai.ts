import Anthropic from "@anthropic-ai/sdk";
import { createHmac, timingSafeEqual, X509Certificate } from "crypto";
import { importX509, jwtVerify } from "jose";

// Increase Vercel function timeout (Hobby plan max = 60s)
export const maxDuration = 30;

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const FREE_LIMIT = 3;

// Used to sign usage tokens — set USAGE_TOKEN_SECRET in Vercel env vars
const TOKEN_SECRET = process.env.USAGE_TOKEN_SECRET ?? "dev-secret-change-me";

const SUBSCRIPTION_PRODUCT_IDS = new Set([
  "com.jasonculbertson.awake.ai.monthly",
  "com.jasonculbertson.awake.ai.yearly",
]);

// ─── Usage Token (no database needed) ────────────────────────────────────────
// Format: base64( JSON { deviceId, count, issuedAt } ) + "." + HMAC signature
// Signed with TOKEN_SECRET so client can't tamper with count.

interface UsagePayload {
  deviceId: string;
  count: number;
  issuedAt: number;
}

function signToken(payload: UsagePayload): string {
  const data = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = createHmac("sha256", TOKEN_SECRET).update(data).digest("base64url");
  return `${data}.${sig}`;
}

function verifyToken(token: string, expectedDeviceId: string): UsagePayload | null {
  try {
    const [data, sig] = token.split(".");
    if (!data || !sig) return null;

    const expectedSig = createHmac("sha256", TOKEN_SECRET)
      .update(data)
      .digest("base64url");

    // Constant-time comparison to prevent timing attacks
    const sigBuf = Buffer.from(sig);
    const expBuf = Buffer.from(expectedSig);
    if (sigBuf.length !== expBuf.length) return null;
    if (!timingSafeEqual(sigBuf, expBuf)) return null;

    const payload: UsagePayload = JSON.parse(
      Buffer.from(data, "base64url").toString("utf8")
    );

    // Ensure token belongs to this device
    if (payload.deviceId !== expectedDeviceId) return null;

    return payload;
  } catch {
    return null;
  }
}

// ─── Apple StoreKit JWS verification ─────────────────────────────────────────

const APPLE_ROOT_CA_G3 = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEUYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygnnkNkA/PsAs1jHKd+3C7/e0lLHJCe1n
R7bGBwI5PPXF1X1aNsXHBxPPdWcJv0G0bAKJvVLjOcFO6c8L1EiSBkOJOIp7mNAR
vAj9aCBe5GwnFlrIaaNjMGEwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6sWq0gkXYm
MB8GA1UdIwQYMBaAFLuw3qFYM4iapIqZ3r6sWq0gkXYmMA8GA1UdEwEB/wQFMAMB
Af8wDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY
2e3v9GwOAEZKuEQ7Cs/WsDsInXA3p1KpgMCCfCvnfZr0rvN73T0CHQ1DGGnNzxUF
JVFklsGHFjNXAFEIpRaV3zTD31Pj3k/WoFnJWn15MqvUUy/JaAo=
-----END CERTIFICATE-----`;

async function verifySubscription(jws: string): Promise<boolean> {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) return false;

    const header = JSON.parse(
      Buffer.from(parts[0], "base64url").toString("utf8")
    );
    const x5c: string[] | undefined = header.x5c;
    if (!x5c || x5c.length < 2) return false;

    const toPem = (der: string) =>
      `-----BEGIN CERTIFICATE-----\n${der}\n-----END CERTIFICATE-----`;

    const leafPem = toPem(x5c[0]);
    const intPem = toPem(x5c[1]);

    const rootCert = new X509Certificate(APPLE_ROOT_CA_G3);
    const intCert = new X509Certificate(intPem);
    const leafCert = new X509Certificate(leafPem);

    if (!intCert.verify(rootCert.publicKey)) return false;
    if (!leafCert.verify(intCert.publicKey)) return false;

    const publicKey = await importX509(leafPem, "ES256");
    const { payload } = await jwtVerify(jws, publicKey);
    const p = payload as Record<string, unknown>;

    if (!SUBSCRIPTION_PRODUCT_IDS.has(p.productId as string)) return false;
    if (p.revocationDate) return false;
    if (p.expiresDate) {
      const expiresMs =
        typeof p.expiresDate === "number"
          ? p.expiresDate
          : Number(p.expiresDate);
      if (Date.now() > expiresMs) return false;
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
Your ONLY job is to interpret sleep/wake commands and return structured JSON.
Refuse any request unrelated to sleep prevention. For off-topic requests return: {"command":"unknown","message":"I can only help with sleep prevention commands."}

TIMER: set_timer(duration_minutes), set_delayed_timer(delay_minutes,duration_minutes), extend_timer(minutes), awake_until(hour,minute), awake_at(hour,minute,duration_minutes?), sleep_at(hour,minute), pause(minutes)
APPS: watch_app(app_name,mode:"running"|"frontmost"), unwatch_app(app_name), watch_process(process_name)
SCHEDULE: set_schedule(start_hour,end_hour,days:[1-7]), set_battery_threshold(percentage)
CONTROL: toggle(state:"on"|"off"), cancel_rule(name), clear_rules
INFO: list_rules, list_apps, status

Current rules: ${rules}
Watched apps: ${apps}

Respond with ONLY valid JSON. No markdown, no explanation.`;
}

// ─── Handler ──────────────────────────────────────────────────────────────────

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
    return Response.json(
      { error: "Missing required fields" },
      { status: 400, headers }
    );
  }

  if (!/^[0-9a-f-]{36}$/i.test(deviceId)) {
    return Response.json(
      { error: "Invalid deviceId" },
      { status: 400, headers }
    );
  }

  // ── Auth check ──────────────────────────────────────────────────────────────

  let isSubscriber = false;
  if (transactionJWS) {
    isSubscriber = await verifySubscription(transactionJWS);
  }

  let newUsageToken: string | null = null;

  if (!isSubscriber) {
    // Verify and increment usage token
    let currentCount = 0;

    if (usageToken) {
      const payload = verifyToken(usageToken, deviceId);
      if (payload) {
        currentCount = payload.count;
      }
      // If token is invalid/tampered, treat as fresh (count=0)
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

    // Issue new signed token with incremented count
    newUsageToken = signToken({
      deviceId,
      count: currentCount + 1,
      issuedAt: Date.now(),
    });
  }

  // ── AI call ─────────────────────────────────────────────────────────────────

  try {
    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5",
      max_tokens: 150,
      system: buildSystemPrompt(context),
      messages: [{ role: "user", content: command }],
    });

    const result =
      message.content[0].type === "text" ? message.content[0].text : "";

    return Response.json(
      {
        result,
        usageToken: newUsageToken,
        freeRequestsUsed: isSubscriber ? null : (newUsageToken ? JSON.parse(Buffer.from(newUsageToken.split(".")[0], "base64url").toString()).count : FREE_LIMIT),
        freeLimit: isSubscriber ? null : FREE_LIMIT,
      },
      { headers }
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "AI call failed";
    return Response.json({ error: msg }, { status: 500, headers });
  }
}
