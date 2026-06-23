import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Removes pi's painted reverse-video "block" cursor from the main prompt.
// The zero-width CURSOR_MARKER is preserved, so with `showHardwareCursor: true`
// the real terminal cursor still positions correctly — you get ONLY your
// terminal's cursor (blue/blinking/whatever), with no black block underneath.
class NoBlockCursorEditor extends CustomEditor {
  render(width: number): string[] {
    const lines = super.render(width);
    // Strip only the reverse-video ON (SGR 7). The trailing reset (SGR 0) and
    // the cursor marker are left intact.
    return lines.map((line) => line.split("\x1b[7m").join(""));
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent(
      (tui, theme, keybindings) => new NoBlockCursorEditor(tui, theme, keybindings),
    );
  });
}
