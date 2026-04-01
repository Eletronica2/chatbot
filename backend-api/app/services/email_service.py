"""SMTP email dispatch service for invites, resets and billing notifications."""
from __future__ import annotations

import asyncio
import logging
import smtplib
from datetime import datetime
from email.message import EmailMessage

from app.config.settings import Settings
from app.db.mysql import MySQLDatabase
from app.domain.email_dispatch import EmailDispatchResult

logger = logging.getLogger(__name__)


class EmailService:
    def __init__(self, settings: Settings, database: MySQLDatabase):
        self.settings = settings
        self.database = database

    @property
    def configured(self) -> bool:
        return bool(
            self.settings.SMTP_HOST.strip()
            and self.settings.SMTP_FROM_EMAIL.strip()
        )

    async def send_invite_email(
        self,
        *,
        tenant_id: str,
        tenant_name: str,
        to_email: str,
        display_name: str,
        action_url: str,
        expires_at: datetime,
    ) -> EmailDispatchResult:
        subject = f"Convite para acessar o painel de {tenant_name}"
        html = f"""
        <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a">
          <h2 style="margin-bottom:8px;">Seu acesso ao painel foi criado</h2>
          <p>Olá, {display_name}.</p>
          <p>Você foi convidado para acessar o painel administrativo de <strong>{tenant_name}</strong>.</p>
          <p>Para concluir o acesso, clique no botão abaixo e defina sua senha:</p>
          <p style="margin:24px 0;">
            <a href="{action_url}" style="background:#4f46e5;color:#fff;text-decoration:none;padding:12px 18px;border-radius:10px;display:inline-block;">Concluir acesso</a>
          </p>
          <p>Se preferir, use este link direto:</p>
          <p><a href="{action_url}">{action_url}</a></p>
          <p>Este convite expira em {expires_at.strftime('%d/%m/%Y %H:%M UTC')}.</p>
        </div>
        """
        text = (
            f"Olá, {display_name}.\n\n"
            f"Você foi convidado para acessar o painel de {tenant_name}.\n"
            f"Conclua o acesso aqui: {action_url}\n\n"
            f"Convite válido até {expires_at.strftime('%d/%m/%Y %H:%M UTC')}."
        )
        return await self._send(
            tenant_id=tenant_id,
            kind="invite",
            to_email=to_email,
            subject=subject,
            text_body=text,
            html_body=html,
        )

    async def send_reset_email(
        self,
        *,
        tenant_id: str,
        tenant_name: str,
        to_email: str,
        display_name: str,
        action_url: str,
        expires_at: datetime,
    ) -> EmailDispatchResult:
        subject = f"Redefinição de senha do painel de {tenant_name}"
        html = f"""
        <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a">
          <h2 style="margin-bottom:8px;">Redefinição de senha</h2>
          <p>Olá, {display_name}.</p>
          <p>Recebemos uma solicitação para redefinir a senha do seu acesso ao painel de <strong>{tenant_name}</strong>.</p>
          <p style="margin:24px 0;">
            <a href="{action_url}" style="background:#4f46e5;color:#fff;text-decoration:none;padding:12px 18px;border-radius:10px;display:inline-block;">Redefinir senha</a>
          </p>
          <p>Se preferir, use este link direto:</p>
          <p><a href="{action_url}">{action_url}</a></p>
          <p>Este link expira em {expires_at.strftime('%d/%m/%Y %H:%M UTC')}.</p>
        </div>
        """
        text = (
            f"Olá, {display_name}.\n\n"
            f"Use o link abaixo para redefinir sua senha do painel de {tenant_name}:\n"
            f"{action_url}\n\n"
            f"Link válido até {expires_at.strftime('%d/%m/%Y %H:%M UTC')}."
        )
        return await self._send(
            tenant_id=tenant_id,
            kind="reset_password",
            to_email=to_email,
            subject=subject,
            text_body=text,
            html_body=html,
        )

    async def send_billing_event_email(
        self,
        *,
        tenant_id: str,
        tenant_name: str,
        to_email: str,
        subject: str,
        body: str,
    ) -> EmailDispatchResult:
        html = f"""
        <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a">
          <h2 style="margin-bottom:8px;">{subject}</h2>
          <p>Olá, equipe de {tenant_name}.</p>
          <p>{body}</p>
        </div>
        """
        return await self._send(
            tenant_id=tenant_id,
            kind="billing_notice",
            to_email=to_email,
            subject=subject,
            text_body=body,
            html_body=html,
        )

    async def _send(
        self,
        *,
        tenant_id: str,
        kind: str,
        to_email: str,
        subject: str,
        text_body: str,
        html_body: str,
    ) -> EmailDispatchResult:
        if not self.configured:
            result = EmailDispatchResult(
                kind=kind,
                to_email=to_email,
                subject=subject,
                status="skipped",
                error="smtp_not_configured",
            )
            await self._log_delivery(tenant_id, result)
            return result

        message = EmailMessage()
        message["From"] = f"{self.settings.SMTP_FROM_NAME} <{self.settings.SMTP_FROM_EMAIL}>"
        message["To"] = to_email
        message["Subject"] = subject
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        try:
            await asyncio.to_thread(self._deliver_message, message)
            result = EmailDispatchResult(
                kind=kind,
                to_email=to_email,
                subject=subject,
                status="sent",
                sent_at=datetime.utcnow(),
            )
        except Exception as exc:  # pragma: no cover - network dependent
            logger.warning("Email delivery failed to %s: %s", to_email, exc)
            result = EmailDispatchResult(
                kind=kind,
                to_email=to_email,
                subject=subject,
                status="failed",
                error=str(exc),
            )

        await self._log_delivery(tenant_id, result)
        return result

    def _deliver_message(self, message: EmailMessage) -> None:
        if self.settings.SMTP_USE_SSL:
            with smtplib.SMTP_SSL(
                self.settings.SMTP_HOST,
                self.settings.SMTP_PORT,
                timeout=15,
            ) as server:
                if self.settings.SMTP_USERNAME:
                    server.login(self.settings.SMTP_USERNAME, self.settings.SMTP_PASSWORD)
                server.send_message(message)
            return

        with smtplib.SMTP(
            self.settings.SMTP_HOST,
            self.settings.SMTP_PORT,
            timeout=15,
        ) as server:
            if self.settings.SMTP_USE_TLS:
                server.starttls()
            if self.settings.SMTP_USERNAME:
                server.login(self.settings.SMTP_USERNAME, self.settings.SMTP_PASSWORD)
            server.send_message(message)

    async def _log_delivery(self, tenant_id: str, result: EmailDispatchResult) -> None:
        tenant_pk = self.database.resolve_tenant_pk(tenant_id)

        def _insert() -> None:
            self.database.insert(
                """
                INSERT INTO email_deliveries (
                    tenant_id,
                    delivery_kind,
                    recipient_email,
                    subject,
                    status,
                    error_message,
                    sent_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    tenant_pk,
                    result.kind,
                    result.to_email,
                    result.subject,
                    result.status,
                    result.error,
                    result.sent_at,
                ),
            )

        await asyncio.to_thread(_insert)

