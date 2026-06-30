#!/usr/bin/env node
/**
 * TODO placeholder olan tüm günleri Gemini ile doldurur.
 *
 * Kullanım:
 *   GEMINI_API_KEY=... node scripts/fill-with-gemini.js maia/WordPacks/2026-06.json
 *   # veya:
 *   GEMINI_API_KEY="$(firebase functions:secrets:access GEMINI_API_KEY)" node scripts/fill-with-gemini.js maia/WordPacks/2026-06.json
 *
 * Flags:
 *   --concurrency N     paralel istek sayısı (varsayılan 4)
 *   --only YYYY-MM-DD   yalnızca bu günü işle
 *   --dry-run           dosyaya yazma, sadece kaç kelime işlenecek raporla
 *
 * - Yalnız `definition` alanı `TODO` ile başlayan kelimeleri günceller.
 * - Her kelime için tek Gemini çağrısı yapar; cevap JSON şemasına göre validate edilir.
 * - Her N kelimede bir checkpoint kaydeder; yarıda kesilirse kalan TODO'lar bir sonraki run'da doldurulur.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { GoogleGenerativeAI } = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "@google",
  "generative-ai"
));

// ----------------------- args / config -----------------------

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 0) {
    fail(
      "usage: GEMINI_API_KEY=... node scripts/fill-with-gemini.js <wordpack.json> [--concurrency N] [--only YYYY-MM-DD] [--dry-run]"
    );
  }
  const target = args[0];
  const opts = {
    target,
    concurrency: 4,
    only: null,
    dryRun: false,
    checkpointEvery: 6,
  };
  for (let i = 1; i < args.length; i++) {
    const a = args[i];
    if (a === "--concurrency") {
      opts.concurrency = parseInt(args[++i], 10) || 4;
    } else if (a === "--only") {
      opts.only = args[++i];
    } else if (a === "--dry-run") {
      opts.dryRun = true;
    } else {
      fail(`unknown arg: ${a}`);
    }
  }
  return opts;
}

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

// ----------------------- gemini -----------------------

const MODELS = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-1.5-flash-002"];

function buildPrompt(entry) {
  const wordCount = entry.word.split(/\s+/).length;
  return `You are an English vocabulary content writer for a CEFR-graded learner app.

Generate teaching content for the word: "${entry.word}"
CEFR level: ${(entry.cefrLevel || "a1").toUpperCase()}
Part of speech: ${entry.partOfSpeech || "any"}
Register: ${entry.registerTag || "neutral"}

Return STRICT JSON ONLY (no markdown, no commentary) with this exact shape:

{
  "definition": "<one short English sentence, ~8-13 words, suitable for a CEFR ${(entry.cefrLevel || "a1").toUpperCase()} learner. MUST NOT contain the word '${entry.word}' or any of its inflected forms.>",
  "examples": [
    "<natural English sentence using the word '${entry.word}' (or a clear inflected form) once, ~10-15 words>",
    "<different natural English sentence using the word, different context, ~10-15 words>",
    "<third natural English sentence using the word, different context, ~10-15 words>"
  ],
  "quiz": [
    {
      "type": "definition",
      "question": "What does \\"${entry.word}\\" mean?",
      "options": [
        "<EXACT same string as the definition above>",
        "<plausible-sounding but WRONG English definition; word count must equal the correct definition's word count ±1>",
        "<another plausible WRONG English definition; word count ±1 from correct>",
        "<another plausible WRONG English definition; word count ±1 from correct>"
      ],
      "correctAnswerIndex": 0
    },
    {
      "type": "blank",
      "question": "Fill in the blank: <use example 2 above, replace the word '${entry.word}' (or its inflected form) with _____>",
      "options": [
        "<the exact form of '${entry.word}' that was replaced — could be inflected like '${entry.word}s', '${entry.word}ed' etc.>",
        "<wrong but plausible single-word option, same part of speech>",
        "<another wrong single-word option>",
        "<another wrong single-word option>"
      ],
      "correctAnswerIndex": 0
    },
    {
      "type": "blank",
      "question": "Fill in the blank: <use example 3 above, replace the word '${entry.word}' (or its inflected form) with _____>",
      "options": [
        "<the exact form of '${entry.word}' that was replaced>",
        "<wrong but plausible single-word option, same part of speech>",
        "<another wrong single-word option>",
        "<another wrong single-word option>"
      ],
      "correctAnswerIndex": 0
    }
  ]
}

Rules:
- Output ONLY valid JSON. No backticks, no prose.
- All strings in English.
- Definition must NOT include the target word.
- Each example must contain the target word (or a natural inflected form) at least once.
- For the definition quiz, the 3 WRONG options must each have a word count within ±1 of the correct option's word count.
- Make distractors plausible (real English, grammatical), but unambiguously wrong.`;
}

async function callGeminiOnce(genAI, prompt) {
  let lastError;
  for (const modelName of MODELS) {
    try {
      const model = genAI.getGenerativeModel({
        model: modelName,
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.7,
        },
      });
      const result = await model.generateContent(prompt);
      const text = result.response.text();
      const parsed = JSON.parse(text);
      return { parsed, modelName };
    } catch (err) {
      lastError = err;
      const msg = err && err.message ? err.message : String(err);
      console.warn(`  ! ${modelName} failed: ${msg.slice(0, 200)}`);
    }
  }
  throw lastError || new Error("all models failed");
}

// ----------------------- validation -----------------------

function validateContent(word, content) {
  const errors = [];
  if (typeof content.definition !== "string" || content.definition.length < 6) {
    errors.push("definition missing/too short");
  }
  if (content.definition && content.definition.toLowerCase().includes(word.toLowerCase())) {
    errors.push("definition contains target word");
  }
  if (!Array.isArray(content.examples) || content.examples.length !== 3) {
    errors.push("examples must be array of 3");
  } else {
    content.examples.forEach((ex, i) => {
      if (typeof ex !== "string" || ex.length < 8) {
        errors.push(`example ${i + 1} too short`);
      }
    });
  }
  if (!Array.isArray(content.quiz) || content.quiz.length !== 3) {
    errors.push("quiz must be array of 3");
  } else {
    content.quiz.forEach((q, i) => {
      if (!q || typeof q.question !== "string") {
        errors.push(`quiz ${i + 1} missing question`);
      }
      if (!Array.isArray(q.options) || q.options.length !== 4) {
        errors.push(`quiz ${i + 1} must have 4 options`);
      }
      if (q.correctAnswerIndex !== 0) {
        errors.push(`quiz ${i + 1} correctAnswerIndex must be 0`);
      }
    });
  }
  return errors;
}

// ----------------------- worker pool -----------------------

async function processInPool(items, worker, concurrency) {
  const results = new Array(items.length);
  let cursor = 0;
  const workers = Array.from({ length: concurrency }, async () => {
    while (true) {
      const i = cursor++;
      if (i >= items.length) return;
      try {
        results[i] = await worker(items[i], i);
      } catch (err) {
        results[i] = { error: err };
      }
    }
  });
  await Promise.all(workers);
  return results;
}

// ----------------------- main -----------------------

async function main() {
  const opts = parseArgs(process.argv);
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    fail("GEMINI_API_KEY env var not set.");
  }
  const targetPath = path.resolve(opts.target);
  if (!fs.existsSync(targetPath)) {
    fail(`file not found: ${targetPath}`);
  }
  const raw = fs.readFileSync(targetPath, "utf8");
  const pack = JSON.parse(raw);
  if (!pack.days) fail("invalid wordpack: no .days");

  // Collect every TODO entry (with day + index pointers so we can write back)
  const tasks = [];
  for (const [dayISO, day] of Object.entries(pack.days)) {
    if (opts.only && dayISO !== opts.only) continue;
    if (!day || !Array.isArray(day.words)) continue;
    day.words.forEach((w, idx) => {
      if (typeof w.definition === "string" && w.definition.startsWith("TODO")) {
        tasks.push({ dayISO, idx, entry: w });
      }
    });
  }

  console.log(
    `Found ${tasks.length} TODO words across ${
      new Set(tasks.map((t) => t.dayISO)).size
    } day(s).`
  );
  if (opts.dryRun) {
    console.log("Dry run — no API calls made.");
    return;
  }
  if (tasks.length === 0) {
    console.log("Nothing to fill. ✓");
    return;
  }

  const genAI = new GoogleGenerativeAI(apiKey);

  let processed = 0;
  let failures = 0;
  const startedAt = Date.now();

  // Periodic checkpoint save
  function saveCheckpoint(reason) {
    fs.writeFileSync(
      targetPath,
      JSON.stringify(pack, null, 2) + "\n",
      "utf8"
    );
    console.log(`  · checkpoint saved (${reason})`);
  }

  await processInPool(
    tasks,
    async (task, i) => {
      const { dayISO, idx, entry } = task;
      const prompt = buildPrompt(entry);
      try {
        const { parsed, modelName } = await callGeminiOnce(genAI, prompt);
        const errors = validateContent(entry.word, parsed);
        if (errors.length > 0) {
          throw new Error(`validation failed: ${errors.join("; ")}`);
        }
        // Ensure quiz definition correct option equals definition exactly
        if (parsed.quiz[0].options[0] !== parsed.definition) {
          parsed.quiz[0].options[0] = parsed.definition;
        }
        // Force question on quiz[0] to canonical form
        parsed.quiz[0].question = `What does "${entry.word}" mean?`;
        parsed.quiz[0].type = "definition";
        parsed.quiz[1].type = "blank";
        parsed.quiz[2].type = "blank";

        // Write into pack
        const target = pack.days[dayISO].words[idx];
        target.definition = parsed.definition;
        target.examples = parsed.examples;
        target.quiz = parsed.quiz;

        processed++;
        const elapsed = ((Date.now() - startedAt) / 1000).toFixed(1);
        console.log(
          `[${processed + failures}/${tasks.length}] ✓ ${dayISO} · ${
            entry.word
          } (${entry.cefrLevel}) [${modelName}, ${elapsed}s]`
        );
      } catch (err) {
        failures++;
        console.error(
          `[${processed + failures}/${tasks.length}] ✗ ${dayISO} · ${
            entry.word
          } — ${err.message}`
        );
      }

      // Save every N successful entries (best-effort)
      if (processed > 0 && processed % opts.checkpointEvery === 0) {
        saveCheckpoint(`every ${opts.checkpointEvery}`);
      }
    },
    opts.concurrency
  );

  saveCheckpoint("final");
  const totalSec = ((Date.now() - startedAt) / 1000).toFixed(1);
  console.log(
    `\nDone: ${processed} filled, ${failures} failed, ${tasks.length} total in ${totalSec}s.`
  );
  if (failures > 0) {
    console.log(
      "Tip: re-run the script — only remaining TODOs will be re-tried."
    );
    process.exit(2);
  }
}

main().catch((err) => {
  console.error("fatal:", err.stack || err.message || err);
  process.exit(1);
});
