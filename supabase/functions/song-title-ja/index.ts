// ローマ字・英字の曲名の、日本語表記の候補を Gemini に聞く。
// アプリは返ってきた候補を iTunes で「そのアーティストの曲として実在するか」確かめてから使う。
// このため、ここでは候補を返すだけで、曲名を保証しない。
// 必要なシークレット: GEMINI_API_KEY（無料枠）。任意: GEMINI_MODEL（既定 gemini-3.5-flash-lite）
//
// 無料枠を超えないよう
// - 同じ曲はキャッシュ（song_title_cache）から返し、Gemini を呼ばない
// - Gemini を呼ぶ回数を、ユーザー別・全体の両方で 1 日ごとに数える（consume_song_title_quota）
//   上限は環境変数で変えられる（SONG_TITLE_DAILY_LIMIT_ANONYMOUS / _USER / _TOTAL）
// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models"
const DEFAULT_MODEL = "gemini-3.5-flash-lite"
const REQUEST_TIMEOUT_MS = 15000
const MAX_TITLES = 10
const MAX_TEXT_LENGTH = 100
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000

function limitFromEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name))
  return Number.isInteger(value) && value > 0 ? value : fallback
}
// 既存の「今後の公演の検索」と無料枠（全体で 1 日 500 回）を分け合うので、専用の上限を持つ
const DAILY_LIMIT_PER_ANONYMOUS_USER = limitFromEnv(
  "SONG_TITLE_DAILY_LIMIT_ANONYMOUS",
  5,
)
const DAILY_LIMIT_PER_USER = limitFromEnv("SONG_TITLE_DAILY_LIMIT_USER", 20)
const DAILY_LIMIT_TOTAL = limitFromEnv("SONG_TITLE_DAILY_LIMIT_TOTAL", 100)

const JAPANESE = /[぀-ヿ㐀-鿿]/

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function normalizeKey(value: string): string {
  return value.normalize("NFKC").toLowerCase().trim().replace(/\s+/g, " ")
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null
  const t = value.trim()
  return t && t.length <= MAX_TEXT_LENGTH ? t : null
}

function buildPrompt(artist: string, titles: string[]): string {
  return [
    `あなたは日本の音楽に詳しい。アーティスト「${artist}」の曲のうち、次のローマ字・英字表記の曲名について、`,
    "Apple Music に登録されている日本語の曲名（公式表記）を答えてください。",
    "- 確信が持てない曲、そのアーティストの曲ではない曲は japanese を null にする。曲名を推測で作らない。",
    "- 英語の曲名でも、公式の日本語表記（カタカナなど）があればそれを答える。公式表記が英字のままなら null。",
    "- 括弧の付記（ライブ版など）は付けず、曲名だけを答える。",
    `曲名: ${JSON.stringify(titles)}`,
  ].join("\n")
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // publishable key だけの呼び出しは verify_jwt を通過するので、セッションのユーザーを必ず検証する
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "")
  if (!token) return json({ error: "unauthorized" }, 401)
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const auth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!)
  const { data: userData, error: userError } = await auth.auth.getUser(token)
  if (userError || !userData?.user) return json({ error: "unauthorized" }, 401)

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }
  const artist = text(payload?.artist)
  const rawTitles = Array.isArray(payload?.titles) ? payload.titles : []
  const titles = [...new Set(rawTitles.map(text).filter(Boolean))].slice(
    0,
    MAX_TITLES,
  )
  if (!artist || titles.length === 0) return json({ error: "invalid_body" }, 400)

  const admin = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const artistKey = normalizeKey(artist)
  const results: Record<string, string | null> = {}

  // キャッシュ（見つからなかった結果も含む）
  const { data: cachedRows, error: cacheError } = await admin
    .from("song_title_cache")
    .select("title_key, japanese, fetched_at")
    .eq("artist_key", artistKey)
    .in("title_key", titles.map(normalizeKey))
  if (cacheError) console.error("cache read failed", cacheError)
  const fresh = new Map<string, string | null>()
  for (const row of cachedRows ?? []) {
    if (Date.now() - new Date(row.fetched_at).getTime() < CACHE_TTL_MS) {
      fresh.set(row.title_key, row.japanese ?? null)
    }
  }
  const misses: string[] = []
  for (const title of titles) {
    const key = normalizeKey(title)
    if (fresh.has(key)) results[title] = fresh.get(key)!
    else misses.push(title)
  }
  if (misses.length === 0) return json({ titles: results })

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return json({ error: "song_title_not_configured" }, 503)

  // Gemini を呼ぶ前に上限を数える（キャッシュに当たった分は数えない）
  const { data: quota, error: quotaError } = await admin.rpc(
    "consume_song_title_quota",
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
    return json({ error: "song_title_upstream_error" }, 500)
  }
  if (quota === "user_limit") return json({ error: "song_title_daily_limit" }, 429)
  if (quota !== "ok") return json({ error: "song_title_global_limit" }, 429)

  try {
    const model = Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL
    const res = await fetch(`${GEMINI_ENDPOINT}/${model}:generateContent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: buildPrompt(artist, misses) }] }],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                title: { type: "STRING" },
                japanese: { type: "STRING", nullable: true },
              },
              required: ["title"],
            },
          },
        },
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
    if (res.status === 429) {
      console.error("gemini rate limited", await res.text())
      return json({ error: "song_title_rate_limited" }, 429)
    }
    if (!res.ok) {
      console.error("gemini error", res.status, await res.text())
      return json({ error: "song_title_upstream_error" }, 502)
    }
    const data = await res.json()
    const body = (data?.candidates?.[0]?.content?.parts ?? [])
      .map((p: any) => (typeof p?.text === "string" ? p.text : ""))
      .join("")
    let parsed: any
    try {
      parsed = JSON.parse(body)
    } catch {
      console.error("gemini returned non-json", body.slice(0, 300))
      return json({ error: "song_title_parse_error" }, 502)
    }
    const byKey = new Map<string, string | null>()
    for (const item of Array.isArray(parsed) ? parsed : []) {
      const title = text(item?.title)
      const japanese = text(item?.japanese)
      if (title) {
        byKey.set(normalizeKey(title), japanese && JAPANESE.test(japanese) ? japanese : null)
      }
    }
    const rows = []
    for (const title of misses) {
      const japanese = byKey.get(normalizeKey(title)) ?? null
      results[title] = japanese
      rows.push({
        artist_key: artistKey,
        title_key: normalizeKey(title),
        japanese,
        fetched_at: new Date().toISOString(),
      })
    }
    const { error: saveError } = await admin.from("song_title_cache").upsert(rows)
    if (saveError) console.error("cache write failed", saveError)
    return json({ titles: results })
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("song title lookup failed", e)
    return json(
      { error: timedOut ? "song_title_timeout" : "song_title_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
