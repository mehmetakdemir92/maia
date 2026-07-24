#!/usr/bin/env node
/**
 * WordPack quiz[] alanlarını orta zorluk kurallarıyla yeniden üretir.
 *
 * Kurallar:
 * - Tanım: doğru şık = definition (Today ile uyumlu). Yanlış şıklar = aynı günün
 *   diğer kelimelerinin tanımları (±1 kelime), aynı POS tercih edilir.
 * - Blank 1: examples[0], Blank 2: examples[1]
 * - Blank şıkları: hedef kelime + aynı gün / aynı POS / domain havuzundan
 *   gramer olarak uyabilen kelimeler; cevap çekimine yakın form.
 *
 * Kullanım:
 *   node scripts/upgrade-quiz-medium.js maia/WordPacks/2026-07.json
 *   node scripts/upgrade-quiz-medium.js maia/WordPacks/2026-07.json --dry-run
 */

"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 0) {
    console.error("usage: node scripts/upgrade-quiz-medium.js <wordpack.json> [--dry-run]");
    process.exit(1);
  }
  return { target: args[0], dryRun: args.includes("--dry-run") };
}

function fnv1a64(text) {
  let hash = 1469598103934665603n;
  for (const ch of text) {
    hash ^= BigInt(ch.charCodeAt(0));
    hash = (hash * 1099511628211n) & 0xffffffffffffffffn;
  }
  return hash;
}

function seededShuffle(arr, seedText) {
  const out = arr.slice();
  let state = fnv1a64(seedText) || 1n;
  function next() {
    state ^= state >> 12n;
    state ^= state << 25n;
    state ^= state >> 27n;
    return Number((state * 2685821657736338717n) & 0xffffffffffffffffn);
  }
  for (let i = out.length - 1; i > 0; i--) {
    const j = next() % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function wordCount(s) {
  return s.trim().split(/\s+/).filter(Boolean).length;
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const VOWELS = new Set(["a", "e", "i", "o", "u"]);

function isVowel(ch) {
  return VOWELS.has((ch || "").toLowerCase());
}

const IRREGULAR = {
  admit: "admitted",
  agree: "agreed",
  break: "broke",
  choose: "chose",
  do: "did",
  go: "went",
  have: "had",
  make: "made",
  read: "read",
  say: "said",
  see: "saw",
  take: "took",
  write: "wrote",
  be: "was",
  begin: "began",
  come: "came",
  give: "gave",
  know: "knew",
  leave: "left",
  mean: "meant",
  pay: "paid",
  run: "ran",
  send: "sent",
  sit: "sat",
  speak: "spoke",
  teach: "taught",
  think: "thought",
  understand: "understood",
  build: "built",
  buy: "bought",
  catch: "caught",
  feel: "felt",
  find: "found",
  get: "got",
  hear: "heard",
  hold: "held",
  keep: "kept",
  lead: "led",
  learn: "learned",
  lose: "lost",
  meet: "met",
  put: "put",
  sell: "sold",
  show: "showed",
  spend: "spent",
  stand: "stood",
  tell: "told",
  win: "won",
};

function toMatchingForm(lemma, answerForm) {
  const l = lemma.trim();
  const lower = l.toLowerCase();
  const a = answerForm.toLowerCase();
  if (a === lower) return l;

  if (IRREGULAR[lower]) {
    const irr = IRREGULAR[lower];
    if (a === irr) return irr;
    if (a.endsWith("ed") && irr.endsWith("ed")) return irr;
  }

  if (a.endsWith("ied") && lower.endsWith("y") && !isVowel(lower[lower.length - 2])) {
    return lower.slice(0, -1) + "ied";
  }
  if (a.endsWith("ed")) {
    if (lower.endsWith("e")) return lower + "d";
    if (lower.endsWith("y") && !isVowel(lower[lower.length - 2])) return lower.slice(0, -1) + "ied";
    return lower + "ed";
  }
  if (a.endsWith("ing")) {
    if (lower.endsWith("e")) return lower.slice(0, -1) + "ing";
    if (lower.endsWith("y") && !isVowel(lower[lower.length - 2])) return lower.slice(0, -1) + "ying";
    return lower + "ing";
  }
  if (a.endsWith("es")) {
    if (lower.endsWith("s") || lower.endsWith("x") || lower.endsWith("ch") || lower.endsWith("sh")) {
      return lower + "es";
    }
  }
  if (a.endsWith("s") && !a.endsWith("ss")) {
    if (lower.endsWith("y") && !isVowel(lower[lower.length - 2])) return lower.slice(0, -1) + "ies";
    return lower + "s";
  }
  return l;
}

function inflectionRegex(lemma) {
  const lower = lemma.toLowerCase();
  const escaped = escapeRegex(lower);

  if (lower.endsWith("ify")) {
    const root = escapeRegex(lower.slice(0, -3));
    return new RegExp(`\\b${root}if(?:y|ies|ied|ying)\\b`, "i");
  }
  if (lower.endsWith("y") && lower.length > 2 && !isVowel(lower[lower.length - 2])) {
    const root = escapeRegex(lower.slice(0, -1));
    return new RegExp(`\\b${root}(?:y|ies|ied|ying)\\b`, "i");
  }
  if (lower.endsWith("e")) {
    return new RegExp(`\\b${escaped}(?:d|ing|s)?\\b`, "i");
  }
  return new RegExp(`\\b${escaped}(?:s|es|ed|ing|er|est)?\\b`, "i");
}

function blankFromExample(sentence, lemma) {
  const trimmed = sentence.trim();
  if (!trimmed || !lemma) return null;

  const patterns = [
    inflectionRegex(lemma),
    new RegExp(`\\b${escapeRegex(lemma)}\\w*\\b`, "i"),
  ];

  for (const pattern of patterns) {
    const match = trimmed.match(pattern);
    if (!match) continue;
    const answer = match[0];
    const blanked = trimmed.replace(match[0], "_____");
    return { sentence: blanked, answer };
  }
  return null;
}

const POS_POOL = {
  noun: {
    general: [
      "window", "gate", "entrance", "hallway", "corner", "surface", "barrier",
      "passage", "panel", "frame", "space", "area", "detail", "topic", "issue",
      "method", "result", "reason", "context", "background", "situation", "report",
      "message", "letter", "note", "story", "article", "review", "sample", "label",
      "receipt", "calendar", "network", "garden", "carpet", "ceiling", "currency",
    ],
    work: ["report", "meeting", "project", "task", "deadline", "client", "team", "plan"],
    education: ["lesson", "chapter", "topic", "exam", "class", "student", "teacher"],
  },
  verb: {
    general: [
      "agree", "confess", "accept", "deny", "explain", "mention", "notice", "choose",
      "compare", "avoid", "refuse", "prepare", "expect", "defend", "decorate",
      "support", "address", "refer", "review", "confirm", "imply", "suggest",
      "describe", "include", "provide", "consider", "develop", "improve", "reduce",
    ],
  },
  adjective: {
    general: [
      "clear", "brief", "likely", "recent", "formal", "typical", "obvious", "subtle",
      "simple", "complex", "direct", "common", "specific", "general", "positive",
    ],
  },
  adverb: {
    general: ["quickly", "rarely", "partly", "fully", "nearly", "hardly", "widely", "finally"],
  },
};

function posKey(pos) {
  const p = (pos || "").toLowerCase();
  if (p === "adj" || p === "adjective") return "adjective";
  if (p === "adv" || p === "adverb") return "adverb";
  if (p === "verb") return "verb";
  return "noun";
}

function poolFor(entry) {
  const pk = posKey(entry.partOfSpeech);
  const domain = (entry.domainTag || "general").toLowerCase();
  const base = POS_POOL[pk] || POS_POOL.noun;
  const domainList = base[domain] || base.general || [];
  return { pk, words: [...new Set([...domainList, ...(base.general || [])])] };
}

function pickDefinitionDistractors(entry, dayWords, seed) {
  const correct = entry.definition.trim();
  const targetCount = wordCount(correct);
  const samePos = dayWords.filter(
    (w) => w.word.toLowerCase() !== entry.word.toLowerCase() && posKey(w.partOfSpeech) === posKey(entry.partOfSpeech)
  );
  const others = dayWords.filter((w) => w.word.toLowerCase() !== entry.word.toLowerCase());
  const candidates = seededShuffle([...samePos, ...others], seed + "|def");

  const chosen = [];
  const used = new Set([correct.toLowerCase().replace(/\.$/, "")]);

  function tryAdd(def, maxDelta) {
    const trimmed = def.trim();
    if (!trimmed) return false;
    const wc = wordCount(trimmed);
    if (Math.abs(wc - targetCount) > maxDelta) return false;
    const key = trimmed.toLowerCase().replace(/\.$/, "");
    if (used.has(key)) return false;
    used.add(key);
    chosen.push(trimmed.endsWith(".") ? trimmed : trimmed + ".");
    return true;
  }

  for (const w of candidates) {
    if (chosen.length >= 3) break;
    tryAdd(w.definition || "", 1);
  }
  if (chosen.length < 3) {
    for (const w of candidates) {
      if (chosen.length >= 3) break;
      tryAdd(w.definition || "", 2);
    }
  }

  const pads = [
    "The surrounding details that help explain a situation clearly.",
    "A brief written opinion about something recently experienced.",
    "Something that blocks or controls access to a space.",
    "To state that something is true, often after some resistance.",
    "The background information needed to understand a topic.",
    "A short written summary of someone's view on a topic.",
    "An opening or passage that connects two separate areas.",
    "To express unwilling agreement after some resistance.",
    "A written evaluation of a book, film, or product.",
    "Physical force used to harm people or damage property.",
    "A number that multiplies a variable in a math expression.",
    "An idea offered as a possible explanation for results.",
    "A difficult duty or heavy responsibility someone must carry.",
  ];
  for (const p of seededShuffle(pads, seed + "|pad")) {
    if (chosen.length >= 3) break;
    tryAdd(p, 2);
  }

  while (chosen.length < 3) {
    const filler = `A common English meaning related to everyday learning point ${chosen.length + 1}.`;
    tryAdd(filler, 99);
  }

  return chosen.slice(0, 3);
}

function pickBlankDistractors(entry, answer, dayWords, seed) {
  const target = entry.word.toLowerCase();
  const domain = (entry.domainTag || "general").toLowerCase();
  const pk = posKey(entry.partOfSpeech);
  const { words: poolWords } = poolFor(entry);

  const sameDaySameDomain = dayWords
    .filter(
      (w) =>
        w.word.toLowerCase() !== target &&
        posKey(w.partOfSpeech) === pk &&
        (w.domainTag || "general").toLowerCase() === domain
    )
    .map((w) => w.word);

  const sameDaySamePos = dayWords
    .filter((w) => w.word.toLowerCase() !== target && posKey(w.partOfSpeech) === pk)
    .map((w) => w.word);

  const raw = seededShuffle(
    [...new Set([...poolWords, ...sameDaySameDomain, ...sameDaySamePos])],
    seed + "|blank"
  );
  const chosen = [];
  const used = new Set([answer.toLowerCase(), target]);

  for (const lemma of raw) {
    if (chosen.length >= 3) break;
    const form = toMatchingForm(lemma, answer);
    const key = form.toLowerCase();
    if (used.has(key)) continue;
    if (form.length < 2) continue;
    used.add(key);
    chosen.push(form);
  }

  const fallback = {
    noun: ["window", "gate", "wall", "floor", "report", "topic", "detail", "method"],
    verb: ["agree", "accept", "explain", "mention", "notice", "support", "review", "refer"],
    adjective: ["clear", "brief", "recent", "formal", "typical", "simple", "direct"],
    adverb: ["quickly", "rarely", "nearly", "finally", "partly", "widely"],
  }[pk] || ["detail", "matter", "option", "choice"];

  for (const lemma of seededShuffle(fallback, seed + "|fb")) {
    if (chosen.length >= 3) break;
    const form = toMatchingForm(lemma, answer);
    const key = form.toLowerCase();
    if (used.has(key)) continue;
    used.add(key);
    chosen.push(form);
  }

  return chosen.slice(0, 3);
}

function makeOptions(correct, distractors, seed) {
  const options = seededShuffle([correct, ...distractors.slice(0, 3)], seed + "|opts");
  const correctIndex = options.findIndex((o) => o.toLowerCase() === correct.toLowerCase());
  return { options, correctAnswerIndex: correctIndex >= 0 ? correctIndex : 0 };
}

function buildDefinitionQuiz(entry, dayWords, dayKey) {
  const seed = `${dayKey}|${entry.word}|definition`;
  const correct = entry.definition.trim();
  const correctFormatted = correct.endsWith(".") ? correct : correct + ".";
  const distractors = pickDefinitionDistractors(entry, dayWords, seed);
  const { options, correctAnswerIndex } = makeOptions(correctFormatted, distractors, seed);
  return {
    type: "definition",
    question: `What does "${entry.word}" mean?`,
    options,
    correctAnswerIndex,
  };
}

function buildBlankQuiz(entry, exampleIndex, dayWords, dayKey, slot) {
  const examples = entry.examples || [];
  const sentence = examples[exampleIndex];
  if (!sentence) return null;

  const blank = blankFromExample(sentence, entry.word);
  if (!blank) return null;

  const seed = `${dayKey}|${entry.word}|blank${slot}`;
  const distractors = pickBlankDistractors(entry, blank.answer, dayWords, seed);
  const { options, correctAnswerIndex } = makeOptions(blank.answer, distractors, seed);

  return {
    type: "blank",
    question: `Fill in the blank: ${blank.sentence}`,
    options,
    correctAnswerIndex,
  };
}

function buildQuiz(entry, dayWords, dayKey) {
  const quizzes = [buildDefinitionQuiz(entry, dayWords, dayKey)];

  // Example 0 + 1: both blanks differ from the old pack (which usually used 1 + 2).
  const preferredBlankIndices = [0, 1, 2];
  for (const idx of preferredBlankIndices) {
    if (quizzes.length >= 3) break;
    const blank = buildBlankQuiz(entry, idx, dayWords, dayKey, quizzes.length);
    if (!blank) continue;
    if (quizzes.some((q) => q.question === blank.question)) continue;
    quizzes.push(blank);
  }

  return quizzes.slice(0, 3);
}

function validateQuiz(entry, quiz) {
  const errors = [];
  if (!Array.isArray(quiz) || quiz.length !== 3) {
    errors.push("need 3 questions");
    return errors;
  }
  for (const [i, q] of quiz.entries()) {
    if (!q.question || !Array.isArray(q.options) || q.options.length !== 4) {
      errors.push(`q${i + 1} bad shape`);
    }
    if (typeof q.correctAnswerIndex !== "number" || q.correctAnswerIndex < 0 || q.correctAnswerIndex > 3) {
      errors.push(`q${i + 1} bad index`);
    }
    const opts = new Set(q.options.map((o) => o.toLowerCase()));
    if (opts.size !== 4) errors.push(`q${i + 1} duplicate options`);
  }
  return errors;
}

function main() {
  const { target, dryRun } = parseArgs(process.argv);
  const abs = path.resolve(target);
  if (!fs.existsSync(abs)) {
    console.error(`file not found: ${abs}`);
    process.exit(1);
  }

  const pack = JSON.parse(fs.readFileSync(abs, "utf8"));
  let updated = 0;
  let failed = [];

  for (const [dayKey, day] of Object.entries(pack.days || {})) {
    const dayWords = day.words || [];
  for (const entry of dayWords) {
    const previousQuiz = entry.quiz;
    const quiz = buildQuiz(entry, dayWords, dayKey);
    const errors = validateQuiz(entry, quiz);
    if (errors.length) {
      failed.push({ word: entry.word, day: dayKey, errors });
      entry.quiz = previousQuiz;
      continue;
    }
    entry.quiz = quiz;
    updated++;
  }
  }

  console.log(`Updated ${updated} words in ${path.basename(abs)}`);
  if (failed.length) {
    console.warn(`Failed ${failed.length} words:`);
    failed.slice(0, 10).forEach((f) => console.warn(`  ${f.day} ${f.word}: ${f.errors.join(", ")}`));
  }

  if (dryRun) {
    console.log("dry-run: file not written");
    const sampleDay = Object.keys(pack.days)[0];
    const sample = pack.days[sampleDay].words[0];
    console.log(JSON.stringify(sample.quiz, null, 2));
    return;
  }

  fs.writeFileSync(abs, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(`Wrote ${abs}`);
}

main();
