import json
import os
import time
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

import firebase_admin
from firebase_admin import auth as fb_auth

from google import genai
from google.genai import types
from google.api_core import exceptions as google_exceptions

app = FastAPI()

# Firebase Admin (Cloud Run'da otomatik credentials kullanır)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
LOCATION = os.environ.get("GCP_LOCATION", "europe-west4")
MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
# generate: use_alternate_model=True iken kullanılır (Flash’tan farklı ağırlık = daha az “kopya” ikinci cümle)
ALT_MODEL = os.environ.get("GEMINI_ALT_MODEL", "gemini-2.5-pro")

def _parse_model_list(raw: str | None, fallback: list[str]) -> list[str]:
    if not raw:
        return fallback
    parts = [p.strip() for p in raw.split(",")]
    return [p for p in parts if p]

# Comma-separated fallback lists (tried in order)
PRIMARY_MODELS = _parse_model_list(
    os.environ.get("GEMINI_MODELS"),
    [MODEL, "gemini-2.5-flash-lite", "gemini-1.5-flash-002"],
)
ALT_MODELS = _parse_model_list(
    os.environ.get("GEMINI_ALT_MODELS"),
    [ALT_MODEL, "gemini-2.5-pro", "gemini-1.5-pro-002"],
)

client = genai.Client(
    vertexai=True,
    project=PROJECT_ID,
    location=LOCATION,
)

def _is_retryable(exc: Exception) -> bool:
    if isinstance(exc, google_exceptions.ResourceExhausted):
        return True
    if isinstance(exc, google_exceptions.TooManyRequests):
        return True
    # Some SDK paths wrap as generic GoogleAPIError with 429-ish messaging
    msg = str(exc).lower()
    return "429" in msg or "resource exhausted" in msg or "rate exceeded" in msg

def _generate_text_vertex(
    *,
    models: list[str],
    prompt: str,
    temperature: float,
    max_output_tokens: int,
) -> str:
    last_err: Exception | None = None
    for model_name in models:
        for attempt in range(4):
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=temperature,
                        max_output_tokens=max_output_tokens,
                    ),
                )
                return (response.text or "").strip()
            except Exception as exc:  # noqa: BLE001 - we classify retryable errors broadly
                last_err = exc
                if not _is_retryable(exc) or attempt >= 3:
                    break
                # exponential backoff with small jitter
                sleep_s = min(8.0, 0.35 * (2**attempt))
                time.sleep(sleep_s)
        # try next model
        continue
    raise HTTPException(status_code=503, detail=f"Gemini generation failed: {last_err}")

class GenerateReq(BaseModel):
    prompt: str
    # İkinci ek örnek cümle için: farklı model (ör. Pro) — prompt tek başına yeterli olmayınca çeşitlilik için
    use_alternate_model: bool = False


class EnrichWordsReq(BaseModel):
    words: list[str]  # 3 kelime; AI sadece phonetic, definition, exampleSentence doldurur
    category: str = "general"


@app.post("/enrich-words")
def enrich_words(req: EnrichWordsReq, authorization: str | None = Header(default=None)):
    """Verdiğin kelimeler için AI ile phonetic, definition, exampleSentence üretir."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing token")

    token = authorization.replace("Bearer ", "")
    try:
        fb_auth.verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    words_list = ", ".join(f'"{w}"' for w in req.words[:10])  # max 10
    prompt = f"""You are an English vocabulary teacher. For each of these words, provide:
- phonetic (IPA notation)
- definition (simple English, one short sentence)
- exampleSentence (natural, daily use, 8-14 words)

Words: {words_list}

Return ONLY valid JSON, no markdown, no code block. Format:
{{"category": "{req.category}", "words": [{{"word": "...", "phonetic": "...", "definition": "...", "exampleSentence": "..."}}]}}
Use the exact same word strings as given, in the same order. One object per word."""

    text = _generate_text_vertex(
        models=PRIMARY_MODELS,
        prompt=prompt,
        temperature=0.5,
        max_output_tokens=1024,
    )
    # Parse JSON from response (strip code fences if present)
    for raw in (text, text.removeprefix("```json").removeprefix("```").strip().removesuffix("```").strip()):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            continue
    raise HTTPException(status_code=500, detail="AI response was not valid JSON")


@app.post("/generate")
def generate(req: GenerateReq, authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing token")

    token = authorization.replace("Bearer ", "")

    try:
        decoded = fb_auth.verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    models = ALT_MODELS if req.use_alternate_model else PRIMARY_MODELS
    # İkinci cümle yolu: biraz daha yüksek sıcaklık + farklı model
    temp = 0.88 if req.use_alternate_model else 0.7

    text = _generate_text_vertex(
        models=models,
        prompt=req.prompt,
        temperature=temp,
        max_output_tokens=512,
    )

    return {"text": text}
