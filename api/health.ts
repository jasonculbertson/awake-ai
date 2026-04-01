export const runtime = "edge";

export default function handler(_req: Request): Response {
  return Response.json({
    ok: true,
    timestamp: new Date().toISOString(),
    hasAnthropicKey: !!process.env.ANTHROPIC_API_KEY,
    hasTokenSecret: !!process.env.USAGE_TOKEN_SECRET,
  });
}
