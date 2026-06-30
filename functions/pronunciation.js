/**
 * Google Cloud Text-to-Speech → Firebase Storage (kalıcı MP3).
 * Path: pronunciations/en-us/{lemma}.mp3
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const textToSpeech = require("@google-cloud/text-to-speech");

const ttsClient = new textToSpeech.TextToSpeechClient();
const LOCALE = "en-us";
const VOICE_NAME = process.env.TTS_VOICE_NAME || "en-US-Neural2-F";

function normalizeLemma(word) {
  const base = String(word || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9'-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
  return base.slice(0, 80);
}

function storagePathForLemma(lemma) {
  return `pronunciations/${LOCALE}/${lemma}.mp3`;
}

function downloadURLForFile(bucketName, path, downloadToken) {
  const encoded = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${downloadToken}`;
}

/**
 * @param {string} word
 * @returns {Promise<{ audioURL: string, lemma: string, cached: boolean }>}
 */
async function ensureWordPronunciation(word) {
  const lemma = normalizeLemma(word);
  if (!lemma) {
    throw new Error("Invalid word");
  }

  const bucket = admin.storage().bucket();
  const path = storagePathForLemma(lemma);
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
    voice: { languageCode: "en-US", name: VOICE_NAME },
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
      },
    },
  });

  const audioURL = downloadURLForFile(bucket.name, path, downloadToken);

  try {
    await admin
      .firestore()
      .collection("pronunciationCache")
      .doc(lemma)
      .set(
        {
          lemma,
          word: displayWord,
          audioURL,
          locale: LOCALE,
          voice: VOICE_NAME,
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
