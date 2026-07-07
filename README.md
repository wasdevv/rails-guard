# rails-guard

**The Claude Code plugin that keeps the agent from dropping your database — destructive Rails commands always ask for your confirmation first.**

Agents are fast, and that's the problem: a single `bin/rails db:reset` executed on autopilot wipes your development data before you finish reading the transcript. rails-guard hooks into `PreToolUse` and inspects every Bash command *before it runs*. If it's destructive and you're in a Rails project, Claude Code shows the permission prompt with the reason — the command only runs after **you** confirm.

```
Claude wants to run: git pull && bin/rails db:reset

[rails-guard] db:reset rewrites or destroys database data

  ❯ 1. Yes
    2. No, and tell Claude what to do differently
```

## What it catches

| Command | Why |
|---|---|
| `db:drop`, `db:reset`, `db:migrate:reset`, `db:schema:load`, `db:setup` | recreate or wipe the database |
| `db:seed:replant` | truncates every table |
| `db:fixtures:load` | replaces data with fixtures |
| `rails destroy` / `rails d <generator>` | deletes generated files |
| `rails runner` with `delete_all`, `destroy_all`, `truncate`, `drop_table` | wipes records through code |

Chained commands (`git pull && bin/rails db:reset`) and wrappers (`docker compose run web rails db:drop`) are caught too — the whole command line is inspected.

## What it deliberately ignores

- **The test database** — `RAILS_ENV=test`, `-e test` and `db:test:*` are disposable by definition.
- **Non-Rails projects** — no `bin/rails` / `config/application.rb` in the working directory, no opinion.
- **Everything else** — `db:migrate`, `db:rollback`, generators, your whole normal flow runs untouched.

## Install

```
/plugin marketplace add wasdevv/rails-guard
/plugin install rails-guard@rails-guard
```

Requires Ruby ≥ 3.0 on your PATH. Pure stdlib — no gems, no Bundler, no startup cost.

## Design principles

- **Ask, never deny** — rails-guard never decides for you; it makes sure a human sees the command. A false positive costs one keystroke, a false negative costs your database. (Corollary: in headless mode, `claude -p`, there is nobody to ask — the command is simply not run.)
- **Fail-safe** — any error inside the hook exits 0 silently; your session never breaks.
- **Honest about limits** — it inspects the command string, not its effects. `echo "rails db:drop"` triggers a harmless confirmation; `psql -c 'DROP TABLE users'` does not trigger anything (no `rails`/`rake` in it). It's a guardrail, not a sandbox.
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

**Plugin de Claude Code que impede o agente de dropar seu banco — comandos Rails destrutivos sempre pedem sua confirmação antes.**

Um hook `PreToolUse` inspeciona cada comando Bash *antes de executar*. Se for destrutivo (`db:drop`, `db:reset`, `db:schema:load`, `rails destroy`, `rails runner` com `delete_all`...) e você estiver num projeto Rails, o Claude Code mostra o prompt de permissão com o motivo — o comando só roda depois que **você** confirmar.

Princípios: **ask, nunca deny** (o guard não decide, ele garante que um humano veja — falso positivo custa 1 tecla, falso negativo custa o banco); banco de teste é descartável (`RAILS_ENV=test` passa direto); fora de projeto Rails o plugin fica invisível; qualquer erro no hook sai silenciosamente sem quebrar a sessão; `RAILS_GUARD_DISABLE=1` desliga tudo. Configuração opcional por projeto via `.rails-guard.yml` (regras `allow`/`ask` próprias).

Instalação:

```
/plugin marketplace add wasdevv/rails-guard
/plugin install rails-guard@rails-guard
```

Combina com o [lean-output](https://github.com/wasdevv/lean-output), do mesmo autor: um economiza seus tokens, o outro protege seus dados.

## License

MIT
