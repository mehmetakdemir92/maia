#!/usr/bin/env node
/**
 * Localizable.xcstrings için Gemini ile batch çeviri.
 *
 * Kullanım:
 *   GEMINI_API_KEY=xxx node scripts/translate-xcstrings.js
 *   GEMINI_API_KEY=xxx node scripts/translate-xcstrings.js --langs de,es,fr
 *   GEMINI_API_KEY=xxx node scripts/translate-xcstrings.js --dry-run
 *
 * Tasarım kararları:
 * - "stale" extractionState olan key'ler atlanır.
 * - Hâlihazırda translated/needs_review olan key'lere dokunulmaz (yalnızca eksikleri doldurur).
 * - %@, %lld, %1$@ gibi placeholder'lar prompt'ta korunmaya zorlanır.
 * - 25'lik gruplarla istek atılır (token tasarrufu + model'in tutarlı JSON döndürebilmesi).
 * - 429/5xx exponential backoff ile 3 kez denenir.
 * - JSON parse hatasında o batch atlanır, log düşülür ve sonraki batch'e geçilir.
 */

const fs = require("fs");
const path = require("path");

const apiKey = process.env.GEMINI_API_KEY;
if (!apiKey) {
  console.error("ERROR: GEMINI_API_KEY env var not set.");
  process.exit(1);
}

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const value = (name) => {
  const i = argv.findIndex((a) => a === `--${name}`);
  return i >= 0 ? argv[i + 1] : null;
};

const targetLangsArg = value("langs") || "de,es,fr";
const targetLangs = targetLangsArg.split(",").map((s) => s.trim()).filter(Boolean);
const isDryRun = flag("dry-run");
const batchSize = parseInt(value("batch") || "25", 10);

const xcstringsPath = path.join(__dirname, "..", "maia", "Localizable.xcstrings");
const raw = fs.readFileSync(xcstringsPath, "utf8");
const catalog = JSON.parse(raw);
const sourceLang = catalog.sourceLanguage || "en";

const langDisplay = {
  en: "English",
  tr: "Turkish",
  de: "German (Deutsch)",
  es: "Spanish (Español)",
  fr: "French (Français)",
  it: "Italian (Italiano)",
  pt: "Portuguese (Português)",
};

function sourceValueFor(key, entry) {
  const locs = entry.localizations || {};
  const src = locs[sourceLang]?.stringUnit?.value;
  if (src && src.trim().length) return src;
  return key;
}

function hasUsableTranslation(entry, lang) {
  const u = entry.localizations?.[lang]?.stringUnit;
  if (!u) return false;
  const state = u.state;
  const val = (u.value || "").trim();
  return val.length > 0 && (state === "translated" || state === "needs_review");
}

function collectPendingForLang(lang) {
  const items = [];
  for (const [key, entry] of Object.entries(catalog.strings || {})) {
    if (entry.extractionState === "stale") continue;
    const source = sourceValueFor(key, entry);
    if (!source || !source.trim()) continue;
    if (hasUsableTranslation(entry, lang)) continue;
    items.push({ key, source });
  }
  return items;
}

const GEMINI_MODELS = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-1.5-flash-latest"];

async function callGemini(prompt) {
  let lastErr;
  for (const model of GEMINI_MODELS) {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ role: "user", parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
            }),
          }
        );
        if (!res.ok) {
          const body = await res.text();
          if (res.status === 429 || res.status >= 500) {
            await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
            lastErr = new Error(`Gemini ${model} ${res.status}: ${body.slice(0, 200)}`);
            continue;
          }
          throw new Error(`Gemini ${model} ${res.status}: ${body.slice(0, 200)}`);
        }
        const data = await res.json();
        const text =
          data?.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("") || "";
        return { text, model };
      } catch (err) {
        lastErr = err;
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
  }
  throw lastErr || new Error("Gemini call failed");
}

function buildPrompt(targetLang, items) {
  const langName = langDisplay[targetLang] || targetLang;
  const sourceName = langDisplay[sourceLang] || sourceLang;
  const payload = items.map((it, idx) => ({ id: idx, source: it.source }));
  return `You are translating UI strings for an iOS English-learning app called Maia from ${sourceName} to ${langName}.

RULES:
- Translate naturally and idiomatically into ${langName}, like a native UI writer.
- Keep brevity: UI strings should match the source length when possible.
- PRESERVE placeholders exactly as they appear: %@, %lld, %d, %1$@, %2$lld, etc. Do not translate them.
- PRESERVE backslash escapes and trailing punctuation.
- PRESERVE emoji and symbols.
- The word "Maia" is a brand name; never translate it.
- Do not add quotation marks around the translation.
- Some strings are product terms (e.g. "Streak", "Quiz", "Premium"); translate them into the natural equivalent used by similar apps in ${langName}.

Return ONLY a valid JSON object with this exact shape:
{"translations":[{"id":0,"value":"..."},{"id":1,"value":"..."}]}

Items to translate (${items.length}):
${JSON.stringify(payload, null, 2)}`;
}

function parseGeminiJson(text) {
  let t = (text || "").trim();
  if (t.startsWith("```")) {
    const nl = t.indexOf("\n");
    if (nl >= 0) t = t.slice(nl + 1);
    const end = t.lastIndexOf("```");
    if (end >= 0) t = t.slice(0, end);
  }
  try {
    return JSON.parse(t);
  } catch {
    const start = t.indexOf("{");
    const end = t.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(t.slice(start, end + 1));
    }
    throw new Error("Invalid JSON from Gemini");
  }
}

function applyTranslations(lang, items, translations) {
  let writes = 0;
  for (const t of translations) {
    const item = items[t.id];
    if (!item) continue;
    const value = (t.value || "").trim();
    if (!value) continue;
    const entry = catalog.strings[item.key];
    if (!entry) continue;
    entry.localizations = entry.localizations || {};
    entry.localizations[lang] = {
      stringUnit: { state: "translated", value },
    };
    writes++;
  }
  return writes;
}

async function translateLang(lang) {
  const pending = collectPendingForLang(lang);
  console.log(`\n=== ${lang.toUpperCase()} ===`);
  console.log(`pending: ${pending.length} strings`);
  if (pending.length === 0) return;
  if (isDryRun) {
    console.log("(dry run — skipping API calls)");
    return;
  }

  let written = 0;
  for (let i = 0; i < pending.length; i += batchSize) {
    const batch = pending.slice(i, i + batchSize);
    const prompt = buildPrompt(lang, batch);
    try {
      const { text, model } = await callGemini(prompt);
      const parsed = parseGeminiJson(text);
      const translations = Array.isArray(parsed?.translations) ? parsed.translations : [];
      const w = applyTranslations(lang, batch, translations);
      written += w;
      console.log(
        `  batch ${Math.floor(i / batchSize) + 1}/${Math.ceil(
          pending.length / batchSize
        )} → ${w}/${batch.length} translated (model: ${model})`
      );
    } catch (err) {
      console.warn(`  batch ${Math.floor(i / batchSize) + 1} FAILED:`, err.message);
    }
  }
  console.log(`written: ${written}`);
}

(async () => {
  console.log(`xcstrings: ${xcstringsPath}`);
  console.log(`sourceLanguage: ${sourceLang}`);
  console.log(`targetLanguages: ${targetLangs.join(", ")}`);
  console.log(`total keys in catalog: ${Object.keys(catalog.strings || {}).length}`);

  for (const lang of targetLangs) {
    await translateLang(lang);
  }

  if (!isDryRun) {
    fs.writeFileSync(xcstringsPath, JSON.stringify(catalog, null, 2) + "\n", "utf8");
    console.log(`\n✅ wrote ${xcstringsPath}`);
  } else {
    console.log("\n(dry run — file not modified)");
  }
})().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});
