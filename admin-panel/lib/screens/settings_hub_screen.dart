import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/subscription_info.dart';
import '../models/tenant_settings.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui_kit.dart';

String _settingsPlanLabel(String value) {
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

String _settingsStatusLabel(String value) {
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

class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({
    super.key,
    required this.onOpenAutomations,
    this.onOpenBilling,
    this.onOpenClients,
  });

  final VoidCallback onOpenAutomations;
  final VoidCallback? onOpenBilling;
  final VoidCallback? onOpenClients;

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  late Future<_SettingsHubData> _future;
  bool _savingAi = false;

  String get _tenantId => authService.tenantId ?? 'default';

  bool get _isSystemHomeContext =>
      authService.isSuperadmin &&
      _tenantId == (authService.homeTenantId ?? '');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SettingsHubData> _load() async {
    if (_isSystemHomeContext) {
      return _SettingsHubData(
        settings: TenantSettings(
          tenantId: _tenantId,
          tenantName: 'Conta do sistema',
          aiEnabled: false,
          flowEditingEnabled: false,
          debugMode: false,
          geminiModel: '',
          fallbackModels: const <String>[],
          availableModels: const <String>[],
        ),
        subscription: SubscriptionInfo(
          tenantId: _tenantId,
          plan: 'enterprise',
          status: 'active',
          renewalDate: null,
          monthlyMessageLimit: 0,
          active: true,
          usedMessages: 0,
          remainingMessages: 0,
        ),
      );
    }

    final results = await Future.wait<dynamic>([
      tenantService.fetchTenantSettings(_tenantId),
      subscriptionService.fetchSubscription(_tenantId),
    ]);

    return _SettingsHubData(
      settings: results[0] as TenantSettings,
      subscription: results[1] as SubscriptionInfo,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _toggleAi(bool enabled) async {
    if (_savingAi || _isSystemHomeContext) return;

    setState(() => _savingAi = true);
    try {
      await tenantService.toggleAi(_tenantId, enabled);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Inteligência artificial ativada com sucesso.'
                : 'Inteligência artificial desativada com sucesso.',
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível atualizar a IA: $err'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingAi = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: FutureBuilder<_SettingsHubData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.settings_suggest_rounded,
              title: 'Não foi possível carregar as configurações',
              message: snapshot.error.toString(),
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return AppEmptyState(
              icon: Icons.settings_suggest_rounded,
              title: 'Configurações indisponíveis',
              message: 'Nenhum dado foi retornado para a empresa em foco.',
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
            );
          }

          final settings = data.settings;
          final subscription = data.subscription;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPanelCard(
                  backgroundColor: AppColors.surfaceAlt,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 980;
                      final left = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppStatusChip(
                            label: 'Configurações gerais',
                            icon: Icons.tune_rounded,
                            backgroundColor: Color(0xFF1A2540),
                            foregroundColor: AppColors.primarySoft,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _isSystemHomeContext
                                ? 'Conta interna da plataforma'
                                : settings.tenantName,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _isSystemHomeContext
                                ? 'A conta do sistema serve para administrar empresas. Para editar automações e IA, selecione uma empresa na área de Clientes.'
                                : 'Ajuste a inteligência artificial, acompanhe o plano ativo e encontre atalhos rápidos para o dia a dia da operação.',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      );

                      final actions = Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _isSystemHomeContext
                                ? widget.onOpenClients
                                : widget.onOpenAutomations,
                            icon: Icon(
                              _isSystemHomeContext
                                  ? Icons.business_rounded
                                  : Icons.auto_awesome_motion_rounded,
                            ),
                            label: Text(
                              _isSystemHomeContext
                                  ? 'Abrir empresas'
                                  : 'Abrir automações',
                            ),
                          ),
                          if (widget.onOpenBilling != null)
                            OutlinedButton.icon(
                              onPressed: widget.onOpenBilling,
                              icon: const Icon(Icons.credit_card_rounded),
                              label: const Text('Ver cobrança'),
                            ),
                          if (widget.onOpenClients != null && !_isSystemHomeContext)
                            OutlinedButton.icon(
                              onPressed: widget.onOpenClients,
                              icon: const Icon(Icons.business_center_rounded),
                              label: const Text('Abrir empresas'),
                            ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            left,
                            const SizedBox(height: AppSpacing.lg),
                            actions,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: AppSpacing.lg),
                          actions,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    AppMetricCard(
                      label: 'IA do chatbot',
                      value: _isSystemHomeContext
                          ? 'Interna'
                          : (settings.aiEnabled ? 'Ativa' : 'Desligada'),
                      helper: _isSystemHomeContext
                          ? 'A conta do sistema não responde clientes diretamente'
                          : 'Modelo principal: ${settings.geminiModel}',
                      icon: Icons.smart_toy_rounded,
                      accent: settings.aiEnabled
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    AppMetricCard(
                      label: 'Plano atual',
                      value: _settingsPlanLabel(subscription.plan),
                      helper: _settingsStatusLabel(subscription.status),
                      icon: Icons.workspace_premium_rounded,
                      accent: AppColors.primary,
                    ),
                    AppMetricCard(
                      label: 'Uso no período',
                      value: '${subscription.usedMessages}',
                      helper: _isSystemHomeContext
                          ? 'Uso não se aplica à conta interna'
                          : 'de ${subscription.monthlyMessageLimit} mensagens previstas',
                      icon: Icons.forum_rounded,
                      accent: AppColors.info,
                    ),
                    AppMetricCard(
                      label: 'Modo de depuração',
                      value: settings.debugMode ? 'Ligado' : 'Desligado',
                      helper: settings.debugMode
                          ? 'Prompts e respostas estão sendo registrados com segurança'
                          : 'Ative só quando precisar investigar comportamento',
                      icon: Icons.bug_report_rounded,
                      accent: settings.debugMode
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1120;
                    final left = _AiControlCard(
                      settings: settings,
                      savingAi: _savingAi,
                      onToggleAi: _isSystemHomeContext
                          ? null
                          : (value) => _toggleAi(value),
                    );
                    final right = _CompanySummaryCard(
                      tenantId: _tenantId,
                      settings: settings,
                      subscription: subscription,
                    );

                    if (compact) {
                      return Column(
                        children: [
                          left,
                          const SizedBox(height: AppSpacing.md),
                          right,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: left),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 5, child: right),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsHubData {
  const _SettingsHubData({
    required this.settings,
    required this.subscription,
  });

  final TenantSettings settings;
  final SubscriptionInfo subscription;
}

class _AiControlCard extends StatelessWidget {
  const _AiControlCard({
    required this.settings,
    required this.savingAi,
    this.onToggleAi,
  });

  final TenantSettings settings;
  final bool savingAi;
  final ValueChanged<bool>? onToggleAi;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'Inteligência artificial',
            subtitle:
                'Controle se a IA está ativa agora e veja quais modelos estão apoiando as respostas do chatbot.',
            action: Tooltip(
              message: 'Quando a IA está desligada, o atendimento depende das automações e do atendimento humano.',
              child: Icon(
                Icons.info_outline_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: settings.aiEnabled
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: AppRadius.md,
                  ),
                  child: Icon(
                    settings.aiEnabled
                        ? Icons.auto_awesome_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: settings.aiEnabled
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.aiEnabled
                            ? 'A IA está pronta para responder'
                            : 'A IA está pausada no momento',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        settings.aiEnabled
                            ? 'Quando a automação não resolver, o chatbot pode responder com linguagem natural.'
                            : 'Enquanto estiver pausada, a experiência vai depender das automações e do atendimento humano.',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.aiEnabled,
                  onChanged: savingAi ? null : onToggleAi,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FieldSummary(
            label: 'Modelo principal',
            value: settings.geminiModel.isEmpty
                ? 'Não configurado'
                : settings.geminiModel,
          ),
          const SizedBox(height: AppSpacing.md),
          _FieldSummary(
            label: 'Modelos de apoio',
            value: settings.fallbackModels.isEmpty
                ? 'Nenhum modelo de apoio configurado'
                : settings.fallbackModels.join(', '),
          ),
        ],
      ),
    );
  }
}

class _CompanySummaryCard extends StatelessWidget {
  const _CompanySummaryCard({
    required this.tenantId,
    required this.settings,
    required this.subscription,
  });

  final String tenantId;
  final TenantSettings settings;
  final SubscriptionInfo subscription;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Resumo da empresa',
            subtitle:
                'Tenha clareza sobre o contexto ativo, o uso do plano e os detalhes principais da operação.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppStatusChip(
                label: 'Empresa: $tenantId',
                icon: Icons.apartment_rounded,
                backgroundColor: AppColors.surfaceAlt,
              ),
              AppStatusChip(
                label: _settingsPlanLabel(subscription.plan),
                icon: Icons.workspace_premium_rounded,
                backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                foregroundColor: AppColors.primarySoft,
              ),
              AppStatusChip(
                label: _settingsStatusLabel(subscription.status),
                icon: subscription.active
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                backgroundColor: subscription.active
                    ? AppColors.success.withValues(alpha: 0.16)
                    : AppColors.warning.withValues(alpha: 0.16),
                foregroundColor:
                    subscription.active ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _FieldSummary(
            label: 'Empresa exibida',
            value: settings.tenantName,
          ),
          const SizedBox(height: AppSpacing.md),
          _FieldSummary(
            label: 'Renovação prevista',
            value: subscription.renewalDate == null
                ? 'Sem data informada'
                : DateFormat('dd/MM/yyyy').format(subscription.renewalDate!),
          ),
          const SizedBox(height: AppSpacing.md),
          _FieldSummary(
            label: 'Mensagens disponíveis',
            value: subscription.monthlyMessageLimit <= 0
                ? 'Não se aplica'
                : '${subscription.remainingMessages} restantes neste ciclo',
          ),
        ],
      ),
    );
  }
}

class _FieldSummary extends StatelessWidget {
  const _FieldSummary({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSoft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
