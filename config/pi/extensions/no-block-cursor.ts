import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Removes pi's painted reverse-video "block" cursor from the main prompt.
// The zero-width CURSOR_MARKER is preserved, so with `showHardwareCursor: true`
// the real terminal cursor still positions correctly — you get ONLY your
// terminal's cursor (blue/blinking/whatever), with no black block underneath.
// Also: make bare `up` on an empty prompt pop the queued messages into the
// editor (same as alt+up / app.message.dequeue) instead of recalling a *copy*
// of the queued text from prompt history and sending a duplicate.
// Falls through to normal history navigation when the queue is empty.
let maybeQueued = false;

class NoBlockCursorEditor extends CustomEditor {
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
    const lines = super.render(width);
    // Strip only the reverse-video ON (SGR 7). The trailing reset (SGR 0) and
    // the cursor marker are left intact.
    return lines.map((line) => line.split("\x1b[7m").join(""));
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("input", (event) => {
    if (event.streamingBehavior) maybeQueued = true;
  });
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent(
      (tui, theme, keybindings) => new NoBlockCursorEditor(tui, theme, keybindings),
    );
  });
}
