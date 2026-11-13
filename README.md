# todo-agents.nvim

Your TODO file is an index of Herdr workspaces.

```markdown
#### ~/code/api
- [ ] Fix validation
- [ ] Add search

#### ~/code/web
- [ ] Fix the error screen
```

Open the file in Neovim **inside Herdr**. Put the cursor on an unchecked task and press `gx`:

1. Herdr creates a worktree and `todo-agent/<id>` branch from the repo's local `main`.
2. Codex opens in that workspace with an empty composer. Type your instructions there.
3. The task becomes a Markdown link to its worktree. Save the TODO file normally.

Press `gx` on the link to return to the workspace's agent, even when a different tab is selected. Links store worktree paths, so moving a task under another heading doesn't change its workspace. If no agent is running, `gx` opens the workspace; use the shell there to start or resume your agent.

## Review changes

In the task's Herdr workspace, create a tab with **Ctrl-B, then C** (the default Herdr binding). The new shell starts in the same worktree with Herdr's default `terminal.new_cwd = "follow"` setting.

Run `git diff main` to inspect the task's changes, `git status` to see untracked files, or `nvim .` to browse and edit. Your agent stays in its own tab. Return to your TODO workspace and use `gx` to jump back to the agent.

Closing Neovim leaves the agent and worktree running in Herdr. Herdr owns persistence, tabs, and worktree removal. Review and merge branches yourself, then edit the checkbox. This plugin never merges, deletes worktrees, or submits task text or file contents to an agent.

## Install

Requires Neovim 0.10+, Git, Herdr TUI 0.9.5+, and an authenticated Codex CLI.

```sh
mise use -g herdr@latest
```

```lua
-- lazy.nvim
{ 'antti-bot/todo-agents.nvim', opts = {} }
```

Or with Neovim's built-in package manager:

```lua
vim.pack.add({ 'https://github.com/antti-bot/todo-agents.nvim' })
require('todo_agents').setup()
```

## Folder headings

Each task uses the last folder line or Markdown heading above it. All heading levels work. Paths can be absolute, `~/...`, or relative to the TODO file. A trailing `/` makes a relative folder name explicit. Without a folder heading, the file's repo is used; an unnamed buffer uses Neovim's current directory.

Missing folders, folders outside Git, and fenced code examples do nothing. Checked tasks cannot start new agents; their existing links still work. The local `main` branch must exist; nothing is fetched or pulled. Uncommitted changes from the original checkout are not copied.

`gx` is the only shortcut. It is local to Markdown, text, and buffers without a filetype. Other links use your existing `gx` mapping. There are no Ex commands. The `herdr://` links are handled by this Neovim plugin; no OS protocol handler is installed.

## Configuration

```lua
require('todo_agents').setup({
  command = { 'codex' }, -- argument array, e.g. { 'claude' }
  mappings = true,      -- false to supply your own mapping
})
```

The Lua entry point is `require('todo_agents').open()`. Commands use the calling Herdr session and socket context. Herdr's worktree directory setting controls where worktrees are created.

## Code and tests

- `lua/todo_agents/init.lua`: TODO parsing, links, `gx`, and agent navigation.
- `lua/todo_agents/worktree.lua`: folder selection and Herdr CLI calls.

There are no plugin metadata files, session-history scans, Neovim terminals, or cleanup timers.

```sh
mise install
mise run test
```

Tests use a real, isolated Herdr server, temporary Git repos, and fake agents. They cover starting from `main` while another branch is checked out, repo selection, shell quoting, switching back from a review tab, and keeping agents alive across Neovim restarts. They never call a model provider or touch your existing Herdr sessions.
