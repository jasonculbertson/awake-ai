import Anthropic from "@anthropic-ai/sdk";
import { kv } from "@vercel/kv";
import { importX509, jwtVerify } from "jose";
import { X509Certificate } from "crypto";

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const FREE_LIMIT = 3;

// Apple Root CA G3 — used to verify StoreKit JWS transaction signatures
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

const SUBSCRIPTION_PRODUCT_IDS = new Set([
  "com.jasonculbertson.awake.ai.monthly",
  "com.jasonculbertson.awake.ai.yearly",
  "com.jasonculbertson.awake.ai.pro",
]);

// Verify Apple StoreKit JWS transaction and return payload if valid subscription
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

    // Verify cert chain: leaf ← intermediate ← Apple Root CA G3
    const rootCert = new X509Certificate(APPLE_ROOT_CA_G3);
    const intCert = new X509Certificate(intPem);
    const leafCert = new X509Certificate(leafPem);

    if (!intCert.verify(rootCert.publicKey)) return false;
    if (!leafCert.verify(intCert.publicKey)) return false;

    // Verify JWS signature
    const publicKey = await importX509(leafPem, "ES256");
    const { payload } = await jwtVerify(jws, publicKey);

    const p = payload as Record<string, unknown>;

    // Check it's one of our subscription products
    if (!SUBSCRIPTION_PRODUCT_IDS.has(p.productId as string)) return false;

    // Check not revoked
    if (p.revocationDate) return false;

    // For subscriptions, check expiry
    if (p.expiresDate) {
      const expiresMs =
        typeof p.expiresDate === "number" ? p.expiresDate : Number(p.expiresDate);
      if (Date.now() > expiresMs) return false;
    }

    return true;
  } catch {
    return false;
  }
}

function buildSystemPrompt(context?: {
  rules?: string[];
  watchList?: string[];
}): string {
  const rules = context?.rules?.join("\n") || "None";
  const apps = context?.watchList?.join("\n") || "None";

  return `You are the AI assistant for Awake AI, a macOS menu bar app that prevents the computer from sleeping.
Your ONLY job is to interpret sleep/wake commands and return structured JSON.
Refuse any request unrelated to sleep prevention. For off-topic requests return: {"command":"unknown","message":"I can only help with sleep prevention commands."}

TIMER COMMANDS:
- {"command":"set_timer","duration_minutes":<int>}
- {"command":"set_delayed_timer","delay_minutes":<int>,"duration_minutes":<int>}
- {"command":"extend_timer","minutes":<int>}
- {"command":"awake_until","hour":<0-23>,"minute":<0-59>}
- {"command":"awake_at","hour":<0-23>,"minute":<0-59>,"duration_minutes":<int|null>}
- {"command":"sleep_at","hour":<0-23>,"minute":<0-59>}
- {"command":"pause","minutes":<int>}

APP COMMANDS:
- {"command":"watch_app","app_name":"<string>","mode":"running"|"frontmost"}
- {"command":"unwatch_app","app_name":"<string>"}
- {"command":"watch_process","process_name":"<string>"}

SCHEDULE/BATTERY:
- {"command":"set_schedule","start_hour":<int>,"end_hour":<int>,"days":[<1-7>]}
- {"command":"set_battery_threshold","percentage":<int>}

CONTROL:
- {"command":"toggle","state":"on"|"off"}
- {"command":"cancel_rule","name":"<string>"}
- {"command":"clear_rules"}

INFO:
- {"command":"list_rules"}
- {"command":"list_apps"}
- {"command":"status"}

Current rules: ${rules}
Watched apps: ${apps}

Respond with ONLY valid JSON. No markdown, no explanation.`;
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // CORS for macOS app
  const headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
  };

  let body: {
    command?: string;
    deviceId?: string;
    transactionJWS?: string;
    context?: { rules?: string[]; watchList?: string[] };
  };

  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400, headers });
  }

  const { command, deviceId, transactionJWS, context } = body;

  if (!command || !deviceId) {
    return Response.json(
      { error: "Missing required fields" },
      { status: 400, headers }
    );
  }

  // Sanitize deviceId (UUID format only)
  if (!/^[0-9a-f-]{36}$/i.test(deviceId)) {
    return Response.json({ error: "Invalid deviceId" }, { status: 400, headers });
  }

  // Check subscription
  let isSubscriber = false;
  if (transactionJWS) {
    isSubscriber = await verifySubscription(transactionJWS);
  }

  // If not subscriber, enforce free limit
  let freeRequestsUsed = 0;
  if (!isSubscriber) {
    const kvKey = `usage:${deviceId}`;
    const count = (await kv.get<number>(kvKey)) ?? 0;
    freeRequestsUsed = count;

    if (count >= FREE_LIMIT) {
      return Response.json(
        {
          error: "Free requests exhausted. Subscribe for unlimited AI.",
          code: "LIMIT_REACHED",
          freeRequestsUsed: count,
          freeLimit: FREE_LIMIT,
        },
        { status: 402, headers }
      );
    }

    // Increment usage
    await kv.set(kvKey, count + 1, { ex: 60 * 60 * 24 * 365 }); // 1 year TTL
    freeRequestsUsed = count + 1;
  }

  // Make AI call using Haiku (cheapest, plenty capable for JSON commands)
  try {
    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 150,
      system: buildSystemPrompt(context),
      messages: [{ role: "user", content: command }],
    });

    const text =
      message.content[0].type === "text" ? message.content[0].text : "";

    return Response.json(
      {
        result: text,
        freeRequestsUsed: isSubscriber ? null : freeRequestsUsed,
        freeLimit: isSubscriber ? null : FREE_LIMIT,
      },
      { headers }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "AI call failed";
    return Response.json({ error: message }, { status: 500, headers });
  }
}
