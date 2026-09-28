// setlist.fm API のプロキシ。API キーをアプリに埋め込まないためにサーバー側で保持する。
// 必要なシークレット: SETLISTFM_API_KEY（https://www.setlist.fm/settings/api で発行）
// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const SETLISTFM_ENDPOINT = "https://api.setlist.fm/rest/1.0/search/setlists"
const REQUEST_TIMEOUT_MS = 8000
const MAX_ARTIST_NAME_LENGTH = 100
const MAX_TOUR_NAME_LENGTH = 200
// setlist.fm の 1 ページの件数
const PAGE_SIZE = 20
// 1 回の呼び出しで取るページ数の上限。キャッシュ外では 1 アーティストにつき setlist.fm をこの回数呼ぶ
const MAX_PAGES = 5
// setlist.fm の上限は公称 1 秒 2 回だが、600ms 間隔でも 429 が返ったので余裕を持たせる
const PAGE_INTERVAL_MS = 1100
// 429 のときの再試行。待ち時間は回数に比例して延ばす
const MAX_RATE_LIMIT_RETRIES = 2
const RATE_LIMIT_BACKOFF_MS = 1500
// 上限は API キー単位で全ユーザー共有のため、同じ検索は 1 日 1 回までにする
const CACHE_TTL_MS = 24 * 60 * 60 * 1000

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/**
 * キャッシュのキー用。全角半角・大文字小文字・連続した空白の違いをまとめる。
 * setlist.fm は単語単位で一致させるので、単語の区切り（空白）自体は残す。
 */
function normalizeKey(value: string): string {
  return value.normalize("NFKC").toLowerCase().trim().replace(/\s+/g, " ")
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

/** setlist.fm の曲は set（本編・アンコール）ごとに入れ子なので平坦化する。 */
function flattenSongs(setlist: any): string[] {
  const sets = setlist?.sets?.set ?? []
  const songs: string[] = []
  for (const set of sets) {
    for (const song of set?.song ?? []) {
      const name = typeof song?.name === "string" ? song.name.trim() : ""
      if (name) songs.push(name)
    }
  }
  return songs
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // publishable key だけの呼び出しはゲートウェイの verify_jwt を通過してしまうため、
  // セッションのユーザーを必ずここで検証する（setlist.fm の日次上限を第三者に消費させない）
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

  const apiKey = Deno.env.get("SETLISTFM_API_KEY")
  if (!apiKey) {
    return json({ error: "setlistfm_not_configured" }, 503)
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }

  const artistName =
    typeof payload?.artistName === "string" ? payload.artistName.trim() : ""
  const tourName =
    typeof payload?.tourName === "string" ? payload.tourName.trim() : ""
  // 公演の候補には、曲がまだ登録されていない公演（開催前など）も出したい
  const includeEmpty = payload?.includeEmpty === true
  if (!artistName || artistName.length > MAX_ARTIST_NAME_LENGTH) {
    return json({ error: "invalid_artist_name" }, 400)
  }
  if (tourName.length > MAX_TOUR_NAME_LENGTH) {
    return json({ error: "invalid_tour_name" }, 400)
  }

  // 直近の公演を多めに取り、アプリ側でツアー名の部分一致に使う。setlist.fm は単語単位の
  // 一致しかできないため。ツアー名の検索は 1 ページで足りる
  const requestedPages = Number.isInteger(payload?.pages) ? payload.pages : 1
  const pages =
    tourName ? 1 : Math.min(Math.max(requestedPages, 1), MAX_PAGES)

  const respond = (all: any[]) =>
    json({
      setlists: all
        .filter((s: any) => includeEmpty || s.songs.length > 0)
        .slice(0, PAGE_SIZE * pages),
    })

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const cacheKey = [
    normalizeKey(artistName),
    normalizeKey(tourName),
    `p${pages}`,
  ].join("|")
  const { data: cached, error: cacheError } = await admin
    .from("setlistfm_cache")
    .select("setlists, fetched_at")
    .eq("cache_key", cacheKey)
    .maybeSingle()
  if (cacheError) {
    console.error("setlistfm cache read failed", cacheError)
  }
  if (
    cached &&
    Date.now() - new Date(cached.fetched_at).getTime() < CACHE_TTL_MS
  ) {
    return respond(cached.setlists ?? [])
  }

  /** 該当なしも含めて保存し、同じ検索で setlist.fm を呼ばないようにする。 */
  async function saveCache(setlists: any[]) {
    const { error } = await admin.from("setlistfm_cache").upsert({
      cache_key: cacheKey,
      setlists,
      fetched_at: new Date().toISOString(),
    })
    if (error) console.error("setlistfm cache write failed", error)
    const expired = new Date(Date.now() - CACHE_TTL_MS).toISOString()
    const { error: purgeError } = await admin
      .from("setlistfm_cache")
      .delete()
      .lt("fetched_at", expired)
    if (purgeError) console.error("setlistfm cache purge failed", purgeError)
  }

  const params = new URLSearchParams({ artistName })
  if (tourName) params.set("tourName", tourName)

  async function fetchPage(page: number): Promise<Response> {
    params.set("p", String(page))
    for (let attempt = 0; ; attempt++) {
      const res = await fetch(`${SETLISTFM_ENDPOINT}?${params}`, {
        headers: {
          "x-api-key": apiKey,
          Accept: "application/json",
          // ja は非対応で 406 になる（対応: en, es, fr, de, pt, tr, it, pl）
          "Accept-Language": "en",
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      })
      if (res.status !== 429 || attempt >= MAX_RATE_LIMIT_RETRIES) return res
      await res.body?.cancel()
      await sleep(RATE_LIMIT_BACKOFF_MS * (attempt + 1))
    }
  }

  try {
    const setlists: any[] = []
    for (let page = 1; page <= pages; page++) {
      if (page > 1) await sleep(PAGE_INTERVAL_MS)
      const res = await fetchPage(page)

      // 該当なし（最後のページの先も含む）は 404 で返ってくる
      if (res.status === 404) break
      if (!res.ok) {
        if (page > 1) {
          // 途中まで取れた分は返すが、欠けた結果をキャッシュして 1 日使い続けないよう保存しない
          console.error("setlist.fm page failed", page, res.status)
          return respond(setlists)
        }
        if (res.status === 429) {
          return json({ error: "setlistfm_rate_limited" }, 429)
        }
        console.error("setlist.fm error", res.status, await res.text())
        return json({ error: "setlistfm_upstream_error" }, 502)
      }

      const data = await res.json()
      const items = data?.setlist ?? []
      setlists.push(
        ...items
          .map((s: any) => ({
            id: String(s?.id ?? ""),
            eventDate: String(s?.eventDate ?? ""),
            artistName: String(s?.artist?.name ?? ""),
            venueName: String(s?.venue?.name ?? ""),
            cityName: String(s?.venue?.city?.name ?? ""),
            tourName: s?.tour?.name ? String(s.tour.name) : null,
            url: s?.url ? String(s.url) : null,
            songs: flattenSongs(s),
          }))
          .filter((s: any) => s.id),
      )
      const total = Number(data?.total ?? 0)
      if (items.length === 0 || page * PAGE_SIZE >= total) break
    }

    await saveCache(setlists)
    return respond(setlists)
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("setlist.fm fetch failed", e)
    return json(
      { error: timedOut ? "setlistfm_timeout" : "setlistfm_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
