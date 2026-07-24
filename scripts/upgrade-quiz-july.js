#!/usr/bin/env node
/**
 * July WordPack quiz[] — kullanıcı kuralları:
 * 1) Tanım: kelime kartı definition'ının paraphrase'i (aynı anlam, farklı söyleyiş).
 * 2–3) Boşluk: hedef kelimeye semantik olarak yakın 4 şık; doğru cevap bazen hedef kelime,
 *     bazen yakın eş anlamlı (cümlede gerçekten o kelime geçmeli).
 *
 *   node scripts/upgrade-quiz-july.js maia/WordPacks/2026-07.json
 */

"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length === 0) {
    console.error("usage: node scripts/upgrade-quiz-july.js <wordpack.json> [--dry-run]");
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

function seededPick(seedText) {
  return Number(fnv1a64(seedText) % 1000000n);
}

function seededBool(seedText) {
  return Number((fnv1a64(seedText) >> 17n) & 1n) === 0;
}

function normalizeText(s) {
  return s.trim().toLowerCase().replace(/\s+/g, " ").replace(/[.!?]+$/, "");
}

function ensurePeriod(s) {
  const t = s.trim();
  if (!t) return t;
  return t.endsWith(".") ? t : t + ".";
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
  admit: "admitted", agree: "agreed", break: "broke", choose: "chose", do: "did",
  go: "went", have: "had", make: "made", read: "read", say: "said", see: "saw",
  take: "took", write: "wrote", be: "was", begin: "began", come: "came", give: "gave",
  know: "knew", leave: "left", mean: "meant", pay: "paid", run: "ran", send: "sent",
  sit: "sat", speak: "spoke", teach: "taught", think: "thought", understand: "understood",
  build: "built", buy: "bought", catch: "caught", feel: "felt", find: "found", get: "got",
  hear: "heard", hold: "held", keep: "kept", lead: "led", learn: "learned", lose: "lost",
  meet: "met", put: "put", sell: "sold", show: "showed", spend: "spent", stand: "stood",
  tell: "told", win: "won", drink: "drank", eat: "ate", fall: "fell", grow: "grew",
  speak: "spoke", write: "wrote", drive: "drove", fly: "flew", sing: "sang",
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

  const patterns = [inflectionRegex(lemma), new RegExp(`\\b${escapeRegex(lemma)}\\w*\\b`, "i")];
  for (const pattern of patterns) {
    const match = trimmed.match(pattern);
    if (!match) continue;
    const answer = match[0];
    const blanked = trimmed.replace(match[0], "_____");
    return { sentence: blanked, answer, original: trimmed };
  }
  return null;
}

// --- Paraphrase engine ---

const PHRASE_SWAPS = [
  [/^\s*To\s+/i, "It means to "],
  [/^\s*A\s+mistaken\s+belief\s+or\s+a\s+flawed\s+argument/i, "An incorrect idea or weak reasoning"],
  [/^\s*A\s+/i, "This is a "],
  [/^\s*An\s+/i, "This is an "],
  [/something that/i, "something which"],
  [/someone who/i, "a person who"],
  [/used to/i, "employed to"],
  [/that helps/i, "which helps"],
  [/making it/i, "so it becomes"],
  [/The quality of being/i, "The state of being"],
  [/A feeling of/i, "An emotion involving"],
  [/A short report that gives an opinion/i, "A brief piece of writing sharing your view"],
  [/opens and closes an entrance/i, "can be opened or shut to enter a room or building"],
  [/helps explain something/i, "makes something easier to understand"],
  [/making it more comprehensible/i, "so others can understand it better"],
  [/based on unsound reasoning/i, "that does not follow good logic"],
  [/into your body/i, "through your mouth"],
  [/form a whole/i, "make up a complete thing"],
  [/in a situation/i, "in a given case"],
  [/for others/i, "for other people"],
  [/about a book, film, or product/i, "on something like a book or movie"],
];

const WORD_SWAPS = [
  ["explain", "clarify"], ["clarify", "explain"], ["complex", "complicated"], ["help", "assist"],
  ["make", "create"], ["give", "provide"], ["show", "display"], ["use", "employ"],
  ["important", "significant"], ["common", "typical"], ["short", "brief"], ["long", "extended"],
  ["open", "unlock"], ["close", "shut"], ["move", "shift"], ["begin", "start"],
  ["end", "finish"], ["think", "believe"], ["know", "understand"], ["want", "wish"],
  ["need", "require"], ["try", "attempt"], ["find", "discover"], ["keep", "maintain"],
  ["change", "alter"], ["build", "construct"], ["break", "damage"], ["buy", "purchase"],
  ["sell", "offer"], ["read", "study"], ["write", "compose"], ["speak", "talk"],
  ["listen", "hear"], ["watch", "observe"], ["learn", "study"], ["teach", "instruct"],
  ["work", "function"], ["live", "reside"], ["die", "pass away"], ["eat", "consume"],
  ["drink", "sip"], ["sleep", "rest"], ["walk", "stroll"], ["run", "jog"],
  ["sit", "remain seated"], ["stand", "stay upright"], ["carry", "transport"],
  ["bring", "deliver"], ["take", "remove"], ["put", "place"], ["hold", "grasp"],
  ["feel", "sense"], ["seem", "appear"], ["look", "seem"], ["become", "turn into"],
  ["include", "contain"], ["contain", "include"], ["provide", "supply"],
  ["describe", "portray"], ["define", "explain"], ["mean", "signify"],
  ["allow", "permit"], ["prevent", "stop"], ["cause", "lead to"], ["result", "outcome"],
  ["reason", "logic"], ["decision", "choice"], ["problem", "issue"], ["solution", "answer"],
  ["idea", "concept"], ["fact", "truth"], ["story", "tale"], ["report", "account"],
  ["message", "note"], ["letter", "note"], ["door", "entryway"], ["window", "opening"],
  ["barrier", "block"], ["entrance", "way in"], ["opinion", "view"], ["belief", "conviction"],
  ["argument", "reasoning"], ["theory", "idea"], ["research", "study"], ["phenomenon", "event"],
  ["controversial", "disputed"], ["mysterious", "puzzling"], ["widely", "broadly"],
  ["rather", "fairly"], ["further", "more"], ["completely", "entirely"],
];

function paraphraseDefinition(definition, seed) {
  let text = definition.trim();
  if (!text) return definition;

  for (const [re, repl] of PHRASE_SWAPS) {
    if (re.test(text)) {
      text = text.replace(re, repl);
      break;
    }
  }

  // Safe lexical swaps only — never change core meaning (no take→remove, etc.).
  const SAFE_SWAPS = [
    ["explain", "clarify"], ["clarify", "make clear"], ["complex", "complicated"],
    ["comprehensible", "easy to understand"], ["something", "something which"],
    ["someone", "a person"], ["helps", "makes it easier to"], ["help", "assist"],
    ["important", "significant"], ["common", "typical"], ["short", "brief"],
    ["opens and closes", "can open or shut"], ["entrance", "way in"],
    ["barrier", "block"], ["opinion", "view"], ["belief", "idea"],
    ["argument", "line of reasoning"], ["unsound reasoning", "weak logic"],
    ["controversial", "disputed"], ["mysterious", "puzzling"],
  ];
  const swaps = seededShuffle(SAFE_SWAPS, seed + "|swap");
  let applied = 0;
  for (const [from, to] of swaps) {
    if (applied >= 2) break;
    const re = new RegExp(`\\b${escapeRegex(from)}\\b`, "i");
    if (re.test(text)) {
      text = text.replace(re, (m) => (m[0] === m[0].toUpperCase() ? to[0].toUpperCase() + to.slice(1) : to));
      applied++;
    }
  }

  if (normalizeText(text) === normalizeText(definition)) {
    if (/^to\s/i.test(definition)) {
      text = "It means " + definition.trim().replace(/^to\s/i, "to ");
    } else if (/^a\s|^an\s/i.test(definition)) {
      text = "This refers to " + definition.trim().replace(/^(a|an)\s/i, "");
    } else {
      text = "In other words, " + definition.trim().replace(/^./, (c) => c.toLowerCase());
    }
  }

  return ensurePeriod(text);
}

// --- Semantic neighbors (close distractors) ---

const NEAR_VERBS = {
  elucidate: ["explain", "clarify", "describe", "illustrate"],
  explain: ["clarify", "describe", "elucidate", "outline"],
  clarify: ["explain", "elucidate", "define", "illustrate"],
  drink: ["sip", "swallow", "consume", "gulp"],
  consist: ["comprise", "contain", "include", "involve"],
  generate: ["create", "produce", "make", "cause"],
  focus: ["concentrate", "center", "target", "emphasize"],
  admit: ["confess", "acknowledge", "accept", "concede"],
  confess: ["admit", "acknowledge", "reveal", "declare"],
  open: ["unlock", "unfasten", "part", "expose"],
  close: ["shut", "seal", "lock", "block"],
  move: ["shift", "relocate", "transfer", "slide"],
  review: ["assess", "evaluate", "examine", "critique"],
  describe: ["explain", "portray", "depict", "outline"],
  improve: ["enhance", "upgrade", "refine", "boost"],
  reduce: ["lower", "decrease", "cut", "lessen"],
  accept: ["approve", "take", "receive", "embrace"],
  deny: ["reject", "refuse", "dispute", "decline"],
  agree: ["accept", "consent", "approve", "align"],
  suggest: ["propose", "recommend", "advise", "offer"],
  consider: ["think about", "weigh", "ponder", "regard"],
  develop: ["build", "create", "grow", "expand"],
  provide: ["supply", "offer", "give", "deliver"],
  include: ["contain", "involve", "cover", "comprise"],
  address: ["tackle", "handle", "approach", "deal with"],
  refer: ["mention", "point to", "cite", "allude"],
  confirm: ["verify", "validate", "affirm", "establish"],
  imply: ["suggest", "indicate", "hint", "signal"],
  mention: ["note", "refer to", "state", "cite"],
  notice: ["observe", "spot", "detect", "see"],
  choose: ["select", "pick", "opt for", "prefer"],
  compare: ["contrast", "weigh", "match", "relate"],
  avoid: ["evade", "escape", "shun", "steer clear of"],
  prepare: ["ready", "plan", "arrange", "set up"],
  expect: ["anticipate", "await", "predict", "foresee"],
  support: ["back", "assist", "uphold", "help"],
  defend: ["protect", "guard", "justify", "shield"],
  decorate: ["adorn", "embellish", "trim", "style"],
};

const NEAR_NOUNS = {
  door: ["gate", "entrance", "entry", "portal"],
  gate: ["door", "entrance", "barrier", "fence"],
  review: ["critique", "assessment", "evaluation", "commentary"],
  context: ["background", "setting", "framework", "situation"],
  fallacy: ["misconception", "myth", "error", "falsehood"],
  credibility: ["trustworthiness", "reliability", "integrity", "honesty"],
  insight: ["understanding", "perception", "awareness", "realization"],
  interest: ["curiosity", "concern", "appeal", "attention"],
  focus: ["center", "emphasis", "priority", "target"],
  language: ["speech", "tongue", "dialect", "words"],
  space: ["area", "room", "zone", "place"],
  report: ["account", "summary", "statement", "record"],
  method: ["approach", "technique", "way", "system"],
  result: ["outcome", "effect", "consequence", "product"],
  reason: ["cause", "motive", "logic", "grounds"],
  detail: ["fact", "point", "element", "particular"],
  topic: ["subject", "theme", "issue", "matter"],
  message: ["note", "communication", "word", "signal"],
  story: ["tale", "account", "narrative", "report"],
  entrance: ["entry", "doorway", "access", "gate"],
  barrier: ["block", "obstacle", "wall", "fence"],
  window: ["opening", "pane", "glass", "slot"],
};

const NEAR_ADJECTIVES = {
  pragmatic: ["practical", "realistic", "sensible", "utilitarian"],
  reluctant: ["unwilling", "hesitant", "resistant", "loath"],
  clear: ["obvious", "plain", "evident", "distinct"],
  brief: ["short", "concise", "compact", "quick"],
  complex: ["complicated", "intricate", "involved", "detailed"],
  simple: ["basic", "plain", "easy", "straightforward"],
  common: ["typical", "usual", "frequent", "ordinary"],
  recent: ["latest", "new", "fresh", "current"],
  formal: ["official", "proper", "ceremonial", "structured"],
  typical: ["normal", "standard", "usual", "common"],
};

const NEAR_ADVERBS = {
  quickly: ["rapidly", "swiftly", "fast", "promptly"],
  rarely: ["seldom", "hardly", "infrequently", "scarcely"],
  nearly: ["almost", "practically", "virtually", "about"],
  finally: ["eventually", "at last", "ultimately", "in the end"],
};

const POS_NEAR = {
  verb: [
    "explain", "clarify", "describe", "mention", "notice", "accept", "deny",
    "agree", "suggest", "consider", "develop", "provide", "include", "support",
    "review", "confirm", "imply", "refer", "address", "prepare", "expect",
    "choose", "compare", "avoid", "reduce", "improve", "generate", "focus",
  ],
  noun: [
    "door", "gate", "entrance", "review", "context", "report", "detail", "topic",
    "message", "story", "method", "result", "reason", "space", "area", "issue",
    "focus", "interest", "insight", "barrier", "window", "frame", "surface",
  ],
  adjective: [
    "clear", "brief", "simple", "complex", "common", "recent", "formal", "typical",
    "practical", "reluctant", "obvious", "basic", "usual", "proper", "normal",
  ],
  adverb: ["quickly", "rarely", "nearly", "finally", "partly", "fully", "widely"],
};

function posKey(pos) {
  const p = (pos || "").toLowerCase();
  if (p === "adj" || p === "adjective") return "adjective";
  if (p === "adv" || p === "adverb") return "adverb";
  if (p === "verb") return "verb";
  return "noun";
}

function nearLemmaPool(entry) {
  return closeNeighborPool(entry);
}

function closeNeighborPool(entry) {
  const lemma = entry.word.toLowerCase();
  const pk = posKey(entry.partOfSpeech);
  const maps = { verb: NEAR_VERBS, noun: NEAR_NOUNS, adjective: NEAR_ADJECTIVES, adverb: NEAR_ADVERBS };
  let specific = maps[pk]?.[lemma] || [];
  if (specific.length < 3) {
    specific = [...new Set([...specific, ...(POS_NEAR[pk] || POS_NEAR.noun).slice(0, 8)])];
  }
  return specific.filter((w) => w.toLowerCase() !== lemma && !w.includes(" "));
}

function replaceFirstMatch(sentence, matchText, replacement) {
  const re = new RegExp(escapeRegex(matchText), "i");
  return sentence.replace(re, replacement);
}

const FALLBACK_BLANKS = {
  verb: [
    "The speaker tried to _____ the main idea more clearly.",
    "Can you _____ this point in simpler terms?",
    "She was asked to _____ the topic during the lesson.",
    "They needed to _____ the issue before making a decision.",
  ],
  noun: [
    "Everyone looked at the _____ in the picture.",
    "The _____ in this sentence carries the key meaning.",
    "Please focus on the _____ that the writer mentions.",
    "The story revolves around a single important _____.",
  ],
  adjective: [
    "The answer seemed too _____ for such a simple question.",
    "Her response was surprisingly _____ given the situation.",
    "That choice looks _____ compared with the other option.",
    "The result was more _____ than anyone expected.",
  ],
  adverb: [
    "He answered the question _____ and moved on.",
    "She _____ finished the task before the deadline.",
    "They _____ understood the rule after one example.",
    "The team worked _____ to solve the problem.",
  ],
};

function pickTemplateSentence(entry, seed) {
  const pk = posKey(entry.partOfSpeech);
  const list = FALLBACK_BLANKS[pk] || FALLBACK_BLANKS.noun;
  return list[seededPick(seed + "|tpl") % list.length];
}

function trySynonymBlank(entry, exampleIndex, neighborLemma, blankInfo) {
  const sentence = entry.examples[exampleIndex];
  if (!sentence || !blankInfo) return null;

  const form = toMatchingForm(neighborLemma, blankInfo.answer);
  if (form.includes(" ")) return null;
  const rewritten = replaceFirstMatch(sentence, blankInfo.answer, form);
  if (normalizeText(rewritten) === normalizeText(sentence)) return null;
  if (!rewritten.toLowerCase().includes(form.toLowerCase())) return null;

  const blanked = rewritten.replace(new RegExp(`\\b${escapeRegex(form)}\\b`, "i"), "_____");
  if (!blanked.includes("_____")) return null;
  return { sentence: blanked, answer: form, lemma: neighborLemma, fromExample: true };
}

function buildTemplateBlank(entry, closeNeighbors, seed, targetAsCorrect) {
  const template = pickTemplateSentence(entry, seed);
  const pk = posKey(entry.partOfSpeech);
  const pool = closeNeighbors.filter((n) => n && !n.includes(" "));
  if (pool.length === 0) pool.push(entry.word);

  let correctLemma;
  if (targetAsCorrect) {
    correctLemma = entry.word;
  } else {
    const altPool = pool.filter((n) => n.toLowerCase() !== entry.word.toLowerCase());
    correctLemma = seededShuffle(altPool.length ? altPool : pool, seed + "|synpick")[0];
  }

  let answerForm = correctLemma;
  if (pk === "verb") {
    answerForm = toMatchingForm(correctLemma, "explain");
  } else if (pk === "adjective") {
    answerForm = toMatchingForm(correctLemma, "clear");
  } else if (pk === "adverb") {
    answerForm = correctLemma;
  } else {
    answerForm = toMatchingForm(correctLemma, entry.word);
  }

  return {
    sentence: template,
    answer: answerForm,
    lemma: correctLemma,
    fromExample: false,
    baseFormForOptions: pk === "verb" ? "explain" : pk === "adjective" ? "clear" : entry.word,
  };
}

function pickDefinitionDistractors(entry, dayWords, seed, paraphrasedCorrect) {
  const targetWC = wordCount(paraphrasedCorrect);
  const others = dayWords.filter((w) => w.word.toLowerCase() !== entry.word.toLowerCase());
  const shuffled = seededShuffle(others, seed + "|defdist");
  const chosen = [];
  const used = new Set([normalizeText(paraphrasedCorrect)]);

  for (const w of shuffled) {
    if (chosen.length >= 3) break;
    const para = paraphraseDefinition(w.definition || "", seed + "|" + w.word);
    const key = normalizeText(para);
    if (used.has(key)) continue;
    if (Math.abs(wordCount(para) - targetWC) > 4) continue;
    used.add(key);
    chosen.push(para);
  }

  const pads = [
    "It means to state something clearly so others can follow your point.",
    "This is a brief written view about something you experienced or read.",
    "Something which blocks or controls the way into a place.",
    "The background details that help you understand what is happening.",
    "A mistaken idea that sounds convincing but does not hold up logically.",
  ].map((p) => paraphraseDefinition(p, seed + "|pad|" + p));

  for (const p of seededShuffle(pads, seed + "|pad")) {
    if (chosen.length >= 3) break;
    const key = normalizeText(p);
    if (used.has(key)) continue;
    used.add(key);
    chosen.push(p);
  }

  while (chosen.length < 3) {
    const filler = paraphraseDefinition(
      `A general English meaning related to everyday learning (${chosen.length + 1}).`,
      seed + "|filler|" + chosen.length
    );
    const key = normalizeText(filler);
    if (!used.has(key)) {
      used.add(key);
      chosen.push(filler);
    }
  }

  return chosen.slice(0, 3);
}

function buildCloseOptions(correct, targetLemma, neighborPool, answerForm, seed, pk) {
  const used = new Set([correct.toLowerCase()]);
  const options = [correct];

  const candidates = seededShuffle(
    [
      ...new Set([
        ...(NEAR_VERBS[targetLemma.toLowerCase()] || []),
        ...(NEAR_NOUNS[targetLemma.toLowerCase()] || []),
        ...(NEAR_ADJECTIVES[targetLemma.toLowerCase()] || []),
        ...(NEAR_ADVERBS[targetLemma.toLowerCase()] || []),
        targetLemma,
        ...neighborPool,
      ]),
    ].filter((n) => !n.includes(" ")),
    seed + "|opts"
  );

  for (const lemma of candidates) {
    if (options.length >= 4) break;
    const form = toMatchingForm(lemma, answerForm);
    const key = form.toLowerCase();
    if (used.has(key)) continue;
    if (form.length < 2 || form.includes(" ")) continue;
    used.add(key);
    options.push(form);
  }

  const pkFallback = POS_NEAR[pk] || POS_NEAR.noun;
  for (const lemma of seededShuffle(pkFallback, seed + "|fb")) {
    if (options.length >= 4) break;
    if (lemma.includes(" ")) continue;
    const form = toMatchingForm(lemma, answerForm);
    const key = form.toLowerCase();
    if (used.has(key)) continue;
    used.add(key);
    options.push(form);
  }

  return options.slice(0, 4);
}

function makeOptions(correct, distractors, seed) {
  const options = seededShuffle([correct, ...distractors.slice(0, 3)], seed + "|mk");
  const correctIndex = options.findIndex((o) => o.toLowerCase() === correct.toLowerCase());
  return { options, correctAnswerIndex: correctIndex >= 0 ? correctIndex : 0 };
}

function buildDefinitionQuiz(entry, dayWords, dayKey) {
  const seed = `${dayKey}|${entry.word}|definition`;
  const paraphrased = paraphraseDefinition(entry.definition, seed);
  const distractors = pickDefinitionDistractors(entry, dayWords, seed, paraphrased);
  const { options, correctAnswerIndex } = makeOptions(paraphrased, distractors, seed);
  return {
    type: "definition",
    question: `What does "${entry.word}" mean?`,
    options,
    correctAnswerIndex,
  };
}

function pickBlankExampleIndices(entry, dayKey, count = 2) {
  const examples = entry.examples || [];
  const viable = [];
  for (let i = 0; i < examples.length; i++) {
    if (blankFromExample(examples[i], entry.word)) viable.push(i);
  }
  if (viable.length === 0) return [0, Math.min(1, examples.length - 1)];
  const shuffled = seededShuffle(viable, `${dayKey}|${entry.word}|exshuffle`);
  const out = shuffled.slice(0, count);
  while (out.length < count) {
    out.push(viable[out.length % viable.length]);
  }
  return out;
}

function buildBlankQuiz(entry, exampleIndex, dayWords, dayKey, slot) {
  const seed = `${dayKey}|${entry.word}|blank${slot}|${exampleIndex}`;
  const closeNeighbors = closeNeighborPool(entry);
  const optionNeighbors = nearLemmaPool(entry);
  const pk = posKey(entry.partOfSpeech);
  // Each blank independently: target word or near synonym (no fixed Q2/Q3 pattern).
  const targetAsCorrect = seededBool(`${dayKey}|${entry.word}|blank|${slot}|ex${exampleIndex}|mode`);

  const examples = entry.examples || [];
  const blankInfo = blankFromExample(examples[exampleIndex], entry.word);

  let blankSentence;
  let answerForm;
  let optionBaseForm;
  let usedTarget = targetAsCorrect;

  if (targetAsCorrect && blankInfo) {
    blankSentence = blankInfo.sentence;
    answerForm = blankInfo.answer;
    optionBaseForm = blankInfo.answer;
    usedTarget = true;
  } else if (!targetAsCorrect && blankInfo) {
    const shuffledNeighbors = seededShuffle(closeNeighbors, seed + "|syn");
    let alt = null;
    for (const neighbor of shuffledNeighbors) {
      alt = trySynonymBlank(entry, exampleIndex, neighbor, blankInfo);
      if (alt && alt.lemma.toLowerCase() !== entry.word.toLowerCase()) break;
      alt = null;
    }
    if (alt) {
      blankSentence = alt.sentence;
      answerForm = alt.answer;
      optionBaseForm = blankInfo.answer;
      usedTarget = false;
    }
  }

  if (!blankSentence) {
    if (targetAsCorrect && blankInfo) {
      blankSentence = blankInfo.sentence;
      answerForm = blankInfo.answer;
      optionBaseForm = blankInfo.answer;
      usedTarget = true;
    } else {
      const tpl = buildTemplateBlank(entry, closeNeighbors, seed, targetAsCorrect);
      blankSentence = tpl.sentence;
      answerForm = tpl.answer;
      optionBaseForm = tpl.baseFormForOptions;
      usedTarget = tpl.lemma.toLowerCase() === entry.word.toLowerCase();
    }
  }

  const rawOptions = buildCloseOptions(
    answerForm,
    entry.word,
    optionNeighbors,
    optionBaseForm,
    seed,
    pk
  );

  if (!usedTarget) {
    const targetForm = toMatchingForm(entry.word, optionBaseForm);
    if (!rawOptions.some((o) => o.toLowerCase() === targetForm.toLowerCase())) {
      rawOptions[rawOptions.length - 1] = targetForm;
    }
  } else {
    // Target is correct — keep one close neighbor visible as a trap.
    for (const neighbor of seededShuffle(closeNeighbors, seed + "|trap")) {
      const form = toMatchingForm(neighbor, optionBaseForm);
      if (form.toLowerCase() === answerForm.toLowerCase()) continue;
      if (!rawOptions.some((o) => o.toLowerCase() === form.toLowerCase())) {
        rawOptions[rawOptions.length - 1] = form;
        break;
      }
    }
  }

  const options = seededShuffle(rawOptions, seed + "|final");
  const correctIndex = options.findIndex((o) => o.toLowerCase() === answerForm.toLowerCase());

  return {
    type: "blank",
    question: `Fill in the blank: ${blankSentence}`,
    options,
    correctAnswerIndex: correctIndex >= 0 ? correctIndex : 0,
    _meta: { targetAsCorrect: usedTarget },
  };
}

function buildQuiz(entry, dayWords, dayKey) {
  const quizzes = [buildDefinitionQuiz(entry, dayWords, dayKey)];

  const blankSlots = [
    { index: 0, slot: 1 },
    { index: 1, slot: 2 },
    { index: 2, slot: 3 },
  ];

  for (const { index, slot } of blankSlots) {
    if (quizzes.length >= 3) break;
    const blank = buildBlankQuiz(entry, index, dayWords, dayKey, slot);
    if (!blank) continue;
    if (quizzes.some((q) => q.question === blank.question)) continue;
    const { _meta, ...quiz } = blank;
    quiz._meta = _meta;
    quizzes.push(quiz);
  }

  return quizzes.slice(0, 3).map(({ _meta, ...q }) => q);
}

function validateQuiz(entry, quiz) {
  const errors = [];
  if (!Array.isArray(quiz) || quiz.length !== 3) {
    errors.push("need 3 questions");
    return errors;
  }

  const def = quiz[0];
  if (def.type !== "definition") errors.push("q1 not definition");
  const para = def.options[def.correctAnswerIndex];
  if (normalizeText(para) === normalizeText(entry.definition)) {
    errors.push("q1 correct equals raw definition (need paraphrase)");
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
  const failed = [];
  let synonymBlanks = 0;
  let targetBlanks = 0;

  for (const [dayKey, day] of Object.entries(pack.days || {})) {
    const dayWords = day.words || [];
    for (const entry of dayWords) {
      const previousQuiz = entry.quiz;
      const rawQuiz = [];
      rawQuiz.push(buildDefinitionQuiz(entry, dayWords, dayKey));
      const [exampleA, exampleB] = pickBlankExampleIndices(entry, dayKey);
      const blankSlots = seededShuffle(
        [
          { index: exampleA, slot: 1 },
          { index: exampleB, slot: 2 },
        ],
        `${dayKey}|${entry.word}|blankorder`
      );
      for (const { index, slot } of blankSlots) {
        if (rawQuiz.length >= 3) break;
        const blank = buildBlankQuiz(entry, index, dayWords, dayKey, slot);
        if (!blank) continue;
        if (rawQuiz.some((q) => q.question === blank.question)) continue;
        if (blank._meta?.targetAsCorrect) targetBlanks++;
        else synonymBlanks++;
        const { _meta, ...quiz } = blank;
        rawQuiz.push(quiz);
      }

      const quiz = rawQuiz.slice(0, 3);
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
  console.log(`Blank stats (approx): ${targetBlanks} target-correct, ${synonymBlanks} near-synonym-correct`);
  if (failed.length) {
    console.warn(`Failed ${failed.length} words:`);
    failed.slice(0, 15).forEach((f) => console.warn(`  ${f.day} ${f.word}: ${f.errors.join(", ")}`));
  }

  if (dryRun) {
    console.log("dry-run: file not written");
    return;
  }

  fs.writeFileSync(abs, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(`Wrote ${abs}`);
}

main();
