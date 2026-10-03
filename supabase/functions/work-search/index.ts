// 映画・本の題名候補を探すプロキシ。API キーをアプリに埋め込まないためにサーバー側で保持する。
// - 映画: TMDB。必要なシークレット: TMDB_API_TOKEN（TMDB の「API 読み込みアクセストークン」）
// - 本: 楽天ブックス書籍検索 API。必要なシークレット: RAKUTEN_APPLICATION_ID / RAKUTEN_ACCESS_KEY
//   楽天は「Web アプリケーション」型で登録し、許可する Web サイトに <project-ref>.supabase.co を入れる
//   （Referer / Origin で呼び出し元を確かめるため。バックエンド型は固定 IP が要り、Edge Functions では使えない）
// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
}

const TMDB_ENDPOINT = "https://api.themoviedb.org/3"
const TMDB_POSTER_BASE = "https://image.tmdb.org/t/p/w185"
const RAKUTEN_BOOKS_ENDPOINT =
  "https://openapi.rakuten.co.jp/services/api/BooksBook/Search/20170404"
const REQUEST_TIMEOUT_MS = 8000
const MAX_QUERY_LENGTH = 100
const MAX_RESULTS = 5
// 楽天は同じ本の単行本・文庫などが別の商品で並ぶので、多めに取ってまとめる
const RAKUTEN_HITS = 15
const MAX_DIRECTORS = 2
const MAX_AUTHORS = 2
// 入力途中の検索が続くので、同じ検索は使い回す。ワーカーが生きている間だけのキャッシュ
const CACHE_TTL_MS = 60 * 60 * 1000
const MAX_CACHE_ENTRIES = 500

const searchCache = new Map<string, { works: unknown[]; at: number }>()
// 監督の日本語名は作品をまたいで同じなので、人物ごとに覚えておく
const personNameCache = new Map<number, string>()

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

class UpstreamError extends Error {
  constructor(readonly code: string, readonly status: number) {
    super(code)
  }
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
  return hit.works
}

function remember(key: string, works: unknown[]) {
  searchCache.set(key, { works, at: Date.now() })
  if (searchCache.size > MAX_CACHE_ENTRIES) {
    searchCache.delete(searchCache.keys().next().value)
  }
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null
  const t = value.trim()
  return t ? t : null
}

/** [notFoundAsNull] なら 404 を該当なしとして null で返す。 */
async function fetchJson(
  url: string,
  init: RequestInit,
  label: string,
  notFoundAsNull = false,
) {
  const res = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })
  if (notFoundAsNull && res.status === 404) {
    await res.body?.cancel()
    return null
  }
  if (res.status === 429) {
    await res.body?.cancel()
    throw new UpstreamError("work_search_rate_limited", 429)
  }
  if (!res.ok) {
    console.error(`${label} error`, res.status, await res.text())
    throw new UpstreamError("work_search_upstream_error", 502)
  }
  return res.json()
}

// ---- 映画（TMDB） ----

function tmdb(path: string, params: Record<string, string>, token: string) {
  const query = new URLSearchParams({ language: "ja-JP", ...params })
  return fetchJson(
    `${TMDB_ENDPOINT}${path}?${query}`,
    { headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } },
    "tmdb",
  )
}

/**
 * 人物名は英語表記で登録されていることが多い（例: Makoto Shinkai）ので、日本語の翻訳があれば使う。
 * 取れなければクレジットの表記のまま。
 */
async function japaneseName(id: number, fallback: string, token: string) {
  const known = personNameCache.get(id)
  if (known) return known
  let name = fallback
  try {
    const data = await tmdb(`/person/${id}/translations`, {}, token)
    for (const t of data?.translations ?? []) {
      const translated = text(t?.data?.name)
      if (t?.iso_639_1 === "ja" && translated) {
        name = translated
        break
      }
    }
  } catch (e) {
    console.error("tmdb person translation failed", id, e)
    return fallback
  }
  personNameCache.set(id, name)
  return name
}

/** 監督は補足なので、取れなくても題名の候補は出す。 */
async function directorsOf(movieId: number, token: string): Promise<string[]> {
  try {
    const credits = await tmdb(`/movie/${movieId}/credits`, {}, token)
    const directors = (credits?.crew ?? [])
      .filter((c: any) => c?.job === "Director" && typeof c?.id === "number")
      .slice(0, MAX_DIRECTORS)
    const names = await Promise.all(
      directors.map((d: any) => japaneseName(d.id, text(d.name) ?? "", token)),
    )
    return names.filter(Boolean)
  } catch (e) {
    console.error("tmdb credits failed", movieId, e)
    return []
  }
}

async function searchMovies(query: string, token: string) {
  const data = await tmdb("/search/movie", {
    query,
    include_adult: "false",
  }, token)
  const movies = (data?.results ?? [])
    .filter((m: any) => typeof m?.id === "number" && text(m?.title))
    .slice(0, MAX_RESULTS)
  return Promise.all(
    movies.map(async (m: any) => {
      const title = text(m.title)
      const original = text(m.original_title)
      const year = Number(text(m.release_date)?.slice(0, 4))
      const directors = await directorsOf(m.id, token)
      return {
        title,
        creator: directors.length ? directors.join("・") : null,
        year: Number.isInteger(year) && year > 0 ? year : null,
        artworkUrl: text(m.poster_path)
          ? `${TMDB_POSTER_BASE}${m.poster_path}`
          : null,
        // 邦題と原題が違う作品は、原題で見分けられるようにする
        description: original && original !== title ? original : null,
      }
    }),
  )
}

// ---- 本（楽天ブックス） ----

const CJK = "\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}ー"
// 楽天の著者名は「村上 春樹」のように姓名の間に空白が入る。日本語の名前だけ詰める
const CJK_SPACE = new RegExp(`(?<=[${CJK}])\\s+(?=[${CJK}])`, "gu")

function authorsOf(raw: unknown): string | null {
  const names = (text(raw) ?? "")
    .split("/")
    .map((n) => n.replace(CJK_SPACE, "").trim())
    .filter(Boolean)
    .slice(0, MAX_AUTHORS)
  return names.length ? names.join("・") : null
}

async function searchBooks(
  query: string,
  applicationId: string,
  accessKey: string,
  referer: string,
) {
  const params = new URLSearchParams({
    applicationId,
    accessKey,
    format: "json",
    formatVersion: "2",
    title: query,
    hits: String(RAKUTEN_HITS),
    // 品切れ・絶版の本も記録したいので含める
    outOfStockFlag: "1",
    elements: "title,author,salesDate,largeImageUrl",
  })
  // 該当なしは 404 で返ってくる
  const data = await fetchJson(
    `${RAKUTEN_BOOKS_ENDPOINT}?${params}`,
    { headers: { Referer: referer, Origin: new URL(referer).origin } },
    "rakuten",
    true,
  )
  const seen = new Set<string>()
  const books = []
  for (const item of data?.Items ?? data?.items ?? []) {
    const title = text(item?.title)
    if (!title) continue
    const creator = authorsOf(item?.author)
    const key = `${normalizeKey(title)}|${creator ?? ""}`
    if (seen.has(key)) continue
    seen.add(key)
    const year = Number(text(item?.salesDate)?.match(/^(\d{4})年/)?.[1])
    const image = text(item?.largeImageUrl)
    books.push({
      title,
      creator,
      year: Number.isInteger(year) ? year : null,
      artworkUrl: image?.startsWith("https://") ? image : null,
      description: null,
    })
    if (books.length >= MAX_RESULTS) break
  }
  return books
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
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const supabase = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!)
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
  const type = payload?.type
  if (type !== "movie" && type !== "book") {
    return json({ error: "invalid_type" }, 400)
  }
  const query = typeof payload?.query === "string" ? payload.query.trim() : ""
  if (!query || query.length > MAX_QUERY_LENGTH) {
    return json({ error: "invalid_query" }, 400)
  }

  const tmdbToken = Deno.env.get("TMDB_API_TOKEN")
  const rakutenId = Deno.env.get("RAKUTEN_APPLICATION_ID")
  const rakutenKey = Deno.env.get("RAKUTEN_ACCESS_KEY")
  if (type === "movie" ? !tmdbToken : !rakutenId || !rakutenKey) {
    return json({ error: "work_search_not_configured" }, 503)
  }

  const cacheKey = `${type}|${normalizeKey(query)}`
  const hit = cached(cacheKey)
  if (hit) return json({ works: hit })

  try {
    const works = type === "movie"
      ? await searchMovies(query, tmdbToken)
      : await searchBooks(query, rakutenId, rakutenKey, `${supabaseUrl}/`)
    remember(cacheKey, works)
    return json({ works })
  } catch (e) {
    if (e instanceof UpstreamError) {
      return json({ error: e.code }, e.status)
    }
    const timedOut = e instanceof DOMException && e.name === "TimeoutError"
    console.error("work search failed", type, e)
    return json(
      { error: timedOut ? "work_search_timeout" : "work_search_upstream_error" },
      timedOut ? 504 : 502,
    )
  }
})
