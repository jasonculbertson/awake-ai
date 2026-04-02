import type { VercelRequest, VercelResponse } from "@vercel/node";
import { importX509, jwtVerify } from "jose";
import { X509Certificate } from "crypto";

const SUBSCRIPTION_PRODUCT_IDS = new Set([
  "com.jasonculbertson.awake.ai.pro",
  "com.jasonculbertson.awake.ai.monthly",
  "com.jasonculbertson.awake.ai.yearly",
]);

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
    const header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
    const x5c: string[] | undefined = header.x5c;
    if (!x5c || x5c.length < 2) return false;
    const toPem = (der: string) => `-----BEGIN CERTIFICATE-----\n${der}\n-----END CERTIFICATE-----`;
    const rootCert = new X509Certificate(APPLE_ROOT_CA_G3);
    const intCert = new X509Certificate(toPem(x5c[1]));
    const leafCert = new X509Certificate(toPem(x5c[0]));
    if (!intCert.verify(rootCert.publicKey)) return false;
    if (!leafCert.verify(intCert.publicKey)) return false;
    const publicKey = await importX509(toPem(x5c[0]), "ES256");
    const { payload } = await jwtVerify(jws, publicKey);
    const p = payload as Record<string, unknown>;
    if (!SUBSCRIPTION_PRODUCT_IDS.has(p.productId as string)) return false;
    if (p.revocationDate) return false;
    if (p.expiresDate) {
      const ms = typeof p.expiresDate === "number" ? p.expiresDate : Number(p.expiresDate);
      if (Date.now() > ms) return false;
    }
    return true;
  } catch { return false; }
}

// ─── System prompt ────────────────────────────────────────────────────────────

function buildSystemPrompt(context?: { rules?: string[]; watchList?: string[] }): string {
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

// ─── Handler ──────────────────────────────────────────────────────────────────

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { command, deviceId, transactionJWS, context } = req.body ?? {};

  if (!command || !deviceId) {
    return res.status(400).json({ error: "Missing required fields" });
  }

  if (typeof command !== "string" || command.length > 500) {
    return res.status(400).json({ error: "Command too long (max 500 characters)" });
  }

  if (!/^[0-9a-f-]{36}$/i.test(deviceId)) {
    return res.status(400).json({ error: "Invalid deviceId" });
  }

  // ── Subscription required ──────────────────────────────────────────────────
  if (!transactionJWS) {
    return res.status(402).json({ error: "Subscription required.", code: "SUBSCRIPTION_REQUIRED" });
  }

  const isSubscriber = await verifySubscription(transactionJWS);
  if (!isSubscriber) {
    return res.status(402).json({ error: "Active subscription required.", code: "SUBSCRIPTION_REQUIRED" });
  }

  // ── Anthropic call ─────────────────────────────────────────────────────────
  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": process.env.ANTHROPIC_API_KEY ?? "",
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 150,
        system: buildSystemPrompt(context),
        messages: [{ role: "user", content: command }],
      }),
    });

    const data = await response.json() as Record<string, unknown>;

    if (!response.ok) {
      const errMsg = (data?.error as Record<string, unknown>)?.message ?? `HTTP ${response.status}`;
      return res.status(500).json({ error: String(errMsg) });
    }

    const content = data.content as Array<{ type: string; text: string }>;
    const result = content?.[0]?.type === "text" ? content[0].text : "";

    return res.json({ result });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "AI call failed";
    console.error("AI call error:", msg);
    return res.status(500).json({ error: msg });
  }
}
