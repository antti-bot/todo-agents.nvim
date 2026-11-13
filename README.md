# todo-agents.nvim

Plan in an ordinary buffer. Launch Claude Code or Codex from a Markdown checkbox and return to its terminal through a link.

```markdown
- [ ] Fix the login redirect
- [ ] Add regression coverage
```

Put the cursor on a task and press `<leader>aa`:

```markdown
- [ ] [Fix the login redirect](todo-agent://codex/174d8b25-33e1-4d88-a213-22c71e1ffabc)
```

The agent opens in a vertical terminal split. It receives the task, source path and line number, and instructions to read a snapshot of the full current buffer, including unsaved edits. Working directory is the nearest Git root, or the TODO file's directory. Unnamed buffers use Neovim's current directory. No special file type is required.

## Install

Requires Neovim **0.10+** and an authenticated `codex` or `claude` executable on `PATH`. No Lua dependencies.

With lazy.nvim, after pushing the private repository:

```lua
{
  'EskelinenAntti/todo-agents.nvim',
  opts = { provider = 'codex' },
}
```

Or try this checkout immediately:

```lua
vim.opt.rtp:prepend('/home/antti/code/todo-agents.nvim')
require('todo_agents').setup({ provider = 'codex' })
```

When adding runtimepath after startup, also run `:runtime plugin/todo_agents.lua`.

## Use

| Shortcut | Action |
| --- | --- |
| `<leader>aa` | Launch the default agent, or open an existing linked agent |
| `<leader>ac` | Launch Claude on an unlinked task |
| `<leader>ax` | Toggle checkbox, preserving its link |
| `gx` | Open the task's agent; ordinary URLs use `vim.ui.open` |

`:TodoAgent [codex\|claude]`, `:TodoAgentOpen`, and `:TodoAgentToggle` also work without mappings. Existing links always reopen their original provider. Checked tasks must be unchecked before launching. Your buffer is modified but never saved automatically. Save it normally to retain links. Checkbox completion is manual and independent of process exit.

Use `<C-\\><C-n>` to leave terminal mode and `<C-w>p` to return to the TODO buffer. Hiding the terminal keeps it running; wiping the terminal buffer or quitting Neovim ends it. Agents run in the same project working tree, so coordinate tasks that edit the same files.

## Reopen after restart

Claude launches with `--session-id` and later uses `--resume` with that ID.

Codex sessions are bound by looking for this task's unique launch marker in recently written `$CODEX_HOME/sessions/**/*.jsonl` transcripts (default `~/.codex`). Discovery retries for roughly one minute. After binding, reopening uses `codex resume <ID>`. The plugin never guesses with `--last`.

If your Codex version disables transcripts or changes their format, run `/status` in Codex, copy the session ID, then run `:TodoAgentBind <ID>` on its task line or in its terminal buffer. This also overrides a previous binding. A missing binding produces an error instead of opening an unrelated conversation.

Links refer to local metadata under `stdpath('state')/todo-agents/`. They work across Neovim restarts on this machine. They are not web links or portable agent sessions. Moving to another machine requires both plugin metadata and the provider's session data.

## Configuration

```lua
require('todo_agents').setup({
  provider = 'codex',
  mappings = true, -- false to keep your own mappings, including gx
  context = true, -- false to send only the task text
  commands = {
    codex = { 'codex' },
    claude = { 'claude', '--model', 'sonnet' },
  },
})

-- Example custom shortcut when mappings = false:
vim.keymap.set('n', '<leader>ta', '<cmd>TodoAgent<cr>')
```

Commands are argument arrays, never shell strings. Provider approval and sandbox settings remain at their CLI defaults. Context snapshots and metadata are private local files and remain available for session reopening; remove old files from the state directory when no longer needed. The full buffer snapshot can contain sensitive text, so disable `context` for buffers you do not want the agent to read.

## Development

```sh
mise install
mise run test
# Or with an existing Neovim: NVIM=/path/to/nvim ./tests/test.sh
```

`mise.toml` pins Neovim and GitHub CLI for development. The plugin itself supports Neovim 0.10+; CI checks the minimum version and stable.

Tests run in isolated state directories, with fake CLI processes; they require no account and make no provider API calls. They cover task parsing, checkbox preservation, terminal launching and reopening, unsaved context, Codex transcript binding, manual binding, and unavailable executables. Live provider authentication and execution need a manual smoke test on a configured machine.

Create and push the private GitHub repository from this checkout under your authenticated GitHub account:

```sh
mise exec -- gh repo create todo-agents.nvim --private --source=. --remote=origin --push
```

CLI integration references: [Codex](https://github.com/openai/codex), [Claude Code](https://code.claude.com/docs/en/cli-reference).
