import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/subscription_info.dart';
import '../models/tenant_settings.dart';
import '../models/whatsapp_account.dart';
import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import 'premium_ui.dart';

String operationPlanLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'starter':
      return 'Inicial';
    case 'growth':
      return 'Crescimento';
    case 'pro':
      return 'Profissional';
    case 'enterprise':
      return 'Empresarial';
    default:
      return value.isEmpty ? 'Plano' : value;
  }
}

String operationStatusLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'active':
      return 'Ativo';
    case 'trialing':
      return 'Em teste';
    case 'past_due':
      return 'Pagamento pendente';
    case 'inactive':
      return 'Inativo';
    case 'canceled':
      return 'Cancelado';
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

String whatsappStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'active':
      return 'Conectado';
    case 'inactive':
      return 'Inativo';
    case 'pending':
      return 'Pendente';
    default:
      return status.isEmpty ? 'Desconhecido' : status;
  }
}

/// Blocos operacionais restantes na Central de Ação.
class OperationHubPanel extends StatelessWidget {
  const OperationHubPanel({
    super.key,
    required this.settings,
    required this.subscription,
    required this.whatsappAccounts,
    this.onOpenBilling,
    this.onOpenClients,
  });

  final TenantSettings settings;
  final SubscriptionInfo subscription;
  final List<WhatsAppAccountModel> whatsappAccounts;
  final VoidCallback? onOpenBilling;
  final VoidCallback? onOpenClients;

  String get _tenantId => authService.tenantId ?? 'default';

  bool get _isSystemHomeContext =>
      authService.isSuperadmin &&
      _tenantId == (authService.homeTenantId ?? '');

  WhatsAppAccountModel? get _defaultWhatsApp {
    for (final item in whatsappAccounts) {
      if (item.isDefault) return item;
    }
    return whatsappAccounts.isNotEmpty ? whatsappAccounts.first : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSystemHomeContext) {
      return PremiumSection(
        title: 'Operação da plataforma',
        subtitle:
            'Conta interna do sistema. Selecione uma empresa para configurar WhatsApp e automações.',
        child: onOpenClients == null
            ? const SizedBox.shrink()
            : PremiumTextButton(
                label: 'Gerenciar empresas',
                icon: Icons.business_rounded,
                primary: true,
                onTap: onOpenClients!,
              ),
      );
    }

    final wa = _defaultWhatsApp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1080;
            final plan = PremiumSection(
              title: 'Plano e consumo',
              subtitle: 'Assinatura e uso de mensagens no ciclo atual.',
              trailing: onOpenBilling == null
                  ? null
                  : PremiumTextButton(
                      label: 'Cobrança',
                      icon: Icons.credit_card_rounded,
                      onTap: onOpenBilling!,
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PremiumBadge(
                        label: operationPlanLabel(subscription.plan),
                        icon: Icons.workspace_premium_rounded,
                        color: AppColors.primary,
                      ),
                      PremiumBadge(
                        label: operationStatusLabel(subscription.status),
                        icon: subscription.active
                            ? Icons.check_circle_rounded
                            : Icons.schedule_rounded,
                        color: subscription.active
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PremiumField(
                    label: 'Mensagens usadas',
                    value: subscription.monthlyMessageLimit <= 0
                        ? '${subscription.usedMessages} no período'
                        : '${subscription.usedMessages} de ${subscription.monthlyMessageLimit}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PremiumField(
                    label: 'Renovação',
                    value: subscription.renewalDate == null
                        ? 'Sem data informada'
                        : DateFormat('dd/MM/yyyy')
                            .format(subscription.renewalDate!),
                  ),
                ],
              ),
            );

            final whatsapp = PremiumSection(
              title: 'WhatsApp conectado',
              subtitle: 'Contas vinculadas à empresa em foco.',
              child: wa == null
                  ? const PremiumComingSoonStrip(
                      title: 'Nenhuma conta configurada',
                      description:
                          'Cadastre números na área de Clientes (superadmin) ou via API de contas WhatsApp.',
                    )
                  : Column(
                      children: [
                        PremiumField(
                          label: 'Conta padrão',
                          value: wa.displayName.isNotEmpty
                              ? wa.displayName
                              : wa.accountKey,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        PremiumField(
                          label: 'Número exibido',
                          value: wa.displayPhoneNumber.isNotEmpty
                              ? wa.displayPhoneNumber
                              : '—',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        PremiumField(
                          label: 'Status',
                          value: whatsappStatusLabel(wa.status),
                        ),
                        if (whatsappAccounts.length > 1) ...[
                          const SizedBox(height: AppSpacing.sm),
                          PremiumField(
                            label: 'Total de contas',
                            value: '${whatsappAccounts.length} vinculadas',
                          ),
                        ],
                      ],
                    ),
            );

            if (compact) {
              return Column(
                children: [
                  plan,
                  const SizedBox(height: AppSpacing.lg),
                  whatsapp,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: plan),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: whatsapp),
                ],
              ),
            );
          },
        ),
        if (onOpenClients != null) ...[
          const SizedBox(height: AppSpacing.lg),
          PremiumSection(
            title: 'Equipe e empresas',
            subtitle: 'Gestão de tenants, usuários e números (superadmin).',
            child: PremiumTextButton(
              label: 'Abrir área de clientes',
              icon: Icons.groups_rounded,
              onTap: onOpenClients!,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PremiumSection(
          title: 'Integrações',
          subtitle: 'Conectores externos — estrutura preparada para expansão.',
          child: const PremiumComingSoonStrip(
            title: 'Integrações em desenvolvimento',
            description:
                'Não há endpoint dedicado de integrações nesta versão. A estrutura visual está pronta para quando o backend estiver disponível.',
          ),
        ),
      ],
    );
  }
}
