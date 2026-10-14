# a2a-check reference package for claude-code

A skill plus the hooks PreToolUse, PostToolUse and Stop (R-37, MVP-R-23). POSIX
shell and `curl` only; no other runtime. Using the package is optional: every
submission through the API is equivalent (R-38).

## Install as a plugin (MVP-R-78)

The same package is a Claude Code plugin: this directory holds `.claude-plugin/plugin.json`, the
marketplace file `.claude-plugin/marketplace.json` and `hooks/hooks.json`. Install it with

    /plugin marketplace add magicsch/a2a-check-plugin
    /plugin install a2a-check@a2a-check

(on the command line `claude plugin marketplace add magicsch/a2a-check-plugin` and `claude plugin install
a2a-check@a2a-check`; a local clone works too, give its path instead of `magicsch/a2a-check-plugin`). `magicsch/a2a-check-plugin` is the
repository that holds this directory as its root; keeping it up to date is the owner's step, the service
does not do it. The plugin brings the skills `a2a-check` and `a2a-check-apply`, the hooks and
`bin/a2a-check`; it contains no credential. **An installed plugin does nothing until you set the
variables below**: without `A2A_AGENT_TOKEN` the hooks make no request at all; with it, in the default
mode `beobachten`, they only read your release rule (R-05); sending needs `A2A_CHECK_MODE=senden`
and the preview you confirm (R-44). There is no package for `claude-cowork`.

## Install by hand

Copy this directory to `.claude/a2a-check/` in your project, copy
`skills/a2a-check/` and `skills/a2a-check-apply/` to `.claude/skills/`, merge the hooks of
`settings.example.json` into `.claude/settings.json`, make `bin/a2a-check` and
`hooks/a2a-check-hook` executable and put `bin/` on your `PATH` (or call it by
its path). Set, in the environment of the agent:

| Variable | Meaning |
|---|---|
| `A2A_CHECK_URL` | base URL of the service |
| `A2A_AGENT_TOKEN` | the agent's token. Read from here only: never written to a file, never printed, handed to `curl` on stdin |
| `A2A_CHECK_MODE` | `beobachten` (default) or `senden`; any other value is refused |
| `A2A_CHECK_DIR` | where the package writes (default `.a2a-check/` in the project) |

## The two modes (R-38)

- `beobachten` (default): everything stays local, for you to look at. No request
  is made except reading your release rule.
- `senden`: submissions and failure reports are sent. You choose it yourself, and
  a submission is sent only after you have read its preview and run
  `a2a-check confirm` (R-44).

## What it does

- **Release rule first (R-05).** Before it assembles anything the package reads
  the agent's release rule with `GET /v1/agent/sharing-policy`. A data class the
  rule blocks is never read and never assembled; a rule that cannot be read means
  nothing is assembled. The package cannot change the rule.
- **Preview (R-44).** `a2a-check preview` lists the selected files, the data
  classes and the sensitive content found locally (credential and personal data
  shapes of `catalog/patterns`, file and line and pattern id, never the
  content). The local check neither replaces the filters of the service nor finds
  everything.
- **Submit.** `a2a-check submit` assembles `configuration` (`CLAUDE.md`,
  `.claude/settings.json`, `.mcp.json`, `.claude/agents`, `.claude/commands`,
  `.claude/rules`, `.claude/skills`, not this skill; never the personal
  `.claude/settings.local.json`) and `loop` (the paths you list in `.a2a-check/loop-files`, one per
  line) as far as the rule allows. In `beobachten` the result is only written to
  `.a2a-check/submission/`. In `senden` it is sent with `POST /v1/submissions`
  once per unchanged content, the check of the submission (`GET /v1/checks/{id}`,
  with its finding list in the finding contract: finding ids, proposals, pattern
  ids) is fetched and kept in `.a2a-check/findings/<check id>.json` (a new check
  never overwrites an earlier one; `a2a-check reset` clears them), with the latest
  copied to `.a2a-check/findings-<data class>.json`, and the
  public pattern catalogue (`GET /v1/catalog/patterns`, read again after every new
  send) to `.a2a-check/patterns.json`, for the skills to read. The submission
  request waits up to 75 seconds (`A2A_MAX_TIME`), longer than the 60 seconds the
  service gives a check.
- **Acting on findings (MVP-R-18).** The skill `a2a-check-apply` reads those two
  files, presents each finding with its proposal and linked patterns, lets the
  agent prepare the change in its own workspace and records the addressed finding
  ids with `a2a-check addressed <id>...` in `.a2a-check/addressed-findings`. That
  command makes no request and writes only inside the project; it refuses an id
  that is in no saved finding list. The skill never sends anything.
- **Failure reports (R-08).** On a failed tool call (`PostToolUseFailure`; an
  interrupted one counts as an abort) and on a turn that ended with an API error
  (`StopFailure`: an abort, or a used-up limit, quota or balance as budget) a
  report according to `catalog/schema/failure-report-1.0.0.json` is written to
  `.a2a-check/reports/<time>-<trigger>-<component>.json`, at most one per trigger
  and component until `a2a-check reset`. `PostToolUse` and `Stop` are registered
  too and report nothing: they see successful calls and ordinary stops. A report holds fixed sentences, the kind of failure and the
  part of the setup; it never holds a line of tool output. In `senden` it is sent
  when the release rule allows `failure_report`.

- **The loop in `senden` (MVP-R-08, MVP-R-24).** After a confirmed send the
  package polls `GET /v1/checks/{id}` with backoff (`A2A_POLL_SLEEPS`, seconds
  between reads, default `2 4 8 16 30`; there is no callback) until the check is
  `done`, `partial` or `failed`, saves its finding list for the skill, and keeps
  the check id in `.a2a-check/last-check-<data class>`. When the setup has changed
  and the operator has confirmed the new preview, the next send is a re-check: it
  carries `recheck_of` (that check id) and one `addressed_finding_ids` per id in
  `.a2a-check/addressed-findings` (only ids in the form of a finding id; the file
  is removed once they were sent). A check still running after the last wait is
  read again at the next run and never sent again. A refusal (HTTP 409: the
  earlier check is unfinished or a finding is escalated until the operator
  acknowledges it) is reported and leaves the content unsent; HTTP 404 (the
  earlier check is gone) starts a new chain, once. `a2a-check reset` forgets the
  chain.

## Not in this package

A package for `claude-cowork` is not part of it.

## Limits

The hooks read `hook_event_name` and `tool_name`, from `PostToolUseFailure` the
flag `is_interrupt`, and from `StopFailure` the value of `error`; the text of
`error` of a failed tool call is never read or kept. A run the user cancels
fires no hook of its own, so no report is made for it. Every hook exits 0 and
prints nothing, so the agent is never blocked by the package.
