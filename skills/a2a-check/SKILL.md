---
name: a2a-check
description: Check this agent's configuration and loop definitions with a2a.training and read the finding list. Use when the operator asks to check, preview or submit the agent's setup, or to read the findings of a check.
---

# a2a-check

The package has two modes. The default is `beobachten`: it only prepares a
submission and failure reports in `.a2a-check/` for the operator to look at, and
sends nothing. The operator switches to `senden` on purpose by setting
`A2A_CHECK_MODE=senden`. You never change the mode, the release rule or the
operator's files yourself.

## Steps

1. Run `a2a-check preview`. It reads the release rule from the service first and
   assembles only the data classes the rule allows. Show the operator its output
   as it is: the selected files, the data classes and the sensitive content
   found locally. The local check does not find everything, and the service
   filters again.
2. When the operator has read the preview and wants to send, they run
   `a2a-check confirm` and set `A2A_CHECK_MODE=senden`. Do not do either for
   them.
3. Run `a2a-check submit`. In `beobachten` it sends nothing. In `senden` it
   sends what was previewed and confirmed, once, and saves the finding list to
   `.a2a-check/findings-<data class>.json`.
4. Read that file and tell the operator what the findings say, in your own
   words, one finding after the other. Change a file of the setup only when the
   operator asks you to, and then only that file.

## Failure reports

The hooks write a failure report when a run is aborted, a budget is used up or a
tool call fails. A report names the kind of failure and the part of the setup
involved, never a line of tool output. They are in `.a2a-check/reports/`. In
`beobachten` they stay there. In `senden` they are sent only if the release rule
allows `failure_report`.

## Never

- Print or write the agent token; it is read from `A2A_AGENT_TOKEN` only.
- Copy tool output, logs or conversation text into a report or a submission.
- Send anything the release rule blocks.
