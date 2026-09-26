// アーティストの今後の公演を Gemini で集める。
// MusicBrainz で公式サイトを特定し、そのページを URL context（無料枠で使える）で読み取る。
// 必要なシークレット: GEMINI_API_KEY（https://aistudio.google.com/apikey で無料発行）
// 任意: GEMINI_MODEL（既定 gemini-3.5-flash-lite）
// 任意: GEMINI_SEARCH_GROUNDING=true で、先に Google 検索（グラウンディング）を試す。
//   無料枠では上限 0 で必ず 429 になり、リクエストを 1 回無駄にするので既定では使わない。
//   有料枠にしたら有効にすると、公式サイト以外（ニュース・チケットサイト）からも探せる。
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
// 検索を伴う生成は数十秒かかることがある
const REQUEST_TIMEOUT_MS = 60000
const MUSICBRAINZ_ENDPOINT = "https://musicbrainz.org/ws/2"
// MusicBrainz は連絡先入りの User-Agent がないと弾く
const MUSICBRAINZ_USER_AGENT = "recolle/1.0 ( https://github.com/mn329/recolle )"
const MUSICBRAINZ_MIN_SCORE = 90
const PAGE_TIMEOUT_MS = 10000
// URL context は 1 リクエスト 20 URL まで。読み込みが遅くならないよう絞る
const MAX_PAGES = 5
const LIVE_LINK_PATTERN =
  /live|tour|schedule|concert|event|ライブ|ツアー|スケジュール|公演/i
const CACHE_TTL_MS = 24 * 60 * 60 * 1000
// 無料枠は 1 日 500 回（プロジェクト全体）。1 人で使い切らないよう、キャッシュ外の検索を制限する
const DAILY_LIMIT_PER_USER = 20
const MAX_ARTIST_NAME_LENGTH = 100
const MAX_EVENTS = 20
const MAX_SOURCES = 8
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/
const TIME_PATTERN = /^([01]?\d|2[0-3]):([0-5]\d)$/

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

/** キャッシュのキー。全角半角・大文字小文字・空白の違いをまとめる。 */
function artistKey(name: string): string {
  return name.normalize("NFKC").toLowerCase().replace(/\s+/g, "")
}

/** 日本時間の今日（YYYY-MM-DD）。 */
function todayInTokyo(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date())
}

/** pages を渡すとそのページだけを読み、省略すると Google 検索で調べるよう指示する。 */
function buildPrompt(artist: string, today: string, pages?: string[]): string {
  const source = pages
    ? [
        `次のページを読んで「${artist}」の今後のライブ・コンサート・ツアー・フェス出演の予定を調べてください。`,
        ...pages,
        `今日は ${today}（日本時間）です。今日以降に開催されるものだけを対象にします。`,
        "ページに書かれている告知だけを載せ、推測や過去の公演は含めないでください。source_url には告知が載っていたページの URL を入れてください。",
      ]
    : [
        `Google 検索で「${artist}」の今後のライブ・コンサート・ツアー・フェス出演の予定を調べてください。`,
        `今日は ${today}（日本時間）です。今日以降に開催されるものだけを対象にします。`,
        "公式サイト・公式 SNS・チケット販売サイト・音楽ニュースで告知が確認できたものだけを載せ、推測や過去の公演、同名の別アーティストの公演は含めないでください。",
      ]
  return [
    ...source,
    "ツアーは公演日ごとに 1 件ずつ分けてください。",
    "結果は次の形式の JSON だけを ```json のコードブロックで出力してください。見つからなければ {\"events\": []} としてください。",
    '{"events":[{"title":"公演名・ツアー名","date":"YYYY-MM-DD","open_time":"HH:MM か null","start_time":"HH:MM か null","venue":"会場名 か null","city":"都市名 か null","source_url":"告知ページの URL か null"}]}',
    `最大 ${MAX_EVENTS} 件、日付の早い順にしてください。`,
  ].join("\n")
}

/** モデルの出力から JSON 部分を取り出す（コードブロックの有無どちらにも対応）。 */
function extractJson(text: string): any {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  const candidate = fenced
    ? fenced[1]
    : text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1)
  try {
    return JSON.parse(candidate)
  } catch {
    return null
  }
}

function cleanText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null
  const text = value.trim()
  if (!text || text.toLowerCase() === "null") return null
  return text.slice(0, maxLength)
}

function cleanTime(value: unknown): string | null {
  const text = cleanText(value, 5)
  const m = text?.match(TIME_PATTERN)
  return m ? `${m[1].padStart(2, "0")}:${m[2]}` : null
}

function cleanDate(value: unknown, today: string): string | null {
  const text = cleanText(value, 10)
  const m = text?.match(DATE_PATTERN)
  if (!m) return null
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  const date = new Date(Date.UTC(y, mo - 1, d))
  // 2026-02-30 のような存在しない日付を弾く
  if (date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d) return null
  return text >= today ? text : null
}

function cleanUrl(value: unknown): string | null {
  const text = cleanText(value, 2000)
  if (!text) return null
  try {
    const url = new URL(text)
    return url.protocol === "https:" || url.protocol === "http:"
      ? url.toString()
      : null
  } catch {
    return null
  }
}

/** モデルの出力は信用せず、形式・日付を検めてから返す。 */
function normalizeEvents(
  parsed: any,
  artist: string,
  today: string,
  allowedUrls?: Set<string>,
) {
  const seen = new Set<string>()
  const events = []
  for (const raw of Array.isArray(parsed?.events) ? parsed.events : []) {
    const date = cleanDate(raw?.date, today)
    if (!date) continue
    const venue = cleanText(raw?.venue, 200)
    const title = cleanText(raw?.title, 200) ?? `${artist} ライブ`
    const key = `${date}|${venue ?? title}`
    if (seen.has(key)) continue
    seen.add(key)
    const sourceUrl = cleanUrl(raw?.source_url)
    events.push({
      title,
      date,
      openTime: cleanTime(raw?.open_time),
      startTime: cleanTime(raw?.start_time),
      venue,
      city: cleanText(raw?.city, 100),
      // 読んだページ以外の URL はモデルの作り話のことがあるため載せない
      sourceUrl:
        sourceUrl && (!allowedUrls || allowedUrls.has(sourceUrl))
          ? sourceUrl
          : null,
    })
  }
  events.sort((a, b) => a.date.localeCompare(b.date))
  return events.slice(0, MAX_EVENTS)
}

/** 検索で参照したページ。URI は Google のリダイレクト URL、title はドメイン名。 */
function normalizeSources(metadata: any) {
  const seen = new Set<string>()
  const sources = []
  for (const chunk of metadata?.groundingChunks ?? []) {
    const uri = cleanUrl(chunk?.web?.uri)
    const title = cleanText(chunk?.web?.title, 200)
    if (!uri || !title || seen.has(title)) continue
    seen.add(title)
    sources.push({ title, uri })
  }
  return sources.slice(0, MAX_SOURCES)
}

/** URL context で実際に読めたページの URL。 */
function retrievedUrls(metadata: any): string[] {
  const urls = []
  for (const page of metadata?.urlMetadata ?? metadata?.url_metadata ?? []) {
    const status = page?.urlRetrievalStatus ?? page?.url_retrieval_status
    if (status !== "URL_RETRIEVAL_STATUS_SUCCESS") continue
    const uri = cleanUrl(page?.retrievedUrl ?? page?.retrieved_url)
    if (uri) urls.push(uri)
  }
  return urls
}

/**
 * 読んだページのうち公式サイトのものを出典にする（リダイレクト先のログイン画面などは除く）。
 * 同じサイトのページは 1 つにまとめ、title はドメイン名。
 */
function sourcesFromPages(urls: string[], pages: string[]) {
  const officialHosts = new Set(pages.map((p) => new URL(p).hostname))
  const seen = new Set<string>()
  const sources = []
  for (const uri of urls) {
    const title = new URL(uri).hostname
    if (!officialHosts.has(title) || seen.has(title)) continue
    seen.add(title)
    sources.push({ title, uri })
  }
  return sources.slice(0, MAX_SOURCES)
}

async function fetchMusicBrainz(path: string): Promise<any> {
  const res = await fetch(`${MUSICBRAINZ_ENDPOINT}/${path}`, {
    headers: { "User-Agent": MUSICBRAINZ_USER_AGENT, Accept: "application/json" },
    signal: AbortSignal.timeout(PAGE_TIMEOUT_MS),
  })
  if (!res.ok) throw new Error(`musicbrainz ${res.status}`)
  return res.json()
}

/** MusicBrainz に登録された公式サイト（official homepage）。見つからなければ null。 */
async function findOfficialSite(artist: string): Promise<string | null> {
  const query = encodeURIComponent(`artist:"${artist.replace(/"/g, "")}"`)
  const search = await fetchMusicBrainz(`artist?query=${query}&limit=1&fmt=json`)
  const found = search?.artists?.[0]
  if (!found?.id || (found.score ?? 0) < MUSICBRAINZ_MIN_SCORE) return null
  const detail = await fetchMusicBrainz(`artist/${found.id}?inc=url-rels&fmt=json`)
  for (const rel of detail?.relations ?? []) {
    if (rel?.type !== "official homepage" || rel?.ended) continue
    const url = cleanUrl(rel?.url?.resource)
    if (url) return url
  }
  return null
}

/**
 * 公式サイトのトップと、ライブ・ツアー告知らしい同じサイト内のページ。
 * URL context はリンクをたどらないため、候補をここで拾っておく。
 */
async function collectSitePages(homepage: string): Promise<string[]> {
  const pages = [homepage]
  try {
    const res = await fetch(homepage, {
      headers: { "User-Agent": MUSICBRAINZ_USER_AGENT },
      signal: AbortSignal.timeout(PAGE_TIMEOUT_MS),
    })
    if (!res.ok) return pages
    const html = await res.text()
    const base = new URL(res.url || homepage)
    for (const m of html.matchAll(/<a\s[^>]*href=["']([^"'#]+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
      if (pages.length >= MAX_PAGES) break
      let url: URL
      try {
        url = new URL(m[1], base)
      } catch {
        continue
      }
      if (url.hostname !== base.hostname) continue
      const label = m[2].replace(/<[^>]*>/g, " ")
      if (!LIVE_LINK_PATTERN.test(url.pathname) && !LIVE_LINK_PATTERN.test(label)) {
        continue
      }
      const href = cleanUrl(url.toString())
      if (href && !pages.includes(href)) pages.push(href)
    }
  } catch (e) {
    console.error("official site fetch failed", homepage, e)
  }
  return pages
}

async function generate(apiKey: string, model: string, body: unknown) {
  return fetch(`${GEMINI_ENDPOINT}/${model}:generateContent`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })
}

function toResponse(row: any, cached: boolean) {
  return {
    events: row.events ?? [],
    sources: row.sources ?? [],
    searchEntryPoint: row.search_entry_point ?? null,
    fetchedAt: row.fetched_at,
    cached,
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // publishable key だけの呼び出しはゲートウェイの verify_jwt を通過してしまうため、
  // セッションのユーザーを必ずここで検証する（Gemini の無料枠を第三者に消費させない）
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "")
  if (!token) {
    return json({ error: "unauthorized" }, 401)
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const auth = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!)
  const { data: userData, error: userError } = await auth.auth.getUser(token)
  if (userError || !userData?.user) {
    return json({ error: "unauthorized" }, 401)
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) {
    return json({ error: "discovery_not_configured" }, 503)
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: "invalid_body" }, 400)
  }
  const artist =
    typeof payload?.artistName === "string" ? payload.artistName.trim() : ""
  if (!artist || artist.length > MAX_ARTIST_NAME_LENGTH) {
    return json({ error: "invalid_artist_name" }, 400)
  }
  const key = artistKey(artist)

  const admin = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const { data: cachedRow, error: cacheError } = await admin
    .from("concert_discovery_cache")
    .select()
    .eq("artist_key", key)
    .maybeSingle()
  if (cacheError) {
    console.error("cache read failed", cacheError)
  }
  if (
    cachedRow &&
    Date.now() - new Date(cachedRow.fetched_at).getTime() < CACHE_TTL_MS
  ) {
    return json(toResponse(cachedRow, true))
  }

  const { data: allowed, error: quotaError } = await admin.rpc(
    "consume_concert_discovery_quota",
    { p_user_id: userData.user.id, p_limit: DAILY_LIMIT_PER_USER },
  )
  if (quotaError) {
    console.error("quota check failed", quotaError)
    return json({ error: "discovery_upstream_error" }, 500)
  }
  if (!allowed) {
    return json({ error: "discovery_daily_limit" }, 429)
  }

  const today = todayInTokyo()
  const model = Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL
  const useSearchGrounding = Deno.env.get("GEMINI_SEARCH_GROUNDING") === "true"
  try {
    let res: Response | null = null
    if (useSearchGrounding) {
      res = await generate(apiKey, model, {
        contents: [{ parts: [{ text: buildPrompt(artist, today) }] }],
        tools: [{ google_search: {} }],
      })
      if (res.status === 429) {
        // 検索の上限に達したときは、公式サイトの読み取りに切り替える
        console.error("gemini search rate limited", await res.text())
        res = null
      }
    }
    let pages: string[] | null = null
    if (!res) {
      let homepage: string | null
      try {
        homepage = await findOfficialSite(artist)
      } catch (e) {
        console.error("musicbrainz lookup failed", e)
        return json({ error: "discovery_upstream_error" }, 502)
      }
      if (!homepage) {
        return json({ error: "discovery_no_official_site" }, 404)
      }
      pages = await collectSitePages(homepage)
      res = await generate(apiKey, model, {
        contents: [{ parts: [{ text: buildPrompt(artist, today, pages) }] }],
        tools: [{ url_context: {} }],
      })
    }
    if (res.status === 429) {
      console.error("gemini rate limited", await res.text())
      return json({ error: "discovery_rate_limited" }, 429)
    }
    if (!res.ok) {
      console.error("gemini error", res.status, await res.text())
      return json({ error: "discovery_upstream_error" }, 502)
    }

    const data = await res.json()
    const candidate = data?.candidates?.[0]
    const text = (candidate?.content?.parts ?? [])
      .map((p: any) => (typeof p?.text === "string" ? p.text : ""))
      .join("")
    const parsed = extractJson(text)
    if (parsed == null) {
      console.error("gemini returned non-json", text.slice(0, 500))
      return json({ error: "discovery_parse_error" }, 502)
    }

    const metadata = candidate?.groundingMetadata
    const retrieved = pages
      ? retrievedUrls(
          candidate?.urlContextMetadata ?? candidate?.url_context_metadata,
        )
      : []
    const row = {
      artist_key: key,
      artist_name: artist,
      events: normalizeEvents(
        parsed,
        artist,
        today,
        pages ? new Set([...pages, ...retrieved]) : undefined,
      ),
      sources: pages
        ? sourcesFromPages(retrieved, pages)
        : normalizeSources(metadata),
      search_entry_point: pages
        ? null
        : cleanText(metadata?.searchEntryPoint?.renderedContent, 50000),
      fetched_at: new Date().toISOString(),
    }
    const { error: saveError } = await admin
      .from("concert_discovery_cache")
      .upsert(row)
    if (saveError) {
      console.error("cache write failed", saveError)
    }
    return json(toResponse(row, false))
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("gemini fetch failed", e)
    return json(
      { error: timedOut ? "discovery_timeout" : "discovery_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
