# gemini-backend — Cloud Run

FastAPI servisi. iOS uygulamasının Firebase Auth token'ını doğrular, prompt'u
Gemini'ye iletir, üretilen metni döner. `maia/ExampleGenerator.swift` bu servisi
çağırır (`baseURL` orada tanımlı).

| Nerede              | Değer                                            |
|---------------------|--------------------------------------------------|
| GCP / Firebase proje | `vocability-6f0f3`                              |
| Proje numarası      | `359781552395`                                    |
| Region              | `europe-west4`                                    |
| Servis URL          | `https://gemini-backend-359781552395.europe-west4.run.app` |

## Gemini erişimi: ücretsiz Developer API

Servis **Vertex AI kullanmıyor**. `genai.Client(api_key=...)` ile ücretsiz
Gemini Developer API'ye (ai.google.dev) gidiyor.

**Neden:** Vertex AI yolu (`vertexai=True, project=..., location=...`) projede
aktif faturalandırma zorunlu kılıyor ve istek başına ücretli. Developer API
ücretsiz kotayla çalışıyor. Karşılığında kota dar — dakikada ~5-6 istek — ve
aşılınca servis 429 döner; uygulama bunu "biraz bekleyin" mesajına çeviriyor
(`ExampleGenerator.friendlyBackendError`).

## Ortam değişkenleri

Cloud Run'da tanımlı olması gerekenler:

| Değişken            | Değer                  |
|---------------------|------------------------|
| `GEMINI_API_KEY`    | ai.google.dev API key  |
| `GEMINI_MODEL`      | `gemini-2.5-flash`     |
| `GEMINI_ALT_MODEL`  | `gemini-2.5-pro`       |

`GCP_PROJECT_ID` / `GCP_LOCATION` **artık kullanılmıyor** (Vertex AI kalıntısı).

> **Dikkat — API key'i terminale yapıştırma.** Bazı terminaller API key'lere
> benzeyen metni otomatik olarak `•` karakterleriyle maskeliyor ve maskeli
> metin gerçek değer olarak kaydedilebiliyor. Sonuç: HTTP header ASCII'ye
> çevrilemediği için her istek `UnicodeEncodeError` ile patlar. Key'i
> değiştirdikten sonra doğrula:
>
> ```bash
> gcloud run services describe gemini-backend --region europe-west4 \
>   --format="value(spec.template.spec.containers[0].env)"
> ```
>
> Değer 39 karakter olmalı ve `•` içermemeli.

## Deploy

Bu klasörden:

```bash
gcloud run deploy gemini-backend --region europe-west4 --source .
```

Env değişkenleri serviste zaten tanımlıysa deploy sırasında korunur.
Sadece bir değişkeni güncellemek için (rebuild etmeden):

```bash
gcloud run services update gemini-backend --region europe-west4 \
  --update-env-vars "GEMINI_API_KEY=..."
```

`--set-env-vars` ile `--remove-env-vars` **aynı komutta kullanılamaz**;
`--set-env-vars` zaten listede olmayan tüm değişkenleri siler.

## Sorun giderme

Servis 5xx dönüyorsa önce container loglarına bak — HTTP durum kodu tek
başına yeterli bilgi vermiyor:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" resource.labels.service_name="gemini-backend"' \
  --limit=30 --format="value(timestamp,textPayload)" --freshness=15m
```

`_generate_text_vertex` her başarısız çağrıda tam traceback basıyor.

Sık görülenler:

| Belirti | Sebep |
|---|---|
| `billing is disabled for this project` | Proje faturalandırma hesabına bağlı değil. Storage/GCS de aynı anda çalışmaz. |
| `UnicodeEncodeError` (httpx `_normalize_header_value`) | `GEMINI_API_KEY` bozuk/maskeli — yukarıdaki uyarıya bak. |
| 429 `RESOURCE_EXHAUSTED` | Ücretsiz kota doldu, bir dakika bekle. |
| `503 The service you requested is not available yet` | Container ayağa kalkarken çöküyor; loglara bak. |
