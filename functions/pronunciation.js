/**
 * Google Cloud Text-to-Speech → Firebase Storage (kalıcı MP3).
 * Path: pronunciations/{locale}/{lemma}.mp3 (en-us, de-de, ...)
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const textToSpeech = require("@google-cloud/text-to-speech");

const ttsClient = new textToSpeech.TextToSpeechClient();

const LANGUAGES = {
  en: {
    locale: "en-us",
    languageCode: "en-US",
    voiceName: process.env.TTS_VOICE_NAME || "en-US-Neural2-F",
  },
  de: {
    locale: "de-de",
    languageCode: "de-DE",
    voiceName: process.env.TTS_VOICE_NAME_DE || "de-DE-Neural2-F",
  },
};

const DEFAULT_LANGUAGE = "en";

function resolveLanguage(language) {
  return LANGUAGES[language] ? language : DEFAULT_LANGUAGE;
}

function normalizeLemma(word) {
  const base = String(word || "")
    .trim()
    .toLowerCase()
    // German umlauts/eszett → ASCII so lemmas stay filesystem/URL-safe.
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9'-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
  return base.slice(0, 80);
}

function storagePathForLemma(lemma, language = DEFAULT_LANGUAGE) {
  const { locale } = LANGUAGES[resolveLanguage(language)];
  return `pronunciations/${locale}/${lemma}.mp3`;
}

function downloadURLForFile(bucketName, path, downloadToken) {
  const encoded = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${downloadToken}`;
}

/**
 * @param {string} word
 * @param {string} [language] ISO 639-1 code ("en" | "de"); defaults to "en".
 * @returns {Promise<{ audioURL: string, lemma: string, cached: boolean }>}
 */
async function ensureWordPronunciation(word, language = DEFAULT_LANGUAGE) {
  const lang = resolveLanguage(language);
  const config = LANGUAGES[lang];
  const lemma = normalizeLemma(word);
  if (!lemma) {
    throw new Error("Invalid word");
  }

  const bucket = admin.storage().bucket();
  const path = storagePathForLemma(lemma, lang);
  const file = bucket.file(path);
  const [exists] = await file.exists();

  if (exists) {
    const [meta] = await file.getMetadata();
    const token =
      meta?.metadata?.firebaseStorageDownloadTokens ||
      meta?.metadata?.downloadTokens;
    if (token) {
      const firstToken = String(token).split(",")[0];
      return {
        audioURL: downloadURLForFile(bucket.name, path, firstToken),
        lemma,
        cached: true,
      };
    }
  }

  const displayWord = String(word).trim();
  const [response] = await ttsClient.synthesizeSpeech({
    input: { text: displayWord },
    voice: { languageCode: config.languageCode, name: config.voiceName },
    audioConfig: {
      audioEncoding: "MP3",
      speakingRate: 0.95,
      pitch: 0,
    },
  });

  if (!response.audioContent) {
    throw new Error("TTS returned empty audio");
  }

  const downloadToken = crypto.randomUUID();
  await file.save(response.audioContent, {
    resumable: false,
    metadata: {
      contentType: "audio/mpeg",
      cacheControl: "public, max-age=31536000",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
        lemma,
        sourceWord: displayWord,
        language: lang,
      },
    },
  });

  const audioURL = downloadURLForFile(bucket.name, path, downloadToken);

  try {
    // English keeps the legacy doc id (plain lemma); other locales are prefixed.
    const docId = lang === DEFAULT_LANGUAGE ? lemma : `${config.locale}:${lemma}`;
    await admin
      .firestore()
      .collection("pronunciationCache")
      .doc(docId)
      .set(
        {
          lemma,
          word: displayWord,
          audioURL,
          locale: config.locale,
          voice: config.voiceName,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
  } catch (err) {
    console.warn("pronunciationCache write failed:", err.message || err);
  }

  return { audioURL, lemma, cached: false };
}

module.exports = {
  ensureWordPronunciation,
  normalizeLemma,
  storagePathForLemma,
};
