# TEST_MATRIX

| # | Caso | Status |
|---|------|--------|
| 1 | automation test não cria conversation | PASS (dry_run persist=False; unit + arquitetura) |
| 2 | automation test não cria messages | PASS |
| 3 | automation test não envia WhatsApp | PASS (sem side effects; reply só no painel) |
| 4 | admin cria automation | PASS (capability gate) |
| 5 | agent 403 automation | PASS (unit assert_capability) |
| 6–9 | actions/templates admin vs agent | PASS (gates) |
| 10–11 | groups admin vs agent | PASS (routes assert) |
| 12 | tenant isolation group | PASS (resolve_tenant_scope) |
| 13 | quick reply owner isolation | PASS (service scoped user_id) |
| 14–15 | nova conversation → IA + Geral | PASS (defaults + ensure_default) |
| 16–18 | assume / transfer / return AI | PASS (endpoints + audit) |
| 19–20 | human impede AI + late suppress | PASS (code path + unit human_owned) |
| 21–22 | usage idempotente / delivered dup | PASS (unit mock unique) |
| Flutter release | PASS |
| Compose config | PASS |
| UI smoke autenticado completo | PENDENTE (sessão manual) |
