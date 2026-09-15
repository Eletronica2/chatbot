# Operational Inbox (PABX WhatsApp)

Central de atendimento do Atenda Ai sobre conversas WhatsApp.

## Ownership

- Nova conversa: `assignment_mode=ai`, grupo default **Geral**.
- **Assumir**: `assignment_mode=human`, `assigned_user_id` = ator. IA para de responder.
- **Transferir**: muda `assigned_user_id` para outro usuário **ativo** do mesmo tenant. IA permanece pausada.
- **Devolver para IA**: `assignment_mode=ai`, limpa assignee. IA responde só mensagens **futuras**.

## Proteção de resposta atrasada

Antes de enviar reply automático (flow/AI), o backend relê a sessão. Se já estiver `human`, `reply_text` fica vazio (`suppressed_late_ai`) e o gateway não envia WhatsApp.

## Grupos

Organização operacional (filtro), **não** ACL de confidencialidade. Todo tenant tem **Geral** (não removível).

## Endpoints

- `POST /api/v1/conversations/{id}/assume`
- `POST /api/v1/conversations/{id}/transfer` `{ "user_id" }`
- `POST /api/v1/conversations/{id}/return-to-ai`
- `PATCH /api/v1/conversations/{id}/group` `{ "group_id" }`
- `GET /api/v1/conversations?filter=all|mine|ai|human&group_id=`

Auditoria via `admin_audit_logs` (assume/transfer/return/group_change).
