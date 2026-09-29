// Run: node tests/window-list.test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

function load(file) {
  const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(/^\.pragma library\s*/, "");
  const module = { exports: {} };
  new Function("module", src)(module);
  return module.exports;
}

const W = load("WindowList.js");
const S = load("SettingsModel.js");

const snap = W.parseSnapshot("ws=3;mon=DP-1;act=0xA1;w=0xa1@3@DP-1@,0xb2@1@DP-2@,0xc3@-98@DP-1@,0xd4@5@DP-1@p,0xa1@3@DP-1@,bogus@1@x@");
assert.strictEqual(snap.workspaceId, 3);
assert.strictEqual(snap.monitor, "DP-1");
assert.strictEqual(snap.active, "0xa1");
assert.deepStrictEqual(snap.windows.map(w => w.address), ["0xa1", "0xb2", "0xc3", "0xd4"], "dedupes and drops junk");
assert.strictEqual(snap.windows[3].pinned, true);

const addrs = list => list.map(w => w.address);
assert.deepStrictEqual(addrs(W.filterWindows(snap.windows, "all", snap, true)), ["0xa1", "0xb2", "0xc3", "0xd4"]);
assert.deepStrictEqual(addrs(W.filterWindows(snap.windows, "all", snap, false)), ["0xa1", "0xb2", "0xd4"], "special excluded");
assert.deepStrictEqual(addrs(W.filterWindows(snap.windows, "workspace", snap, true)), ["0xa1", "0xd4"], "pinned follows workspace");
assert.deepStrictEqual(addrs(W.filterWindows(snap.windows, "monitor", snap, true)), ["0xa1", "0xc3", "0xd4"]);

assert.strictEqual(W.initialIndex(snap.windows, "0xa1", "next"), 1, "first tab lands on previous window");
assert.strictEqual(W.initialIndex(snap.windows, "0xa1", "prev"), 3);
assert.strictEqual(W.initialIndex(snap.windows, "", "next"), 0, "nothing focused: most recent window");
assert.strictEqual(W.initialIndex([{ address: "0xa1" }], "0xa1", "next"), 0);
assert.strictEqual(W.initialIndex([], "", "next"), -1);

assert.strictEqual(W.step(3, 4, 1), 0);
assert.strictEqual(W.step(0, 4, -1), 3);
assert.strictEqual(W.step(1, 4, -6), 3);
assert.strictEqual(W.nextScope("all"), "workspace");
assert.strictEqual(W.nextScope("monitor"), "all");

let fit = W.layout(3, 1700, 800, 260, 200, 12, 0.4);
assert.deepStrictEqual([fit.cols, fit.rows, fit.scale], [3, 1, 1]);
fit = W.layout(40, 1700, 800, 260, 200, 12, 0.4);
assert.ok(fit.rows * fit.scale * 200 + (fit.rows - 1) * 12 <= 800, "shrinks to fit");

assert.deepStrictEqual(S.normalize(undefined), S.DEFAULTS);
assert.deepStrictEqual(S.normalize({ scope: "nope", showDelay: 5000, previews: false }),
  { scope: "all", showDelay: 1000, previews: false, workspaceBadges: true, includeSpecial: true });
assert.strictEqual(S.entryFromConfig({ plugins: [{ id: "x" }, { id: "p", scope: "monitor" }] }, "p").scope, "monitor");

const gmail = 'omarchy-launch-webapp "https://mail.google.com/mail/u/0/?service=mail#inbox"';
assert.strictEqual(W.webappMatch("chrome-mail.google.com__mail_u_0_-Profile_1", gmail), 2);
assert.strictEqual(W.webappMatch("chrome-mail.google.com__mail_u_1_-Profile_1", gmail), 1);
assert.strictEqual(W.webappMatch("chrome-youtube.com__-Default", 'omarchy-launch-webapp "https://youtube.com/"'), 1);
assert.strictEqual(W.webappMatch("chrome-drive.google.com__drive_my-drive-Profile_1", gmail), 0);
assert.strictEqual(W.webappMatch("foot", gmail), 0);

console.log("ok");
