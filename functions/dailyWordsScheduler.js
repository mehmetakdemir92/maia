/**
 * İstanbul takvim günü için günlük 3 kelime: Swift DailyWordsService ile aynı havuz + FNV-1a rotasyon.
 * Firestore’daki diğer günlerin kelimeleri "used"; bugünün dokümanı hariç tutulur (oluşturma anıyla uyum).
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const GEMINI_TEXT_MODELS = (
  process.env.GEMINI_TEXT_MODELS ||
  "gemini-2.5-flash,gemini-2.5-flash-lite,gemini-1.5-flash-latest"
)
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);

/** Swift DailyWordsService.manualWordsByDate ile aynı rol; boş. */
const MANUAL_WORDS_BY_DATE = {};

/** Swift VocabularyCategory ile aynı (callable + zamanlanmış iş). */
const ALLOWED_DAILY_WORD_CATEGORIES = new Set(["general", "ieltsToefl", "travel", "career"]);
const MIN_LEVEL = 1;
const MAX_LEVEL = 11;

function calendarDayISO(d = new Date()) {
  return d.toLocaleDateString("en-CA", { timeZone: "Europe/Istanbul" });
}

function normalizeLevel(level) {
  const n = Number(level);
  if (!Number.isFinite(n)) return MIN_LEVEL;
  const rounded = Math.trunc(n);
  return Math.min(MAX_LEVEL, Math.max(MIN_LEVEL, rounded));
}

function dailyWordsDocId(dateStr, userLevel) {
  return `${dateStr}_l${normalizeLevel(userLevel)}`;
}

function parsePoolLine(line) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) return null;
  if (!trimmed.includes("|")) {
    return {
      word: trimmed,
      cefrLevel: null,
      domainTag: null,
      partOfSpeech: null,
      registerTag: null,
      frequencyBand: null,
    };
  }
  const parts = trimmed.split("|").map((s) => s.trim());
  const word = parts[0];
  if (!word) return null;
  const nilIfEmpty = (s) => (s && s.length ? s : null);
  const cefr = nilIfEmpty(parts[1]);
  const domain = nilIfEmpty(parts[2]);
  const pos = nilIfEmpty(parts[3]);
  const reg = nilIfEmpty(parts[4]);
  let fb = null;
  if (parts.length > 5 && parts[5] !== "") {
    const n = parseInt(parts[5], 10);
    if (Number.isFinite(n)) fb = n;
  }
  return {
    word,
    cefrLevel: cefr ? cefr.toLowerCase() : null,
    domainTag: domain,
    partOfSpeech: pos ? pos.toLowerCase() : null,
    registerTag: reg ? reg.toLowerCase() : null,
    frequencyBand: fb,
  };
}

function loadPoolEntries(poolFilePath) {
  const raw = fs.readFileSync(poolFilePath, "utf8");
  const seen = new Set();
  const out = [];
  for (const line of raw.split(/\r?\n/)) {
    const e = parsePoolLine(line);
    if (!e) continue;
    const k = e.word.toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(e);
  }
  return out;
}

function stableHash(text) {
  let h = 1469598103934665603n;
  const prime = 1099511628211n;
  const mask = (1n << 64n) - 1n;
  for (let i = 0; i < text.length; i++) {
    h ^= BigInt(text.charCodeAt(i));
    h = (h * prime) & mask;
  }
  return h;
}

function stableWordScore(dateStr, word) {
  return stableHash(`${dateStr}|${word.toLowerCase()}`);
}

function dedupePoolWords(entries) {
  const seen = new Set();
  const out = [];
  for (const e of entries) {
    const k = e.word.toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(e.word);
  }
  return out;
}

function wordsForDate(dateStr, usedSet, entries, userLevel) {
  const pool = entries.slice();
  if (pool.length === 0) {
    return ["learn", "practice", "review"];
  }
  const available = pool.filter((e) => !usedSet.has(e.word.toLowerCase()));
  if (available.length < 3) {
    return [];
  }

  const rankEntries = (candidates, salt) =>
    [...candidates].sort((a, b) => {
      const as = stableWordScore(`${dateStr}|${salt}`, a.word);
      const bs = stableWordScore(`${dateStr}|${salt}`, b.word);
      if (as < bs) return -1;
      if (as > bs) return 1;
      const la = a.word.toLowerCase();
      const lb = b.word.toLowerCase();
      if (la < lb) return -1;
      if (la > lb) return 1;
      return 0;
    });

  const desiredBands = preferredCEFRBands(userLevel);
  const selected = [];
  const selectedWords = new Set();
  let remaining = available.slice();

  for (const band of desiredBands) {
    const bucket = remaining.filter((e) => (e.cefrLevel || "").toLowerCase() === band);
    const pick = rankEntries(bucket, `band-${band}`)[0];
    if (!pick) continue;
    selected.push(pick);
    selectedWords.add(pick.word.toLowerCase());
    remaining = remaining.filter((e) => e.word.toLowerCase() !== pick.word.toLowerCase());
  }

  if (selected.length < 3) {
    const leftovers = remaining.filter((e) => !selectedWords.has(e.word.toLowerCase()));
    for (const entry of rankEntries(leftovers, "fallback")) {
      if (selected.length >= 3) break;
      selected.push(entry);
      selectedWords.add(entry.word.toLowerCase());
    }
  }

  if (selected.length !== 3) return [];

  const finalRanked = [...selected].sort((a, b) => {
    const as = stableWordScore(dateStr, a.word);
    const bs = stableWordScore(dateStr, b.word);
    if (as < bs) return -1;
    if (as > bs) return 1;
    const la = a.word.toLowerCase();
    const lb = b.word.toLowerCase();
    if (la < lb) return -1;
    if (la > lb) return 1;
    return 0;
  });
  return finalRanked.map((e) => e.word);
}

function wordsForDateOrManual(dateStr, usedSet, entries, userLevel) {
  const manual = MANUAL_WORDS_BY_DATE[dateStr];
  if (manual && manual.length === 3) {
    return manual.slice();
  }
  return wordsForDate(dateStr, usedSet, entries, userLevel);
}

async function collectUsedExcludingDateAndLevel(db, excludeDocId, userLevel) {
  const snap = await db.collection("dailyWords").get();
  const used = new Set();
  const levelSuffix = `_l${normalizeLevel(userLevel)}`;
  for (const doc of snap.docs) {
    if (doc.id === excludeDocId) continue;
    if (!doc.id.endsWith(levelSuffix)) continue;
    const words = doc.data()?.words;
    if (!Array.isArray(words)) continue;
    for (const item of words) {
      const w = item?.word;
      if (typeof w === "string" && w.length) used.add(w.toLowerCase());
    }
  }
  return used;
}

function preferredCEFRBands(userLevel) {
  switch (normalizeLevel(userLevel)) {
    case 1: return ["a1", "a1", "a2"];
    case 2: return ["a2", "a2", "a1"];
    case 3: return ["a2", "a2", "b1"];
    case 4: return ["b1", "b1", "a2"];
    case 5: return ["b1", "b1", "b2"];
    case 6: return ["b1", "b1", "b2"];
    case 7: return ["b2", "b2", "c1"];
    case 8: return ["c1", "c1", "b2"];
    case 9: return ["c1", "c1", "c2"];
    case 10: return ["c1", "c1", "c2"];
    case 11: return ["c2", "c2", "c1"];
    default: return ["a1", "a1", "a2"];
  }
}

function logJobEvent(event, payload) {
  console.log(JSON.stringify({ event, ...payload }));
}

function buildEntryByLemma(entries) {
  const m = {};
  for (const e of entries) {
    m[e.word.toLowerCase()] = e;
  }
  return m;
}

function stripCodeFences(text) {
  let t = text.trim();
  if (t.startsWith("```")) {
    const nl = t.indexOf("\n");
    if (nl !== -1) t = t.slice(nl + 1);
    const end = t.lastIndexOf("```");
    if (end !== -1) t = t.slice(0, end);
  }
  return t.trim();
}

function parseEnrichJson(text) {
  const stripped = stripCodeFences(text);
  try {
    return JSON.parse(stripped);
  } catch {
    const start = stripped.indexOf("{");
    const end = stripped.lastIndexOf("}");
    if (start !== -1 && end > start) {
      return JSON.parse(stripped.slice(start, end + 1));
    }
    throw new Error("Gemini enrich: invalid JSON");
  }
}

async function enrichWordsGemini(genAI, lemmas, category) {
  const wordsList = lemmas.map((w) => `"${w}"`).join(", ");
  const prompt = `You are an English vocabulary teacher. For each of these words, provide:
- phonetic (IPA notation)
- definition (simple English, one short sentence)
- exampleSentence (natural, daily use, 8-14 words)

Words: ${wordsList}

Return ONLY valid JSON, no markdown, no code block. Format:
{"category": "${category}", "words": [{"word": "...", "phonetic": "...", "definition": "...", "exampleSentence": "..."}]}
Use the exact same word strings as given, in the same order. One object per word.`;

  let result = null;
  let usedModel = null;
  let lastError = null;
  for (const modelName of GEMINI_TEXT_MODELS) {
    try {
      const model = genAI.getGenerativeModel({ model: modelName });
      result = await model.generateContent(prompt);
      usedModel = modelName;
      break;
    } catch (err) {
      lastError = err;
      console.warn(`Gemini enrich model failed (${modelName}):`, err.message || err);
    }
  }
  if (!result) {
    throw lastError || new Error("Gemini enrich: no model succeeded");
  }
  const response = result.response;
  if (!response || !response.text) {
    throw new Error("Gemini enrich: no text");
  }
  const payload = parseEnrichJson(response.text());
  if (!payload.words || !Array.isArray(payload.words) || payload.words.length < 3) {
    throw new Error("Gemini enrich: missing words array");
  }
  console.log(`dailyWords enrich used model: ${usedModel}`);
  return payload;
}

function wordFirestoreDict(item, meta) {
  const dict = {
    word: item.word,
    definition: item.definition,
    exampleSentence: item.exampleSentence,
  };
  if (item.phonetic) dict.phonetic = item.phonetic;
  if (meta?.cefrLevel) dict.cefrLevel = meta.cefrLevel;
  if (meta?.domainTag) dict.domainTag = meta.domainTag;
  if (meta?.partOfSpeech) dict.partOfSpeech = meta.partOfSpeech;
  if (meta?.registerTag) dict.registerTag = meta.registerTag;
  if (meta?.frequencyBand != null) dict.frequencyBand = meta.frequencyBand;
  return dict;
}

function buildFirestoreWordsFromPayload(payload, entryByLemma) {
  return payload.words.slice(0, 3).map((item) => {
    const meta = entryByLemma[item.word.toLowerCase()];
    return wordFirestoreDict(item, meta);
  });
}

/** @param {{ getGemini: () => unknown, date?: string, category?: string, userLevel?: number, forceRegenerate?: boolean }} opts */
async function runDailyWordsJob(opts) {
  const { getGemini } = opts;
  const db = admin.firestore();
  const date =
    typeof opts.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(opts.date.trim())
      ? opts.date.trim()
      : calendarDayISO();
  const category =
    typeof opts.category === "string" && ALLOWED_DAILY_WORD_CATEGORIES.has(opts.category)
      ? opts.category
      : "general";
  const userLevel = normalizeLevel(opts.userLevel);
  const docId = dailyWordsDocId(date, userLevel);
  const source = opts.source || "unknown";
  const forceRegenerate = Boolean(opts.forceRegenerate);
  const poolPath = path.join(__dirname, "DailyWordPool.txt");
  if (!fs.existsSync(poolPath)) {
    throw new Error(`DailyWordPool.txt missing at ${poolPath}`);
  }
  const entries = loadPoolEntries(poolPath);
  const used = await collectUsedExcludingDateAndLevel(db, docId, userLevel);
  const lemmas = wordsForDateOrManual(date, used, entries, userLevel);

  if (lemmas.length !== 3) {
    logJobEvent("daily_words_skipped", {
      date,
      level: userLevel,
      source,
      status: "pool_exhausted",
      poolRemaining: lemmas.length,
      fallbackUsed: false,
    });
    return { skipped: true, reason: "pool_exhausted", date, level: userLevel };
  }

  const ref = db.collection("dailyWords").doc(docId);
  const existing = await ref.get();
  if (existing.exists && !forceRegenerate) {
    const arr = existing.data()?.words;
    if (Array.isArray(arr) && arr.length === 3) {
      const parsedSorted = arr.map((w) => (w.word || "").toLowerCase()).sort().join("\0");
      const expSorted = lemmas.map((w) => w.toLowerCase()).sort().join("\0");
      if (parsedSorted === expSorted) {
        const complete = arr.every(
          (w) =>
            w.definition &&
            w.exampleSentence &&
            String(w.definition).trim() &&
            String(w.exampleSentence).trim()
        );
        if (complete) {
          logJobEvent("daily_words_skipped", {
            date,
            level: userLevel,
            source,
            status: "already_complete",
            poolRemaining: Math.max(0, entries.length - used.size),
            fallbackUsed: false,
          });
          return { skipped: true, reason: "already_complete", date, level: userLevel };
        }
      }
    }
  }

  const genAI = getGemini();
  const payload = await enrichWordsGemini(genAI, lemmas, category);
  const entryByLemma = buildEntryByLemma(entries);
  const wordsForFirestore = buildFirestoreWordsFromPayload(payload, entryByLemma);

  await ref.set(
    {
      date,
      level: userLevel,
      category: payload.category || "general",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      words: wordsForFirestore,
    },
    { merge: true }
  );

  logJobEvent("daily_words_written", {
    date,
    level: userLevel,
    source,
    status: "ok",
    poolRemaining: Math.max(0, entries.length - used.size - lemmas.length),
    fallbackUsed: false,
    lemmas,
  });
  return { ok: true, date, level: userLevel, docId, lemmas };
}

module.exports = {
  runDailyWordsJob,
  calendarDayISO,
  dailyWordsDocId,
  normalizeLevel,
  loadPoolEntries,
  wordsForDateOrManual,
  collectUsedExcludingDateAndLevel,
  preferredCEFRBands,
  ALLOWED_DAILY_WORD_CATEGORIES,
};
