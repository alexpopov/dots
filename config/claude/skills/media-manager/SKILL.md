---
name: media-manager
description: Use this skill when adding movies or TV shows to Radarr/Sonarr on zorn, doing manual release searches, or checking download status in qBittorrent. Covers selection criteria (audio, quality, size), reusable scripts, and curl patterns.
---

# Media Manager — Radarr / Sonarr / qBittorrent

All services run on **zorn.local** as rootless podman containers.

| Service      | Host port | Root folder |
|---|---|---|
| Radarr       | 7878      | `/movies`   |
| Sonarr       | 8989      | `/tv`       |
| qBittorrent  | 8082      | —           |

API keys live in `~/.zshenv` (or `.env` on zorn) as `RADARR_API_KEY` and `SONARR_API_KEY`. Never hardcode them — dots is a public repo.

On zorn the scripts can also auto-read keys from the container config files:
- `/home/alp/Containers/media-stack/config/radarr/config.xml` → `<ApiKey>`
- `/home/alp/Containers/media-stack/config/sonarr/config.xml` → `<ApiKey>`

## Scripts

Both scripts live alongside this `SKILL.md` and are referenced via `${CLAUDE_SKILL_DIR}`.

```
${CLAUDE_SKILL_DIR}/media-search   # find, rank, and grab a release for a movie or show
${CLAUDE_SKILL_DIR}/media-add      # add a movie/show to Radarr/Sonarr library only (no search)
```

Set env vars before running from the Mac:
```bash
export RADARR_API_KEY=<key>
export SONARR_API_KEY=<key>
export RADARR_HOST=zorn.local   # default
export SONARR_HOST=zorn.local   # default
```

On zorn the scripts auto-detect the key from the XML config if the env var is not set.

---

## Adding a movie (Radarr)

```bash
# Add monitored (Radarr will auto-search):
python3 ${CLAUDE_SKILL_DIR}/media-add movie "Chinatown" 1974

# Add unmonitored + no auto-search (manual grab only):
python3 ${CLAUDE_SKILL_DIR}/media-add movie "Chinatown" 1974 --no-monitor
```

Raw curl equivalent:
```bash
# 1. Look up TMDB ID
curl -s "http://zorn.local:7878/api/v3/movie/lookup?term=Chinatown+1974" \
  -H "X-Api-Key: $RADARR_API_KEY" | jq '[.[] | {title, year, tmdbId}]'

# 2. Add (use tmdbId, titleSlug, images from lookup result)
curl -s -X POST "http://zorn.local:7878/api/v3/movie" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d '{
    "tmdbId": 829, "title": "Chinatown", "year": 1974,
    "qualityProfileId": 4, "rootFolderPath": "/movies",
    "monitored": true, "titleSlug": "chinatown-1974", "images": [],
    "minimumAvailability": "released",
    "addOptions": {"searchForMovie": true}
  }'
```

## Adding a TV show (Sonarr)

```bash
python3 ${CLAUDE_SKILL_DIR}/media-add show "The Bear" --no-monitor
```

Raw curl equivalent:
```bash
curl -s "http://zorn.local:8989/api/v3/series/lookup?term=The+Bear" \
  -H "X-Api-Key: $SONARR_API_KEY" | jq '[.[] | {title, year, tvdbId}]'
```

---

## Manual release search

```bash
# Search and let the script pick (prints its reasoning):
python3 ${CLAUDE_SKILL_DIR}/media-search movie 83        # Radarr movie ID
python3 ${CLAUDE_SKILL_DIR}/media-search show 12         # Sonarr episode ID

# Dry run — show ranked list, don't grab:
python3 ${CLAUDE_SKILL_DIR}/media-search movie 83 --dry-run
```

### Selection criteria

The script scores and filters releases according to these rules:

**Audio — Sonos only supports Dolby.** Reject any release where the dominant
audio track is DTS-HD MA, DTS-X, DTS-HD, or plain DTS. Prefer in order:
1. TrueHD Atmos
2. DD+ Atmos / EAC3 Atmos
3. TrueHD
4. DD+ / EAC3
5. AC3 / Dolby Digital
6. AAC, Opus (acceptable fallback)

**Size budget:**
- 1080p: target 2–5 GB. Below 1.5 GB is over-compressed; above 7 GB is a
  remux and rarely worth the space.
- 4K: target 8–15 GB. Below 5 GB sacrifices too much at 4K; above 20 GB is
  remux territory.

**Source preference (1080p):** BluRay > WEBDL > WEBRip > HDTV

**Scoring algorithm:**
1. Hard-reject: banned audio, size outside budget, fewer than 5 seeders.
2. Sort by seeders descending (primary).
3. Tiebreak by `source_quality × size_score` (bang-for-buck within the budget window).
4. Pick top result. Print full ranked list and rejection reasons.

**Seeder floor:** don't grab anything with fewer than 5 seeders unless nothing
else is available.

---

## Verify a download in qBittorrent

```bash
# Check status of all torrents:
curl -s --cookie-jar /tmp/qbt.jar --cookie /tmp/qbt.jar \
  -d "username=admin&password=$QBT_PASSWORD" \
  "http://zorn.local:8082/api/v2/auth/login"

curl -s --cookie /tmp/qbt.jar \
  "http://zorn.local:8082/api/v2/torrents/info" \
  | jq '.[] | select(.state | startswith("stalled") or . == "downloading") | {name: .name, state: .state, seeds: .num_seeds, progress: .progress}'
```

From inside zorn (no auth required — LocalHostAuth is disabled inside the container):
```bash
ssh alp@zorn.local 'podman exec qbittorrent curl -s http://localhost:8082/api/v2/torrents/info' \
  | jq '.[] | {name: .name[:50], state: .state, seeds: .num_seeds}'
```

---

## Quality profile IDs (Radarr)

| ID | Name            |
|----|-----------------|
| 1  | Any             |
| 4  | HD-1080p        |
| 5  | Ultra-HD        |
| 6  | HD - 720p/1080p |

Use profile `4` for standard 1080p, `5` for 4K.

## Radarr movie status check

```bash
# Check if a movie is already in Radarr:
curl -s "http://zorn.local:7878/api/v3/movie/lookup?term=Whiplash+2014" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  | jq '.[] | select(.year == 2014) | {title, year, tmdbId, hasFile}'
```
