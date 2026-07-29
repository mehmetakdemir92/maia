#!/usr/bin/env node
/**
 * Fill exampleTranslationsTr for monthly WordPacks (EN and DE).
 *
 * Usage:
 *   GEMINI_API_KEY="$(firebase functions:secrets:access GEMINI_API_KEY)" \
 *     node scripts/fill-example-translations-tr.js maia/WordPacks/2026-08.json
 *   node scripts/fill-example-translations-tr.js maia/WordPacks/2026-08.de.json
 *
 * Flags:
 *   --force          overwrite existing TR glosses
 *   --concurrency N  parallel Gemini calls (default 4)
 *   --dry-run
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { GoogleGenerativeAI } = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "@google",
  "generative-ai"
));

const MODELS = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-flash-latest"];

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = argv.slice(2);
  if (!args[0]) {
    fail("usage: node scripts/fill-example-translations-tr.js <pack.json> [--force] [--concurrency N] [--dry-run]");
  }
  const opts = {
    target: path.resolve(args[0]),
    force: false,
    concurrency: 4,
    dryRun: false,
  };
  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--force") opts.force = true;
    else if (args[i] === "--dry-run") opts.dryRun = true;
    else if (args[i] === "--concurrency") opts.concurrency = parseInt(args[++i], 10) || 4;
    else fail(`unknown arg ${args[i]}`);
  }
  return opts;
}

function extractJSON(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < 0) throw new Error("no JSON");
  return JSON.parse(text.slice(start, end + 1));
}

function needsTr(entry, force) {
  const examples = entry.examples || [];
  if (examples.length === 0) return false;
  const tr = entry.exampleTranslationsTr;
  if (force) return true;
  if (!Array.isArray(tr) || tr.length !== examples.length) return true;
  return tr.some((t) => !t || !String(t).trim());
}

function buildPrompt(entry, sourceLang) {
  const examples = entry.examples || [];
  const enHints = Array.isArray(entry.exampleTranslations) ? entry.exampleTranslations : null;
  return `You translate learner-app example sentences into natural Turkish.

Source language: ${sourceLang}
Headword: "${entry.word}"
CEFR: ${(entry.cefrLevel || "").toUpperCase()}

Translate EACH example into clear, natural Turkish for a Turkish learner.
Keep meaning faithful; do not add explanations.
Return STRICT JSON only:
{
  "exampleTranslationsTr": ["...", "...", "..."]
}

Examples (${examples.length}):
${examples.map((e, i) => `${i + 1}. ${e}`).join("\n")}
${enHints ? `\nEnglish glosses (reference only):\n${enHints.map((e, i) => `${i + 1}. ${e}`).join("\n")}` : ""}

exampleTranslationsTr MUST have exactly ${examples.length} strings.`;
}

async function translateOne(model, entry, sourceLang) {
  const result = await model.generateContent(buildPrompt(entry, sourceLang));
  const parsed = extractJSON(result.response.text());
  const tr = parsed.exampleTranslationsTr;
  if (!Array.isArray(tr) || tr.length !== entry.examples.length) {
    throw new Error(`expected ${entry.examples.length} TR strings, got ${Array.isArray(tr) ? tr.length : typeof tr}`);
  }
  return tr.map((t) => String(t || "").trim());
}

async function mapPool(items, concurrency, worker) {
  const out = new Array(items.length);
  let i = 0;
  async function run() {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await worker(items[idx], idx);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => run()));
  return out;
}

async function main() {
  const opts = parseArgs(process.argv);
  if (!fs.existsSync(opts.target)) fail(`file not found: ${opts.target}`);

  let apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    apiKey = execFileSync("firebase", ["functions:secrets:access", "GEMINI_API_KEY"], {
      encoding: "utf8",
    }).trim();
  }

  const pack = JSON.parse(fs.readFileSync(opts.target, "utf8"));
  const sourceLang = opts.target.includes(".de.json") ? "German" : "English";
  const jobs = [];
  for (const [day, dayPayload] of Object.entries(pack.days || {})) {
    (dayPayload.words || []).forEach((entry, index) => {
      if (needsTr(entry, opts.force)) {
        jobs.push({ day, index, entry });
      }
    });
  }

  console.log(`${path.basename(opts.target)}: ${jobs.length} words need TR glosses (${sourceLang})`);
  if (opts.dryRun || jobs.length === 0) return;

  const genAI = new GoogleGenerativeAI(apiKey);
  let done = 0;

  await mapPool(jobs, opts.concurrency, async (job) => {
    let lastErr = null;
    let tr = null;
    for (const modelName of MODELS) {
      const model = genAI.getGenerativeModel({
        model: modelName,
        generationConfig: { temperature: 0.2 },
      });
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          tr = await translateOne(model, job.entry, sourceLang);
          lastErr = null;
          break;
        } catch (err) {
          lastErr = err;
          await new Promise((r) => setTimeout(r, 300 * attempt));
        }
      }
      if (tr) break;
    }
    if (!tr) {
      console.error(`FAIL ${job.day} ${job.entry.word}: ${lastErr && lastErr.message}`);
      return;
    }
    pack.days[job.day].words[job.index].exampleTranslationsTr = tr;
    done += 1;
    if (done % 20 === 0 || done === jobs.length) {
      console.log(`  progress ${done}/${jobs.length}`);
      fs.writeFileSync(opts.target, JSON.stringify(pack, null, 2) + "\n", "utf8");
    }
  });

  fs.writeFileSync(opts.target, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(`✓ wrote ${opts.target}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
