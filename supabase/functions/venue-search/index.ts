// 会場名の候補を探すプロキシ。API キーをアプリに埋め込まないためにサーバー側で保持する。
// Google Places API (New) の Autocomplete を使う。必要なシークレット: GOOGLE_PLACES_API_KEY
//   キーは Google Cloud で「Places API (New)」だけに絞り、アプリ制限は付けない
//   （Edge Functions は固定 IP を持たず、リファラも送らないため）。
//
// 課金は Autocomplete のリクエスト単位。入力途中の検索が何度も飛ぶので
// - アプリ側で入力をデバウンスする
// - 同じ検索はワーカーのメモリで使い回す
// - セッショントークンを受け取り、1 回の入力〜確定をまとめて数えさせる
// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const PLACES_AUTOCOMPLETE_ENDPOINT =
  "https://places.googleapis.com/v1/places:autocomplete"
const REQUEST_TIMEOUT_MS = 8000
const MIN_QUERY_LENGTH = 2
const MAX_QUERY_LENGTH = 100
const MAX_RESULTS = 5
// 入力途中の検索が続くので、同じ検索は使い回す。ワーカーが生きている間だけのキャッシュ
const CACHE_TTL_MS = 60 * 60 * 1000
const MAX_CACHE_ENTRIES = 500

// 会場は建物や施設なので、住所や地名そのものは候補から外す
const INCLUDED_PRIMARY_TYPES = ["establishment"]

// Google を呼ぶ検索（キャッシュに当たらなかった分）の 1 日あたりの上限。課金を抑えるため。
// 匿名アカウントは作り直せるので、ユーザー別とは別に全ユーザー合計も数える（環境変数で変えられる）
function limitFromEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name))
  return Number.isInteger(value) && value > 0 ? value : fallback
}
const DAILY_LIMIT_PER_ANONYMOUS_USER = limitFromEnv(
  "VENUE_SEARCH_DAILY_LIMIT_ANONYMOUS",
  60,
)
const DAILY_LIMIT_PER_USER = limitFromEnv("VENUE_SEARCH_DAILY_LIMIT_USER", 150)
const DAILY_LIMIT_TOTAL = limitFromEnv("VENUE_SEARCH_DAILY_LIMIT_TOTAL", 300)

const searchCache = new Map<string, { venues: unknown[]; at: number }>()

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

/** キャッシュのキー用。全角半角・大文字小文字・空白の違いをまとめる。 */
function normalizeKey(value: string): string {
  return value.normalize("NFKC").toLowerCase().trim().replace(/\s+/g, " ")
}

function cached(key: string): unknown[] | null {
  const hit = searchCache.get(key)
  if (!hit) return null
  searchCache.delete(key)
  if (Date.now() - hit.at > CACHE_TTL_MS) return null
  searchCache.set(key, hit)
  return hit.venues
}

function remember(key: string, venues: unknown[]) {
  searchCache.set(key, { venues, at: Date.now() })
  if (searchCache.size > MAX_CACHE_ENTRIES) {
    searchCache.delete(searchCache.keys().next().value)
  }
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null
  const t = value.trim()
  return t ? t : null
}

/**
 * 候補の補足に出す住所。
 *
 * Places の secondaryText は「日本、〒105-0011 東京都港区…」のように長いので、
 * 国名と郵便番号を落として都道府県から出す。
 */
function shortAddress(value: unknown): string | null {
  const raw = text(value)
  if (!raw) return null
  return text(
    raw
      .replace(/^日本[、,]\s*/, "")
      .replace(/^〒?\s*\d{3}-?\d{4}\s*/, ""),
  )
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // publishable key だけの呼び出しはゲートウェイの verify_jwt を通過してしまうため、
  // セッションのユーザーを必ずここで検証する（API の上限を第三者に消費させない）
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "")
  if (!token) {
    return json({ error: "unauthorized" }, 401)
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  )
  const { data: userData, error: userError } = await supabase.auth.getUser(
    token,
  )
  if (userError || !userData?.user) {
    return json({ error: "unauthorized" }, 401)
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }
  const query = typeof payload?.query === "string" ? payload.query.trim() : ""
  if (
    query.length < MIN_QUERY_LENGTH || query.length > MAX_QUERY_LENGTH
  ) {
    return json({ error: "invalid_query" }, 400)
  }
  // 1 回の入力〜確定をまとめて数えさせるためのトークン。無くても検索はできる
  const sessionToken = text(payload?.sessionToken)

  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY")
  if (!apiKey) {
    return json({ error: "venue_search_not_configured" }, 503)
  }

  const cacheKey = normalizeKey(query)
  const hit = cached(cacheKey)
  if (hit) return json({ venues: hit })

  // キャッシュに当たらず Google を呼ぶ前に、上限を数える
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const { data: quota, error: quotaError } = await admin.rpc(
    "consume_venue_search_quota",
    {
      p_user_id: userData.user.id,
      p_user_limit: userData.user.is_anonymous
        ? DAILY_LIMIT_PER_ANONYMOUS_USER
        : DAILY_LIMIT_PER_USER,
      p_global_limit: DAILY_LIMIT_TOTAL,
    },
  )
  if (quotaError) {
    console.error("quota check failed", quotaError)
    return json({ error: "venue_search_upstream_error" }, 500)
  }
  if (quota === "user_limit") {
    return json({ error: "venue_search_daily_limit" }, 429)
  }
  if (quota !== "ok") {
    return json({ error: "venue_search_global_limit" }, 429)
  }

  try {
    const res = await fetch(PLACES_AUTOCOMPLETE_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        // 課金は返すフィールドではなくリクエスト単位だが、要る分だけに絞る
        "X-Goog-FieldMask":
          "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat",
      },
      body: JSON.stringify({
        input: query,
        languageCode: "ja",
        regionCode: "JP",
        includedRegionCodes: ["jp"],
        includedPrimaryTypes: INCLUDED_PRIMARY_TYPES,
        ...(sessionToken ? { sessionToken } : {}),
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
    if (res.status === 429) {
      await res.body?.cancel()
      return json({ error: "venue_search_rate_limited" }, 429)
    }
    if (!res.ok) {
      console.error("places autocomplete error", res.status, await res.text())
      return json({ error: "venue_search_upstream_error" }, 502)
    }
    const data = await res.json()

    const venues = []
    const seen = new Set<string>()
    for (const s of data?.suggestions ?? []) {
      const p = s?.placePrediction
      const placeId = text(p?.placeId)
      const name = text(p?.structuredFormat?.mainText?.text)
      if (!placeId || !name) continue
      // 同じ施設が別の placeId で並ぶことがあるので、名前でまとめる
      const key = normalizeKey(name)
      if (seen.has(key)) continue
      seen.add(key)
      venues.push({
        placeId,
        name,
        address: shortAddress(p?.structuredFormat?.secondaryText?.text),
      })
      if (venues.length >= MAX_RESULTS) break
    }

    remember(cacheKey, venues)
    return json({ venues })
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("venue search failed", e)
    return json(
      {
        error: timedOut
          ? "venue_search_timeout"
          : "venue_search_upstream_error",
      },
      timedOut ? 504 : 502,
    )
  }
})
