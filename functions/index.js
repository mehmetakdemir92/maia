/**
 * Vocability Cloud Functions
 * - generateExample: Gemini (AI Studio) ile kelime için yeni örnek cümle üretir
 * - correctSentence: Gemini ile diary'deki kullanıcı cümlesini düzeltir (grammar/vocab)
 *
 * API key: firebase functions:secrets:set GEMINI_API_KEY
 * Key al: https://aistudio.google.com/app/apikey
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();

// Secret Manager'dan API key - runWith ile bağlanır
const runtimeOpts = { secrets: ["GEMINI_API_KEY"] };

function getGemini() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY secret not set. Run: firebase functions:secrets:set GEMINI_API_KEY");
  }
  return new GoogleGenerativeAI(apiKey);
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
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

    const prompt = `You are an English vocabulary teacher. Generate ONE new, natural example sentence that uses the word "${word}" correctly. The word means: ${definition}.${exampleSentence ? ` Existing example (do not copy): ${exampleSentence}` : ""} Reply with ONLY the single sentence, no quotes, no explanation.`;

    const result = await model.generateContent(prompt);
    const response = result.response;
    if (!response || !response.text) {
      console.error("Gemini generateExample: no text in response", JSON.stringify(result));
      throw new functions.https.HttpsError("internal", "Gemini returned no text.");
    }
    const sentence = response.text().trim().replace(/^["']|["']$/g, "");
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
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

    const prompt = `You are an English teacher. The student wrote a sentence using the word "${word}"${definition ? ` (meaning: ${definition})` : ""}. Correct their sentence for grammar and spelling. Keep the same meaning and keep it one sentence. Reply with ONLY the corrected sentence, no quotes, no explanation. Student's sentence: ${userSentence}`;

    const result = await model.generateContent(prompt);
    const response = result.response;
    if (!response || !response.text) {
      console.error("Gemini correctSentence: no text in response", JSON.stringify(result));
      throw new functions.https.HttpsError("internal", "Gemini returned no text.");
    }
    const corrected = response.text().trim().replace(/^["']|["']$/g, "");
    return { corrected };
  } catch (err) {
    console.error("correctSentence error:", err.message || err);
    throw new functions.https.HttpsError("internal", err.message || "Gemini API error");
  }
});
