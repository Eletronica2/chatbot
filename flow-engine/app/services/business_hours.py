"""Helpers to evaluate establishment opening hours for conversational CTAs."""
from __future__ import annotations

from datetime import datetime, time, timedelta
from typing import Any, Dict, Tuple

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore

_WEEKDAY_KEYS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
)


def _weekday_key(dt: datetime) -> str:
    return _WEEKDAY_KEYS[dt.weekday()]


def _parse_hhmm(value: str) -> time | None:
    raw = (value or "").strip()
    if not raw:
        return None
    parts = raw.split(":")
    if len(parts) < 2:
        return None
    try:
        hour = int(parts[0])
        minute = int(parts[1])
        return time(hour=hour, minute=minute)
    except ValueError:
        return None


def _interval_for_day(
    schedule: Dict[str, Any], day_key: str
) -> Tuple[time, time] | None:
    day_cfg = schedule.get(day_key)
    if not isinstance(day_cfg, dict):
        return None
    open_t = _parse_hhmm(str(day_cfg.get("open") or ""))
    close_t = _parse_hhmm(str(day_cfg.get("close") or ""))
    if open_t is None or close_t is None:
        return None
    return open_t, close_t


def _is_open_at(
    now: datetime, open_t: time, close_t: time
) -> bool:
    current = now.time()
    if open_t <= close_t:
        return open_t <= current < close_t
    # crosses midnight (e.g. 18:00 -> 00:00)
    return current >= open_t or current < close_t


def open_status(
    business_hours: Dict[str, Any] | None,
    *,
    now: datetime | None = None,
) -> Tuple[bool, str]:
    """
    Returns (is_open, human_hint_for_next_opening).
    """
    if not business_hours or not isinstance(business_hours, dict):
        return True, ""

    tz_name = str(business_hours.get("timezone") or "America/Sao_Paulo")
    if ZoneInfo is not None:
        try:
            tz = ZoneInfo(tz_name)
            moment = (now or datetime.now(tz=tz)).astimezone(tz)
        except Exception:
            moment = now or datetime.now()
    else:
        moment = now or datetime.now()

    schedule = business_hours.get("schedule")
    if not isinstance(schedule, dict):
        return True, ""

    day_key = _weekday_key(moment)
    interval = _interval_for_day(schedule, day_key)
    if interval is None:
        return True, ""

    open_t, close_t = interval
    if _is_open_at(moment, open_t, close_t):
        return True, ""

    # Find next opening (today later or upcoming days)
    for offset in range(0, 8):
        candidate_day = moment + timedelta(days=offset)
        key = _weekday_key(candidate_day)
        next_interval = _interval_for_day(schedule, key)
        if next_interval is None:
            continue
        next_open, _ = next_interval
        if offset == 0 and candidate_day.time() < next_open:
            label = f"hoje às {next_open.strftime('%Hh')}"
            return False, label
        if offset > 0:
            day_names = {
                "monday": "segunda",
                "tuesday": "terça",
                "wednesday": "quarta",
                "thursday": "quinta",
                "friday": "sexta",
                "saturday": "sábado",
                "sunday": "domingo",
            }
            label = f"{day_names.get(key, key)} às {next_open.strftime('%Hh')}"
            return False, label

    return False, "no próximo horário de funcionamento"


def apply_contextual_cta(
    message: str,
    business_hours: Dict[str, Any] | None,
    *,
    now: datetime | None = None,
) -> str:
    """Replace {cta_pedido} with open/closed appropriate copy."""
    if not message or "{cta_pedido}" not in message:
        return message

    is_open, next_hint = open_status(business_hours, now=now)
    if is_open:
        cta = "Quer fazer um pedido ou ver o cardápio? 😊"
    else:
        hint = next_hint or "em breve"
        cta = (
            f"No momento estamos fechados — abrimos {hint}. "
            "Até lá, posso te mostrar o cardápio ou as promoções! 🍕"
        )
    return message.replace("{cta_pedido}", cta)
