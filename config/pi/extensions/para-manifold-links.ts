import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as os from "node:os";
import * as path from "node:path";

// para-manifold-links
// --------------------
// Any reference to a file under ~/para (or the underlying
// ~/persistent/workspace tree) gets the resolved Manifold explorer URL
// appended after it, so the path is clickable / shareable straight from
// the terminal.
//
// Why this works: ~/para is a symlink to ~/persistent/workspace/para, and
// ~/persistent/workspace is a manifoldfs FUSE mount whose root maps to the
// `tree/` view of the bucket `bucket_<user>_workspace`. So:
//
//   ~/para/foo/bar.md
//     -> ~/persistent/workspace/para/foo/bar.md
//     -> bucket tree path  para/foo/bar.md
//     -> https://www.internalfb.com/manifold/explorer/
//          bucket_<user>_workspace/tree/para/foo/bar.md
//
// Applied in two places:
//   - message_end : rewrites the assistant's finalized text
//   - tool_result : rewrites bash / read / other tool output
//
// Idempotent: if the resolved URL is already present in the text, the path
// is left untouched (no double-append).
//
// Disable with PI_PARA_LINKS_DISABLE=1.

const HOME = os.homedir();
const USER = os.userInfo().username;

// manifoldfs presents the bucket's tree/ mount as the workspace root.
const BUCKET = `bucket_${USER}_workspace`;
const TREE = "tree";
const WORKSPACE_ROOT = path.join(HOME, "persistent", "workspace");
const PARA_LINK = path.join(HOME, "para"); // -> PARA_REAL (a symlink)
const PARA_REAL = path.join(WORKSPACE_ROOT, "para"); // resolved target

const MANIFOLD_BASE = `https://www.internalfb.com/manifold/explorer/${BUCKET}/${TREE}`;

// Match references to files under ~/para, in any of the forms that show up
// in text: tilde form, absolute home form, or the resolved-symlink form
// (.../persistent/workspace/para/...). Every form contains "/para/", which
// the cheap fast-path in annotate() relies on. We stop at whitespace and
// characters that commonly terminate a path token in prose / markdown /
// shell output.
const PATH_RE = new RegExp(
  String.raw`(?<![\w./~-])(?:~|/home/[\w.-]+)(?:/persistent/workspace)?/para/[^\s\x60'"<>)\]}]+`,
  "g",
);

function expandHome(p: string): string {
  if (p === "~") return HOME;
  if (p.startsWith("~/")) return path.join(HOME, p.slice(2));
  return p;
}

// Turn an absolute path under ~/para into its bucket-relative tree path
// (always "para/<rel>"), or null if it is not under para.
function bucketRelPath(absPath: string): string | null {
  for (const root of [PARA_LINK, PARA_REAL]) {
    if (absPath === root || absPath.startsWith(root + path.sep)) {
      const rel = path.relative(root, absPath);
      return rel ? `para/${rel}` : "para";
    }
  }
  return null;
}

function manifoldUrlFor(matchedPath: string): string | null {
  const rel = bucketRelPath(expandHome(matchedPath));
  if (!rel) return null;
  // Keep slashes readable; encode each segment for safety (spaces, etc.).
  const encoded = rel.split("/").map(encodeURIComponent).join("/");
  return `${MANIFOLD_BASE}/${encoded}`;
}

// Append the Manifold URL after the first occurrence of each distinct para
// path. Strips trailing prose punctuation off the captured token first.
function annotate(text: string): string {
  if (!text || !text.includes("para")) return text;
  const annotated = new Set<string>();
  return text.replace(PATH_RE, (token) => {
    // Peel trailing punctuation that prose tends to glue onto a path.
    const m = token.match(/[.,;:!?]+$/);
    const trailing = m ? m[0] : "";
    const clean = trailing ? token.slice(0, -trailing.length) : token;

    const url = manifoldUrlFor(clean);
    if (!url) return token;
    if (annotated.has(url)) return token; // first occurrence only
    // Idempotency: never append a URL that is already in the text.
    if (text.includes(url)) return token;
    annotated.add(url);
    return `${clean} (${url})${trailing}`;
  });
}

function annotateContent(content: any): { changed: boolean; content: any } {
  if (!Array.isArray(content)) return { changed: false, content };
  let changed = false;
  const next = content.map((block: any) => {
    if (block && block.type === "text" && typeof block.text === "string") {
      const updated = annotate(block.text);
      if (updated !== block.text) {
        changed = true;
        return { ...block, text: updated };
      }
    }
    return block;
  });
  return { changed, content: changed ? next : content };
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_PARA_LINKS_DISABLE === "1") return;

  // Assistant's own messages.
  pi.on("message_end", async (event) => {
    if (event.message.role !== "assistant") return;
    const { changed, content } = annotateContent(event.message.content);
    if (!changed) return;
    return { message: { ...event.message, content } };
  });

  // Tool output (bash, read, etc.).
  pi.on("tool_result", async (event) => {
    const { changed, content } = annotateContent(event.content);
    if (!changed) return;
    return { content };
  });
}
