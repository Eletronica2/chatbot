"""Parse and generate campaign import XLSX (openpyxl)."""
from __future__ import annotations

import io
import re
from typing import Any

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from app.utils.phone_utils import normalize_whatsapp_phone

PHONE_COL = "telefone"
CONSENT_COL = "consentimento"
REQUIRED_CONSENT_VALUES = {"sim", "yes", "1", "true", "s"}
DENIED_CONSENT_VALUES = {"nao", "não", "no", "0", "false", "n", "nao autorizado", "não autorizado"}
_HEADER_FILL = PatternFill("solid", fgColor="0E7490")
_HEADER_FONT = Font(color="FFFFFF", bold=True)


def _digits_phone(raw: str) -> str:
    return normalize_whatsapp_phone(str(raw or "").strip())


def _header_key(raw: str) -> str:
    text = str(raw or "").strip().lower()
    text = text.replace("á", "a").replace("ã", "a").replace("é", "e")
    if text in {"telefone", "phone", "celular"}:
        return PHONE_COL
    if text in {"consentimento", "consent"}:
        return CONSENT_COL
    if text.startswith("variavel "):
        suffix = text.split()[-1]
        return suffix if suffix.isdigit() or suffix else text
    return text


def _safe_cell(value: Any) -> Any:
    if isinstance(value, str) and value[:1] in "=+-@":
        return "'" + value
    return value


def _style_header(ws) -> None:
    for cell in ws[1]:
        cell.fill = _HEADER_FILL
        cell.font = _HEADER_FONT
        cell.alignment = Alignment(vertical="center")
    ws.auto_filter.ref = ws.dimensions
    ws.freeze_panes = "A2"
    for idx, cell in enumerate(ws[1], start=1):
        width = max(14, min(36, len(str(cell.value or "")) + 4))
        ws.column_dimensions[get_column_letter(idx)].width = width


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
        header = [_header_key(c) for c in next(rows)]
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
        consent_denied = False
        consent_ok = False
        if CONSENT_COL in col_index:
            raw_consent = row[col_index[CONSENT_COL]] if col_index[CONSENT_COL] < len(row) else ""
            consent = str(raw_consent or "").strip().lower()
            if consent in DENIED_CONSENT_VALUES:
                consent_denied = True
                row_errors.append("contato explicitamente não autorizado")
            elif consent in REQUIRED_CONSENT_VALUES:
                consent_ok = True
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
                "consent_denied": consent_denied,
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
    variable_labels: dict[str, str] | None = None,
) -> bytes:
    wb = Workbook()
    dest = wb.active
    dest.title = "Destinatarios"
    labels = variable_labels or {}
    headers = ["Telefone"]
    for key in variable_columns:
        label = (labels.get(str(key)) or "").strip() or f"Variável {key}"
        headers.append(label)
    dest.append(headers)
    dest.column_dimensions["A"].number_format = "@"
    _style_header(dest)

    inst = wb.create_sheet("Instrucoes")
    inst.append(["Instruções"])
    inst.append(["Uma linha por destinatário na aba Destinatarios. Esta aba não é importada."])
    inst.append([f"Template: {template_name} ({language}) — {category}"])
    inst.append(["Telefone com DDI, como texto. Exemplo: 5534999999999"])
    inst.append(["A autorização dos destinatários é declarada na revisão da campanha, não nesta planilha."])
    if body_example:
        inst.append([f"Texto do modelo: {body_example}"])
    for key in variable_columns:
        label = (labels.get(str(key)) or "").strip() or f"Variável {key}"
        inst.append([f"{label}: preencha o valor do parâmetro {key} do template"])
    inst.column_dimensions["A"].width = 88

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def build_results_xlsx(
    *,
    campaign_name: str,
    template_name: str,
    recipients: list[dict[str, Any]],
    consumption_estimate: dict[str, Any] | None = None,
    status_totals: dict[str, Any] | None = None,
    category: str = "",
    status: str = "",
) -> bytes:
    from datetime import datetime
    from zoneinfo import ZoneInfo

    tz = ZoneInfo("America/Sao_Paulo")

    def as_local(value: Any):
        if not isinstance(value, datetime):
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=ZoneInfo("UTC"))
        return value.astimezone(tz).replace(tzinfo=None)

    wb = Workbook()
    summary = wb.active
    summary.title = "Resumo"
    totals = status_totals or {}
    summary.append(["Campanha", _safe_cell(campaign_name)])
    summary.append(["Template", _safe_cell(template_name)])
    if category:
        summary.append(["Categoria", category])
    if status:
        summary.append(["Status", status])
    summary.append(["Destinatários", len(recipients)])
    for label, key in (
        ("Enviadas", "sent"),
        ("Entregues", "delivered"),
        ("Lidas", "read"),
        ("Falhas", "failed"),
        ("Pendentes", "pending"),
        ("Incertas", "uncertain"),
    ):
        if key in totals and totals[key]:
            summary.append([label, int(totals[key])])
        elif key in totals and key in {"sent", "delivered", "failed"}:
            summary.append([label, int(totals[key] or 0)])
    rate = totals.get("delivery_rate")
    if isinstance(rate, (int, float)):
        cell_row = summary.max_row + 1
        summary.append(["Taxa de entrega", float(rate) / 100])
        summary.cell(cell_row, 2).number_format = "0.0%"
    if consumption_estimate and consumption_estimate.get("consumption_estimate") not in (None, ""):
        amount = float(consumption_estimate["consumption_estimate"])
        row_i = summary.max_row + 1
        summary.append(["Custo estimado Meta (BRL)", amount])
        summary.cell(row_i, 2).number_format = '"R$" #,##0.00'
    summary.append(["Aviso", "Mensagens cobradas diretamente pela Meta. Valores são estimativas."])
    summary.column_dimensions["A"].width = 32
    summary.column_dimensions["B"].width = 48

    dest = wb.create_sheet("Destinatarios")
    param_keys: list[str] = []
    for row in recipients:
        body = row.get("body_params") or {}
        if isinstance(body, str):
            continue
        for key in body:
            if str(key) not in param_keys:
                param_keys.append(str(key))
    headers = ["Telefone", *[f"Variável {k}" for k in param_keys], "Situação", "Enviada em", "Entregue em", "Lida em", "Motivo da falha"]
    dest.append(headers)
    labels = {
        "pending": "Pendente",
        "sending": "Enviando",
        "sent": "Enviada",
        "delivered": "Entregue",
        "read": "Lida",
        "failed": "Falhou",
        "uncertain": "Incerta",
        "invalid": "Inválida",
    }
    for row in recipients:
        body = row.get("body_params") or {}
        if isinstance(body, str):
            body = {}
        values = [_safe_cell(row.get("phone_e164"))]
        for key in param_keys:
            values.append(_safe_cell(body.get(key) or ""))
        values.append(labels.get(str(row.get("status") or ""), str(row.get("status") or "")))
        values.extend(
            [
                as_local(row.get("sent_at")),
                as_local(row.get("delivered_at")),
                as_local(row.get("read_at")),
                _safe_cell(row.get("error_message") or "") if row.get("status") == "failed" else "",
            ]
        )
        dest.append(values)
    for col in range(3 + len(param_keys), 6 + len(param_keys)):
        for cell in dest.iter_cols(min_col=col, max_col=col, min_row=2):
            for item in cell:
                if isinstance(item.value, datetime):
                    item.number_format = "DD/MM/YYYY HH:MM"
    _style_header(dest)
    dest.column_dimensions["A"].number_format = "@"

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()