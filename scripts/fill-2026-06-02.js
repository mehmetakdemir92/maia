#!/usr/bin/env node
/**
 * 2026-06-02 gününü manuel curated içerikle doldurur.
 * fill-2026-06-01.js ile aynı pattern; yalnızca bir günü hedefler.
 * Kullanım: node scripts/fill-2026-06-02.js
 */

"use strict";

const fs = require("fs");
const path = require("path");

const TARGET = path.join(__dirname, "..", "maia", "WordPacks", "2026-06.json");
const DAY_KEY = "2026-06-02";

const DAY_TWO = [
  {
    word: "shop",
    cefrLevel: "a1",
    phonetic: "/ʃɒp/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 1,
    definition:
      "A building where people buy things, especially food or small items.",
    examples: [
      "The little shop on the corner sells fresh bread every morning.",
      "She works in a small shop near the city center.",
      "We stopped at the shop to buy milk on the way home.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "shop" mean?',
        options: [
          "A building where people buy things, especially food or small items.",
          "A long route used by buses to carry many passengers daily.",
          "A small wooden box used by farmers to store ripe apples.",
          "A friendly note left on the kitchen table for family members.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She works in a small _____ near the city center.",
        options: ["shop", "garden", "hospital", "library"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: We stopped at the _____ to buy milk on the way home.",
        options: ["shop", "beach", "lake", "forest"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "friend",
    cefrLevel: "a1",
    phonetic: "/frend/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 1,
    definition:
      "A person you know well and like, but who is not family.",
    examples: [
      "My best friend lives just two streets away from my house.",
      "She made a new friend on her very first day at school.",
      "I called my friend to ask for help with my homework.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "friend" mean?',
        options: [
          "A person you know well and like, but who is not family.",
          "A short letter sent to thank a stranger for some help.",
          "A small animal that lives in the cold mountains of Europe.",
          "A long line of customers waiting outside a busy new shop.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: My best _____ lives just two streets away from my house.",
        options: ["friend", "teacher", "doctor", "manager"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She made a new _____ on her very first day at school.",
        options: ["friend", "mistake", "painting", "sandwich"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "represent",
    cefrLevel: "a2",
    phonetic: "/ˌrep.rɪˈzent/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 2,
    definition:
      "To speak or act officially for a person, group, or country.",
    examples: [
      "She was chosen to represent her country at the international games.",
      "This drawing is meant to represent the company's main values clearly.",
      "Two lawyers will represent the family during the upcoming court case.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "represent" mean?',
        options: [
          "To speak or act officially for a person, group, or country.",
          "To clean a kitchen carefully before a large family dinner.",
          "To follow a stranger quietly through narrow streets at night.",
          "To borrow a friend's coat on a cold and rainy day.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She was chosen to _____ her country at the international games.",
        options: ["represent", "criticize", "abandon", "forget"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Two lawyers will _____ the family during the upcoming court case.",
        options: ["represent", "decorate", "paint", "ignore"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "satisfy",
    cefrLevel: "a2",
    phonetic: "/ˈsæt.ɪs.faɪ/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 2,
    definition:
      "To make someone pleased by giving them what they want or need.",
    examples: [
      "It is hard to satisfy every customer in a very busy restaurant.",
      "Her short answer did not satisfy the curious child at all.",
      "A walk in the park can satisfy his daily need for air.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "satisfy" mean?',
        options: [
          "To make someone pleased by giving them what they want or need.",
          "To borrow a thick book from the library for one week.",
          "To cook a small meal alone in a quiet old kitchen.",
          "To wait outside a busy office for a friend after work.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: It is hard to _____ every customer in a very busy restaurant.",
        options: ["satisfy", "ignore", "scare", "criticize"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Her short answer did not _____ the curious child at all.",
        options: ["satisfy", "frighten", "surprise", "follow"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "confirm",
    cefrLevel: "b1",
    phonetic: "/kənˈfɜːm/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 3,
    definition: "To say that something is definitely true or correct.",
    examples: [
      "Please confirm your appointment by replying to this email today.",
      "The hotel called to confirm our reservation for next Friday.",
      "Recent tests confirm that the new medicine works as expected.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "confirm" mean?',
        options: [
          "To say that something is definitely true or correct.",
          "To clean an old window with a soft cloth.",
          "To paint a wooden fence on a sunny morning.",
          "To borrow a pen from a friend in class.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please _____ your appointment by replying to this email today.",
        options: ["confirm", "criticize", "forget", "ignore"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Recent tests _____ that the new medicine works as expected.",
        options: ["confirm", "deny", "hide", "refuse"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "minimum",
    cefrLevel: "b1",
    phonetic: "/ˈmɪn.ɪ.məm/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 3,
    definition:
      "The smallest possible amount or level that is allowed or needed.",
    examples: [
      "You need a minimum of three years of experience for this job.",
      "The shop accepts cards, but with a minimum purchase of five pounds.",
      "Always try to keep your daily screen time at a sensible minimum.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "minimum" mean?',
        options: [
          "The smallest possible amount or level that is allowed or needed.",
          "A short summary written at the top of a long report.",
          "A long shadow cast by tall trees in the late afternoon.",
          "A formal letter sent to parents at the end of term.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: You need a _____ of three years of experience for this job.",
        options: ["minimum", "holiday", "contract", "hobby"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The shop accepts cards, but with a _____ purchase of five pounds.",
        options: ["minimum", "festival", "comedy", "costume"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "perceive",
    cefrLevel: "b2",
    phonetic: "/pəˈsiːv/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 5,
    definition:
      "To notice or understand something through your senses or thought.",
    examples: [
      "Animals can perceive sounds that humans are unable to hear clearly.",
      "Many customers perceive higher prices as a sign of better quality.",
      "It took her a moment to perceive the change in his mood.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "perceive" mean?',
        options: [
          "To notice or understand something through your senses or thought.",
          "To paint a wooden chair using bright and colorful patterns.",
          "To borrow a small radio from an elderly neighbor friend.",
          "To cook a simple meal for two during a quiet evening.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Animals can _____ sounds that humans are unable to hear clearly.",
        options: ["perceive", "ignore", "criticize", "forget"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: It took her a moment to _____ the change in his mood.",
        options: ["perceive", "decorate", "paint", "ignore"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "decade",
    cefrLevel: "b2",
    phonetic: "/ˈdek.eɪd/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 4,
    definition: "A period of ten years counted as one unit of time.",
    examples: [
      "The neighborhood has changed dramatically over the last decade or so.",
      "She has worked at the same company for more than a decade.",
      "This song was extremely popular during the first decade of the century.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "decade" mean?',
        options: [
          "A period of ten years counted as one unit of time.",
          "A small group of musicians playing inside a quiet church hall.",
          "A short break taken by office workers every morning at eleven.",
          "A long letter sent to old friends after a quiet holiday.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She has worked at the same company for more than a _____.",
        options: ["decade", "sandwich", "balloon", "scarf"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: This song was extremely popular during the first _____ of the century.",
        options: ["decade", "dinner", "parade", "lunchbox"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "respondent",
    cefrLevel: "c1",
    phonetic: "/rɪˈspɒn.dənt/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 5,
    definition:
      "A person who answers questions in a survey or formal study.",
    examples: [
      "Each respondent was asked to rate the product on a five-point scale.",
      "Nearly every respondent in the survey supported the proposed new policy.",
      "The researcher carefully recorded what each respondent said during the interview.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "respondent" mean?',
        options: [
          "A person who answers questions in a survey or formal study.",
          "A small bird often seen near rivers in early spring season.",
          "A large wooden chest used for storing old family photos quietly.",
          "A friendly note pinned on the door of a small office.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Each _____ was asked to rate the product on a five-point scale.",
        options: ["respondent", "sandwich", "balcony", "blanket"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Nearly every _____ in the survey supported the proposed new policy.",
        options: ["respondent", "hallway", "suitcase", "carpet"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "plasma",
    cefrLevel: "c1",
    phonetic: "/ˈplæz.mə/",
    partOfSpeech: "noun",
    domainTag: "general",
    registerTag: "neutral",
    frequencyBand: 5,
    definition:
      "The clear liquid part of blood that carries cells and proteins.",
    examples: [
      "Doctors quickly separated the plasma from the rest of the donated blood.",
      "Hospitals often store plasma to treat patients with serious burn injuries.",
      "The lab studied how plasma reacts with different types of new medicine.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "plasma" mean?',
        options: [
          "The clear liquid part of blood that carries cells and proteins.",
          "The thin paper used to wrap small gifts at children's parties.",
          "The shiny metal frame that holds a heavy mirror on walls.",
          "The narrow path between rooms inside a small old country house.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Doctors quickly separated the _____ from the rest of the donated blood.",
        options: ["plasma", "balcony", "blanket", "sandwich"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Hospitals often store _____ to treat patients with serious burn injuries.",
        options: ["plasma", "parade", "sandwich", "hallway"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "operative",
    cefrLevel: "c2",
    phonetic: "/ˈɒp.ər.ə.tɪv/",
    partOfSpeech: "adj",
    domainTag: "general",
    registerTag: "formal",
    frequencyBand: 5,
    definition:
      "Working or in force; producing the intended effect right now.",
    examples: [
      "The new safety rules become operative from the first of next month.",
      "Only one of the two engines was still operative after the accident.",
      "The agreement remains operative until either party decides to cancel it.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "operative" mean?',
        options: [
          "Working or in force; producing the intended effect right now.",
          "Made entirely of clean glass and bright polished metal frames.",
          "Decorated with bright paint along long and narrow city streets.",
          "Spoken slowly during meetings with very nervous and tired employees.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The new safety rules become _____ from the first of next month.",
        options: ["operative", "optional", "accidental", "illegal"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Only one of the two engines was still _____ after the accident.",
        options: ["operative", "decorative", "musical", "vegetable"],
        correctAnswerIndex: 0,
      },
    ],
  },
  {
    word: "corroborate",
    cefrLevel: "c2",
    phonetic: "/kəˈrɒb.ə.reɪt/",
    partOfSpeech: "verb",
    domainTag: "general",
    registerTag: "formal",
    frequencyBand: 5,
    definition:
      "To give support to a statement or theory with new evidence.",
    examples: [
      "Two witnesses came forward to corroborate the driver's version of events.",
      "Recent studies corroborate the link between regular exercise and better sleep.",
      "The detective needed more proof to corroborate the suspect's strange story.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "corroborate" mean?',
        options: [
          "To give support to a statement or theory with new evidence.",
          "To clean a kitchen carefully before a large family dinner gathering.",
          "To paint an old fence using bright colors on a Saturday.",
          "To borrow a friend's expensive coat on a cold autumn day.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Two witnesses came forward to _____ the driver's version of events.",
        options: ["corroborate", "criticize", "ignore", "abandon"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Recent studies _____ the link between regular exercise and better sleep.",
        options: ["corroborate", "deny", "hide", "refuse"],
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
  if (!pack.days || !pack.days[DAY_KEY]) {
    console.error(`error: ${DAY_KEY} girdisi yok. Önce generator'ı çalıştır.`);
    process.exit(1);
  }
  pack.days[DAY_KEY] = { words: DAY_TWO };
  fs.writeFileSync(TARGET, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(
    `✓ ${DAY_KEY}: ${DAY_TWO.length} kelime curated içerikle dolduruldu.`
  );
}

main();
