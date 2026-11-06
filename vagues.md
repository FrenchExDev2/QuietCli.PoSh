# Vagues de providers QuietCli2 (inventaire RTK)

## Source et méthode

- **Clone RTK local :** `C:\code\FrenchExDev\FrenchExDev_i2\Rust\rtk`
- **Git :** branche `develop`, commit `b47e05b5` (2026-11-04 13:41:28 +0100), tag `dev-1.2.0-rc.614`, crate `rtk` **0.49.0**
- **Méthode :** union des premiers tokens `rtk_cmd` dans `src/discover/rules.rs` (**93**) et des binaires déduits de `src/filters/*.toml` absents des rules (**+20**) = **113 binaires distincts**
- Les **%** sont les `savings_pct` estimés par RTK dans `rules.rs` (heuristique embarquée), **pas** une mesure terrain QuietCli ni une facture tokens réelle
- L'**ordre des vagues** est une **estimation** de priorité produit (stack Jean Windows/dotnet/pwsh/podman/winget, Git déjà commencé, commandes mises en avant dans le README RTK). **Aucune statistique d'usage agent mesurée** n'a été trouvée dans le clone pour ordonner ces vagues
- QuietCli vérifié sous `QuietCliEcosystem` : v2 = Core + Git Partial ; v1 = Git `status` porcelain seulement
- Légende statut : `[~]` = partiel présent ; `[ ]` = à faire

Total listé ci-dessous : **113** binaires (vague 1=15, vague 2=34, vague 3=64).

## Vague 1 — socle agent + stack Jean

- [ ] **cargo** — sous-cmd: test 90.0%, check 80.0%, fmt (passthrough) — mécanisme: Rust (src/cmds/rust/cargo_cmd.rs) — RTK: 80.0% — machine-readable: --message-format=json — statut: à faire
- [ ] **curl** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/cloud/curl_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **docker** — sous-cmd: ps, images, logs, run, exec, build, compose ps/logs/build — mécanisme: Rust (src/cmds/cloud/container.rs) — RTK: 85.0% — machine-readable: --format json — statut: à faire
- [ ] **dotnet** — sous-cmd: build, test, restore, format (+ binlog/trx) — mécanisme: Rust (src/cmds/dotnet/dotnet_cmd.rs) + TOML (dotnet-build.toml) — RTK: 70.0% — machine-readable: binlog, TRX, format report — statut: à faire
- [ ] **find** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/find_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **gh** — sous-cmd: pr, run, issue (+ passthrough autres) — mécanisme: Rust (src/cmds/git/gh_cmd.rs) — RTK: 82.0% — machine-readable: --json — statut: à faire
- [~] **git** — sous-cmd: status, diff, log, show, add, commit, checkout, push, pull, branch, fetch, stash, worktree, ls-tree (git_cmd.rs) — mécanisme: Rust (src/cmds/git/git_cmd.rs) — RTK: 70.0% — machine-readable: --porcelain=v2, -z, --format — statut: QuietCli2 partiel (Qualification=Partial; v1 status only)
- [ ] **grep** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/search.rs) — RTK: 75.0% — machine-readable: texte — statut: à faire
- [ ] **ls** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/ls.rs) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **npm** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/npm_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **npx** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: rules rewrite wrapper — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pnpm** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/pnpm_cmd.rs) — RTK: 80.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **rg** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/search.rs) — RTK: 75.0% — machine-readable: texte (--json possible) — statut: à faire
- [ ] **tree** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/tree.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **wget** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/cloud/wget_cmd.rs) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire

## Vague 2 — build / test / cloud fréquents chez les agents

- [ ] **ast-grep** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/ast_grep_cmd.rs) — RTK: 85.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **aws** — sous-cmd: sts 80.0%, s3 60.0%, ec2 85.0%, ecs 90.0%, rds 80.0%, cloudformation 90.0%, logs 88.0%, lambda 90.0%, iam 85.0%, dynamodb 70.0%, s3api 75.0%, eks 87.0%, sqs 78.0%, secretsmanager 75.0% — mécanisme: Rust (src/cmds/cloud/aws_cmd.rs) — RTK: 80.0% — machine-readable: JSON CLI — statut: à faire
- [ ] **bun** — sous-cmd: test 90.0%, install 70.0%, pm ls 70.0%, run (passthrough), pm (passthrough), build (passthrough) — mécanisme: Rust (src/cmds/js/bun_cmd.rs) — RTK: 75.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ctest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/ctest_cmd.rs) — RTK: 80.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **deno** — sous-cmd: test 90.0%, lint 40.0%, check 50.0%, run (passthrough), task (passthrough), install (passthrough), compile (passthrough) — mécanisme: Rust (src/cmds/js/deno_cmd.rs) — RTK: 75.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **diff** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: rules — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **gcloud** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (gcloud.toml) — RTK: 65.0% — machine-readable: --format=json — statut: à faire
- [ ] **glab** — sous-cmd: mr, ci, issue (+ passthrough) — mécanisme: Rust (src/cmds/git/glab_cmd.rs) — RTK: 82.0% — machine-readable: --output json (selon cmd) — statut: à faire
- [ ] **go** — sous-cmd: test 90.0%, build 80.0%, vet 75.0% — mécanisme: Rust (src/cmds/go/go_cmd.rs) — RTK: 85.0% — machine-readable: go test -json — statut: à faire
- [ ] **golangci-lint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/go/golangci_cmd.rs) — RTK: 85.0% — machine-readable: --out-format=json — statut: à faire
- [ ] **gt** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/git/gt_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **jest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: rules (JS test path) — RTK: 99.0% — machine-readable: --json — statut: à faire
- [ ] **kubectl** — sous-cmd: get pods, get services, logs — mécanisme: Rust (src/cmds/cloud/container.rs) — RTK: 85.0% — machine-readable: -o json — statut: à faire
- [ ] **lint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/lint_cmd.rs) — RTK: 84.0% — machine-readable: eslint/biome JSON selon outil — statut: à faire
- [ ] **mypy** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/python/mypy_cmd.rs) — RTK: 80.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **next** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/next_cmd.rs) — RTK: 87.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ng** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/ng_cmd.rs) — RTK: 20.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **oc** — sous-cmd: get pods, get services, logs — mécanisme: Rust (src/cmds/cloud/container.rs) — RTK: 85.0% — machine-readable: -o json — statut: à faire
- [ ] **pip** — sous-cmd: list 75.0%, outdated 80.0% — mécanisme: Rust (src/cmds/python/pip_cmd.rs) — RTK: 75.0% — machine-readable: --format=json (list) — statut: à faire
- [ ] **playwright** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/playwright_cmd.rs) — RTK: 94.0% — machine-readable: reporters JSON — statut: à faire
- [ ] **poetry** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (poetry-install.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **prettier** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/prettier_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **prisma** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/prisma_cmd.rs) — RTK: 88.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **psql** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/cloud/psql_cmd.rs) — RTK: 75.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pytest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/python/pytest_cmd.rs) — RTK: 90.0% — machine-readable: junit/json plugins — statut: à faire
- [ ] **read** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/read.rs) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ruff** — sous-cmd: check 80.0%, format 75.0% — mécanisme: Rust (src/cmds/python/ruff_cmd.rs) — RTK: 80.0% — machine-readable: --output-format json — statut: à faire
- [ ] **sqlfluff** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/python/sqlfluff_cmd.rs) — RTK: 75.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **terraform** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (terraform-plan.toml) — RTK: 70.0% — machine-readable: -json (plan) — statut: à faire
- [ ] **tofu** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (tofu-fmt.toml, tofu-init.toml, tofu-plan.toml, tofu-validate.toml) — RTK: 70.0% — machine-readable: -json — statut: à faire
- [ ] **tsc** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/tsc_cmd.rs) — RTK: 83.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **uv** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/python/uv_cmd.rs) + TOML (uv-sync.toml) — RTK: 65.0% — machine-readable: --format json (selon subcmd) — statut: à faire
- [ ] **vitest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/js/vitest_cmd.rs) — RTK: 99.0% — machine-readable: reporters JSON — statut: à faire
- [ ] **wc** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/system/wc_cmd.rs) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire

## Vague 3 — longue traîne (TOML / niches / autres langages)

- [ ] **ansible-playbook** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ansible-playbook.toml) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **basedpyright** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (basedpyright.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **biome** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (biome.toml) — RTK: — (pas de savings_pct) — machine-readable: --reporter json — statut: à faire
- [ ] **brew** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (brew-install.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **bundle** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (bundle-install.toml) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **bunx** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: rules rewrite wrapper — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **composer** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (composer-install.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **df** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (df.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **du** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (du.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ecs** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/ecs_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **fail2ban-client** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (fail2ban-client.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **gcc** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (gcc.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **gradlew** — sous-cmd: test 90.0%, build 80.0%, check 80.0% — mécanisme: Rust (src/cmds/jvm/gradlew_cmd.rs) — RTK: 75.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **hadolint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (hadolint.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **helm** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (helm.toml) — RTK: 65.0% — machine-readable: -o json — statut: à faire
- [ ] **iptables** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (iptables.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **jira** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (jira.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **jj** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (jj.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **jq** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (jq.toml) — RTK: — (pas de savings_pct) — machine-readable: JSON natif — statut: à faire
- [ ] **just** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (just.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **liquibase** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (liquibase.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **make** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (make.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **markdownlint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (markdownlint.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **mise** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (mise.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **mix** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (mix-compile.toml, mix-format.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **mvn** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/jvm/mvn_cmd.rs) — RTK: 82.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **mvnd** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: rules (mvn daemon) — RTK: 82.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **nx** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (nx.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ollama** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ollama.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **oxlint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (oxlint.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **paratest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/paratest_cmd.rs) — RTK: 80.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pest** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/pest_cmd.rs) — RTK: 80.0% — machine-readable: junit/json — statut: à faire
- [ ] **php** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/php_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **phpstan** — sous-cmd: analyse 65.0%, analyze 65.0% — mécanisme: Rust (src/cmds/php/phpstan_cmd.rs) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **phpt** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/phpt_cmd.rs) — RTK: 99.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **phpunit** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/phpunit_cmd.rs) — RTK: 75.0% — machine-readable: junit/json — statut: à faire
- [ ] **ping** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ping.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/php/pint_cmd.rs) — RTK: 70.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pio** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (pio-run.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pre-commit** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (pre-commit.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ps** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ps.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **pulumi** — sous-cmd: up 66.0%, destroy 72.0%, refresh 35.0%, preview 25.0%, stack 29.0% — mécanisme: TOML (pulumi-destroy.toml, pulumi-preview.toml, pulumi-refresh.toml, pulumi-stack.toml, pulumi-up.toml) — RTK: 45.0% — machine-readable: events JSON — statut: à faire
- [ ] **quarto** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (quarto-render.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **rake** — sous-cmd: test 90.0% — mécanisme: Rust (src/cmds/ruby/rake_cmd.rs) — RTK: 85.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **rspec** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/ruby/rspec_cmd.rs) — RTK: 65.0% — machine-readable: --format json — statut: à faire
- [ ] **rsync** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (rsync.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **rubocop** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: Rust (src/cmds/ruby/rubocop_cmd.rs) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **sbt** — sous-cmd: test 90.0%, testOnly 90.0%, compile 75.0% — mécanisme: Rust (src/cmds/scala/sbt_cmd.rs) — RTK: 80.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **shellcheck** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (shellcheck.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **shopify** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (shopify-theme.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **skopeo** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (skopeo.toml) — RTK: — (pas de savings_pct) — machine-readable: formats structures — statut: à faire
- [ ] **sops** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (sops.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **spring-boot** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (spring-boot.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ssh** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ssh.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **stat** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (stat.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **swift** — sous-cmd: test 90.0% — mécanisme: TOML (swift-build.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **systemctl** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (systemctl-status.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **task** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (task.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **trunk** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (trunk-build.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire
- [ ] **turbo** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (turbo.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **ty** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (ty.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **xcodebuild** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (xcodebuild.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **yadm** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (yadm.toml) — RTK: — (pas de savings_pct) — machine-readable: texte / à qualifier — statut: à faire
- [ ] **yamllint** — sous-cmd: voir rules/filtre (sous-commandes non listées dans subcmd_savings) — mécanisme: TOML (yamllint.toml) — RTK: 65.0% — machine-readable: texte / à qualifier — statut: à faire

## Hors RTK, pertinents Windows

Suggestions (absents du catalogue RTK rewrite/filters comme providers dédiés, utiles pour Jean) :

- [ ] **pwsh** / **powershell** — shell natif agents Windows ; RTK les traite comme wrappers/hooks, pas comme binaires filtrés
- [ ] **winget** — installation paquets Windows
- [ ] **podman** et **podman compose** — conteneurs Jean ; RTK n'a pas de `rtk_cmd` podman (motif test `docker|podman` seulement dans `toml_filter.rs`)
- [ ] **az** — Azure CLI (aws/gcloud existent chez RTK, pas az)
- [ ] **nuget** — packages .NET hors `dotnet` CLI
- [ ] **msbuild** — build .NET classique
- [ ] **cmdlets PowerShell** comme providers natifs : `Get-ChildItem`, `Get-Process`, `Get-Content`, `Get-Service`, `Get-NetTCPConnection`, etc. (hors modèle binaire RTK)
- [ ] **choco** (suggestion) — Chocolatey
- [ ] **scoop** (suggestion) — Scoop
- [ ] **wsl** (suggestion) — pont Linux depuis Windows
- [ ] **sc.exe** (suggestion) — services Windows
- [ ] **schtasks** (suggestion) — tâches planifiées
- [ ] **wevtutil** / **Get-WinEvent** (suggestion) — journaux événements
- [ ] **docker** reste Vague 1 ; **podman** est l'équivalent hors RTK à traiter explicitement

## Autres idées

1. **Session pwsh persistante (position de Jean)** — l'agent doit réutiliser une session `pwsh` déjà chargée (modules + moteur amortis) au lieu de lancer un `pwsh` neuf à chaque commande. Le **hook** reste un **shim léger de réécriture seulement** ; documenter ce mode « session persistante » pour les agents (Claude/Cursor/Codex/etc.).
2. **RewriteForms** dans `Register-QuietHandler` + **Install-QuietHook** multi-agents (init style RTK).
3. **Lexer shell** bash et pwsh (`&&`, `|`, `;`, wrappers `bash -c` / `pwsh -Command`).
4. **Passthrough** sur le chemin hook, `QUIETCLI_DISABLED`, `exclude_commands` (ne pas bloquer les commandes sans handler).
5. **config.toml** utilisateur/projet (`~/.quietcli2/config.toml`) en complément des env `QUIETCLI_*`.
6. **discover** QuietCli qui propose les **modules à installer** via l'installateur modulaire (différence structurelle vs catalogue RTK monolithique).
7. **Recall opt-in** uniquement échec/troncature, borné, scrub secrets ; double usage : récupération agent + **fixtures** pour qualifier des handlers.
8. **États de couverture réels** : `Specialized`, `ExitOnly`, `Missing` ; outcomes `Partial` / `Unsupported` au lieu d'afficher un faux `Executed` complet.
9. **Pipeline de génération de provider assistée par IA** : `New-QuietModule`, gabarit, fixtures, qualification auto.
10. Brancher réellement **`QUIETCLI_ENGINE_MODE=InProcess`** (documenté dans `docs/performance-and-hosting.md`, absent de `Protocol.ps1` actuel).
11. Mettre **AGENTS.md** à jour (pump vers `quiet`).
12. **Script de purge** de `artifacts\` (volume gitignored / bloat).

---

Fichier généré pour Jean Emile — lecture inventaire RTK `b47e05b5` — écriture unique `vagues.md` — pas de commit.
