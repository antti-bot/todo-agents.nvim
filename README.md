# todo-agents.nvim

A text file of tasks, with links to Codex sessions.

```markdown
~/code/api
- [ ] Fix validation
- [ ] Add regression coverage

~/code/web
- [ ] Fix the error screen
```

Put the cursor on a task and press `gx`. The plugin creates a Git worktree for that task and opens Codex in the current window. Codex opens with an empty composer; enter your prompt when ready. The plugin does not send the task text or file contents.

Once Codex's session ID is available, the task becomes a normal Markdown link:

```markdown
- [ ] [Fix validation](codex://8df0bb21-5693-425b-a295-651b6c36f022)
```

`gx` on the task or its link returns to that exact session. You can also put the link in another note. Save your file normally; the plugin never saves it for you.

## Install

Requires Neovim 0.10+, Git, and an authenticated Codex CLI on `PATH`.

```lua
-- lazy.nvim
{
  'antti-bot/todo-agents.nvim',
  opts = {},
}
```

To use the local checkout:

```lua
vim.opt.rtp:prepend('/home/antti/code/todo-agents.nvim')
require('todo_agents').setup()
```

## The file

Use an ordinary Markdown or text file. The plugin attaches when it finds a checkbox task or `codex://` link.

Each task belongs to **one repo**: the last folder line above it. Folders can be `~/code/repo`, absolute paths, or paths relative to the TODO file. Markdown headings such as `# ~/code/repo` also work. A trailing `/` makes a relative folder name explicit. Consecutive folder lines do not form a group; the last one wins. If the heading names a missing folder or a folder outside a Git repository, `gx` does nothing.

Without a folder line, a task belongs to the Git repo containing the file. An unnamed buffer uses Neovim's current directory. Fenced code examples are ignored. Reading and editing the file creates no worktrees.

Existing session links keep their original repo even if you move them under a different heading. To plan a change across repos, write a task under each repo.

`gx` is the only plugin shortcut. On a plain task it starts Codex; on a linked task it reopens that session. Other links use your existing `gx` mapping. The `codex://` scheme is handled inside Neovim; no OS protocol registration is needed.

The mapping is local to task buffers. Enter and other editing keys keep their usual behavior. Edit the checkbox as normal text. To switch back from Codex, use `<C-\><C-n>` to leave terminal mode, then Neovim's `<C-^>` (usually Ctrl-6) to return to the alternate buffer. Hiding the terminal keeps it running.

## Worktrees and sessions

Each task gets a `todo-agent/<task-id>` branch and a worktree under `~/.todo-agents/worktrees/`. It starts from the selected repo's local `main` branch, which must exist. The plugin does not fetch or pull. Uncommitted changes in your main checkout are not copied.

When the agent exits, its terminal is deleted, or Neovim quits normally, a clean worktree is removed. Its branch is retained, including unmerged commits. Reopening the session recreates the worktree from that branch. Modified, untracked, and ignored files prevent removal; there are no routine notifications. Crashes can leave worktrees behind.

Review and merge each task branch yourself, then mark its checkbox. Branches are never merged or deleted automatically. Deleting a task branch prevents reopening its worktree.

The plugin finds Codex's exact session ID by matching the task's unique worktree path in `$CODEX_HOME/sessions/` (default `~/.codex/sessions/`). While waiting, the link temporarily uses `codex://task/<task-id>`. It still reopens the running terminal. Reopening a stopped task requires its session ID to have been discovered.

Session metadata remains in `stdpath('state')/todo-agents/`. Links require that local metadata and Codex's own session history. New launches do not save TODO snapshots; snapshots from older versions can be removed manually. Codex's approval and sandbox defaults are unchanged.

## Configuration

```lua
require('todo_agents').setup({
  command = { 'codex' },
  mappings = true,
})
```

`command` is an argument array, for example `{ 'codex', '--no-alt-screen' }`. Set `mappings = false` to provide your own keys. The Lua entry point is `require('todo_agents').open()`.

## Reading the code

- `lua/todo_agents/init.lua`: task parsing, session launch, persistence, links, buffer mappings, and error display.
- `lua/todo_agents/worktree.lua`: folder headings, Git repo validation, and worktree creation and cleanup.

There are no runtime dependencies beyond Neovim, Git, and Codex. The [Codex CLI reference](https://developers.openai.com/codex/cli/reference/) documents session resume behavior.

## Development

```sh
mise install
mise run test
```

Or run `NVIM=/path/to/nvim ./tests/test.sh`. Tests use temporary Git repositories and a fake Codex process; Python 3 is required only for the tests. They cover repo scope, session discovery and links, restart/resume, worktree cleanup, dirty-file preservation, and normal Neovim shutdown. They do not make provider API calls.

To create and push the public repository:

```sh
mise exec -- gh repo create antti-bot/todo-agents.nvim --public --source=. --remote=origin --push
```
