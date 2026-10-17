# Security

Please report vulnerabilities privately through [GitHub's security advisories](https://github.com/MariSchn/Islet/security/advisories/new) rather than in a public issue. I'll reply within a few days.

## What Islet exposes

- The Agents plugin listens on `127.0.0.1:7365` and the Scripts plugin on `127.0.0.1:7366`. Both only accept requests with a random bearer token that is stored in files only your user can read. Neither can run commands or read files on your behalf, and neither approves agent requests by itself.
- The agent hook scripts in `~/.claude`, `~/.codex` and `~/.gemini` forward session events to Islet and pass its answers to permission requests back to the agent. They pass nothing else back, and on a Mac they only send a permission request to a listener that runs as your user, so a program that takes over the port while Islet isn't running can't answer for you.
- For remote machines, an SSH `RemoteForward` makes the remote's `127.0.0.1:7365` reach Islet. Remote hosts get their own token, which you can revoke in Settings › Agents. On Linux, the hook script only talks to the forwarded port when your own SSH session owns it.

Islet doesn't collect analytics. It connects to the internet itself only to check for updates on GitHub and to load Spotify artwork; the GitHub plugin asks the GitHub CLI for your pull requests.
