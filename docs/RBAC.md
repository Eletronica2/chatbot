# RBAC — Atenda Ai

## Roles

| Role | Significado |
|------|-------------|
| `superadmin` (+ aliases) | Operador Atenda Ai / backoffice |
| `owner` / `manager` / `admin` | Administrador da empresa (tenant admin) |
| `agent` / `member` | Atendente |

Fonte: `backend-api/app/api/access.py` → `capabilities_for`.

## Capabilities

| Capability | Admin | Agent |
|------------|-------|-------|
| Conversas (ver/responder/assumir/transferir) | sim | sim |
| Grupos (CRUD) | sim | não |
| Equipe | sim | não |
| Automações / Ações / Templates | sim | não |
| WhatsApp config | sim | não |
| Plano e cobrança | sim | não |
| Respostas rápidas (próprias) | sim | sim |
| Backoffice Clientes | só superadmin | não |

Mutations proibidas retornam **403** no backend. Flutter esconde menu, mas não é a autoridade.

## Sidebar

- **Admin**: Visão Geral, Conversas, Automações, Ações, Templates, Grupos, Respostas rápidas, WhatsApp, Equipe, Plano e cobrança.
- **Agent**: Visão Geral, Conversas, Respostas rápidas.
