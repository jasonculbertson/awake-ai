export const maxDuration = 10;

export default function handler(req: Request): Response {
  return Response.json({
    ok: true,
    timestamp: new Date().toISOString(),
    hasAnthropicKey: !!process.env.ANTHROPIC_API_KEY,
    hasTokenSecret: !!process.env.USAGE_TOKEN_SECRET,
  });
}
