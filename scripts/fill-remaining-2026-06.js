#!/usr/bin/env node
/**
 * Kalan TODO kelimeleri (2026-06-15, 26, 28, 29, 30) curated içerikle doldurur.
 * Kullanım: node scripts/fill-remaining-2026-06.js
 */

"use strict";

const fs = require("fs");
const path = require("path");

const TARGET = path.join(__dirname, "..", "maia", "WordPacks", "2026-06.json");

/** @type {Record<string, object>} */
const CURATED = {
  coherent: {
    phonetic: "/kəʊˈhɪə.rənt/",
    definition:
      "Logical and clear; easy to follow because all parts fit together well.",
    examples: [
      "She gave a coherent explanation of why the project had failed.",
      "Without enough sleep, it is hard to write a coherent essay.",
      "The witness told a coherent story that matched the evidence.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "coherent" mean?',
        options: [
          "Logical and clear; easy to follow because all parts fit together well.",
          "Extremely loud and difficult to ignore in a crowded public place.",
          "Made entirely of glass and polished metal in a modern office.",
          "Spoken slowly during meetings with very nervous new employees.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Without enough sleep, it is hard to write a _____ essay.",
        options: ["coherent", "fragile", "distant", "ancient"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The witness told a _____ story that matched the evidence.",
        options: ["coherent", "random", "broken", "silent"],
        correctAnswerIndex: 0,
      },
    ],
  },
  differ: {
    phonetic: "/ˈdɪf.ər/",
    definition: "To be unlike or not the same as someone or something else.",
    examples: [
      "Our opinions differ on how to spend the holiday budget.",
      "These two phones differ mainly in screen size and battery life.",
      "Children often differ from their parents in music taste.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "differ" mean?',
        options: [
          "To be unlike or not the same as someone or something else.",
          "To clean a kitchen carefully before guests arrive for dinner.",
          "To borrow a thick book from the library for one week only.",
          "To wait outside a busy office for a friend after work.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: These two phones _____ mainly in screen size and battery life.",
        options: ["differ", "agree", "match", "repeat"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Children often _____ from their parents in music taste.",
        options: ["differ", "follow", "copy", "join"],
        correctAnswerIndex: 0,
      },
    ],
  },
  volume: {
    phonetic: "/ˈvɒl.juːm/",
    definition:
      "The amount of space something fills, or how loud a sound is.",
    examples: [
      "Please turn down the volume on the television; it is too loud.",
      "The volume of water in the tank dropped during the long drought.",
      "Sales volume increased sharply after the new advertising campaign.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "volume" mean?',
        options: [
          "The amount of space something fills, or how loud a sound is.",
          "A short note added at the end of a formal business letter.",
          "A small animal often seen near rivers in early spring season.",
          "A friendly greeting used between strangers on long train rides.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please turn down the _____ on the television; it is too loud.",
        options: ["volume", "color", "height", "weight"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Sales _____ increased sharply after the new advertising campaign.",
        options: ["volume", "weather", "silence", "patience"],
        correctAnswerIndex: 0,
      },
    ],
  },
  nitrogen: {
    phonetic: "/ˈnaɪ.trə.dʒən/",
    definition:
      "A colorless gas that makes up most of the air we breathe.",
    examples: [
      "Plants need nitrogen in the soil to grow strong and healthy.",
      "The scientist measured how much nitrogen was present in the sample.",
      "Liquid nitrogen is kept at extremely low temperatures in the lab.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "nitrogen" mean?',
        options: [
          "A colorless gas that makes up most of the air we breathe.",
          "A thin paper used to wrap small gifts at children's parties.",
          "A shiny metal frame that holds a heavy mirror on walls.",
          "A narrow path between rooms inside a small old country house.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Plants need _____ in the soil to grow strong and healthy.",
        options: ["nitrogen", "silence", "carpet", "sandwich"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Liquid _____ is kept at extremely low temperatures in the lab.",
        options: ["nitrogen", "parade", "blanket", "hallway"],
        correctAnswerIndex: 0,
      },
    ],
  },
  entail: {
    phonetic: "/ɪnˈteɪl/",
    definition:
      "To involve something as a necessary part or result of an action.",
    examples: [
      "The new job will entail working late at least twice a week.",
      "Building the bridge will entail huge costs and careful planning.",
      "Accepting the offer may entail moving to another city next year.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "entail" mean?',
        options: [
          "To involve something as a necessary part or result of an action.",
          "To clean a kitchen carefully before a large family dinner gathering.",
          "To paint an old fence using bright colors on a sunny Saturday.",
          "To borrow a friend's expensive coat on a cold autumn day.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The new job will _____ working late at least twice a week.",
        options: ["entail", "prevent", "ignore", "cancel"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Accepting the offer may _____ moving to another city next year.",
        options: ["entail", "avoid", "deny", "refuse"],
        correctAnswerIndex: 0,
      },
    ],
  },
  ameliorate: {
    phonetic: "/əˈmiː.li.ə.reɪt/",
    definition: "To make a bad or difficult situation better or less severe.",
    examples: [
      "New policies were introduced to ameliorate poverty in rural areas.",
      "The doctor tried to ameliorate the patient's pain with gentle care.",
      "Extra funding could ameliorate some of the school's staffing problems.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "ameliorate" mean?',
        options: [
          "To make a bad or difficult situation better or less severe.",
          "To intensify the effect or gravity of an already adverse situation.",
          "To completely eliminate the origin or cause of a difficult problem.",
          "To introduce new elements that complicate an already tricky scenario.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: New policies were introduced to _____ poverty in rural areas.",
        options: ["ameliorate", "worsen", "ignore", "abandon"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Extra funding could _____ some of the school's staffing problems.",
        options: ["ameliorate", "aggravate", "hide", "refuse"],
        correctAnswerIndex: 0,
      },
    ],
  },
  color: {
    phonetic: "/ˈkʌl.ər/",
    definition:
      "The quality of things that we see with our eyes, such as red or blue.",
    examples: [
      "What is your favorite color for painting the bedroom walls?",
      "The leaves change color every autumn in this part of the country.",
      "She wore a bright color that stood out in the crowd.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "color" mean?',
        options: [
          "The quality of things that we see with our eyes, such as red or blue.",
          "A long route used by buses to carry many passengers every day.",
          "A small wooden box used by farmers to store ripe apples.",
          "A friendly note left on the kitchen table for family members.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The leaves change _____ every autumn in this part of the country.",
        options: ["color", "shape", "weight", "price"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She wore a bright _____ that stood out in the crowd.",
        options: ["color", "sound", "smell", "taste"],
        correctAnswerIndex: 0,
      },
    ],
  },
  happy: {
    phonetic: "/ˈhæp.i/",
    definition: "Feeling or showing pleasure, contentment, or joy.",
    examples: [
      "The children were happy when they heard about the school trip.",
      "She looked happy after receiving good news from her family.",
      "A short walk in the sun can make me feel happy again.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "happy" mean?',
        options: [
          "Feeling or showing pleasure, contentment, or joy.",
          "Extremely tired after working for many hours without rest.",
          "Made entirely of clean glass and bright polished metal frames.",
          "Spoken slowly during meetings with very nervous new employees.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She looked _____ after receiving good news from her family.",
        options: ["happy", "angry", "bored", "hungry"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: A short walk in the sun can make me feel _____ again.",
        options: ["happy", "heavy", "empty", "frozen"],
        correctAnswerIndex: 0,
      },
    ],
  },
  strategy: {
    phonetic: "/ˈstræt.ə.dʒi/",
    definition:
      "A careful plan designed to achieve a particular goal over time.",
    examples: [
      "The team discussed a new strategy to win more customers this year.",
      "Her marketing strategy focused on social media and short videos.",
      "Without a clear strategy, the project quickly lost direction.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "strategy" mean?',
        options: [
          "A careful plan designed to achieve a particular goal over time.",
          "A short break taken by office workers every morning at eleven.",
          "A long letter sent to old friends after a quiet holiday.",
          "A small group of musicians playing inside a quiet church hall.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Her marketing _____ focused on social media and short videos.",
        options: ["strategy", "recipe", "garden", "window"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Without a clear _____, the project quickly lost direction.",
        options: ["strategy", "sandwich", "blanket", "hallway"],
        correctAnswerIndex: 0,
      },
    ],
  },
  allow: {
    phonetic: "/əˈlaʊ/",
    definition: "To let someone do something or let something happen.",
    examples: [
      "The teacher does not allow phones during the exam.",
      "This ticket will allow you to enter the museum once.",
      "Parents should allow children time to play outside every day.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "allow" mean?',
        options: [
          "To let someone do something or let something happen.",
          "To borrow a thick book from the library for one week only.",
          "To cook a small meal alone in a quiet old kitchen.",
          "To wait outside a busy office for a friend after work.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: This ticket will _____ you to enter the museum once.",
        options: ["allow", "prevent", "force", "hide"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Parents should _____ children time to play outside every day.",
        options: ["allow", "deny", "ignore", "criticize"],
        correctAnswerIndex: 0,
      },
    ],
  },
  respond: {
    phonetic: "/rɪˈspɒnd/",
    definition: "To say or do something as a reaction to a question or event.",
    examples: [
      "Please respond to my email before the end of the week.",
      "The patient did not respond well to the first type of medicine.",
      "How quickly did the company respond to the customer complaint?",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "respond" mean?',
        options: [
          "To say or do something as a reaction to a question or event.",
          "To clean an old window with a soft cloth on a Saturday.",
          "To paint a wooden fence on a sunny morning in summer.",
          "To borrow a pen from a friend during a long class.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please _____ to my email before the end of the week.",
        options: ["respond", "forget", "ignore", "delay"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The patient did not _____ well to the first type of medicine.",
        options: ["respond", "travel", "sleep", "cook"],
        correctAnswerIndex: 0,
      },
    ],
  },
  mission: {
    phonetic: "/ˈmɪʃ.ən/",
    definition:
      "An important job or purpose that someone is sent or chosen to do.",
    examples: [
      "The charity's mission is to provide clean water to rural villages.",
      "He accepted a dangerous mission behind enemy lines during the war.",
      "Our school's mission focuses on creativity, respect, and lifelong learning.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "mission" mean?',
        options: [
          "An important job or purpose that someone is sent or chosen to do.",
          "A short summary written at the top of a long business report.",
          "A long shadow cast by tall trees in the late afternoon sun.",
          "A formal letter sent to parents at the end of the school term.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He accepted a dangerous _____ behind enemy lines during the war.",
        options: ["mission", "holiday", "recipe", "costume"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Our school's _____ focuses on creativity, respect, and lifelong learning.",
        options: ["mission", "sandwich", "blanket", "parade"],
        correctAnswerIndex: 0,
      },
    ],
  },
  whereas: {
    phonetic: "/weərˈæz/",
    definition:
      "Used to compare two different facts or situations in contrast.",
    examples: [
      "She loves city life, whereas her brother prefers the quiet countryside.",
      "The north is dry, whereas the south receives heavy rain every year.",
      "He wanted to save money, whereas his partner preferred to spend it.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "whereas" mean?',
        options: [
          "Used to compare two different facts or situations in contrast.",
          "Therefore; used to draw a strong logical conclusion from evidence.",
          "Meanwhile; used to describe events happening at the same time.",
          "Suddenly; used at the start of dramatic news reports on television.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She loves city life, _____ her brother prefers the quiet countryside.",
        options: ["whereas", "because", "unless", "until"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He wanted to save money, _____ his partner preferred to spend it.",
        options: ["whereas", "while", "before", "after"],
        correctAnswerIndex: 0,
      },
    ],
  },
  cope: {
    phonetic: "/kəʊp/",
    definition:
      "To deal successfully with a difficult problem or situation.",
    examples: [
      "It took her a while to cope with the stress of the new job.",
      "Young parents often struggle to cope when their baby won't sleep.",
      "The hospital has extra staff to help cope with the winter flu season.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "cope" mean?',
        options: [
          "To deal successfully with a difficult problem or situation.",
          "To paint a wooden chair using bright and colorful patterns.",
          "To borrow a small radio from an elderly neighbor friend.",
          "To cook a simple meal for two during a quiet evening.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: It took her a while to _____ with the stress of the new job.",
        options: ["cope", "ignore", "forget", "abandon"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The hospital has extra staff to help _____ with the winter flu season.",
        options: ["cope", "celebrate", "decorate", "compete"],
        correctAnswerIndex: 0,
      },
    ],
  },
  appellant: {
    phonetic: "/əˈpel.ənt/",
    definition:
      "A person who appeals to a higher court to change a legal decision.",
    examples: [
      "The appellant argued that the original trial had been unfair.",
      "Lawyers for the appellant filed new documents with the court yesterday.",
      "The judge listened carefully to the appellant's reasons for appeal.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "appellant" mean?',
        options: [
          "A person who appeals to a higher court to change a legal decision.",
          "A small bird often seen near rivers in the early spring season.",
          "A large wooden chest used for storing old family photographs quietly.",
          "A friendly note pinned on the door of a small office.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Lawyers for the _____ filed new documents with the court yesterday.",
        options: ["appellant", "sandwich", "balcony", "blanket"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The judge listened carefully to the _____'s reasons for appeal.",
        options: ["appellant", "hallway", "suitcase", "carpet"],
        correctAnswerIndex: 0,
      },
    ],
  },
  appendix: {
    phonetic: "/əˈpen.dɪks/",
    definition:
      "A section at the end of a book with extra information or details.",
    examples: [
      "The report includes an appendix with all the raw survey data.",
      "Please check the appendix for a full list of references and sources.",
      "She added an appendix explaining the technical terms used in the text.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "appendix" mean?',
        options: [
          "A section at the end of a book with extra information or details.",
          "A thin paper used to wrap small gifts at children's birthday parties.",
          "A shiny metal frame that holds a heavy mirror on office walls.",
          "A narrow path between rooms inside a small old country house.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please check the _____ for a full list of references and sources.",
        options: ["appendix", "balcony", "blanket", "sandwich"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She added an _____ explaining the technical terms used in the text.",
        options: ["appendix", "parade", "hallway", "lunchbox"],
        correctAnswerIndex: 0,
      },
    ],
  },
  exemplify: {
    phonetic: "/ɪɡˈzem.plɪ.faɪ/",
    definition: "To be a typical example of something; to show it clearly.",
    examples: [
      "Her calm leadership exemplifies the values our company wants to promote.",
      "This case exemplifies the risks of investing without proper research.",
      "The poem exemplifies the style of writing popular in the nineteenth century.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "exemplify" mean?',
        options: [
          "To be a typical example of something; to show it clearly.",
          "To clean a kitchen carefully before a large family dinner gathering.",
          "To paint an old fence using bright colors on a sunny Saturday.",
          "To borrow a friend's expensive coat on a cold autumn day.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: This case _____ the risks of investing without proper research.",
        options: ["exemplifies", "hides", "denies", "refuses"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The poem _____ the style of writing popular in the nineteenth century.",
        options: ["exemplifies", "attacks", "avoids", "breaks"],
        correctAnswerIndex: 0,
      },
    ],
  },
  expedite: {
    phonetic: "/ˈek.spə.daɪt/",
    definition: "To make an action or process happen more quickly.",
    examples: [
      "Paying an extra fee can expedite the delivery of your package.",
      "The manager asked staff to expedite the review of urgent applications.",
      "New software was introduced to expedite data entry across the team.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "expedite" mean?',
        options: [
          "To make an action or process happen more quickly.",
          "To slow down a process deliberately to save money on resources.",
          "To cancel a meeting without telling anyone in advance at all.",
          "To hide important documents from colleagues during a long project.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Paying an extra fee can _____ the delivery of your package.",
        options: ["expedite", "delay", "cancel", "ignore"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: New software was introduced to _____ data entry across the team.",
        options: ["expedite", "block", "freeze", "waste"],
        correctAnswerIndex: 0,
      },
    ],
  },
  class: {
    phonetic: "/klɑːs/",
    definition:
      "A group of students who are taught together at school or college.",
    examples: [
      "Our English class starts at nine o'clock every Monday morning.",
      "The teacher asked the whole class to open their books to page ten.",
      "She made many friends in her first class at the new school.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "class" mean?',
        options: [
          "A group of students who are taught together at school or college.",
          "A long route used by buses to carry many passengers every day.",
          "A small wooden box used by farmers to store ripe apples.",
          "A friendly note left on the kitchen table for family members.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The teacher asked the whole _____ to open their books to page ten.",
        options: ["class", "garden", "kitchen", "street"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She made many friends in her first _____ at the new school.",
        options: ["class", "meal", "trip", "song"],
        correctAnswerIndex: 0,
      },
    ],
  },
  skill: {
    phonetic: "/skɪl/",
    definition:
      "The ability to do something well, usually gained through practice.",
    examples: [
      "Good communication is an important skill in almost every job.",
      "She developed her cooking skill by practicing recipes every weekend.",
      "Learning a new language takes time, patience, and real skill.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "skill" mean?',
        options: [
          "The ability to do something well, usually gained through practice.",
          "A short note added at the end of a formal business letter.",
          "A small animal often seen near rivers in early spring season.",
          "A friendly greeting used between strangers on long train rides.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She developed her cooking _____ by practicing recipes every weekend.",
        options: ["skill", "weather", "silence", "color"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Learning a new language takes time, patience, and real _____.",
        options: ["skill", "luck", "noise", "rain"],
        correctAnswerIndex: 0,
      },
    ],
  },
  thereby: {
    phonetic: "/ˌðeəˈbaɪ/",
    definition: "As a result of that; by that means or in that way.",
    examples: [
      "She saved money every month, thereby building a small emergency fund.",
      "The company cut costs and thereby improved its chances of survival.",
      "He apologized sincerely, thereby easing the tension in the room.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "thereby" mean?',
        options: [
          "As a result of that; by that means or in that way.",
          "Before anything else happens; at the very start of a long day.",
          "Without any reason at all; in a completely random manner today.",
          "Despite strong opposition; against the wishes of most people present.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: She saved money every month, _____ building a small emergency fund.",
        options: ["thereby", "however", "although", "unless"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He apologized sincerely, _____ easing the tension in the room.",
        options: ["thereby", "never", "rarely", "barely"],
        correctAnswerIndex: 0,
      },
    ],
  },
  reflect: {
    phonetic: "/rɪˈflekt/",
    definition:
      "To think carefully about something, or to throw back light or sound.",
    examples: [
      "Take a moment to reflect on what you learned from the experience.",
      "The lake was so calm that the mountains seemed to reflect in the water.",
      "Her essay reflects a deep understanding of the topic.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "reflect" mean?',
        options: [
          "To think carefully about something, or to throw back light or sound.",
          "To clean a kitchen carefully before guests arrive for dinner.",
          "To borrow a thick book from the library for one week only.",
          "To wait outside a busy office for a friend after work.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Take a moment to _____ on what you learned from the experience.",
        options: ["reflect", "shout", "run", "sell"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Her essay _____ a deep understanding of the topic.",
        options: ["reflects", "denies", "hides", "breaks"],
        correctAnswerIndex: 0,
      },
    ],
  },
  guarantee: {
    phonetic: "/ˌɡær.ənˈtiː/",
    definition:
      "A formal promise that something will happen or be of good quality.",
    examples: [
      "The shop offers a two-year guarantee on all electronic products.",
      "I cannot guarantee that the train will arrive on time today.",
      "The contract includes a guarantee that repairs will be done within a week.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "guarantee" mean?',
        options: [
          "A formal promise that something will happen or be of good quality.",
          "A short break taken by office workers every morning at eleven.",
          "A long letter sent to old friends after a quiet holiday.",
          "A small group of musicians playing inside a quiet church hall.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The shop offers a two-year _____ on all electronic products.",
        options: ["guarantee", "recipe", "garden", "window"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: I cannot _____ that the train will arrive on time today.",
        options: ["guarantee", "forget", "ignore", "delay"],
        correctAnswerIndex: 0,
      },
    ],
  },
  desire: {
    phonetic: "/dɪˈzaɪər/",
    definition: "A strong feeling of wanting something or wishing for it.",
    examples: [
      "Her desire to travel grew stronger after she finished university.",
      "There is a growing desire among voters for more honest politicians.",
      "He spoke openly about his desire to start his own business.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "desire" mean?',
        options: [
          "A strong feeling of wanting something or wishing for it.",
          "A formal apology offered after a serious workplace accident.",
          "A long shadow seen on the floor at sunset in summer.",
          "A polite request made by tourists at hotel reception desks.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Her _____ to travel grew stronger after she finished university.",
        options: ["desire", "fear", "hatred", "silence"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: He spoke openly about his _____ to start his own business.",
        options: ["desire", "refusal", "doubt", "anger"],
        correctAnswerIndex: 0,
      },
    ],
  },
  submit: {
    phonetic: "/səbˈmɪt/",
    definition:
      "To give a document, application, or piece of work to someone in authority.",
    examples: [
      "Please submit your assignment before midnight on Friday.",
      "She decided to submit her resignation after the disagreement.",
      "All candidates must submit their forms online by the deadline.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "submit" mean?',
        options: [
          "To give a document, application, or piece of work to someone in authority.",
          "To paint a wooden chair using bright and colorful patterns.",
          "To borrow a small radio from an elderly neighbor friend.",
          "To cook a simple meal for two during a quiet evening.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Please _____ your assignment before midnight on Friday.",
        options: ["submit", "hide", "burn", "lose"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: All candidates must _____ their forms online by the deadline.",
        options: ["submit", "ignore", "delete", "refuse"],
        correctAnswerIndex: 0,
      },
    ],
  },
  cooperate: {
    phonetic: "/kəʊˈɒp.ər.eɪt/",
    definition: "To work together with others to achieve a shared goal.",
    examples: [
      "The two departments agreed to cooperate on the new marketing project.",
      "Children learn to cooperate when they play team sports at school.",
      "Witnesses refused to cooperate with the police during the investigation.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "cooperate" mean?',
        options: [
          "To work together with others to achieve a shared goal.",
          "To compete fiercely against others for a single prize or reward.",
          "To leave a meeting early without saying goodbye to anyone.",
          "To criticize colleagues openly during a tense team discussion.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Children learn to _____ when they play team sports at school.",
        options: ["cooperate", "argue", "compete", "escape"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Witnesses refused to _____ with the police during the investigation.",
        options: ["cooperate", "travel", "sleep", "cook"],
        correctAnswerIndex: 0,
      },
    ],
  },
  equilibrium: {
    phonetic: "/ˌiː.kwɪˈlɪb.ri.əm/",
    definition:
      "A state of balance between opposing forces or influences.",
    examples: [
      "The market reached equilibrium when supply finally matched demand.",
      "Yoga can help restore a sense of mental equilibrium after stress.",
      "Scientists studied how the ecosystem maintains its natural equilibrium.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "equilibrium" mean?',
        options: [
          "A state of balance between opposing forces or influences.",
          "A small bird often seen near rivers in the early spring season.",
          "A large wooden chest used for storing old family photographs quietly.",
          "A friendly note pinned on the door of a small office.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The market reached _____ when supply finally matched demand.",
        options: ["equilibrium", "sandwich", "balcony", "blanket"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Scientists studied how the ecosystem maintains its natural _____.",
        options: ["equilibrium", "hallway", "suitcase", "carpet"],
        correctAnswerIndex: 0,
      },
    ],
  },
  absorption: {
    phonetic: "/əbˈzɔːp.ʃən/",
    definition:
      "The process of taking in a liquid, gas, or information completely.",
    examples: [
      "The sponge's absorption of water was surprisingly fast and thorough.",
      "Vitamin absorption improves when you eat certain foods together.",
      "Her complete absorption in the novel made her miss the bus stop.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "absorption" mean?',
        options: [
          "The process of taking in a liquid, gas, or information completely.",
          "A thin paper used to wrap small gifts at children's birthday parties.",
          "A shiny metal frame that holds a heavy mirror on office walls.",
          "A narrow path between rooms inside a small old country house.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Vitamin _____ improves when you eat certain foods together.",
        options: ["absorption", "rejection", "expansion", "division"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Her complete _____ in the novel made her miss the bus stop.",
        options: ["absorption", "hatred", "silence", "anger"],
        correctAnswerIndex: 0,
      },
    ],
  },
  proliferate: {
    phonetic: "/prəˈlɪf.ər.eɪt/",
    definition: "To increase rapidly in number or spread widely.",
    examples: [
      "Fast-food restaurants began to proliferate across the city in the 1990s.",
      "Rumors tend to proliferate quickly on social media during a crisis.",
      "Certain bacteria can proliferate in warm, damp environments within hours.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "proliferate" mean?',
        options: [
          "To increase rapidly in number or spread widely.",
          "To decrease slowly until almost nothing remains in the area.",
          "To stay completely still without moving for a long time.",
          "To disappear suddenly without leaving any trace behind at all.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Rumors tend to _____ quickly on social media during a crisis.",
        options: ["proliferate", "vanish", "shrink", "freeze"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: Certain bacteria can _____ in warm, damp environments within hours.",
        options: ["proliferate", "starve", "sleep", "melt"],
        correctAnswerIndex: 0,
      },
    ],
  },
  hegemony: {
    phonetic: "/hɪˈɡem.ə.ni/",
    definition:
      "Leadership or dominant influence of one country or group over others.",
    examples: [
      "The empire maintained its hegemony over trade routes for centuries.",
      "Critics warned that cultural hegemony could silence smaller nations' voices.",
      "The debate focused on whether economic hegemony leads to lasting peace.",
    ],
    quiz: [
      {
        type: "definition",
        question: 'What does "hegemony" mean?',
        options: [
          "Leadership or dominant influence of one country or group over others.",
          "A traditional cake served at large family birthday celebrations.",
          "A formal letter sent to schools by parents at the end of term.",
          "A rapid signal flashed by ships during stormy nights at sea.",
        ],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The empire maintained its _____ over trade routes for centuries.",
        options: ["hegemony", "silence", "weakness", "friendship"],
        correctAnswerIndex: 0,
      },
      {
        type: "blank",
        question:
          "Fill in the blank: The debate focused on whether economic _____ leads to lasting peace.",
        options: ["hegemony", "sandwich", "parade", "scarf"],
        correctAnswerIndex: 0,
      },
    ],
  },
};

function applyCurated(wordEntry) {
  const key = wordEntry.word.toLowerCase();
  const curated = CURATED[key];
  if (!curated) {
    throw new Error(`no curated content for: ${wordEntry.word}`);
  }
  if (curated.phonetic) wordEntry.phonetic = curated.phonetic;
  wordEntry.definition = curated.definition;
  wordEntry.examples = curated.examples;
  wordEntry.quiz = curated.quiz;
}

function main() {
  const raw = fs.readFileSync(TARGET, "utf8");
  const pack = JSON.parse(raw);
  let filled = 0;
  let missing = [];

  for (const day of Object.values(pack.days)) {
    for (const w of day.words) {
      if (
        typeof w.definition === "string" &&
        w.definition.startsWith("TODO")
      ) {
        const key = w.word.toLowerCase();
        if (!CURATED[key]) {
          missing.push(w.word);
          continue;
        }
        applyCurated(w);
        filled++;
      }
    }
  }

  fs.writeFileSync(TARGET, JSON.stringify(pack, null, 2) + "\n", "utf8");
  console.log(`✓ ${filled} kelime curated içerikle dolduruldu.`);
  if (missing.length) {
    console.error("Eksik curated:", missing.join(", "));
    process.exit(1);
  }

  // verify zero TODOs
  let todos = 0;
  for (const day of Object.values(pack.days)) {
    todos += day.words.filter((w) => w.definition.startsWith("TODO")).length;
  }
  console.log(`✓ Kalan TODO: ${todos}`);
}

main();
