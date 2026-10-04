#!/usr/bin/env python3
"""指定したメールアドレスのアカウントに、App Store 用スクリーンショットのための記録をまとめて入れる（開発用）。

記録は、実在のアーティスト・作品と間違われないよう、すべて架空の名前にしている。

使い方（鍵はこのスクリプトを動かす端末の環境変数だけで使い、どこにも保存しない）:

  export SUPABASE_SERVICE_KEY='...'            # ダッシュボードの Project Settings > API > service_role
  python3 scripts/seed_test_data.py            # 何も書き込まず、入れる内容と対象ユーザーを確認する
  python3 scripts/seed_test_data.py --apply    # 実際に入れる
  python3 scripts/seed_test_data.py --delete   # このスクリプトが入れた記録だけを消す（--apply で実行）

- 接続先は .env の SUPABASE_URL。
- 対象のアカウントは、先にアプリでそのメールアドレスのログインを一度しておくこと。
- 記録の id は固定の UUID なので、何度実行しても同じ記録が上書きされるだけで、増えない。
- ほかのユーザーの記録は触らない。
"""

import argparse
import json
import os
import random
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import date, timedelta
from pathlib import Path

DEFAULT_EMAIL = "nnkm8329@gmail.com"
NAMESPACE = uuid.UUID("5f2a3c1e-6b7d-4e0a-9a52-7c1d9f3b8e10")
TEST_TAG = ""  # 題名の先頭に付ける印。スクリーンショットでは付けない（見分けたいときだけ "【テスト】" など）

TODAY = date.today()


def load_url() -> str:
    env = Path(__file__).resolve().parent.parent / ".env"
    for line in env.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*SUPABASE_URL\s*=\s*(\S+)", line)
        if m:
            return m.group(1).strip("'\"").rstrip("/")
    sys.exit(".env に SUPABASE_URL がありません")


def request(method, url, key, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", key)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            text = res.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url} が失敗しました: {e.code} {e.read().decode()[:400]}")


def find_user_id(base, key, email):
    page = 1
    while True:
        q = urllib.parse.urlencode({"page": page, "per_page": 200})
        res = request("GET", f"{base}/auth/v1/admin/users?{q}", key)
        users = res.get("users", []) if isinstance(res, dict) else []
        for u in users:
            if (u.get("email") or "").lower() == email.lower():
                return u["id"]
        if len(users) < 200:
            return None
        page += 1


def rid(name):
    return str(uuid.uuid5(NAMESPACE, name))


def d(offset_days):
    return (TODAY + timedelta(days=offset_days)).isoformat()


def base_row(name, kind, title, who, offset, **extra):
    row = {
        "id": rid(name),
        "type": kind,
        "title": f"{TEST_TAG}{title}",
        "artist_or_author": who,
        "date": d(offset),
        "ticket_image_url": "",
        "ticket_image_urls": [],
        "event_format": "oneman",
        "acts": [],
        "setlist": None,
        "mc_memo": None,
        "impressions": None,
        "ticket_source": None,
        "venue": None,
        "seat": None,
        "ticket_price": None,
        "open_time": None,
        "start_time": None,
        "end_time": None,
        "end_date": None,
        "link_url": None,
    }
    row.update(extra)
    return row


ARTISTS = [
    "夜凪ユウ", "THE LANTERNS", "星空ミオ", "SUNSET PARADE", "水無月レイ", "Neon Harbor",
    "ミツバチ急行", "凪ノ海", "Aoi Hoshizora", "白石 澪", "cloudy picnic", "透明少年",
]
VENUES = [
    "日本武道館", "さいたまスーパーアリーナ", "東京ドーム", "横浜アリーナ", "Zepp Haneda",
    "Zepp Shinjuku", "大阪城ホール", "京セラドーム大阪", "NHKホール", "LINE CUBE SHIBUYA",
    "豊洲PIT", "Zepp Nagoya", "福岡PayPayドーム", "幕張メッセ",
]
SOURCES = ["e+", "ローチケ", "チケットぴあ", "ファンクラブ", "公式サイト", "当日券", "友人から"]
SONGS = [
    "夜明けのフィルム", "ネオンの海", "約束の屋上", "星のレシート", "さよならスクランブル", "青い教室",
    "ひかりの輪郭", "週末のメロディ", "帰り道のうた", "僕らの夏休み", "ミッドナイト・ライン", "花火の裏側",
    "遠回りの地図", "キミのいない朝", "透明な季節", "ドライブスルー・ムーン", "最後のカーテンコール",
    "ラストダンス", "Blue Hour", "Snow Letter", "Paper Planes", "ハートビート・サマー",
]
IMPRESSIONS = [
    "初めて生で聴けた。イントロで鳥肌が立った。",
    "アンコールの一曲目が一番よかった。",
    "音がとても良く、2 階席でもしっかり届いた。",
    "MC が長くて笑った。グッズの列は 40 分待ち。",
    "セトリが最高だった。また行きたい。",
    "天気が悪かったけれど、会場の熱気で気にならなかった。",
]
MC = [
    "「今日はみんなの声が聞けてうれしい」",
    "ツアーの思い出と、次のアルバムの話。",
    "メンバー紹介でいじり合いが続いた。",
]


def build_rows(rng):
    rows = []

    # ライブ（ワンマン）: 過去 24 件 + これから 5 件
    for i in range(24):
        offset = -rng.randint(7, 700)
        who = rng.choice(ARTISTS)
        songs = rng.sample(SONGS, rng.randint(8, 16))
        has_time = rng.random() < 0.85
        start_h = rng.choice([17, 18, 18, 19])
        row = base_row(
            f"live-past-{i}", "live", f"{who} ONE-MAN TOUR {2024 + i % 3}", who, offset,
            venue=rng.choice(VENUES),
            ticket_source=rng.choice(SOURCES),
            seat=rng.choice([None, "1 階 Aブロック 12 列", "2 階 スタンド 4 列", "アリーナ B 8 番", "立見"]),
            ticket_price=rng.choice([None, 6800, 7700, 8800, 9900, 12000]),
            setlist="\n".join(songs) if rng.random() < 0.8 else None,
            mc_memo=rng.choice(MC) if rng.random() < 0.4 else None,
            impressions=rng.choice(IMPRESSIONS) if rng.random() < 0.8 else None,
            link_url="https://eplus.jp/sf/detail/0000000000" if rng.random() < 0.2 else None,
        )
        if has_time:
            row["open_time"] = f"{start_h - 1}:00"
            row["start_time"] = f"{start_h}:{rng.choice(['00', '30'])}"
            if rng.random() < 0.5:
                row["end_time"] = f"{start_h + 2}:{rng.choice(['00', '30'])}"
        rows.append(row)
    for i in range(5):
        who = ARTISTS[i]
        rows.append(base_row(
            f"live-future-{i}", "live", f"{who} ARENA TOUR", who, 5 + i * 17,
            venue=VENUES[i], ticket_source=SOURCES[i], ticket_price=9800,
            open_time="17:00", start_time="18:00",
        ))

    # 対バン 6 件
    for i in range(6):
        a, b, c = rng.sample(ARTISTS, 3)
        rows.append(base_row(
            f"taiban-{i}", "live", f"対バンライブ Vol.{i + 1}", a, -rng.randint(20, 500),
            event_format="taiban", venue=rng.choice(VENUES[4:]),
            ticket_source=rng.choice(SOURCES), ticket_price=rng.choice([4500, 5500, 6000]),
            open_time="17:30", start_time="18:00",
            acts=[
                {"artist": a, "songs": rng.sample(SONGS, 5), "is_main": True},
                {"artist": b, "songs": rng.sample(SONGS, 4), "is_main": False},
                {"artist": c, "songs": [], "is_main": False},
            ],
            impressions=rng.choice(IMPRESSIONS),
        ))

    # フェス（複数日）5 件。終演時刻なしを含める
    fes = ["SEASIDE SOUND FES", "GREEN FIELD MUSIC DAYS", "MOUNTAIN ECHO", "COUNTDOWN SPARKS", "HARBOR LIGHTS FES"]
    for i, name in enumerate(fes):
        start = -rng.randint(30, 600) if i < 4 else 20  # 最後の 1 件はこれから
        days = 3 if i % 2 == 0 else 2
        row = base_row(
            f"fes-{i}", "live", f"{name} 202{4 + i % 3}", rng.choice(ARTISTS), start,
            event_format="festival", venue=rng.choice(["幕張メッセ", "国営ひたちなか海浜公園", "新潟・苗場スキー場", "インテックス大阪"]),
            ticket_source=rng.choice(SOURCES), ticket_price=rng.choice([15000, 18000, 32000]),
            end_date=d(start + days - 1),
            acts=[
                {"artist": rng.choice(ARTISTS), "songs": rng.sample(SONGS, 4), "is_main": True, "day": 1},
                {"artist": rng.choice(ARTISTS), "songs": rng.sample(SONGS, 3), "is_main": False, "day": 1},
                {"artist": rng.choice(ARTISTS), "songs": [], "is_main": False, "day": 2},
            ],
            impressions=rng.choice(IMPRESSIONS),
        )
        rows.append(row)

    # 日をまたぐカウントダウン（開場が開演より遅い時刻）
    rows.append(base_row(
        "countdown-overnight", "live", "年越しカウントダウン", "THE LANTERNS", -300,
        venue="幕張メッセ", ticket_source="ファンクラブ", ticket_price=11000,
        open_time="23:30", start_time="0:30", end_time="3:00",
    ))

    # 映画 10 件
    movies = [
        ("星降る夜の約束", "久遠 しずく"), ("海辺のカメラ", "鳴海 透"), ("終電のあとで", "北条 アリサ"),
        ("ひなたの町", "三雲 恒一"), ("ミッドナイト・ジャム", "J・ハーパー"), ("紙の月に触れて", "霧島 雅"),
        ("雨のち、青", "小夜 まどか"), ("リトル・ラジオ", "M・ケンジントン"), ("白い図書館", "春日 凛"),
        ("夏のアルバム", "柊 あおい"),
    ]
    for i, (t, who) in enumerate(movies):
        rows.append(base_row(
            f"movie-{i}", "movie", t, who, -rng.randint(3, 800) if i < 9 else 8,
            venue=rng.choice(["TOHOシネマズ 新宿", "イオンシネマ 幕張新都心", "109シネマズ 湘南", "ユナイテッド・シネマ 豊洲"]),
            ticket_source=rng.choice(["劇場窓口", "劇場のサイト・アプリ", "ムビチケ", "前売券"]),
            ticket_price=rng.choice([1000, 1500, 1900, 2000]),
            start_time=f"{rng.choice([10, 13, 16, 19, 21])}:{rng.choice(['00', '15', '40'])}",
            impressions=rng.choice(IMPRESSIONS) if rng.random() < 0.8 else None,
        ))

    # 本 8 件
    books = [
        ("夜のはじまりに", "水城 ゆず"), ("すこしだけ遠くへ", "宇佐美 かなで"), ("図書室の魔法", "榊原 ひより"),
        ("ふたりの航海日誌", "R・アンダーソン"), ("朝焼けのレシピ", "桐谷 まひる"), ("白い街の手紙", "天城 ナツ"),
        ("星を数える仕事", "久我 ミナト"), ("月曜日の窓", "七瀬 ほたる"),
    ]
    for i, (t, who) in enumerate(books):
        rows.append(base_row(
            f"book-{i}", "book", t, who, -rng.randint(3, 600),
            ticket_source=rng.choice(["書店", "Amazon", "楽天ブックス", "電子書籍", "図書館"]),
            ticket_price=rng.choice([None, 880, 1200, 1650, 2200]),
            impressions=rng.choice(IMPRESSIONS) if rng.random() < 0.75 else None,
        ))

    # その他 5 件
    others = ["展覧会", "舞台", "スポーツ観戦", "落語", "ミュージカル"]
    for i, t in enumerate(others):
        rows.append(base_row(
            f"other-{i}", "other", f"{t}", "", -rng.randint(10, 400) if i < 4 else 12,
            venue=rng.choice(["国立新美術館", "帝国劇場", "東京ドーム", "新宿末廣亭"]),
            ticket_source=rng.choice(["チケットぴあ", "公式サイト", "当日券"]),
            ticket_price=rng.choice([1800, 3500, 8500]),
        ))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", default=DEFAULT_EMAIL)
    ap.add_argument("--apply", action="store_true", help="実際に書き込む（付けなければ確認だけ）")
    ap.add_argument("--delete", action="store_true", help="このスクリプトが入れた記録を消す")
    args = ap.parse_args()

    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not key:
        sys.exit("環境変数 SUPABASE_SERVICE_KEY を設定してください（スクリプトの先頭の説明を参照）")
    base = load_url()
    user_id = find_user_id(base, key, args.email)
    if user_id is None:
        sys.exit(f"{args.email} のユーザーが見つかりません。先にそのアカウントでアプリにログインしてください")

    rows = build_rows(random.Random(20261003))
    for r in rows:
        r["user_id"] = user_id
    ids = [r["id"] for r in rows]

    print(f"接続先: {base}")
    print(f"対象: {args.email} ({user_id})")
    kinds = {}
    for r in rows:
        kinds[r["type"]] = kinds.get(r["type"], 0) + 1
    print(f"{'削除' if args.delete else '投入'}する記録: {len(rows)} 件 {kinds}")

    if not args.apply:
        print("確認だけで、書き込んでいません。実行するには --apply を付けてください。")
        return

    if args.delete:
        q = "id=in.(" + ",".join(ids) + f")&user_id=eq.{user_id}"
        request("DELETE", f"{base}/rest/v1/records?{q}", key, headers={"Prefer": "return=minimal"})
        print("削除しました。")
        return

    # 先に 1 件だけ入れて、列の型などが合わない場合に途中で止める
    request(
        "POST", f"{base}/rest/v1/records", key, rows[:1],
        {"Prefer": "resolution=merge-duplicates,return=minimal"},
    )
    request(
        "POST", f"{base}/rest/v1/records", key, rows[1:],
        {"Prefer": "resolution=merge-duplicates,return=minimal"},
    )
    print("投入しました。アプリを開き直すと表示されます。")


if __name__ == "__main__":
    main()
