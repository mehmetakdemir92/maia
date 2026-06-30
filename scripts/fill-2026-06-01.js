#!/usr/bin/env node
/**
 * 2026-06-01 gününü manuel curated içerikle doldurur.
 * Tek seferlik bir sample dolgu; aylık paketin geri kalanı TODO placeholder kalır.
 * Kullanım: node scripts/fill-2026-06-01.js
 */

"use strict";

const fs = require("fs");
const path = require("path");

const TARGET = path.join(__dirname, "..", "maia", "WordPacks", "2026-06.json");

const DAY_ONE = [
  {
    word: "door",
    cefrLevel: "a1",
    phonetic: "/dɔːr/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 1,
    definition: "A movable barrier that opens and closes an entrance.",
    examples: [
      "Please close the door behind you when you leave.",
      "The cat scratched at the door to be let in.",
      "We painted the front door bright red last weekend.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "door" mean?',
        options: [
          "A movable barrier that opens and closes an entrance.",
          "A small window placed high above kitchen sinks.",
          "A flat surface used for serving family meals.",
          "A long passage between rooms inside large houses.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please close the _____ behind you when you leave.",
        options: ["door", "window", "fence", "ceiling"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: We painted the front _____ bright red last weekend.",
        options: ["door", "garden", "carpet", "ceiling"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "review",
    cefrLevel: "a1",
    phonetic: "/rɪˈvjuː/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 2,
    definition:
      "A short report that gives an opinion about a book, film, or product.",
    examples: [
      "I read a positive review of the new restaurant online.",
      "Her review of the film was published in the newspaper.",
      "Before buying the camera, he checked every customer review.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "review" mean?',
        options: [
          "A short report giving an opinion about a product.",
          "A formal contract signed before joining a company.",
          "A polite note sent to thank a close friend.",
          "A meeting between students and a school principal.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: I read a positive _____ of the new restaurant online.",
        options: ["review", "recipe", "menu", "manager"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Before buying the camera, he checked every customer _____.",
        options: ["review", "receipt", "sample", "label"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "context",
    cefrLevel: "a2",
    phonetic: "/ˈkɒn.tekst/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 2,
    definition: "The situation or background that helps explain something.",
    examples: [
      "Without the right context, the joke didn't make any sense.",
      "She read the chapter again to understand the historical context.",
      "Quoting words out of context can change their meaning completely.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "context" mean?',
        options: [
          "The situation or background that helps explain something.",
          "A short note added at the end of a letter.",
          "A polite question used by strangers on long trains.",
          "A small drawing placed at the top of pages.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Without the right _____, the joke didn't make any sense.",
        options: ["context", "recipe", "costume", "network"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She read the chapter again to understand the historical _____.",
        options: ["context", "calendar", "ceiling", "currency"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "admit",
    cefrLevel: "a2",
    phonetic: "/ədˈmɪt/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 2,
    definition: "To agree that something is true, often unwillingly.",
    examples: [
      "He had to admit that he was wrong about the dates.",
      "She finally admitted she had broken the vase.",
      "The teacher admitted that the test was harder than expected.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "admit" mean?',
        options: [
          "To agree that something is true, often unwillingly.",
          "To leave a quiet room without saying goodbye.",
          "To finish a project earlier than the agreed deadline.",
          "To decorate a wall with several framed photographs.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He had to _____ that he was wrong about the dates.",
        options: ["admit", "prepare", "refuse", "expect"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She finally _____ she had broken the vase.",
        options: ["admitted", "decorated", "defended", "suspected"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "burden",
    cefrLevel: "b1",
    phonetic: "/ˈbɜː.dən/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 4,
    definition:
      "A heavy load or a difficult responsibility someone has to carry.",
    examples: [
      "Caring for her elderly parents became a heavy burden over time.",
      "He didn't want his health problems to be a burden on his family.",
      "The new tax placed an unfair burden on small businesses.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "burden" mean?',
        options: [
          "A heavy load or a difficult responsibility to carry.",
          "A shiny medal given to athletes after long races.",
          "A friendly greeting used in formal business letters.",
          "A small toy designed for very young toddlers.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Caring for her elderly parents became a heavy _____ over time.",
        options: ["burden", "hobby", "reward", "dance"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The new tax placed an unfair _____ on small businesses.",
        options: ["burden", "holiday", "contract", "summer"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "violence",
    cefrLevel: "b1",
    phonetic: "/ˈvaɪə.ləns/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 3,
    definition:
      "Behavior that uses physical force to hurt people or damage things.",
    examples: [
      "The film contains scenes of graphic violence and is not for children.",
      "The protest ended without any violence after police kept order.",
      "She left the relationship because of his repeated violence at home.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "violence" mean?',
        options: [
          "Behavior using physical force to hurt people or damage things.",
          "A traditional dance performed at large outdoor weddings.",
          "A formal speech given by a head of state.",
          "A long paper written by university students each semester.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The film contains scenes of graphic _____ and is not for children.",
        options: ["violence", "comedy", "music", "cooking"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The protest ended without any _____ after police kept order.",
        options: ["violence", "applause", "music", "snow"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "sustain",
    cefrLevel: "b2",
    phonetic: "/səˈsteɪn/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 4,
    definition: "To keep something going or to support something over time.",
    examples: [
      "It is hard to sustain such a fast pace for the whole day.",
      "The bridge was strong enough to sustain heavy trucks every hour.",
      "Healthy eating helps sustain your energy throughout the morning.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "sustain" mean?',
        options: [
          "To keep something going or support it over time.",
          "To suddenly stop talking during an important conversation.",
          "To explain a complex problem briefly to a child.",
          "To buy several copies of the same expensive book.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: It is hard to _____ such a fast pace for the whole day.",
        options: ["sustain", "ignore", "forget", "deliver"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Healthy eating helps _____ your energy throughout the morning.",
        options: ["sustain", "attack", "criticize", "avoid"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "illustrate",
    cefrLevel: "b2",
    phonetic: "/ˈɪl.ə.streɪt/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 4,
    definition:
      "To explain or make something clearer using examples or pictures.",
    examples: [
      "The teacher used a chart to illustrate the company's growth.",
      "These graphs illustrate how the climate has changed since 1950.",
      "Let me illustrate my point with a quick example from work.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "illustrate" mean?',
        options: [
          "To explain something clearly using examples or pictures.",
          "To clean a kitchen carefully before guests arrive.",
          "To wait quietly outside an office for an interview.",
          "To borrow a friend's coat on a rainy autumn day.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The teacher used a chart to _____ the company's growth.",
        options: ["illustrate", "ignore", "repeat", "refuse"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Let me _____ my point with a quick example from work.",
        options: ["illustrate", "hide", "abandon", "criticize"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "coefficient",
    cefrLevel: "c1",
    phonetic: "/ˌkəʊ.ɪˈfɪʃ.ənt/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 5,
    definition:
      "A number used in math to multiply a variable in an expression.",
    examples: [
      "In the term 5x, the coefficient of x is five.",
      "The friction coefficient between the two surfaces was unusually low.",
      "Engineers calculated the safety coefficient before approving the design.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "coefficient" mean?',
        options: [
          "A number used in math to multiply a variable.",
          "A traditional cake served at large family birthdays.",
          "A formal letter sent to schools by parents weekly.",
          "A rapid signal flashed by ships during stormy nights.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: In the term 5x, the _____ of x is five.",
        options: ["coefficient", "rhyme", "suffix", "paragraph"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The friction _____ between the two surfaces was unusually low.",
        options: ["coefficient", "audience", "breakfast", "manager"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "albeit",
    cefrLevel: "c1",
    phonetic: "/ɔːlˈbiː.ɪt/",
    partOfSpeech: "conj",
    domainTag: "general",
    registerTag: "formal",
    frequencyBand: 5,
    definition: "Although; used to introduce a contrast or limitation.",
    examples: [
      "She agreed to help, albeit with some hesitation in her voice.",
      "The test was useful, albeit a little long for younger students.",
      "He returned home safely, albeit several hours later than planned.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "albeit" mean?',
        options: [
          "Although; used to introduce a contrast or limitation.",
          "Therefore; used to draw a strong logical conclusion.",
          "Meanwhile; used to describe events happening at once.",
          "Suddenly; used at the start of dramatic news reports.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She agreed to help, _____ with some hesitation in her voice.",
        options: ["albeit", "because", "unless", "until"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The test was useful, _____ a little long for younger students.",
        options: ["albeit", "until", "while", "before"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "axiomatic",
    cefrLevel: "c2",
    phonetic: "/ˌæk.si.əˈmæt.ɪk/",
    partOfSpeech: "adj",
    domainTag: "general",
    registerTag: "formal",
    frequencyBand: 5,
    definition:
      "Considered to be obviously true and not needing any proof.",
    examples: [
      "It is axiomatic that all citizens deserve equal treatment under the law.",
      "In their team, careful planning before action was almost axiomatic.",
      "He treated honesty as an axiomatic value he never compromised on.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "axiomatic" mean?',
        options: [
          "Considered obviously true and not needing any proof.",
          "Made entirely of glass, light, and polished steel.",
          "Decorated with bright paint along narrow city streets.",
          "Spoken slowly during meetings with very nervous employees.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: It is _____ that all citizens deserve equal treatment under the law.",
        options: ["axiomatic", "surprising", "optional", "illegal"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He treated honesty as an _____ value he never compromised on.",
        options: ["axiomatic", "accidental", "optional", "unusual"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "hypothesis",
    cefrLevel: "c2",
    phonetic: "/haɪˈpɒθ.ə.sɪs/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "formal",
    frequencyBand: 5,
    definition:
      "An idea suggested as a possible explanation that can be tested.",
    examples: [
      "The team designed an experiment to test their main hypothesis.",
      "Her hypothesis about the new compound turned out to be correct.",
      "Scientists often propose a bold hypothesis before gathering any data.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "hypothesis" mean?',
        options: [
          "An idea suggested as a possible explanation to test.",
          "A formal apology offered after a serious workplace accident.",
          "A long shadow seen on the floor at sunset.",
          "A polite request made by tourists at hotel reception.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The team designed an experiment to test their main _____.",
        options: ["hypothesis", "dinner", "balloon", "hallway"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Scientists often propose a bold _____ before gathering any data.",
        options: ["hypothesis", "sandwich", "parade", "scarf"],
        correctAnswerIndex: 0,
      },
    ],
  },
];

function main() {
  if (!fs.existsSync(TARGET)) {
    console.error(`error: ${TARGET} bulunamadı.`);
    process.exit(1);
  }
  const raw = fs.readFileSync(TARGET, "utf8");
  const pack = JSON.parse(raw);
  if (!pack.days || !pack.days["2026-06-01"]) {
    console.error("error: 2026-06-01 girdisi yok. Önce generator'ı çalıştır.");
    process.exit(1);
  }
  pack.days["2026-06-01"] = { words: DAY_ONE };
  fs.writeFileSync(TARGET, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(
    `✓ 2026-06-01: ${DAY_ONE.length} kelime curated içerikle dolduruldu.`
  );
}

main();
