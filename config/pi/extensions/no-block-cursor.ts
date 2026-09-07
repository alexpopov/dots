import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// One CustomEditor doing three things, because pi allows only a single editor
// component (a second setEditorComponent wins and silently drops the first):
//
//  1. No block cursor: strip pi's painted reverse-video (SGR 7) block from the
//     prompt, leaving the real terminal cursor (with showHardwareCursor:true).
//  2. Queue dequeue on `up`: bare `up` on an empty prompt pops queued messages
//     into the editor (like alt+up / app.message.dequeue) instead of recalling a
//     *copy* of the queued text and sending a duplicate; falls through to history
//     when the queue is empty.
//  3. @path highlight: color @path mentions in the theme's success color when
//     they resolve to an existing file/dir (merged in from ivangromov's
//     at-path-highlight, which can't coexist as a separate editor extension).
let maybeQueued = false;

// --- @path highlighting (merged from at-path-highlight) --------------------
const AT_PATH_PATTERN = /(^|[\s([{<]|\x1b\[[0-9;]*m)@(?:"([^"\n\x1b]*)"|'([^'\n\x1b]*)'|([^\s"'`<>\x1b]+))/g;
const TRAILING_PUNCTUATION = new Set([".", ",", ";", ":", "!", "?", ")", "]", "}"]);

function resolveMentionPath(cwd: string, mentionPath: string): string {
  if (mentionPath === "~") return os.homedir();
  if (mentionPath.startsWith("~/")) return path.join(os.homedir(), mentionPath.slice(2));
  if (path.isAbsolute(mentionPath)) return mentionPath;
  return path.resolve(cwd, mentionPath);
}

function stripTrailingPunctuation(text: string): string {
  let end = text.length;
  while (end > 0 && TRAILING_PUNCTUATION.has(text[end - 1]!)) end--;
  return text.slice(0, end);
}

function existingMention(cwd: string, rawPathText: string): { pathText: string; trailingText: string } | undefined {
  if (rawPathText.length === 0) return undefined;
  const candidates: string[] = [];
  const add = (c: string) => { if (c.length > 0 && !candidates.includes(c)) candidates.push(c); };
  add(rawPathText);
  const noPunct = stripTrailingPunctuation(rawPathText);
  add(noPunct);
  const lineSuffix = noPunct.match(/^(.*?)(:\d+(?::\d+)?)$/); // @file:line[:col]
  if (lineSuffix?.[1]) add(lineSuffix[1]);
  for (const c of candidates) {
    if (existsSync(resolveMentionPath(cwd, c))) return { pathText: c, trailingText: rawPathText.slice(c.length) };
  }
  return undefined;
}

class NoBlockCursorEditor extends CustomEditor {
  constructor(
    tui: any,
    theme: any,
    keybindings: any,
    private readonly cwd: string,
    private readonly colorAtPath: (text: string) => string,
  ) {
    super(tui, theme, keybindings);
  }

  handleInput(data: string): void {
    if (
      maybeQueued &&
      this.getText().length === 0 &&
      this.keybindings.matches(data, "tui.editor.cursorUp")
    ) {
      const dequeue = (this as any).actionHandlers?.get("app.message.dequeue");
      dequeue?.();
      maybeQueued = false; // drained either way
      // Nothing restored => queue was actually empty; fall through to history.
      if (this.getText().length > 0) return;
    }
    super.handleInput(data);
  }

  render(width: number): string[] {
    return super.render(width).map((line) => {
      // Strip only reverse-video ON (SGR 7); trailing reset + cursor marker stay.
      const noCursor = line.split("\x1b[7m").join("");
      return this.highlightExistingAtPaths(noCursor);
    });
  }

  private highlightExistingAtPaths(line: string): string {
    return line.replace(AT_PATH_PATTERN, (match, prefix, dq, sq, bare) => {
      const quote = dq !== undefined ? '"' : sq !== undefined ? "'" : undefined;
      const rawPathText = (dq ?? sq ?? bare) as string;
      const existing = existingMention(this.cwd, rawPathText);
      if (!existing) return match;
      if (quote) return `${prefix}${this.colorAtPath(`@${quote}${rawPathText}${quote}`)}`;
      return `${prefix}${this.colorAtPath(`@${existing.pathText}`)}${existing.trailingText}`;
    });
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("input", (event) => {
    if (event.streamingBehavior) maybeQueued = true;
  });
  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setEditorComponent(
      (tui, theme, keybindings) =>
        new NoBlockCursorEditor(tui, theme, keybindings, ctx.cwd, (text) => ctx.ui.theme.fg("success", text)),
    );
  });
}
