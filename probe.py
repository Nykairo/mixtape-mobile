import json
import os
import traceback

import requests
from ytmusicapi import YTMusic
from ytmusicapi.parsers.search import get_search_params

OUT = "probe-out"
os.makedirs(OUT, exist_ok=True)
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"


def save(name, data):
    with open(f"{OUT}/{name}.json", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)


def step(name, fn):
    print(f"\n===== {name}", flush=True)
    try:
        fn()
    except Exception:
        traceback.print_exc()


yt = YTMusic(language="en", location="US")
songs = {}
cps = {}


def find_songs():
    for q in ["blinding lights the weeknd", "get lucky daft punk", "levitating dua lipa", "as it was harry styles",
              "holocene bon iver", "bohemian rhapsody queen", "seven nation army white stripes", "bad guy billie eilish"]:
        first = yt.search(q, filter="songs", limit=3)[0]
        songs[q] = first
        print(q, "->", first["videoId"], first.get("title"), first.get("duration"), first.get("videoType"))


def counterparts():
    for q, s in songs.items():
        wp = yt.get_watch_playlist(videoId=s["videoId"], limit=1)
        first = (wp.get("tracks") or [{}])[0]
        cp = first.get("counterpart")
        if cp:
            cps[q] = cp
        print(q, "| first:", first.get("videoId"), first.get("videoType"), first.get("length"),
              "| counterpart:", cp and (cp.get("videoId"), cp.get("videoType"), cp.get("length"), cp.get("views")),
              "| lyrics:", wp.get("lyrics"), "| related:", wp.get("related"))


def raw_next():
    vid = songs["blinding lights the weeknd"]["videoId"]
    base = {"enablePersistentPlaylistPanel": True, "isAudioOnly": True, "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "videoId": vid, "playlistId": "RDAMVM" + vid,
            "watchEndpointMusicSupportedConfigs": {"watchEndpointMusicConfig": {
                "hasPersistentPlaylistPanel": True, "musicVideoType": "MUSIC_VIDEO_TYPE_ATV"}}}
    for name, body in [("audio_only", base), ("not_audio_only", {**base, "isAudioOnly": False}),
                       ("plain", {"videoId": vid, "playlistId": "RDAMVM" + vid, "isAudioOnly": True}),
                       ("bare", {"videoId": vid, "playlistId": "RDAMVM" + vid})]:
        r = yt._send_request("next", body)
        text = json.dumps(r)
        print(name, "wrappers:", text.count("playlistPanelVideoWrapperRenderer"),
              "counterparts:", text.count("counterpartRenderer"), "size:", len(text))
        save(f"next_{name}", r)


def suggestions():
    print(yt.get_search_suggestions("daft p"))
    save("suggestions", yt._send_request("music/get_search_suggestions", {"input": "daft p"}))


def search():
    for f in [None, "songs", "videos", "albums", "artists", "playlists"]:
        params = get_search_params(f, None, False)
        body = {"query": "daft punk"}
        if params:
            body["params"] = params
        r = yt._send_request("search", body)
        save(f"search_{f or 'all'}", r)
        print(f, params, len(json.dumps(r)))
    for r in yt.search("daft punk")[:6]:
        print("  all:", r.get("category"), r.get("resultType"), r.get("title") or r.get("artist"))


def artist_album():
    a = yt.search("daft punk", filter="artists", limit=1)[0]
    print("artist", a.get("browseId"), a.get("artist"))
    save("artist_raw", yt._send_request("browse", {"browseId": a["browseId"]}))
    art = yt.get_artist(a["browseId"])
    print("artist keys", list(art.keys()), "songs:", len((art.get("songs") or {}).get("results") or []))
    al = yt.search("random access memories daft punk", filter="albums", limit=1)[0]
    print("album", al.get("browseId"), al.get("title"))
    save("album_raw", yt._send_request("browse", {"browseId": al["browseId"]}))
    alb = yt.get_album(al["browseId"])
    print("album tracks", len(alb.get("tracks") or []), alb.get("audioPlaylistId"))


def lyrics():
    vid = songs["blinding lights the weeknd"]["videoId"]
    wp = yt.get_watch_playlist(videoId=vid, limit=1)
    lid = wp.get("lyrics")
    print("lyrics id", lid)
    if lid:
        save("lyrics_plain", yt._send_request("browse", {"browseId": lid}))
        with yt.as_mobile():
            save("lyrics_timed", yt._send_request("browse", {"browseId": lid}))
        timed = yt.get_lyrics(lid, timestamps=True)
        print("timed:", timed and timed.get("hasTimestamps"), str(timed)[:300])
    r = requests.get("https://lrclib.net/api/get", timeout=15,
                     params={"track_name": "Blinding Lights", "artist_name": "The Weeknd", "duration": 200})
    print("lrclib", r.status_code, ((r.json().get("syncedLyrics") or "")[:120]) if r.ok else r.text[:200])


def heat():
    ctx = {"client": {"clientName": "WEB", "clientVersion": "2.20251105.01.00", "hl": "en", "gl": "US"}}
    ids = [songs["blinding lights the weeknd"]["videoId"]] + [c["videoId"] for c in list(cps.values())[:2]]
    for i, vid in enumerate(ids):
        r = requests.post("https://www.youtube.com/youtubei/v1/next?prettyPrint=false", timeout=20,
                          json={"context": ctx, "videoId": vid},
                          headers={"User-Agent": UA, "Origin": "https://www.youtube.com"})
        t = r.text
        print(vid, "status", r.status_code, "macroMarkersListEntity:", t.count("macroMarkersListEntity"),
              "intensityScoreNormalized:", t.count("intensityScoreNormalized"), "size", len(t))
        if i < 2:
            save(f"web_next_{i}", r.json())


def home():
    for bid in ["FEmusic_home", "FEmusic_moods_and_genres", "FEmusic_charts"]:
        r = yt._send_request("browse", {"browseId": bid})
        save(f"browse_{bid}", r)
        print(bid, len(json.dumps(r)))


def ytdlp():
    import yt_dlp
    vid = (list(cps.values())[0]["videoId"]) if cps else songs["blinding lights the weeknd"]["videoId"]
    fmt = "bestvideo[height<=480][vcodec^=avc1]/bestvideo[height<=480]/best[height<=480]"
    for client in [None, ["visionos"], ["tv"]]:
        o = {"quiet": True, "skip_download": True, "format": fmt, "js_runtimes": {"node": {}}}
        if client:
            o["extractor_args"] = {"youtube": {"player_client": client}}
        try:
            info = yt_dlp.YoutubeDL(o).extract_info("https://www.youtube.com/watch?v=" + vid, download=False)
            kinds = sorted({(f.get("vcodec") or "?")[:4] for f in info.get("formats") or []})
            print(client, "ok", info.get("format_id"), info.get("height"), "heat", bool(info.get("heatmap")), kinds)
        except Exception as e:
            print(client, "error", str(e)[:300])


def video_search():
    out = {}
    for q, song in songs.items():
        artist = ", ".join(a["name"] for a in song.get("artists") or [])
        res = yt.search(f"{song['title']} {artist}", filter="videos", limit=10)
        out[q] = {"song": {"title": song["title"], "artists": [a["name"] for a in song.get("artists") or []],
                           "duration_seconds": song.get("duration_seconds")},
                  "videos": [{k: r.get(k) for k in ("title", "videoId", "artists", "duration", "duration_seconds",
                                                     "videoType", "views", "resultType")} for r in res]}
        print(q, "->", [(r.get("title"), r.get("duration")) for r in res[:4]])
    save("video_search", out)
    vid = songs["blinding lights the weeknd"]["videoId"]
    save("search_videos_raw", yt._send_request("search", {"query": "Blinding Lights The Weeknd",
                                                         "params": get_search_params("videos", None, False)}))


def related():
    wp = yt.get_watch_playlist(videoId=songs["holocene bon iver"]["videoId"], limit=1)
    rid = wp.get("related")
    if rid:
        save("related_raw", yt._send_request("browse", {"browseId": rid}))
        rel = yt.get_song_related(rid)
        print("related sections:", [s.get("title") for s in rel])


def home_titles():
    for bid in ["FEmusic_home", "FEmusic_charts", "FEmusic_moods_and_genres"]:
        j = json.load(open(f"{OUT}/browse_{bid}.json"))
        text = json.dumps(j)
        print(bid, "carousels:", text.count("musicCarouselShelfRenderer"), "chips:", text.count("chipCloudChipRenderer"))
        try:
            secs = j["contents"]["singleColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]
            for sec in secs:
                k = list(sec.keys())[0]
                hdr = json.dumps(sec[k].get("header", {}))[:0]
                title = ""
                try:
                    title = sec[k]["header"]["musicCarouselShelfBasicHeaderRenderer"]["title"]["runs"][0]["text"]
                except Exception:
                    pass
                print("   ", k, title, len(sec[k].get("contents") or sec[k].get("items") or []))
        except Exception as e:
            print("   layout?", e)


def heat_of(vid):
    ctx = {"client": {"clientName": "WEB", "clientVersion": "2.20251105.01.00", "hl": "en", "gl": "US"}}
    r = requests.post("https://www.youtube.com/youtubei/v1/next?prettyPrint=false", timeout=20,
                      json={"context": ctx, "videoId": vid}, headers={"User-Agent": UA, "Origin": "https://www.youtube.com"})
    j = r.json()
    for m in ((j.get("frameworkUpdates") or {}).get("entityBatchUpdate") or {}).get("mutations") or []:
        e = (m.get("payload") or {}).get("macroMarkersListEntity")
        if e and e["markersList"].get("markerType") == "MARKER_TYPE_HEATMAP":
            return [(int(x["startMillis"]) / 1000, int(x["durationMillis"]) / 1000, float(x["intensityScoreNormalized"]))
                    for x in e["markersList"]["markers"]]
    return []


def seconds_curve(heat, dur):
    out = [0.0] * int(dur)
    for a, d, v in heat:
        for t in range(int(a), min(int(dur), int(a + d) + 1)):
            out[t] = v
    return out


def align(song, video, sdur, vdur):
    s, v = seconds_curve(song, sdur), seconds_curve(video, vdur)
    lo, hi = -10, int(vdur - sdur) + 10
    best = []
    skip = max(6, int(sdur * 0.05))
    for o in range(lo, hi + 1):
        xs, ys = [], []
        for t in range(skip, int(sdur) - 3):
            if 0 <= t + o < len(v):
                xs.append(s[t]); ys.append(v[t + o])
        if len(xs) < sdur * 0.6:
            continue
        mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
        cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        vx = sum((x - mx) ** 2 for x in xs) ** 0.5
        vy = sum((y - my) ** 2 for y in ys) ** 0.5
        if vx and vy:
            best.append((cov / (vx * vy), o))
    best.sort(reverse=True)
    return best[:3]


def heat_align():
    vs = json.load(open(f"{OUT}/video_search.json"))
    for q, d in vs.items():
        song = songs[q]
        sheat = heat_of(song["videoId"])
        sdur = d["song"]["duration_seconds"]
        main = d["song"]["artists"][0].lower()
        for r in d["videos"]:
            names = [a.get("name", "").lower() for a in r.get("artists") or []]
            if r["videoType"] != "MUSIC_VIDEO_TYPE_OMV" or main not in names or not r["duration_seconds"]:
                continue
            vheat = heat_of(r["videoId"])
            res = align(sheat, vheat, sdur, r["duration_seconds"]) if sheat and vheat else "no heat"
            print(q, "|", r["title"][:50], r["videoId"], "diff", r["duration_seconds"] - sdur, "| best", res)


for name, fn in [("songs", find_songs), ("heat align", heat_align)]:
    step(name, fn)
