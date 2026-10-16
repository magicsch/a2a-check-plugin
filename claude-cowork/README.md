# a2a-check plugin for Claude Cowork (MVP-R-87)

A plugin with two things and nothing else:

- the **connector** to the a2a-check service, `.mcp.json`, with the address `https://api.a2a-check.com/mcp`;
- one **skill**, `skills/check-setup/SKILL.md`, whose text is the check instruction (`catalog/check-instruction-1.0.0.md`
  of the service, the text the prompt `check_setup` returns).

It contains no credential, no hook and no script. Installing it makes no request: the first request comes when you sign
in and approve the connection (the e-mail address and the six-digit code we send you; no account key and no agent form
are needed). Every submission is a tool call through the connector, and your AI shows you the files and waits for your
okay before it sends them.

## Install

Upload this directory as a plugin in Claude Cowork (as a zip), or add the repository that holds it as a plugin
marketplace and install `a2a-check-cowork` from it (`.claude-plugin/marketplace.json`). Then sign in and approve the
connection when Claude Cowork asks, and start the skill `check-setup` ("check this agent").

Without the plugin the same path works: add a custom connector with the address above and give your AI the check
instruction (the page `https://api.a2a-check.com/start` shows it with the three steps).

This plugin is not the Claude Code plugin (`reference/claude-code`, MVP-R-78), which brings hooks and a sending
script. The two are independent: neither changes the other. Putting the marketplace online is the owner's step; the
service does not host it.
