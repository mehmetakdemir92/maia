/**
 * Maia Cloud Functions
 * - generateExample: Gemini (AI Studio) ile kelime için yeni örnek cümle üretir
 * - correctSentence: Gemini ile diary'deki kullanıcı cümlesini düzeltir (grammar/vocab)
 * - scheduledDailyWords / ensureDailyWords: Firestore dailyWords + Cloud TTS telaffuz URL’leri
 * - ensureWordPronunciation: tek kelime TTS (Storage önbellek)
 *
 * API key: firebase functions:secrets:set GEMINI_API_KEY
 * Key al: https://aistudio.google.com/app/apikey
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const {
  runDailyWordsJob,
  calendarDayISO,
  ALLOWED_DAILY_WORD_CATEGORIES,
  normalizeLevel,
} = require("./dailyWordsScheduler");
const { ensureWordPronunciation } = require("./pronunciation");

admin.initializeApp();

// Secret Manager'dan API key - runWith ile bağlanır
const runtimeOpts = { secrets: ["GEMINI_API_KEY"] };
const GEMINI_TEXT_MODELS = (
  process.env.GEMINI_TEXT_MODELS ||
  "gemini-2.5-flash,gemini-2.5-flash-lite,gemini-1.5-flash-latest"
)
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);

function getGemini() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY secret not set. Run: firebase functions:secrets:set GEMINI_API_KEY");
  }
  return new GoogleGenerativeAI(apiKey);
}

async function generateTextWithModelFallback(genAI, prompt) {
  let lastError;
  for (const modelName of GEMINI_TEXT_MODELS) {
    try {
      const model = genAI.getGenerativeModel({ model: modelName });
      const result = await model.generateContent(prompt);
      return { result, modelName };
    } catch (err) {
      lastError = err;
      console.warn(`Gemini model failed (${modelName}):`, err.message || err);
    }
  }
  throw lastError || new Error("No Gemini model succeeded.");
}

/**
 * Kelime için yeni bir örnek cümle üretir (Generate more).
 * Callable: { word, definition, exampleSentence }
 */
exports.generateExample = functions.runWith(runtimeOpts).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const { word, definition, exampleSentence } = data;
  if (!word || !definition) {
    throw new functions.https.HttpsError("invalid-argument", "word and definition required.");
  }

  try {
    const genAI = getGemini();

    const prompt = `You are an English vocabulary teacher. Generate ONE new, natural example sentence that uses the word "${word}" correctly. The word means: ${definition}.${exampleSentence ? ` Existing example (do not copy): ${exampleSentence}` : ""} Reply with ONLY the single sentence, no quotes, no explanation.`;

    const { result, modelName } = await generateTextWithModelFallback(genAI, prompt);
    const response = result.response;
    if (!response || !response.text) {
      console.error("Gemini generateExample: no text in response", JSON.stringify(result));
      throw new functions.https.HttpsError("internal", "Gemini returned no text.");
    }
    const sentence = response.text().trim().replace(/^["']|["']$/g, "");
    console.log(`generateExample used model: ${modelName}`);
    return { sentence };
  } catch (err) {
    console.error("generateExample error:", err.message || err);
    throw new functions.https.HttpsError("internal", err.message || "Gemini API error");
  }
});

/**
 * Kullanıcının yazdığı cümleyi düzeltir (grammar/spelling). Kelime bağlamında.
 * Callable: { word, definition, userSentence }
 */
exports.correctSentence = functions.runWith(runtimeOpts).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const { word, definition, userSentence } = data;
  if (!word || !userSentence) {
    throw new functions.https.HttpsError("invalid-argument", "word and userSentence required.");
  }

  try {
    const genAI = getGemini();

    const prompt = `You are an English teacher. The student wrote a sentence using the word "${word}"${definition ? ` (meaning: ${definition})` : ""}. Improve grammar, spelling, and natural word choice with MINIMAL edits: keep the student's wording and structure whenever possible; do not rewrite from scratch. One sentence only. Reply with ONLY the corrected sentence, no quotes, no explanation. Student's sentence: ${userSentence}`;

    const { result, modelName } = await generateTextWithModelFallback(genAI, prompt);
    const response = result.response;
    if (!response || !response.text) {
      console.error("Gemini correctSentence: no text in response", JSON.stringify(result));
      throw new functions.https.HttpsError("internal", "Gemini returned no text.");
    }
    const corrected = response.text().trim().replace(/^["']|["']$/g, "");
    console.log(`correctSentence used model: ${modelName}`);
    return { corrected };
  } catch (err) {
    console.error("correctSentence error:", err.message || err);
    throw new functions.https.HttpsError("internal", err.message || "Gemini API error");
  }
});

/**
 * İstemci Firestore’a yazamaz; bugünün dailyWords/{yyyy-MM-dd}_l{level} dokümanını Admin ile oluşturur veya tamamlar.
 * Callable: { date?: string, category?: string, userLevel: number } — date verilirse sunucu günü (İstanbul) ile aynı olmalı.
 */
exports.ensureDailyWords = functions
  .runWith({
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 300,
    memory: "512MB",
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
    }
    const serverDate = calendarDayISO();
    if (data?.date != null && typeof data.date === "string" && data.date !== serverDate) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Date must match server today (Europe/Istanbul)."
      );
    }
    const rawCategory = typeof data?.category === "string" ? data.category : "general";
    if (!ALLOWED_DAILY_WORD_CATEGORIES.has(rawCategory)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid category.");
    }
    if (data?.userLevel == null) {
      throw new functions.https.HttpsError("invalid-argument", "userLevel is required.");
    }
    const userLevel = normalizeLevel(data.userLevel);
    try {
      const result = await runDailyWordsJob({
        getGemini,
        date: serverDate,
        category: rawCategory,
        userLevel,
        source: "callable_ensureDailyWords",
      });
      if (result.skipped && result.reason === "pool_exhausted") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Not enough unused words left in the pool for today."
        );
      }
      return result;
    } catch (err) {
      if (err instanceof functions.https.HttpsError) {
        throw err;
      }
      console.error("ensureDailyWords error:", err.message || err);
      throw new functions.https.HttpsError("internal", err.message || "ensureDailyWords failed");
    }
  });

/**
 * Cloud Scheduler (Pub/Sub) — deploy sonrası otomatik job.
 * İlk kez: Google Cloud Console’da Cloud Scheduler API açık olmalı.
 */
exports.scheduledDailyWords = functions
  .runWith({
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 300,
    memory: "512MB",
  })
  .pubsub.schedule("0 0 * * *")
  .timeZone("Europe/Istanbul")
  .onRun(async () => {
    const results = [];
    for (let level = 1; level <= 11; level += 1) {
      const result = await runDailyWordsJob({
        getGemini,
        userLevel: level,
        source: "scheduled_daily_words",
      });
      results.push(result);
    }
    console.log("scheduledDailyWords results:", JSON.stringify(results));
    return results;
  });

/**
 * Operasyonel callable: belirli gün+seviye için regenerate/backfill.
 * Callable: { date?: string, category?: string, userLevel: number, forceRegenerate?: boolean }
 * Güvenlik: yalnızca admin claim olan kullanıcılar.
 */
/**
 * Kelime telaffuzu: Storage'da MP3 yoksa Cloud TTS ile üretir, kalıcı download URL döner.
 * Callable: { word: string }
 */
exports.ensureWordPronunciation = functions
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
    }
    const word = typeof data?.word === "string" ? data.word.trim() : "";
    if (!word || word.length > 64) {
      throw new functions.https.HttpsError("invalid-argument", "word is required (max 64 chars).");
    }
    try {
      return await ensureWordPronunciation(word);
    } catch (err) {
      console.error("ensureWordPronunciation error:", err.message || err);
      throw new functions.https.HttpsError("internal", err.message || "Pronunciation failed");
    }
  });

exports.regenerateDailyWords = functions
  .runWith({
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 300,
    memory: "512MB",
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!context.auth.token || context.auth.token.admin !== true) {
      throw new functions.https.HttpsError("permission-denied", "Admin role required.");
    }
    if (data?.userLevel == null) {
      throw new functions.https.HttpsError("invalid-argument", "userLevel is required.");
    }
    const targetDate = typeof data?.date === "string" && data.date.trim().length
      ? data.date.trim()
      : calendarDayISO();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
      throw new functions.https.HttpsError("invalid-argument", "date must be yyyy-MM-dd.");
    }
    const rawCategory = typeof data?.category === "string" ? data.category : "general";
    if (!ALLOWED_DAILY_WORD_CATEGORIES.has(rawCategory)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid category.");
    }
    const userLevel = normalizeLevel(data.userLevel);
    const forceRegenerate = Boolean(data?.forceRegenerate);
    try {
      return await runDailyWordsJob({
        getGemini,
        date: targetDate,
        category: rawCategory,
        userLevel,
        forceRegenerate,
        source: "admin_regenerate",
      });
    } catch (err) {
      if (err instanceof functions.https.HttpsError) {
        throw err;
      }
      console.error("regenerateDailyWords error:", err.message || err);
      throw new functions.https.HttpsError("internal", err.message || "regenerateDailyWords failed");
    }
  });
