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
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/

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
  const date = typeof payload?.date === "string" ? payload.date : ""
  if (!artistName || artistName.length > MAX_ARTIST_NAME_LENGTH) {
    return json({ error: "invalid_artist_name" }, 400)
  }
  if (date && !DATE_PATTERN.test(date)) {
    return json({ error: "invalid_date" }, 400)
  }

  const params = new URLSearchParams({ artistName, p: "1" })
  if (date) {
    // setlist.fm は dd-MM-yyyy 形式
    const [y, m, d] = date.split("-")
    params.set("date", `${d}-${m}-${y}`)
  }

  try {
    const res = await fetch(`${SETLISTFM_ENDPOINT}?${params}`, {
      headers: {
        "x-api-key": apiKey,
        Accept: "application/json",
        // ja は非対応で 406 になる（対応: en, es, fr, de, pt, tr, it, pl）
        "Accept-Language": "en",
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })

    // 該当なしは 404 で返ってくる
    if (res.status === 404) {
      return json({ setlists: [] })
    }
    if (res.status === 429) {
      return json({ error: "setlistfm_rate_limited" }, 429)
    }
    if (!res.ok) {
      console.error("setlist.fm error", res.status, await res.text())
      return json({ error: "setlistfm_upstream_error" }, 502)
    }

    const data = await res.json()
    const setlists = (data?.setlist ?? [])
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
      .filter((s: any) => s.id && s.songs.length > 0)
      .slice(0, 10)

    return json({ setlists })
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("setlist.fm fetch failed", e)
    return json(
      { error: timedOut ? "setlistfm_timeout" : "setlistfm_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
