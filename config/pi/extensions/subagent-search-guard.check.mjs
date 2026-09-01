// Self-check for subagent-search-guard's WALKER regex.
//   node subagent-search-guard.check.mjs
//
// Reads the regex literal straight out of the extension so the two can't drift.
// (The extension itself can't be imported here: it pulls in pi runtime types.)
import assert from "node:assert";
import { readFileSync } from "node:fs";

const src = readFileSync(`${import.meta.dirname}/subagent-search-guard.ts`, "utf8");
const literal = src.match(/^const WALKER =\s*\n?\s*(\/.*\/[gimsuy]*);$/m)?.[1];
assert.ok(literal, "could not find the WALKER regex literal in the extension");
const WALKER = new RegExp(literal.slice(1, literal.lastIndexOf("/")));

const BLOCK = [
  // the one that got through the old command-position regex, in the wild
  `cd ~/fbsource && timeout 300 grep -rn "x" --include=*.json . 2>/dev/null | head -15`,
  `grep -rn foo .`,
  `grep -R foo .`,
  `grep --recursive foo .`,
  `grep --dereference-recursive foo .`,
  `sudo find / -name foo`,
  `xargs -0 grep -rl foo`,
  `git grep foo`,
  `nice -n 19 rg pattern`,
  `FOO=1 timeout 60 fd bar`,
  `meta-rg thing`,
];
const ALLOW = [
  `grep foo /etc/passwd`,
  `grep -n foo file.c`,
  `grep --color foo file.c`, // trailing r in a long flag is not -r
  `sed -n '1,5p' file | grep foo`,
  `grep foo file | sort -r`, // -r belongs to sort, not grep
  `ls -R /tmp`,
  `git log --oneline | head`,
  `ls /proc/self/fd`, // walker name as a path component
  `cat ~/dots/find.txt`,
];
// Known false positive: the regex can't see quoting, so a walker named inside a
// string still blocks. Accepted -- see the ponytail note in the extension.
const KNOWN_FALSE_POSITIVES = [`echo "use grep -r for this"`];

for (const c of BLOCK) assert.equal(WALKER.test(c), true, `should BLOCK: ${c}`);
for (const c of ALLOW) assert.equal(WALKER.test(c), false, `should ALLOW: ${c}`);
for (const c of KNOWN_FALSE_POSITIVES) {
  assert.equal(WALKER.test(c), true, `known false positive changed behaviour: ${c}`);
}
console.log(`ok ${BLOCK.length + ALLOW.length + KNOWN_FALSE_POSITIVES.length} cases`);
