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
    fail("usage: node scripts/generate-monthly-pack.js YYYY-MM [--force | --merge]");
  }
  const monthKey = args[0];
  if (!/^\d{4}-\d{2}$/.test(monthKey)) {
    fail(`invalid month "${monthKey}". Expected YYYY-MM (e.g. 2026-06).`);
  }
  const flags = new Set(args.slice(1));
  if (flags.has("--force") && flags.has("--merge")) {
    fail("--force ve --merge birlikte kullanılamaz.");
  }
  return {
    monthKey,
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
  const { monthKey, force, merge } = parseArgs(process.argv);

  if (!fs.existsSync(OUT_DIR)) {
    fs.mkdirSync(OUT_DIR, { recursive: true });
  }
  const outPath = path.join(OUT_DIR, `${monthKey}.json`);
  const exists = fs.existsSync(outPath);

  if (exists && !force && !merge) {
    fail(
      `${path.relative(REPO_ROOT, outPath)} zaten var. ` +
        `Mevcut alanları korumak için --merge, üzerine yazmak için --force kullan.`
    );
  }

  const fresh = buildSkeleton(monthKey);

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
