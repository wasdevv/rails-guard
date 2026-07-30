# rails-guard

**The Claude Code plugin that keeps the agent from dropping your database — irrecoverable commands are blocked, risky ones ask first.**

Agents are fast, and that's the problem: a single `bin/rails db:reset` executed on autopilot wipes your development data before you finish reading the transcript. rails-guard hooks into `PreToolUse` and inspects every Bash command *before it runs*. If it's destructive and you're in a Rails project, Claude Code shows the permission prompt with the reason — the command only runs after **you** confirm.

```
Claude wants to run: git pull && bin/rails db:setup

[rails-guard] db:setup rewrites or destroys database data

  ❯ 1. Yes
    2. No, and tell Claude what to do differently
```

## What it catches

Two tiers of response — **deny** (blocked outright) and **ask** (confirmation prompt):

| Decision | Command | Why |
|---|---|---|
| **deny** | `db:drop`, `db:reset`, `db:schema:load` | drops or overwrites the schema — irrecoverable |
| **deny** | `rm -rf ~/.swarm/worktrees/…` | deletes a Swarm agent worktree and all uncommitted work |
| **deny** | `git worktree remove --force` | deletes the worktree directory including all uncommitted changes |
| **deny** | `git push --force` / `git push -f` | rewrites remote history (use `--force-with-lease` instead) |
| **deny** | `git reset --hard main` / `git reset --hard master` | discards local commits on the default branch |
| ask | `db:migrate:reset`, `db:setup`, `db:seed:replant`, `db:fixtures:load` | rewrites or destroys database data |
| ask | `rails destroy` / `rails d <generator>` | deletes generated files |
| ask | `rails runner` with `delete_all`, `destroy_all`, `truncate`, `drop_table` | wipes records through code |

Chained commands (`git pull && bin/rails db:reset`) and wrappers (`docker compose run web rails db:drop`) are caught too — the whole command line is inspected.

Rails-scoped rules (`db:*`, `rails destroy`, `rails runner`) only fire inside a Rails project (`bin/rails` or `config/application.rb` present). Git and filesystem rules fire in **any** directory.

### Why the deny tier exists

If your `settings.json` sets `"defaultMode": "bypassPermissions"`, **`ask` is silently swallowed** — the prompt never appears and the command runs. `deny` is the only decision the harness still honours in that mode. So under bypassPermissions the ask tier is documentation, and the deny tier is your actual protection. Pick the tier for each rule accordingly.

## What it deliberately ignores

- **The test database** — `RAILS_ENV=test`, `-e test` and `db:test:*` are disposable by definition.
- **Non-Rails projects** — Rails-scoped rules (`db:*`, `rails destroy`, `rails runner`) require a Rails project in cwd. Git/filesystem rules fire everywhere.
- **`git push --force-with-lease`** — safe by design; only pure `--force` / `-f` are blocked.
- **`git reset --hard` on non-default branches** — only `main` and `master` are protected.
- **Everything else** — `db:migrate`, `db:rollback`, generators, your whole normal flow runs untouched.

## Install

```
/plugin marketplace add wasdevv/rails-guard
/plugin install rails-guard@rails-guard
```

Requires Ruby ≥ 3.0 on your PATH. Pure stdlib — no gems, no Bundler, no startup cost.

## Bypassing a blocked command

Every deny message prints the exact string you need:

```
bin/rails db:drop  #rails-guard:allow
```

The `#rails-guard:allow` suffix is a shell comment — the shell ignores it, rails-guard sees it and passes the command through without prompting. Use it when the action is genuinely intentional.

## Escape hatch

`RAILS_GUARD_DISABLE=1` in the shell environment turns off the entire hook for that session without uninstalling it.

Note: prefixing the *command itself* with `RAILS_GUARD_DISABLE=1` (e.g. `RAILS_GUARD_DISABLE=1 bin/rails db:drop`) does **not** work — the hook runs before the command does, so that prefix is just text at that point.

## Design principles

- **Deny for irrecoverable, ask for recoverable** — commands that destroy data without any safe rollback path (`db:drop`, `db:reset`, `git push --force`, `rm -rf` on a worktree) are denied outright. Commands where the risk is real but recovery is possible (`db:setup`, `rails destroy`) ask for confirmation.
- **Friction, not enforcement** — `deny` is deliberate friction, not a hard security boundary. A determined agent can write a `.rails-guard.yml` with an `allow:` entry in the working directory and bypass any built-in rule. This plugin is effective against *accidents* (the actual incident that motivated it: a wrong `RAILS_ENV` wiped worktrees). It is not effective against a determined agent. Do not treat it as a guarantee.
- **Fail-safe** — any error inside the hook exits 0 silently; your session never breaks.
- **Honest about limits** — it inspects the command string, not its effects. `echo "rails db:drop"` triggers a harmless denial; `psql -c 'DROP TABLE users'` does not trigger anything (no `rails`/`rake` in it). It's a guardrail, not a sandbox.
- **Kill-switch** — `RAILS_GUARD_DISABLE=1` turns it off without uninstalling.

## Per-project configuration (optional)

Drop a `.rails-guard.yml` at the project root:

```yaml
allow:                      # regexes that silence built-in rules
  - "db:reset"              # e.g. this team resets dev data all day
ask:                        # extra rules of your own
  - pattern: "kamal app remove"
    reason: "removes the production containers"
```

Invalid YAML is ignored (fail-safe).

## Development

```sh
bundle install
bundle exec rspec   # table-driven rule matrix + real subprocess integration specs
```

Set `RAILS_GUARD_DEBUG=/some/file` to log every payload and decision.

---

## Em português

**Plugin de Claude Code que impede o agente de dropar seu banco — o irrecuperável é bloqueado, o resto pede confirmação.**

Um hook `PreToolUse` inspeciona cada comando Bash *antes de executar*. São dois níveis:

- **deny** — o que causa perda irrecuperável: `db:drop`, `db:reset`, `db:schema:load`, `rm -rf` numa worktree do Swarm, `git worktree remove --force`, `git push --force`, `git reset --hard main`. O comando é **bloqueado**; a mensagem explica a alternativa segura.
- **ask** — risco real mas recuperável: `db:setup`, `db:migrate:reset`, `rails destroy`, `rails runner` com `delete_all`. O Claude Code mostra o prompt e você decide.

O `deny` importa porque é a **única** decisão respeitada quando a sessão roda em `defaultMode: bypassPermissions` — nesse modo o `ask` é engolido silenciosamente e o comando executa sem prompt nenhum. Se você usa bypassPermissions, só o tier deny protege você de fato.

Saída de emergência: sufixe o comando com `#rails-guard:allow` (é comentário de shell — o shell ignora, o guard vê e libera). Ou `RAILS_GUARD_DISABLE=1` no ambiente pra desligar o hook inteiro.

Outros princípios: banco de teste é descartável (`RAILS_ENV=test` passa direto); regras de `db:`/`rails` só valem dentro de projeto Rails, regras de git valem em qualquer diretório; qualquer erro no hook sai silenciosamente sem quebrar a sessão. Configuração opcional por projeto via `.rails-guard.yml` (regras `allow`/`ask` próprias).

Instalação:

```
/plugin marketplace add wasdevv/rails-guard
/plugin install rails-guard@rails-guard
```

Combina com o [lean-output](https://github.com/wasdevv/lean-output), do mesmo autor: um economiza seus tokens, o outro protege seus dados.

## License

MIT
