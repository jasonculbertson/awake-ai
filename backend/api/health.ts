import type { VercelRequest, VercelResponse } from "@vercel/node";

export default async function handler(_req: VercelRequest, res: VercelResponse) {
  // Test outbound connectivity to Anthropic
  let anthropicReachable = false;
  let anthropicError = "";
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": process.env.ANTHROPIC_API_KEY ?? "", "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: "claude-haiku-4-5", max_tokens: 10, messages: [{ role: "user", content: "hi" }] }),
    });
    anthropicReachable = true;
    anthropicError = `HTTP ${r.status}`;
  } catch (e: unknown) {
    anthropicError = e instanceof Error ? e.message : String(e);
  }

  res.json({
    ok: true,
    timestamp: new Date().toISOString(),
    hasAnthropicKey: !!process.env.ANTHROPIC_API_KEY,
    hasTokenSecret: !!process.env.USAGE_TOKEN_SECRET,
    anthropicReachable,
    anthropicError,
    nodeVersion: process.version,
  });
}
