# Task: make every user-visible string in the assigned Flutter files bilingual (Arabic / English)

Repo: SamaFox Flutter app (`app/`). Problem: switching the app language to English changes almost nothing,
because ~2,800 Arabic strings are hard-coded in ~210 files. A shared helper now exists — read it first:
`app/lib/l10n/tr.dart`:

    String tr(String ar, String en)   // returns Arabic unless the user chose English

The app rebuilds every widget after a language switch, so `tr()` needs no BuildContext.

## Your files
ONLY the files listed in `I18N_FILES.txt` (repo root of this worktree). Another engineer is editing the
other half of the app at the same time — touching any other file causes merge conflicts.
NEVER edit: `app/lib/l10n/*`, `app/lib/main.dart`, `app/lib/providers/*`, any `*_strings.dart`, `pubspec.yaml`.

## Rules
1. Wrap every user-visible Arabic string literal: `'قبول'` → `tr('قبول', 'Accept')`.
   Keep the Arabic text EXACTLY as it is (byte for byte). Keep `$var` / `${expr}` interpolations in both.
   Add `import '<relative path>/l10n/tr.dart';` (match the file's existing import style: relative or package:samafox/...).
2. Also wrap user-visible English-only literals in your files (e.g. `'Coins'`, `'Target'`, `'Manager'` shown as labels)
   → `tr('عملات', 'Coins')`. Do NOT wrap brand names (SamaFox), `VIP`, `CP`, `ID`, numbers, emojis-only strings.
3. Remove `const` wherever a `tr()` call now sits inside a const expression (`const Text('x')` → `Text(tr(...))`,
   and any enclosing `const [...]` / `const SizedBox(child: ...)` etc.). Do not remove unrelated `const`s.
4. Strings evaluated once and cached (top-level `const`/`final`, `static const`/`static final`, fields set in
   `initState`, default constructor parameter values that must be const) → turn them into getters or compute them
   inside `build`/at display time, so they change when the language changes. If a const default parameter holds
   Arabic text, make it nullable and resolve it with tr() where used.
5. DO NOT translate: comments, `debugPrint`/`print`/log messages, map keys, enum/ID/status values, anything sent to
   or compared with server data (`==`, `contains`, `switch` cases, `startsWith`), regexes, asset paths, URLs.
   If an Arabic literal is BOTH displayed and compared, leave it and add a `// i18n: compared with server data` comment.
6. Files that already pick a language themselves (e.g. `ar ? 'نص' : 'text'`, or a `XStrings.of(context)` class):
   leave those parts alone; only wrap remaining hard-coded literals.
7. English style: short, natural app UI English, sentence case. Terms: وكالة=Agency, وكالة المضيفين=Hosting agency,
   وكالة الشحن=Recharge agency, مضيف=Host, وكيل=Agent, شحن=Recharge, تارجت=Target, عملات/كوينز=Coins,
   ماس=Diamonds, غرفة=Room, مايك/مقعد=Mic/Seat, هدية=Gift, متجر=Store, حقيبة=Bag, إطار=Frame, دخولية=Entrance,
   فقاعة دردشة=Chat bubble, شارة=Badge, مركبة=Vehicle, المستوى=Level, الإدارة=Management, أتابعه=Following,
   يتابعني=Followers, أصدقاء=Friends, الزوار=Visitors, الرئيسية=Home, الرسائل=Messages, الألعاب=Games,
   حسابي/الملف الشخصي=Profile, إعدادات=Settings, وكالتي=My agency, منح=Grant, السجل=Log.
8. Minimal diffs: do not reformat, reorder, rename, or "improve" anything else. No logic changes.
9. Work file by file. After every ~10 files: `git add -A && git commit -m "i18n(<your tool name>): <short list>"`
   (if git is blocked by your sandbox, just continue — the orchestrator will commit). Keep `HANDOFF.md` up to date:
   files done, files remaining, anything skipped and why. Delete nothing.
10. When all files are done, re-read each changed file once for: unbalanced parentheses, a `tr(` left inside a
    `const`, a missing import, Arabic text accidentally altered. Then finish with a summary in HANDOFF.md.
