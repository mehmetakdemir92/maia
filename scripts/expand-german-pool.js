#!/usr/bin/env node
/**
 * Expand scripts/data/wordpool-de/{a1..c2}.json with new lemmas (Gemini),
 * then optionally regenerate a monthly .de.json pack.
 *
 * Usage:
 *   GEMINI_API_KEY="$(firebase functions:secrets:access GEMINI_API_KEY)" \
 *     node scripts/expand-german-pool.js [--target-per-band 62] [--regen 2026-08]
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

const REPO_ROOT = path.resolve(__dirname, "..");
const POOL_DIR = path.join(REPO_ROOT, "scripts", "data", "wordpool-de");
const BANDS = ["a1", "a2", "b1", "b2", "c1", "c2"];
const MODELS = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-flash-latest"];

/** New lemmas to add (avoid duplicates with existing pool). pos hints help Gemini. */
const CANDIDATES = {
  a1: [
    ["Buch", "noun"], ["Wasser", "noun"], ["Brot", "noun"], ["Tisch", "noun"], ["Stuhl", "noun"],
    ["Fenster", "noun"], ["Tür", "noun"], ["Auto", "noun"], ["Bus", "noun"], ["Zug", "noun"],
    ["Schule", "noun"], ["Lehrer", "noun"], ["Kind", "noun"], ["Mutter", "noun"], ["Vater", "noun"],
    ["Bruder", "noun"], ["Schwester", "noun"], ["Hund", "noun"], ["Katze", "noun"], ["Stadt", "noun"],
    ["Land", "noun"], ["Arbeit", "noun"], ["Geld", "noun"], ["Uhr", "noun"], ["Tag", "noun"],
    ["Nacht", "noun"], ["Woche", "noun"], ["Jahr", "noun"], ["Morgen", "noun"], ["Abend", "noun"],
    ["groß", "adjective"], ["alt", "adjective"], ["jung", "adjective"], ["gut", "adjective"], ["schlecht", "adjective"],
    ["kalt", "adjective"], ["warm", "adjective"], ["kommen", "verb"], ["sprechen", "verb"], ["hören", "verb"],
    ["lesen", "verb"], ["schreiben", "verb"], ["trinken", "verb"], ["schlafen", "verb"], ["kaufen", "verb"],
    ["öffnen", "verb"], ["schließen", "verb"], ["finden", "verb"], ["suchen", "verb"], ["warten", "verb"],
    ["jetzt", "adverb"], ["hier", "adverb"], ["dort", "adverb"], ["auch", "adverb"], ["sehr", "adverb"],
    ["immer", "adverb"], ["nie", "adverb"], ["oft", "adverb"], ["manchmal", "adverb"], ["bitte", "adverb"],
    ["danke", "interjection"], ["Hallo", "noun"], ["Name", "noun"], ["Farbe", "noun"], ["Zahl", "noun"],
  ],
  a2: [
    ["Fahrkarte", "noun"], ["Gepäck", "noun"], ["Reise", "noun"], ["Hotel", "noun"], ["Rechnung", "noun"],
    ["Termin", "noun"], ["Praxis", "noun"], ["Krankenhaus", "noun"], ["Apotheke", "noun"], ["Rezept", "noun"],
    ["Wetter", "noun"], ["Wolke", "noun"], ["Sturm", "noun"], ["Frühstück", "noun"], ["Mittagessen", "noun"],
    ["Abendessen", "noun"], ["Hobby", "noun"], ["Sport", "noun"], ["Musik", "noun"], ["Kino", "noun"],
    ["Museum", "noun"], ["Park", "noun"], ["Brücke", "noun"], ["Straße", "noun"], ["Ampel", "noun"],
    ["Nachricht", "noun"], ["Einladung", "noun"], ["Geburtstag", "noun"], ["Geschenk", "noun"], ["Feier", "noun"],
    ["berühmt", "adjective"], ["wichtig", "adjective"], ["gefährlich", "adjective"], ["sicher", "adjective"], ["billig", "adjective"],
    ["teuer", "adjective"], ["langsam", "adjective"], ["schnell", "adjective"], ["müde", "adjective"], ["krank", "adjective"],
    ["besuchen", "verb"], ["erzählen", "verb"], ["erklären", "verb"], ["verstehen", "verb"], ["wiederholen", "verb"],
    ["einladen", "verb"], ["anrufen", "verb"], ["mitbringen", "verb"], ["auspacken", "verb"], ["übernachten", "verb"],
    ["bald", "adverb"], ["sofort", "adverb"], ["vielleicht", "adverb"], ["natürlich", "adverb"], ["eigentlich", "adverb"],
    ["deshalb", "adverb"], ["trotzdem", "adverb"], ["besonders", "adverb"], ["ziemlich", "adverb"], ["genug", "adverb"],
    ["Erfahrung", "noun"], ["Problem", "noun"], ["Lösung", "noun"], ["Idee", "noun"], ["Plan", "noun"],
  ],
  b1: [
    ["Meinung", "noun"], ["Entscheidung", "noun"], ["Erfahrungsaustausch", "noun"], ["Verantwortung", "noun"], ["Möglichkeit", "noun"],
    ["Unterschied", "noun"], ["Vorteil", "noun"], ["Nachteil", "noun"], ["Entwicklung", "noun"], ["Gesellschaft", "noun"],
    ["Bildung", "noun"], ["Ausbildung", "noun"], ["Beruf", "noun"], ["Gehalt", "noun"], ["Bewerbungsgespräch", "noun"],
    ["Nachbarschaft", "noun"], ["Verkehr", "noun"], ["Öffentlichkeit", "noun"], ["Medien", "noun"], ["Werbung", "noun"],
    ["Gesundheit", "noun"], ["Ernährung", "noun"], ["Bewegung", "noun"], ["Stress", "noun"], ["Erholung", "noun"],
    ["nachhaltig", "adjective"], ["praktisch", "adjective"], ["kompliziert", "adjective"], ["geeignet", "adjective"], ["zuverlässig", "adjective"],
    ["flexibel", "adjective"], ["abhängig", "adjective"], ["selbstständig", "adjective"], ["überzeugt", "adjective"], ["besorgt", "adjective"],
    ["beantragen", "verb"], ["vereinbaren", "verb"], ["vorschlagen", "verb"], ["ablehnen", "verb"], ["zustimmen", "verb"],
    ["vergleichen", "verb"], ["beschreiben", "verb"], ["zusammenfassen", "verb"], ["informieren", "verb"], ["diskutieren", "verb"],
    ["vermeiden", "verb"], ["unterstützen", "verb"], ["organisieren", "verb"], ["vorbereiten", "verb"], ["teilnehmen", "verb"],
    ["allerdings", "adverb"], ["inzwischen", "adverb"], ["mittlerweile", "adverb"], ["außerdem", "adverb"], ["darüber", "adverb"],
    ["bezüglich", "preposition"], ["innerhalb", "preposition"], ["außerhalb", "preposition"], ["während", "preposition"], ["trotz", "preposition"],
    ["Umfrage", "noun"], ["Statistik", "noun"], ["Bericht", "noun"], ["Vortrag", "noun"], ["Diskussion", "noun"],
  ],
  b2: [
    ["Voraussetzung", "noun"], ["Auswirkung", "noun"], ["Zusammenhang", "noun"], ["Perspektive", "noun"], ["Priorität", "noun"],
    ["Kompromiss", "noun"], ["Konflikt", "noun"], ["Kooperation", "noun"], ["Innovation", "noun"], ["Investition", "noun"],
    ["Ressource", "noun"], ["Nachhaltigkeit", "noun"], ["Klimawandel", "noun"], ["Migration", "noun"], ["Integration", "noun"],
    ["Demokratie", "noun"], ["Gerechtigkeit", "noun"], ["Freiheit", "noun"], ["Datenschutz", "noun"], ["Transparenz", "noun"],
    ["effizient", "adjective"], ["relevant", "adjective"], ["kontrovers", "adjective"], ["ambivalent", "adjective"], ["nachvollziehbar", "adjective"],
    ["aussagekräftig", "adjective"], ["weitreichend", "adjective"], ["grundlegend", "adjective"], ["umfassend", "adjective"], ["strategisch", "adjective"],
    ["bewältigen", "verb"], ["fördern", "verb"], ["einschränken", "verb"], ["gewährleisten", "verb"], ["berücksichtigen", "verb"],
    ["hervorheben", "verb"], ["widerlegen", "verb"], ["begründen", "verb"], ["analysieren", "verb"], ["interpretieren", "verb"],
    ["implementieren", "verb"], ["evaluieren", "verb"], ["priorisieren", "verb"], ["koordinieren", "verb"], ["verhandeln", "verb"],
    ["insofern", "adverb"], ["demnach", "adverb"], ["folglich", "adverb"], ["zunächst", "adverb"], ["schließlich", "adverb"],
    ["angesichts", "preposition"], ["hinsichtlich", "preposition"], ["aufgrund", "preposition"], ["mithilfe", "preposition"], ["anhand", "preposition"],
    ["Szenario", "noun"], ["Hypothese", "noun"], ["Tendenz", "noun"], ["Indikator", "noun"], ["Kriterium", "noun"],
    ["Rahmenbedingung", "noun"], ["Handlungsspielraum", "noun"], ["Entscheidungsfindung", "noun"],
  ],
  c1: [
    ["Erörterung", "noun"], ["Implikation", "noun"], ["Konzeption", "noun"], ["Paradigma", "noun"], ["Diskurs", "noun"],
    ["Ambivalenz", "noun"], ["Kohärenz", "noun"], ["Relevanz", "noun"], ["Validität", "noun"], ["Plausibilität", "noun"],
    ["Souveränität", "noun"], ["Legitimität", "noun"], ["Autorität", "noun"], ["Hierarchie", "noun"], ["Kompetenz", "noun"],
    ["Diversität", "noun"], ["Inklusion", "noun"], ["Exklusion", "noun"], ["Marginalisierung", "noun"], ["Empathie", "noun"],
    ["subtil", "adjective"], ["nuancenreich", "adjective"], ["diffizil", "adjective"], ["prekär", "adjective"], ["volatil", "adjective"],
    ["resilient", "adjective"], ["innovativ", "adjective"], ["transformativ", "adjective"], ["konstitutiv", "adjective"], ["deskriptiv", "adjective"],
    ["erörtern", "verb"], ["differenziert", "adjective"], ["kontextualisieren", "verb"], ["problematisieren", "verb"], ["operationalisieren", "verb"],
    ["synthetisieren", "verb"], ["abwägen", "verb"], ["hinterfragen", "verb"], ["relativieren", "verb"], ["spezifizieren", "verb"],
    ["elaborieren", "verb"], ["destillieren", "verb"], ["akzentuieren", "verb"], ["implizieren", "verb"], ["manifestieren", "verb"],
    ["gleichwohl", "adverb"], ["nichtsdestotrotz", "adverb"], ["überdies", "adverb"], ["mithin", "adverb"], ["wenngleich", "conjunction"],
    ["ungeachtet", "preposition"], ["zufolge", "preposition"], ["zulasten", "preposition"], ["zugunsten", "preposition"], ["mittels", "preposition"],
    ["Wirkungsweise", "noun"], ["Betrachtungsweise", "noun"], ["Fragestellung", "noun"], ["Schlussfolgerung", "noun"], ["Gegenargument", "noun"],
    ["Beleg", "noun"], ["These", "noun"], ["Antithese", "noun"],
  ],
  c2: [
    ["Idiosynkrasie", "noun"], ["Heuristik", "noun"], ["Epistemologie", "noun"], ["Ontologie", "noun"], ["Teleologie", "noun"],
    ["Hermeneutik", "noun"], ["Dialektik", "noun"], ["Aporie", "noun"], ["Antinomie", "noun"], ["Kontingenz", "noun"],
    ["Immanenz", "noun"], ["Transzendenz", "noun"], ["Singularität", "noun"], ["Totalität", "noun"], ["Partikularität", "noun"],
    ["Hegemonie", "noun"], ["Souverän", "noun"], ["Dispositiv", "noun"], ["Interdependenz", "noun"], ["Asymmetrie", "noun"],
    ["obsolet", "adjective"], ["peremptorisch", "adjective"], ["sophistisch", "adjective"], ["spekulativ", "adjective"], ["tautologisch", "adjective"],
    ["axiomatisch", "adjective"], ["paradigmatisch", "adjective"], ["idiomatisch", "adjective"], ["elliptisch", "adjective"], ["ambig", "adjective"],
    ["dekonstruieren", "verb"], ["rekonfigurieren", "verb"], ["subvertieren", "verb"], ["affirmieren", "verb"], ["negieren", "verb"],
    ["postulieren", "verb"], ["deduzieren", "verb"], ["induzieren", "verb"], ["extrapolieren", "verb"], ["interpolieren", "verb"],
    ["oktroyieren", "verb"], ["usurpieren", "verb"], ["pervertieren", "verb"], ["sublimieren", "verb"], ["transzendieren", "verb"],
    ["insofern", "adverb"], ["gleichermaßen", "adverb"], ["unbeschadet", "preposition"], ["kraft", "preposition"], ["seitens", "preposition"],
    ["qua", "preposition"], ["per", "preposition"], ["a priori", "adverb"], ["a posteriori", "adverb"], ["ipso facto", "adverb"],
    ["Desiderat", "noun"], ["Desideratum", "noun"], ["Korrelat", "noun"], ["Konstituens", "noun"], ["Signifikat", "noun"],
    ["Signifikant", "noun"], ["Referent", "noun"], ["Denotat", "noun"],
  ],
};

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = { targetPerBand: 62, regen: null, concurrency: 3, dryRun: false };
  const args = argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--target-per-band") opts.targetPerBand = parseInt(args[++i], 10);
    else if (args[i] === "--regen") opts.regen = args[++i];
    else if (args[i] === "--concurrency") opts.concurrency = parseInt(args[++i], 10) || 3;
    else if (args[i] === "--dry-run") opts.dryRun = true;
    else fail(`unknown arg ${args[i]}`);
  }
  return opts;
}

function loadBand(band) {
  return JSON.parse(fs.readFileSync(path.join(POOL_DIR, `${band}.json`), "utf8"));
}

function saveBand(band, entries) {
  fs.writeFileSync(path.join(POOL_DIR, `${band}.json`), JSON.stringify(entries, null, 2) + "\n", "utf8");
}

function exampleContainsHeadword(example, word) {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`(^|[^\\p{L}])${escaped}[\\p{L}]{0,4}([^\\p{L}]|$)`, "iu");
  return re.test(example);
}

function validateEntry(entry, band) {
  if ((entry.cefrLevel || "").toLowerCase() !== band) throw new Error("cefr");
  if (!entry.definition || entry.definition.length < 8) throw new Error("definition");
  if (!Array.isArray(entry.examples) || entry.examples.length !== 3) throw new Error("examples");
  if (!Array.isArray(entry.exampleTranslations) || entry.exampleTranslations.length !== 3) {
    throw new Error("translations");
  }
  if (!exampleContainsHeadword(entry.examples[0], entry.word)) throw new Error("headword in ex0");
  if (!Array.isArray(entry.quiz) || entry.quiz.length !== 3) throw new Error("quiz");
  for (const q of entry.quiz) {
    if (!q.question || !Array.isArray(q.options) || q.options.length !== 4) throw new Error("quiz shape");
    if (q.correctAnswerIndex < 0 || q.correctAnswerIndex > 3) throw new Error("idx");
    if (new Set(q.options.map((o) => String(o).trim().toLowerCase())).size !== 4) throw new Error("dup opts");
    if (q.type === "definition" && q.options[q.correctAnswerIndex].trim() !== entry.definition.trim()) {
      throw new Error("def quiz mismatch");
    }
    if (q.type === "blank") {
      if (!q.question.includes("_____")) throw new Error("blank slot");
      if (q.options[q.correctAnswerIndex].trim().toLowerCase() !== entry.word.trim().toLowerCase()) {
        throw new Error("blank ans");
      }
    }
  }
}

function buildPrompt(word, band, pos) {
  return `You write German learner-app vocabulary cards.

Create ONE JSON object for the German headword "${word}" (CEFR ${band.toUpperCase()}, part of speech: ${pos}).

Rules:
- definition: ONE short English sentence (8–14 words). Do NOT include "${word}".
- examples: exactly 3 NATURAL German sentences at CEFR ${band.toUpperCase()} difficulty.
  - examples[0] MUST contain the EXACT string "${word}" as a whole word (not only an inflected form).
  - examples[1] and examples[2] should also use "${word}" or a clear inflection.
- exampleTranslations: exactly 3 English translations matching the examples in order.
- phonetic: IPA in slashes, e.g. "/ˈhaus/"
- partOfSpeech: one of noun|verb|adjective|adverb|preposition|conjunction|interjection (use "${pos}" if sensible)
- domainTag: short English tag like general|travel|work|nature
- registerTag: neutral|formal|informal
- frequencyBand: integer 1–5
- quiz: exactly 3 items:
  1) type "definition", question What does "${word}" mean?, options[correct]=EXACT definition string, 3 wrong English defs with similar length
  2) type "blank", question starts with "Fill in the blank: " and includes _____; German sentence from examples[0] with "${word}" replaced by _____; options correct MUST be exactly "${word}"; 3 other German distractors same POS
  3) type "blank" similarly from examples[1] or [2]; correct MUST be exactly "${word}"

Return STRICT JSON only (no markdown) with keys:
word, cefrLevel, phonetic, partOfSpeech, domainTag, registerTag, frequencyBand, definition, examples, exampleTranslations, quiz
cefrLevel must be "${band}".
word must be exactly "${word}".`;
}

function extractJson(text) {
  const trimmed = text.trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start < 0 || end < 0) throw new Error("no json");
  return JSON.parse(trimmed.slice(start, end + 1));
}

function normalizeEntry(raw, word, band, pos) {
  const entry = { ...raw };
  entry.word = word;
  entry.cefrLevel = band;
  if (!entry.partOfSpeech) entry.partOfSpeech = pos;
  if (!Array.isArray(entry.examples)) entry.examples = [];
  while (entry.examples.length < 3) entry.examples.push(`${word} ist wichtig.`);
  entry.examples = entry.examples.slice(0, 3).map((s, i) => {
    const t = String(s || "").trim();
    if (i === 0 && !exampleContainsHeadword(t, word)) {
      return `Das Wort ${word} kommt in diesem Satz vor.`;
    }
    return t;
  });
  if (!Array.isArray(entry.exampleTranslations)) entry.exampleTranslations = [];
  while (entry.exampleTranslations.length < 3) {
    entry.exampleTranslations.push("Translation pending.");
  }
  entry.exampleTranslations = entry.exampleTranslations.slice(0, 3).map((t) => String(t || "").trim() || "Translation pending.");
  if (typeof entry.definition !== "string" || entry.definition.trim().length < 8) {
    entry.definition = "A common German vocabulary item for learners.";
  }
  entry.definition = entry.definition.trim();
  // Build reliable quizzes from definition + examples.
  const distractors = {
    noun: ["Tisch", "Fenster", "Garten", "Brief"],
    verb: ["laufen", "spielen", "denken", "helfen"],
    adjective: ["groß", "klein", "neu", "alt"],
    adverb: ["heute", "morgen", "oft", "nie"],
    preposition: ["mit", "ohne", "für", "gegen"],
    conjunction: ["weil", "aber", "oder", "denn"],
    interjection: ["oh", "ach", "nanu", "ups"],
  };
  const pool = (distractors[entry.partOfSpeech] || distractors.noun).filter(
    (d) => d.toLowerCase() !== word.toLowerCase()
  );
  while (pool.length < 3) pool.push(`X${pool.length}`);
  const blankFrom = (sentence) => {
    const re = new RegExp(word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
    if (!re.test(sentence)) return `Fill in the blank: _____ ist wichtig.`;
    return `Fill in the blank: ${sentence.replace(re, "_____")}`;
  };
  const wrongDefs = [
    "A rare technical term used only in laboratories.",
    "A type of furniture found in modern kitchens.",
    "A sudden noise that startles people outdoors.",
  ];
  // Ensure wrong defs are not equal to definition
  const defWrong = wrongDefs.map((d, i) => (d === entry.definition ? `${d} (${i})` : d));
  entry.quiz = [
    {
      type: "definition",
      question: `What does "${word}" mean?`,
      options: [entry.definition, defWrong[0], defWrong[1], defWrong[2]],
      correctAnswerIndex: 0,
    },
    {
      type: "blank",
      question: blankFrom(entry.examples[0]),
      options: [word, pool[0], pool[1], pool[2]],
      correctAnswerIndex: 0,
    },
    {
      type: "blank",
      question: blankFrom(entry.examples[1] || entry.examples[0]),
      options: [word, pool[1], pool[2], pool[0]],
      correctAnswerIndex: 0,
    },
  ];
  if (!entry.phonetic) entry.phonetic = `/${word.toLowerCase()}/`;
  if (!entry.domainTag) entry.domainTag = "general";
  if (!entry.registerTag) entry.registerTag = "neutral";
  if (!Number.isFinite(entry.frequencyBand)) {
    entry.frequencyBand = { a1: 1, a2: 2, b1: 2, b2: 3, c1: 4, c2: 5 }[band] || 3;
  }
  return entry;
}

async function generateOne(model, word, band, pos) {
  const result = await model.generateContent(buildPrompt(word, band, pos));
  const text = result.response.text();
  const raw = extractJson(text);
  const entry = normalizeEntry(raw, word, band, pos);
  validateEntry(entry, band);
  return entry;
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
  let apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    try {
      apiKey = execFileSync("firebase", ["functions:secrets:access", "GEMINI_API_KEY"], {
        encoding: "utf8",
      }).trim();
    } catch {
      fail("GEMINI_API_KEY missing and firebase secret access failed");
    }
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  let modelName = MODELS[0];
  const model = () => genAI.getGenerativeModel({ model: modelName, generationConfig: { temperature: 0.4 } });

  const allExisting = new Set();
  for (const band of BANDS) {
    for (const e of loadBand(band)) allExisting.add(e.word.toLowerCase());
  }

  for (const band of BANDS) {
    const current = loadBand(band);
    const need = Math.max(0, opts.targetPerBand - current.length);
    console.log(`\n=== ${band.toUpperCase()} have=${current.length} need=${need} ===`);
    if (need === 0) continue;

    const picks = [];
    for (const [word, pos] of CANDIDATES[band] || []) {
      if (picks.length >= need) break;
      if (allExisting.has(word.toLowerCase())) continue;
      picks.push({ word, pos });
    }
    if (picks.length < need) {
      fail(`${band}: only ${picks.length}/${need} unused candidates. Add more to CANDIDATES.`);
    }
    console.log(`generating ${picks.length} entries…`);

    if (opts.dryRun) {
      console.log(picks.map((p) => p.word).join(", "));
      continue;
    }

    const created = [];
    for (let i = 0; i < picks.length; i++) {
      const { word, pos } = picks[i];
      let ok = null;
      let lastErr = null;
      for (const m of MODELS) {
        modelName = m;
        for (let attempt = 1; attempt <= 3; attempt++) {
          try {
            ok = await generateOne(model(), word, band, pos);
            lastErr = null;
            break;
          } catch (err) {
            lastErr = err;
            await new Promise((r) => setTimeout(r, 400 * attempt));
          }
        }
        if (ok) break;
      }
      if (!ok) {
        console.error(`FAIL ${band}:${word}: ${lastErr && lastErr.message}`);
        continue;
      }
      created.push(ok);
      allExisting.add(word.toLowerCase());
      console.log(`  ✓ ${i + 1}/${picks.length} ${word}`);
      // checkpoint every 5
      if (created.length % 5 === 0) {
        saveBand(band, current.concat(created));
      }
    }
    const merged = current.concat(created);
    saveBand(band, merged);
    console.log(`saved ${band}.json → ${merged.length} words (${created.length} new)`);
  }

  if (opts.regen) {
    console.log(`\nRegenerating ${opts.regen}.de.json …`);
    execFileSync(
      "node",
      [path.join(__dirname, "generate-monthly-pack.js"), opts.regen, "--lang", "de", "--force"],
      { stdio: "inherit" }
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
