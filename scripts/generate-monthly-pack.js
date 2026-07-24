#!/usr/bin/env node
/**
 * Aylık WordPack iskeleti üretir: maia/WordPacks/{YYYY-MM}.json
 *
 * Her gün için her CEFR bandında (a1, a2, b1, b2, c1, c2) 2 kelime seçer; toplam 12 kelime.
 * Seçim deterministik (FNV-1a 64-bit hash) — aynı ay için tekrar çalıştırınca aynı kelimeler döner.
 * Aynı ay içinde bir kelime tekrar seçilmez (uniqueWithinMonth).
 *
 * Kullanım:
 *   node scripts/generate-monthly-pack.js 2026-06
 *   node scripts/generate-monthly-pack.js 2026-06 --force      # var olanı sil ve yeniden yaz
 *   node scripts/generate-monthly-pack.js 2026-06 --merge      # mevcut definition/examples/quiz alanlarını koru
 *
 * Almanca (öğrenim dili):
 *   node scripts/generate-monthly-pack.js 2026-07 --lang de [--force]
 *
 *   Almanca havuz scripts/data/wordpool-de/{a1..c2}.json dosyalarındadır ve
 *   içerik elle hazırlanmış TAM içeriktir; Gemini doldurması gerekmez.
 *   Kural: kelime + örnek cümleler ALMANCA (kelimenin CEFR seviyesine uygun),
 *   definition + quiz soruları İNGİLİZCE (blank şıkları Almanca kelimeler).
 *   Çıktı: maia/WordPacks/{YYYY-MM}.de.json
 *   Havuz banttaki gün sayısından küçükse kelimeler ay içinde (eşit aralıklarla)
 *   tekrar eder; havuza kelime ekleyip yeniden üreterek tekrarı azaltabilirsin.
 *
 * Üretilen JSON şeması (definition/examples/quiz alanlarını sen elle doldurursun):
 *   {
 *     "month": "YYYY-MM",
 *     "days": {
 *       "YYYY-MM-DD": {
 *         "words": [
 *           {
 *             "word": "...",
 *             "cefrLevel": "a1",
 *             "phonetic": null,
 *             "partOfSpeech": "verb",
 *             "domainTag": "general",
 *             "registerTag": "neutral",
 *             "frequencyBand": 2,
 *             "definition": "TODO: tek cümlelik tanım, kelimenin kendisini içermesin.",
 *             "examples": ["TODO: ...", "TODO: ...", "TODO: ..."],
 *             "quiz": [
 *               // Kural: type=definition için doğru şık `definition` alanının TAM hali olmalı
 *               // (kırpma/paraphrase yok), yanlış 3 şıkkın kelime sayısı doğru şıkka ±1.
 *               { "type": "definition", "question": "What does \"...\" mean?", "options": ["TODO: definition tam hali", "TODO: ±1 kelime", "TODO: ±1 kelime", "TODO: ±1 kelime"], "correctAnswerIndex": 0 },
 *               { "type": "blank", "question": "Fill in the blank: TODO _____ TODO.", "options": ["...", "TODO:", "TODO:", "TODO:"], "correctAnswerIndex": 0 },
 *               { "type": "blank", "question": "Fill in the blank: TODO _____ TODO.", "options": ["...", "TODO:", "TODO:", "TODO:"], "correctAnswerIndex": 0 }
 *             ]
 *           },
 *           ...
 *         ]
 *       },
 *       ...
 *     }
 *   }
 */

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..");
const POOL_PATH = path.join(REPO_ROOT, "functions", "DailyWordPool.txt");
const OUT_DIR = path.join(REPO_ROOT, "maia", "WordPacks");

const BANDS = ["a1", "a2", "b1", "b2", "c1", "c2"];
const WORDS_PER_BAND_PER_DAY = 2;

// ----------------------- args -----------------------

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 0) {
    fail("usage: node scripts/generate-monthly-pack.js YYYY-MM [--force | --merge] [--lang de]");
  }
  const monthKey = args[0];
  if (!/^\d{4}-\d{2}$/.test(monthKey)) {
    fail(`invalid month "${monthKey}". Expected YYYY-MM (e.g. 2026-06).`);
  }
  const rest = args.slice(1);
  let lang = "en";
  const flags = new Set();
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === "--lang") {
      lang = rest[i + 1];
      i += 1;
      continue;
    }
    flags.add(rest[i]);
  }
  if (!["en", "de"].includes(lang)) {
    fail(`unsupported --lang "${lang}". Supported: en, de.`);
  }
  if (flags.has("--force") && flags.has("--merge")) {
    fail("--force ve --merge birlikte kullanılamaz.");
  }
  if (lang !== "en" && flags.has("--merge")) {
    fail("--merge yalnızca İngilizce (skeleton) akışında desteklenir.");
  }
  return {
    monthKey,
    lang,
    force: flags.has("--force"),
    merge: flags.has("--merge"),
  };
}

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

// ----------------------- pool -----------------------

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
  return {
    word,
    cefrLevel: parts[1] ? parts[1].toLowerCase() : null,
    domainTag: nilIfEmpty(parts[2]),
    partOfSpeech: parts[3] ? parts[3].toLowerCase() : null,
    registerTag: parts[4] ? parts[4].toLowerCase() : null,
    frequencyBand: parts[5] && parts[5] !== "" && Number.isFinite(parseInt(parts[5], 10))
      ? parseInt(parts[5], 10)
      : null,
  };
}

function loadPool() {
  if (!fs.existsSync(POOL_PATH)) {
    fail(`DailyWordPool.txt bulunamadı: ${POOL_PATH}`);
  }
  const raw = fs.readFileSync(POOL_PATH, "utf8");
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

// ----------------------- hash -----------------------

/** FNV-1a 64-bit (BigInt) — Swift WordPackStore.stableScore ile aynı. */
function stableScore(text) {
  let h = 1469598103934665603n;
  const prime = 1099511628211n;
  const mask = (1n << 64n) - 1n;
  for (let i = 0; i < text.length; i++) {
    h ^= BigInt(text.charCodeAt(i));
    h = (h * prime) & mask;
  }
  return h;
}

function rankByDate(entries, salt) {
  const scored = entries.map((e) => ({ entry: e, score: stableScore(`${salt}|${e.word.toLowerCase()}`) }));
  scored.sort((a, b) => {
    if (a.score < b.score) return -1;
    if (a.score > b.score) return 1;
    return a.entry.word.toLowerCase() < b.entry.word.toLowerCase() ? -1 : 1;
  });
  return scored.map((s) => s.entry);
}

// ----------------------- date helpers -----------------------

function daysInMonth(monthKey) {
  const [y, m] = monthKey.split("-").map((s) => parseInt(s, 10));
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

function isoDate(monthKey, day) {
  return `${monthKey}-${String(day).padStart(2, "0")}`;
}

// ----------------------- skeleton builder -----------------------

function placeholderQuiz(word) {
  return [
    {
      // Doğru şık = entry.definition'ın TAM hali (kırpma yok).
      // Yanlış 3 şıkkın kelime sayısı, doğru şıkka ±1 olmalı.
      type: "definition",
      question: `What does "${word}" mean?`,
      options: [
        "TODO: definition'ın tam hali (kelimeyi içermesin)",
        "TODO: yanlış şık — doğru şıkkın kelime sayısına ±1",
        "TODO: yanlış şık — doğru şıkkın kelime sayısına ±1",
        "TODO: yanlış şık — doğru şıkkın kelime sayısına ±1",
      ],
      correctAnswerIndex: 0,
    },
    {
      type: "blank",
      question: `Fill in the blank: TODO _____ TODO.`,
      options: [word, "TODO:", "TODO:", "TODO:"],
      correctAnswerIndex: 0,
    },
    {
      type: "blank",
      question: `Fill in the blank: TODO _____ TODO.`,
      options: [word, "TODO:", "TODO:", "TODO:"],
      correctAnswerIndex: 0,
    },
  ];
}

function buildSkeletonWord(entry) {
  return {
    word: entry.word,
    cefrLevel: entry.cefrLevel || "a1",
    phonetic: null,
    partOfSpeech: entry.partOfSpeech || null,
    domainTag: entry.domainTag || null,
    registerTag: entry.registerTag || null,
    frequencyBand: entry.frequencyBand || null,
    definition: "TODO: tek cümlelik tanım, kelimenin kendisini içermesin.",
    examples: [
      `TODO: ${entry.word} kelimesini doğal şekilde içeren 1. örnek cümle.`,
      `TODO: ${entry.word} kelimesini doğal şekilde içeren 2. örnek cümle.`,
      `TODO: ${entry.word} kelimesini doğal şekilde içeren 3. örnek cümle.`,
    ],
    quiz: placeholderQuiz(entry.word),
  };
}

function selectWordsForDay({ pool, monthKey, dayISO, usedInMonth }) {
  const byBand = new Map();
  for (const band of BANDS) byBand.set(band, []);
  for (const entry of pool) {
    const band = (entry.cefrLevel || "").toLowerCase();
    if (byBand.has(band)) byBand.get(band).push(entry);
  }

  const selected = [];
  const dayUsed = new Set();
  for (const band of BANDS) {
    const bandPool = byBand.get(band).filter((e) => !usedInMonth.has(e.word.toLowerCase()));
    const ranked = rankByDate(bandPool, `${dayISO}|month-${monthKey}|band-${band}`);
    let picked = 0;
    for (const entry of ranked) {
      if (picked >= WORDS_PER_BAND_PER_DAY) break;
      if (dayUsed.has(entry.word.toLowerCase())) continue;
      selected.push(entry);
      dayUsed.add(entry.word.toLowerCase());
      usedInMonth.add(entry.word.toLowerCase());
      picked += 1;
    }
    if (picked < WORDS_PER_BAND_PER_DAY) {
      // Bant havuzu o ay içinde tükendi — yine de yazmayı dene (dolduramazsa uyar).
      const reuseRanked = rankByDate(byBand.get(band), `${dayISO}|reuse-${band}`);
      for (const entry of reuseRanked) {
        if (picked >= WORDS_PER_BAND_PER_DAY) break;
        if (dayUsed.has(entry.word.toLowerCase())) continue;
        selected.push(entry);
        dayUsed.add(entry.word.toLowerCase());
        picked += 1;
      }
      if (picked < WORDS_PER_BAND_PER_DAY) {
        console.warn(
          `⚠️  ${dayISO}: ${band.toUpperCase()} bandında yeterli kelime yok ` +
            `(${picked}/${WORDS_PER_BAND_PER_DAY}). DailyWordPool.txt'e ekleyebilirsin.`
        );
      }
    }
  }
  return selected;
}

function buildSkeleton(monthKey) {
  const pool = loadPool();
  const days = {};
  const usedInMonth = new Set();
  const totalDays = daysInMonth(monthKey);
  for (let day = 1; day <= totalDays; day++) {
    const dayISO = isoDate(monthKey, day);
    const entries = selectWordsForDay({ pool, monthKey, dayISO, usedInMonth });
    days[dayISO] = {
      words: entries.map(buildSkeletonWord),
    };
  }
  return { month: monthKey, days };
}

// ----------------------- German (full-content pool) -----------------------

const DE_POOL_DIR = path.join(REPO_ROOT, "scripts", "data", "wordpool-de");

function loadGermanPool() {
  const byBand = new Map();
  const seen = new Set();
  for (const band of BANDS) {
    const filePath = path.join(DE_POOL_DIR, `${band}.json`);
    if (!fs.existsSync(filePath)) {
      fail(`Almanca havuz dosyası eksik: ${path.relative(REPO_ROOT, filePath)}`);
    }
    let entries;
    try {
      entries = JSON.parse(fs.readFileSync(filePath, "utf8"));
    } catch (err) {
      fail(`${band}.json parse edilemedi: ${err.message}`);
    }
    if (!Array.isArray(entries) || entries.length === 0) {
      fail(`${band}.json boş ya da dizi değil.`);
    }
    for (const entry of entries) {
      validateGermanEntry(entry, band);
      const key = entry.word.toLowerCase();
      if (seen.has(key)) {
        fail(`Almanca havuzda tekrar eden kelime: "${entry.word}" (${band}).`);
      }
      seen.add(key);
    }
    byBand.set(band, entries);
  }
  return byBand;
}

/** Baş kelime örnek cümlede geçiyor mu (Almanca çekim ekleri toleranslı). */
function exampleContainsHeadword(example, word) {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`(^|[^\\p{L}])${escaped}[\\p{L}]{0,4}([^\\p{L}]|$)`, "iu");
  return re.test(example);
}

function validateGermanEntry(entry, band) {
  const where = `${band}.json → "${entry && entry.word}"`;
  if (!entry || typeof entry.word !== "string" || !entry.word.trim()) {
    fail(`${band}.json içinde word alanı eksik bir kayıt var.`);
  }
  if ((entry.cefrLevel || "").toLowerCase() !== band) {
    fail(`${where}: cefrLevel "${entry.cefrLevel}" dosya bandı (${band}) ile uyuşmuyor.`);
  }
  if (typeof entry.definition !== "string" || entry.definition.trim().length < 8) {
    fail(`${where}: definition eksik ya da çok kısa.`);
  }
  if (entry.definition.toLowerCase().includes(entry.word.toLowerCase())) {
    console.warn(`⚠️  ${where}: definition kelimenin kendisini içeriyor.`);
  }
  if (!Array.isArray(entry.examples) || entry.examples.length !== 3) {
    fail(`${where}: examples tam 3 cümle olmalı.`);
  }
  if (!exampleContainsHeadword(entry.examples[0], entry.word)) {
    fail(`${where}: 1. örnek cümle baş kelimeyi içermiyor.`);
  }
  if (!Array.isArray(entry.quiz) || entry.quiz.length !== 3) {
    fail(`${where}: quiz tam 3 soru olmalı.`);
  }
  entry.quiz.forEach((q, i) => {
    if (!q || typeof q.question !== "string" || !Array.isArray(q.options) || q.options.length !== 4) {
      fail(`${where}: quiz[${i}] şekli bozuk (question + 4 options gerekli).`);
    }
    if (!Number.isInteger(q.correctAnswerIndex) || q.correctAnswerIndex < 0 || q.correctAnswerIndex > 3) {
      fail(`${where}: quiz[${i}].correctAnswerIndex 0-3 aralığında olmalı.`);
    }
    const normalized = q.options.map((o) => String(o).trim().toLowerCase());
    if (new Set(normalized).size !== 4) {
      fail(`${where}: quiz[${i}] şıkları tekrar ediyor.`);
    }
    const correct = q.options[q.correctAnswerIndex];
    if (q.type === "definition" && correct.trim() !== entry.definition.trim()) {
      fail(`${where}: quiz[${i}] (definition) doğru şık definition ile birebir aynı olmalı.`);
    }
    if (q.type === "blank") {
      if (!q.question.includes("_____")) {
        fail(`${where}: quiz[${i}] (blank) soruda _____ yok.`);
      }
      if (correct.trim().toLowerCase() !== entry.word.trim().toLowerCase()) {
        fail(`${where}: quiz[${i}] (blank) doğru şık baş kelime olmalı.`);
      }
    }
  });
}

function buildGermanPackWord(entry) {
  return {
    word: entry.word,
    cefrLevel: entry.cefrLevel.toLowerCase(),
    phonetic: entry.phonetic || null,
    partOfSpeech: entry.partOfSpeech || null,
    domainTag: entry.domainTag || "general",
    registerTag: entry.registerTag || "neutral",
    frequencyBand: Number.isFinite(entry.frequencyBand) ? entry.frequencyBand : null,
    definition: entry.definition,
    examples: entry.examples,
    quiz: entry.quiz,
  };
}

/**
 * Ay için Almanca pack üretir. Her gün her banttan 2 kelime (toplam 12).
 * Bant havuzu ay bazında deterministik sıralanır; havuz kısaysa kelimeler
 * mümkün olan en geniş aralıkla tekrar eder (N kelime → N/2 günde bir).
 */
function buildGermanPack(monthKey) {
  const byBand = loadGermanPool();
  const totalDays = daysInMonth(monthKey);

  const rankedByBand = new Map();
  for (const band of BANDS) {
    const ranked = rankByDate(byBand.get(band), `de|month-${monthKey}|band-${band}`);
    if (ranked.length < WORDS_PER_BAND_PER_DAY + 1) {
      fail(`${band} bandında en az ${WORDS_PER_BAND_PER_DAY + 1} kelime gerekli.`);
    }
    if (ranked.length < totalDays) {
      console.warn(
        `⚠️  ${band.toUpperCase()}: havuzda ${ranked.length} kelime var; ay içinde ` +
          `kelimeler ~${Math.ceil(ranked.length / WORDS_PER_BAND_PER_DAY)} günde bir tekrar eder.`
      );
    }
    rankedByBand.set(band, ranked);
  }

  const days = {};
  for (let day = 1; day <= totalDays; day++) {
    const dayISO = isoDate(monthKey, day);
    const words = [];
    for (const band of BANDS) {
      const ranked = rankedByBand.get(band);
      const n = ranked.length;
      const start = ((day - 1) * WORDS_PER_BAND_PER_DAY) % n;
      for (let k = 0; k < WORDS_PER_BAND_PER_DAY; k++) {
        words.push(buildGermanPackWord(ranked[(start + k) % n]));
      }
    }
    days[dayISO] = { words };
  }
  return { month: monthKey, days };
}

// ----------------------- merge -----------------------

function mergeWithExisting(existing, fresh) {
  if (!existing || !existing.days) return fresh;
  const out = { month: fresh.month, days: {} };
  for (const [dayISO, day] of Object.entries(fresh.days)) {
    const existingDay = existing.days[dayISO];
    if (!existingDay) {
      out.days[dayISO] = day;
      continue;
    }
    out.days[dayISO] = mergeDay(existingDay, day);
  }
  return out;
}

function mergeDay(existingDay, freshDay) {
  const existingByWord = new Map(
    (existingDay.words || []).map((w) => [w.word.toLowerCase(), w])
  );
  const merged = freshDay.words.map((freshWord) => {
    const prev = existingByWord.get(freshWord.word.toLowerCase());
    if (!prev) return freshWord;
    // mevcut definition/examples/quiz/phonetic'i koru; metadatayı yenile.
    return {
      ...freshWord,
      phonetic: prev.phonetic ?? freshWord.phonetic,
      definition: prev.definition ?? freshWord.definition,
      examples: Array.isArray(prev.examples) && prev.examples.length
        ? prev.examples
        : freshWord.examples,
      quiz: Array.isArray(prev.quiz) && prev.quiz.length ? prev.quiz : freshWord.quiz,
    };
  });
  return { words: merged };
}

// ----------------------- main -----------------------

function main() {
  const { monthKey, lang, force, merge } = parseArgs(process.argv);

  if (!fs.existsSync(OUT_DIR)) {
    fs.mkdirSync(OUT_DIR, { recursive: true });
  }
  const fileName = lang === "en" ? `${monthKey}.json` : `${monthKey}.${lang}.json`;
  const outPath = path.join(OUT_DIR, fileName);
  const exists = fs.existsSync(outPath);

  if (exists && !force && !merge) {
    fail(
      `${path.relative(REPO_ROOT, outPath)} zaten var. ` +
        `Mevcut alanları korumak için --merge, üzerine yazmak için --force kullan.`
    );
  }

  const fresh = lang === "de" ? buildGermanPack(monthKey) : buildSkeleton(monthKey);

  let final = fresh;
  if (exists && merge) {
    const existingRaw = fs.readFileSync(outPath, "utf8");
    let existing;
    try {
      existing = JSON.parse(existingRaw);
    } catch (err) {
      fail(`mevcut JSON parse edilemedi (${outPath}): ${err.message}`);
    }
    final = mergeWithExisting(existing, fresh);
  }

  fs.writeFileSync(outPath, JSON.stringify(final, null, 2) + "\n", "utf8");
  const wordCount = Object.values(final.days).reduce(
    (sum, d) => sum + (d.words ? d.words.length : 0),
    0
  );
  const dayCount = Object.keys(final.days).length;
  console.log(
    `✓ ${path.relative(REPO_ROOT, outPath)} yazıldı (${dayCount} gün, toplam ${wordCount} kelime)` +
      (merge ? " — mevcut definition/examples/quiz alanları korundu" : "")
  );
  console.log(
    `  Düzenlemeyi ${path.relative(REPO_ROOT, outPath)} dosyasından yaparsın; uygulama bundle üzerinden okur.`
  );
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    fail(err.message || String(err));
  }
}
