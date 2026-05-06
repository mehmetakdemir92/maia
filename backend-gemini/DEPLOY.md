# Cloud Run'a deploy (gemini-backend)

## Firebase / GCP uyumu

Backend, Firebase Auth token’larını doğruluyor; **aynı GCP projesi** kullanılmalı.

| Nerede              | Değer            |
|---------------------|------------------|
| Firebase project ID | `maia-6f0f3` |
| GCP project number  | `359781552395`   |
| Cloud Run URL       | `...359781552395.europe-west4.run.app` |

Firebase’te proje değiştirdiysen veya yeni proje açtıysan:

1. **Yeni proje kullanıyorsan**: Firebase Console’dan yeni projenin `GoogleService-Info.plist` dosyasını indir, Xcode’da eskisinin üzerine koy. Backend’i de **o yeni projede** deploy et; Cloud Run env’te `GCP_PROJECT_ID` = yeni proje ID’si olsun.
2. **Aynı proje (maia-6f0f3)** kullanıyorsan: Sadece gcloud’un bu projeye bağlı olduğundan emin ol (aşağıdaki komutlar).

Önce proje ve giriş kontrolü:

```bash
gcloud config get-value project          # maia-6f0f3 olmalı
gcloud auth list                         # ACTIVE bir hesap olmalı
gcloud auth application-default login    # Gerekirse tekrar giriş (deploy için)
```

## Gereksinimler

- [Google Cloud CLI (gcloud)](https://cloud.google.com/sdk/docs/install) yüklü ve `gcloud auth login` yapılmış olmalı.
- Proje: `maia-6f0f3` (Firebase ile aynı).

## Tek seferde deploy

Proje kökünden (maia) çalıştır:

```bash
gcloud run deploy gemini-backend \
  --source backend-gemini \
  --region europe-west4 \
  --project maia-6f0f3 \
  --allow-unauthenticated
```

- `--source backend-gemini`: Bu klasörden Docker image build edilir ve deploy edilir.
- `--allow-unauthenticated`: Servis herkese açık URL’den erişilebilir (zaten Bearer token ile auth yapıyorsun).

İlk seferde “Enable required APIs?” sorusu çıkarsa **Y** de.

## Ortam değişkenleri (zaten ayarlıysa atla)

Servis daha önce deploy edildiyse `GCP_PROJECT_ID` ve isteğe bağlı `GEMINI_MODEL` zaten Cloud Run’da ayarlıdır. İlk kez deploy ediyorsan:

```bash
gcloud run deploy gemini-backend \
  --source backend-gemini \
  --region europe-west4 \
  --project maia-6f0f3 \
  --allow-unauthenticated \
  --set-env-vars "GCP_PROJECT_ID=maia-6f0f3"
```

(Gemini için Vertex AI aynı projede açıksa ekstra bir key gerekmez; default service account kullanılır.)

## Deploy sonrası

Deploy bittikten sonra terminalde servis URL’i yazar (örn. `https://gemini-backend-xxxxx.europe-west4.run.app`). Uygulamadaki `DailyWordsService` içindeki `baseURL` bu adresle aynı olmalı; farklıysa Xcode’da o satırı güncelle.
