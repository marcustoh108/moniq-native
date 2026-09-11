// Supabase Edge Function: ai-chat
//
// Holds the shared Anthropic API key as a server-side secret (ANTHROPIC_API_KEY) —
// it never reaches the client, so it can't be extracted from the app and abused.
// Enforces a monthly per-user question cap via the increment_ai_usage() Postgres
// function (see household-schema.sql), which is the real enforcement boundary —
// this function trusts nothing the client claims about its own usage.
//
// Deploy with: supabase functions deploy ai-chat
// Required secrets (set via `supabase secrets set`):
//   ANTHROPIC_API_KEY   — your Anthropic API key (server-side only, never sent to clients)
//   MONTHLY_QUESTION_CAP — optional, defaults to 40 if unset

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-haiku-4-5-20251001"; // cheapest current model — keeps per-question cost low
const MAX_TOKENS = 500; // caps output cost per question; answers here should be short anyway
const DEFAULT_CAP = 40;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header — sign in to use included AI questions." }, 401);
    }

    // Client bound to the caller's own JWT, so auth.uid() inside increment_ai_usage()
    // resolves to the actual signed-in user — not something the client can spoof.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { question, financialSummary } = await req.json();
    if (!question || typeof question !== "string" || !question.trim()) {
      return json({ error: "No question provided." }, 400);
    }
    if (question.length > 2000) {
      return json({ error: "Question is too long." }, 400);
    }

    const cap = parseInt(Deno.env.get("MONTHLY_QUESTION_CAP") ?? "") || DEFAULT_CAP;

    // Atomic check-and-increment — this is the actual rate limit. If two requests
    // race, Postgres row locking in increment_ai_usage() serializes them correctly.
    const { data: usageRows, error: usageError } = await supabase.rpc("increment_ai_usage", {
      p_limit: cap,
    });
    if (usageError) {
      console.error("increment_ai_usage error:", usageError);
      return json({ error: "Could not verify usage — try again." }, 500);
    }
    const usage = usageRows?.[0];
    if (!usage || !usage.allowed) {
      return json(
        {
          error: "monthly_cap_reached",
          message: `You've used all ${cap} included AI questions this month. It resets on the 1st, or switch to your own API key in Settings for unlimited use.`,
          currentCount: usage?.current_count ?? cap,
          limit: cap,
        },
        429
      );
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      console.error("ANTHROPIC_API_KEY secret is not set on this Edge Function.");
      return json({ error: "AI feature is not configured on the server yet." }, 500);
    }

    const systemPrompt =
      "You are a helpful, concise financial assistant inside the MonIQ budgeting app. " +
      "Answer using only the user's data below. Keep answers short — a few sentences, " +
      "not a report. If the data doesn't cover what's asked, say so plainly.\n\n" +
      (financialSummary || "(no financial summary provided)");

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: systemPrompt,
        messages: [{ role: "user", content: question.trim() }],
      }),
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      console.error("Anthropic API error:", anthropicRes.status, errText);
      return json({ error: "The AI service didn't respond correctly — try again shortly." }, 502);
    }

    const data = await anthropicRes.json();
    const textBlock = (data.content || []).find((b: { type: string }) => b.type === "text");

    return json({
      answer: textBlock?.text || "I couldn't generate a response.",
      currentCount: usage.current_count,
      limit: cap,
    });
  } catch (e) {
    console.error("ai-chat unexpected error:", e);
    return json({ error: "Something went wrong — try again." }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
