---
name: a2a-check-apply
description: Act on a finished a2a-check result, the step after the check ran. Work through the saved findings (by id such as AU-01, by severity, "what the check flagged"), apply the proposals to this project's config files, and record which finding ids were addressed, including the addressed_finding_ids for the re-check. Use whenever the operator wants the setup improved after a check or asks what is fixed versus still open; English and German ("Befunde abarbeiten", "merk dir, welche behandelt sind"). Not for running or submitting a check (a2a-check), reading a score alone, or findings from linters or PR reviewers.
---

# a2a-check-apply

This skill turns a finding list into changes the agent prepares in its own
workspace. It reads files that `a2a-check submit` has already saved, changes only
files of this project the operator has asked about, and records which findings
were addressed. It never sends anything, makes no network call and writes nothing
outside the project.

## What it reads

- `.a2a-check/findings-<data class>.json`: the check as the service answered it.
  The findings are in `finding_list.findings`; each has a `finding_id`, the
  `rule_id`, a `severity` with its `level` and `reason`, a `location`, the
  `evidence` (the offending line), a `proposal`, a `status`, a `next_step` and the
  `pattern_ids` of the patterns that explain the fix.
- `.a2a-check/patterns.json`: the public pattern catalogue as `a2a-check submit`
  saved it. Look a pattern up by its `pattern_id`: it has a `title`, a `rationale`
  and a `before` and an `after` example.

If either file is missing, say so and stop: ask the operator to run
`a2a-check submit` in the mode they chose. Do not fetch anything yourself.

## Steps

1. For each finding, in the order of the file, tell the operator, in plain words:
   what is wrong (the `severity.reason`), where (`location`), the service's
   `proposal`, and, for every id in `pattern_ids`, the pattern's title and its
   before and after example. A finding with an empty `pattern_ids` has no pattern;
   say that, do not invent one.
2. Ask which findings the operator wants addressed. Do not change anything for the
   others.
3. For each finding the operator chose, prepare the change in the file named by
   `location`, as the proposal and the pattern describe, and show the operator the
   change. Change no other file. A finding whose `status` is `resolved` needs no
   change. A finding with no `location.file` (a declaration the whole setup lacks)
   names no file: ask the operator which existing configuration file of the project
   should hold it, or whether to add one, and change only that file once they have
   answered.
4. After the operator has accepted a change, record the finding:
   `a2a-check addressed <finding_id>`. That writes the id into
   `.a2a-check/addressed-findings` in the workspace and nothing else. It refuses an
   id that is not in a saved finding list.
5. Tell the operator that the next submission can reference these ids; sending it
   is the operator's choice (`A2A_CHECK_MODE=senden` and `a2a-check confirm`).

## Never

- Send anything, call the service or any other address, or run a command that
  does. The only command this skill runs is `a2a-check addressed`.
- Write outside the project, or change a file the findings do not name.
- Make up a proposal, a pattern or a finding id.
- Print or write the agent token.
