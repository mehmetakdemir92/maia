# backend-coach (Day 1)

TypeScript + Gemini **streaming** hello world for Maia interview prep.

## Run locally

```bash
cd backend-coach
cp .env.example .env
# Edit .env: set GEMINI_API_KEY, or COACH_MOCK_STREAM=1 for plumbing without a key
npm install
npm run dev
```

Health check:

```bash
curl -s http://127.0.0.1:8787/health
```

Stream (SSE):

```bash
curl -N -X POST http://127.0.0.1:8787/coach/stream \
  -H 'Content-Type: application/json' \
  -d '{"sentence":"i go to school yesterday","word":"yesterday"}'
```

You should see multiple `data: {"text":...}` lines arrive over time, then `{"done":true}`.

## iOS (Simulator)

1. Leave `COACH_SKIP_AUTH=1` in `.env`.
2. Run this server on your Mac.
3. Open Maia → Settings → **Debug: Coach stream**.
4. Base URL default: `http://127.0.0.1:8787` (Simulator only).

Physical device: use your Mac LAN IP (e.g. `http://192.168.x.x:8787`) in the demo screen.

## Day 1 done when

- [x] TypeScript service runs
- [x] `/coach/stream` emits SSE chunks
- [x] iOS DEBUG screen shows text appearing token-by-token
