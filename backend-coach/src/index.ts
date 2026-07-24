import "dotenv/config";
import cors from "cors";
import express, { type Request, type Response, type NextFunction } from "express";
import { GoogleGenerativeAI } from "@google/generative-ai";
import admin from "firebase-admin";

const PORT = Number(process.env.PORT || 8787);
const SKIP_AUTH = process.env.COACH_SKIP_AUTH === "1";
const MOCK_STREAM = process.env.COACH_MOCK_STREAM === "1";
const MODEL = process.env.GEMINI_MODEL || "gemini-2.5-flash";

type StreamBody = {
  sentence?: string;
  word?: string;
  definition?: string;
};

function ensureFirebase(): void {
  if (admin.apps.length > 0) return;
  // Application Default Credentials on Cloud Run; optional locally when SKIP_AUTH=1.
  try {
    admin.initializeApp();
  } catch (err) {
    console.warn("firebase-admin init skipped/failed:", (err as Error).message);
  }
}

async function requireAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  if (SKIP_AUTH) {
    next();
    return;
  }

  const header = req.header("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    next(Object.assign(new Error("Missing Bearer token"), { status: 401 }));
    return;
  }

  try {
    ensureFirebase();
    await admin.auth().verifyIdToken(match[1]);
    next();
  } catch (err) {
    next(Object.assign(new Error("Invalid token"), { status: 401, cause: err }));
  }
}

function writeSse(res: Response, payload: unknown): void {
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function buildPrompt(body: StreamBody): string {
  const sentence = (body.sentence || "").trim();
  const word = (body.word || "").trim();
  const definition = (body.definition || "").trim();

  if (!sentence) {
    throw Object.assign(new Error("sentence is required"), { status: 400 });
  }

  return [
    "You are Maia's English vocabulary coach.",
    word ? `Focus word: "${word}"${definition ? ` (${definition})` : ""}.` : "",
    "Improve the student's sentence with MINIMAL edits: fix grammar/spelling, keep meaning.",
    "Then add one short tip (1 sentence) about word usage.",
    "Keep the whole reply under 80 words. No markdown fences.",
    "",
    `Student sentence: ${sentence}`,
  ]
    .filter(Boolean)
    .join("\n");
}

async function streamMock(res: Response, sentence: string): Promise<void> {
  const text =
    `Improved: ${sentence.replace(/\bi\b/g, "I")}\n` +
    `Tip: Keep practicing this pattern in short diary sentences.`;
  for (const token of text.split(/(\s+)/)) {
    if (!token) continue;
    writeSse(res, { text: token });
    await new Promise((r) => setTimeout(r, 35));
  }
}

async function streamGemini(res: Response, prompt: string): Promise<void> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw Object.assign(new Error("GEMINI_API_KEY not set (or enable COACH_MOCK_STREAM=1)"), {
      status: 500,
    });
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: MODEL });
  const result = await model.generateContentStream(prompt);

  for await (const chunk of result.stream) {
    const text = chunk.text();
    if (text) writeSse(res, { text });
  }
}

const app = express();
app.use(cors());
app.use(express.json({ limit: "32kb" }));

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "backend-coach",
    mock: MOCK_STREAM,
    skipAuth: SKIP_AUTH,
    model: MODEL,
  });
});

app.post("/coach/stream", requireAuth, async (req, res) => {
  const body = (req.body || {}) as StreamBody;

  try {
    const prompt = buildPrompt(body);

    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders?.();

    writeSse(res, { event: "start", mock: MOCK_STREAM });

    if (MOCK_STREAM) {
      await streamMock(res, (body.sentence || "").trim());
    } else {
      await streamGemini(res, prompt);
    }

    writeSse(res, { done: true });
    res.end();
  } catch (err) {
    const status = (err as { status?: number }).status || 500;
    const message = (err as Error).message || "stream failed";
    if (res.headersSent) {
      writeSse(res, { error: message });
      res.end();
      return;
    }
    res.status(status).json({ error: message });
  }
});

app.use((err: Error & { status?: number }, _req: Request, res: Response, _next: NextFunction) => {
  res.status(err.status || 500).json({ error: err.message || "error" });
});

app.listen(PORT, () => {
  console.log(
    `[backend-coach] http://127.0.0.1:${PORT}  mock=${MOCK_STREAM} skipAuth=${SKIP_AUTH} model=${MODEL}`
  );
});
