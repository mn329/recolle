// Google Places API (New) のテキスト検索のプロキシ。API キーをアプリに埋め込まないためにサーバー側で保持する。
// 必要なシークレット: GOOGLE_PLACES_API_KEY（Google Cloud で Places API (New) を有効にして発行）
// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const ENDPOINT = "https://places.googleapis.com/v1/places:searchText"
const REQUEST_TIMEOUT_MS = 8000
const MAX_QUERY_LENGTH = 100
const MAX_RESULTS = 5

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // publishable key だけの呼び出しは verify_jwt を通過してしまうため、ユーザーを必ずここで検証する
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "")
  if (!token) return json({ error: "unauthorized" }, 401)
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  )
  const { data: userData, error: userError } = await supabase.auth.getUser(
    token,
  )
  if (userError || !userData?.user) return json({ error: "unauthorized" }, 401)

  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY")
  if (!apiKey) return json({ error: "places_not_configured" }, 503)

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }
  const query = typeof payload?.query === "string" ? payload.query.trim() : ""
  if (!query || query.length > MAX_QUERY_LENGTH) {
    return json({ error: "invalid_query" }, 400)
  }

  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        // 必要な項目だけ要求して課金の区分を抑える
        "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress",
      },
      body: JSON.stringify({
        textQuery: query,
        languageCode: "ja",
        regionCode: "JP",
        pageSize: MAX_RESULTS,
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
    if (!res.ok) {
      console.error("places error", res.status, await res.text())
      return json({ error: "places_upstream_error" }, 502)
    }
    const data = await res.json()
    const places = (data?.places ?? [])
      .map((p: any) => ({
        id: String(p?.id ?? ""),
        name: String(p?.displayName?.text ?? ""),
        address: p?.formattedAddress ? String(p.formattedAddress) : null,
      }))
      .filter((p: any) => p.id && p.name)
    return json({ places })
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("places fetch failed", e)
    return json(
      { error: timedOut ? "places_timeout" : "places_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
