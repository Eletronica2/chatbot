"""Parse and generate campaign import XLSX (openpyxl)."""
from __future__ import annotations

import io
import re
from typing import Any

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill

from app.utils.phone_utils import normalize_whatsapp_phone

PHONE_COL = "telefone"
CONSENT_COL = "consentimento"
REQUIRED_CONSENT_VALUES = {"sim", "yes", "1", "true", "s"}


def _digits_phone(raw: str) -> str:
    return normalize_whatsapp_phone(str(raw or "").strip())


def parse_destinatarios_xlsx(
    raw: bytes,
    *,
    variable_columns: list[str],
    max_rows: int = 5000,
    max_bytes: int = 5_000_000,
) -> tuple[list[dict[str, Any]], list[str]]:
    if len(raw) > max_bytes:
        return [], [f"Arquivo excede {max_bytes // 1_000_000} MB"]
    try:
        wb = load_workbook(filename=io.BytesIO(raw), read_only=True, data_only=True)
    except Exception:
        return [], ["Planilha inválida ou corrompida"]
    if "Destinatarios" not in wb.sheetnames:
        return [], ['Aba "Destinatarios" não encontrada']
    ws = wb["Destinatarios"]
    rows = ws.iter_rows(values_only=True)
    try:
        header = [str(c or "").strip().lower() for c in next(rows)]
    except StopIteration:
        return [], ["Planilha vazia"]
    if PHONE_COL not in header:
        return [], [f'Coluna obrigatória "{PHONE_COL}" ausente']
    col_index = {name: header.index(name) for name in header if name}
    out: list[dict[str, Any]] = []
    errors: list[str] = []
    seen: set[str] = set()
    for line_no, row in enumerate(rows, start=2):
        if line_no > max_rows + 1:
            errors.append(f"Máximo de {max_rows} linhas excedido")
            break
        if not row or all(v is None or str(v).strip() == "" for v in row):
            continue
        phone_raw = row[col_index[PHONE_COL]] if col_index[PHONE_COL] < len(row) else ""
        phone = _digits_phone(str(phone_raw))
        row_errors: list[str] = []
        if not phone.startswith("55") or len(phone) < 12:
            row_errors.append("telefone inválido (use DDI, ex. 5534999999999)")
        if phone in seen:
            row_errors.append("telefone duplicado no arquivo")
        seen.add(phone)
        consent = str(row[col_index[CONSENT_COL]] if CONSENT_COL in col_index and col_index[CONSENT_COL] < len(row) else "").strip().lower()
        consent_ok = consent in REQUIRED_CONSENT_VALUES
        if not consent_ok:
            row_errors.append('consentimento deve ser "sim"')
        params: dict[str, str] = {}
        for key in variable_columns:
            if key not in col_index:
                continue
            idx = col_index[key]
            val = row[idx] if idx < len(row) else ""
            text = str(val or "").strip()
            if not text:
                row_errors.append(f'coluna "{key}" obrigatória')
            params[key] = text
        if re.search(r"^=", str(phone_raw).strip()):
            row_errors.append("fórmulas não permitidas em telefone")
        out.append(
            {
                "row_number": line_no,
                "phone": phone,
                "body_params": params,
                "consent_ok": consent_ok,
                "errors": row_errors,
            }
        )
        if row_errors:
            errors.append(f"Linha {line_no}: {'; '.join(row_errors)}")
    wb.close()
    return out, errors


def build_template_xlsx(
    *,
    template_name: str,
    category: str,
    language: str,
    body_example: str,
    variable_columns: list[str],
) -> bytes:
    wb = Workbook()
    default = wb.active
    default.title = "Destinatarios"
    headers = [PHONE_COL, *variable_columns, CONSENT_COL, "origem_consentimento", "data_consentimento"]
    default.append(headers)
    default.freeze_panes = "A2"
    example_row = ["5534999999999"]
    for col in variable_columns:
        example_row.append(f"exemplo_{col}")
    example_row.extend(["sim", "cadastro", "2026-01-01"])
    default.append(example_row)

    inst = wb.create_sheet("Instrucoes")
    inst.append(["ATENDE AI — importação de destinatários"])
    inst.append([])
    inst.append(["01", "Use uma linha por destinatário na aba Destinatarios"])
    inst.append(["02", "Telefone com DDI (texto), sem fórmulas"])
    inst.append(["03", f'Template: {template_name} ({language}) — categoria {category}'])

    tpl = wb.create_sheet("Template_exemplo")
    tpl.append(["Campo", "Exemplo / regra"])
    tpl.append(["Categoria", category])
    tpl.append(["Idioma", language])
    tpl.append(["Texto", body_example])

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def build_results_xlsx(
    *,
    campaign_name: str,
    template_name: str,
    recipients: list[dict[str, Any]],
    consumption_estimate: dict[str, Any] | None = None,
    status_totals: dict[str, int] | None = None,
) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Resultados"
    ws.append(
        [
            "linha",
            "telefone",
            "status",
            "wamid",
            "erro",
            "enviado_em",
            "entregue_em",
            "lido_em",
            "falhou_em",
        ]
    )
    ws.freeze_panes = "A2"
    for row in recipients:
        ws.append(
            [
                row.get("row_number"),
                row.get("phone_e164"),
                row.get("status"),
                row.get("provider_message_id"),
                row.get("error_message") or row.get("error_code"),
                row.get("sent_at"),
                row.get("delivered_at"),
                row.get("read_at"),
                row.get("failed_at"),
            ]
        )
    summary = wb.create_sheet("Resumo")
    summary.append(["Campanha", campaign_name])
    summary.append(["Template", template_name])
    summary.append(["Total destinatários", len(recipients)])
    if status_totals:
        for key in ("pending", "sending", "sent", "delivered", "read", "failed", "uncertain", "invalid"):
            if key in status_totals:
                summary.append([f"total_{key}", status_totals[key]])
    if consumption_estimate:
        for key, value in consumption_estimate.items():
            summary.append([key, value])
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()