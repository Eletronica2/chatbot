part of 'backoffice_screen.dart';

mixin _ClientesEmpresasUi on State<BackofficeScreen> {
  _BackofficeScreenState get _s => this as _BackofficeScreenState;

  Widget _buildTenantsOverviewCard() {
    final activeCount =
        _s._tenants.where((tenant) => tenant.status == 'active').length;
    final shown = _s._filteredTenants.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '$shown de ${_s._tenants.length} · $activeCount ativas',
        style: const TextStyle(color: _kSubtle, fontSize: 11, height: 1.3),
      ),
    );
  }

  Widget _buildTenantsPanel() {
    final homeTenantId = authService.homeTenantId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Empresas',
                          style: TextStyle(
                            color: _kText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Selecione para operar o tenant.',
                          style: TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _s._showCreateTenantDialog,
                    style: _s._fillAccent,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nova'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _s._searchCtrl,
                onChanged: _s._onSearchChanged,
                style: const TextStyle(color: _kText, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar empresa, identificador ou email',
                  hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _kMuted,
                    size: 18,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: _kInput,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kAccent),
                  ),
                ),
              ),
              _buildTenantsOverviewCard(),
            ],
          ),
        ),
        Expanded(child: _buildTenantsMasterBody(homeTenantId)),
      ],
    );
  }

  Widget _buildTenantsMasterBody(String? homeTenantId) {
    if (_s._loadingTenants) {
      return const _ClientesSkeletonList();
    }
    if (_s._tenantsError != null) {
      return _ClientesInlineError(
        message: _s._tenantsError!,
        onRetry: _s._loadTenants,
      );
    }
    if (_s._tenants.isEmpty) {
      return const _EmptyCardState(
        icon: Icons.apartment_outlined,
        title: 'Nenhuma empresa',
        message: 'Cadastre a primeira empresa para começar a operar o SaaS.',
      );
    }
    if (_s._filteredTenants.isEmpty) {
      return const _EmptyCardState(
        icon: Icons.search_off_rounded,
        title: 'Nenhuma empresa encontrada',
        message: 'Ajuste a busca. Ela filtra nome, identificador e e-mail.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: _s._filteredTenants.length,
      itemBuilder: (_, index) {
        final tenant = _s._filteredTenants[index];
        final selected = tenant.tenantId == _s._selectedTenant?.tenantId;
        final isHomeTenant = homeTenantId != null &&
            homeTenantId.isNotEmpty &&
            tenant.tenantId == homeTenantId;
        return _TenantMasterTile(
          tenant: tenant,
          selected: selected,
          isHomeTenant: isHomeTenant && authService.isSuperadmin,
          onTap: () => _s._selectTenant(tenant),
        );
      },
    );
  }

  Widget _buildDetailsPanel({bool showBack = false}) {
    final tenant = _s._selectedTenant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetailHeader(tenant, showBack: showBack),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.pageOf(context),
            switchInCurve: AppMotion.pageCurve,
            switchOutCurve: AppMotion.pageCurve,
            child: KeyedSubtree(
              key: ValueKey<String>(
                '${tenant?.tenantId ?? 'none'}|${_s._detailTab}|${_s._loadingDetails}|${_s._detailsError ?? ''}',
              ),
              child: _buildDetailBody(tenant),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailHeader(TenantAdminSummary? tenant, {required bool showBack}) {
    final subscription = _s._subscription;
    return Container(
      padding: EdgeInsets.fromLTRB(16, showBack ? 4 : 14, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            TextButton.icon(
              onPressed: () => setState(() => _s._compactDetailOpen = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Voltar'),
              style: TextButton.styleFrom(
                foregroundColor: _kText,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          if (tenant == null)
            const Text(
              'Detalhe da empresa',
              style: TextStyle(
                color: _kText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            Text(
              tenant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tenant.tenantId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_s._isSystemTenantContext)
                  const _Tag(
                    label: 'Sistema',
                    background: Color(0xFF1E293B),
                    foreground: Color(0xFFBFDBFE),
                  ),
                _Tag(
                  label: _planLabel(subscription?.plan ?? tenant.plan),
                  background: const Color(0xFF163044),
                  foreground: _kAccentSoft,
                ),
                _Tag(
                  label: _statusLabel(subscription?.status ?? tenant.status),
                  background: _statusPositive(subscription?.status ?? tenant.status)
                      ? const Color(0xFF064E3B)
                      : const Color(0xFF7F1D1D),
                  foreground: _statusPositive(subscription?.status ?? tenant.status)
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFFFCA5A5),
                ),
              ],
            ),
          ],
          if (tenant != null && !_s._isSystemTenantContext) ...[
            const SizedBox(height: 12),
            _buildDetailTabs(),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailTabs() {
    const tabs = <(String, String)>[
      ('resumo', 'Resumo'),
      ('assinatura', 'Assinatura'),
      ('whatsapp', 'Contas'),
      ('usuarios', 'Usuários'),
      ('automacoes', 'Automações'),
      ('auditoria', 'Auditoria'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _DetailTabChip(
                label: tab.$2,
                selected: _s._detailTab == tab.$1,
                onTap: () => setState(() => _s._detailTab = tab.$1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailBody(TenantAdminSummary? tenant) {
    if (tenant == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _EmptyCardState(
            icon: Icons.apartment_outlined,
            title: 'Selecione uma empresa',
            message: 'Escolha um item à esquerda para ver o detalhe operacional.',
          ),
        ),
      );
    }
    if (_s._loadingDetails) {
      return const _ClientesSkeletonDetail();
    }
    if (_s._detailsError != null) {
      return _ClientesInlineError(
        message: _s._detailsError!,
        onRetry: () => _s._selectTenant(tenant, openCompact: false),
      );
    }
    if (_s._isSystemTenantContext) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _DetailCard(
          title: 'Conta interna do sistema',
          subtitle: 'Contexto interno do painel SaaS.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tenant.name,
                style: const TextStyle(
                  color: _kText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta conta interna não consome plano, não usa contas WhatsApp e não possui automações próprias. Para visualizar ou editar automações, selecione uma empresa comercial na coluna da esquerda.',
                style: TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricBox(label: 'Conta interna', value: tenant.tenantId),
                  _MetricBox(
                    label: 'Criado em',
                    value: _s._formatDate(tenant.createdAt),
                  ),
                  const _MetricBox(
                    label: 'Tipo',
                    value: 'Administrador do sistema',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: _buildSelectedDetailSection(tenant),
    );
  }

  Widget _buildSelectedDetailSection(TenantAdminSummary tenant) {
    switch (_s._detailTab) {
      case 'assinatura':
        return _buildAssinaturaSection(tenant);
      case 'whatsapp':
        return _buildWhatsAppDetailSection();
      case 'usuarios':
        return _buildUsersSection();
      case 'automacoes':
        return _buildFlowsSection();
      case 'auditoria':
        return _buildAuditSection();
      case 'resumo':
      default:
        return _buildResumoSection(tenant);
    }
  }

  Widget _buildResumoSection(TenantAdminSummary tenant) {
    final subscription = _s._subscription;
    return _DetailCard(
      title: 'Resumo',
      subtitle: 'Dados cadastrais e consumo da empresa selecionada.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricBox(label: 'Empresa', value: tenant.name),
          _MetricBox(label: 'Identificação', value: tenant.tenantId),
          if (tenant.email.isNotEmpty)
            _MetricBox(label: 'E-mail', value: tenant.email),
          _MetricBox(
            label: 'Responsável',
            value: tenant.ownerEmail ?? 'Não informado',
          ),
          _MetricBox(
            label: 'Plano',
            value: _planLabel(subscription?.plan ?? tenant.plan),
          ),
          _MetricBox(
            label: 'Status',
            value: _statusLabel(subscription?.status ?? tenant.status),
          ),
          _MetricBox(
            label: 'Criado em',
            value: _s._formatDate(tenant.createdAt),
          ),
          _MetricBox(
            label: 'Atualizado em',
            value: _s._formatDate(tenant.updatedAt),
          ),
          if (subscription != null) ...[
            _MetricBox(
              label: 'Mensagens no ciclo',
              value: '${subscription.usedMessages} / ${subscription.monthlyMessageLimit}',
            ),
            _MetricBox(
              label: 'Renovação',
              value: _s._formatDate(subscription.renewalDate),
            ),
          ],
          _MetricBox(label: 'Usuários', value: '${_s._users.length}'),
          _MetricBox(label: 'Contas WhatsApp', value: '${_s._accounts.length}'),
          _MetricBox(label: 'Automações', value: '${_s._flows.length}'),
        ],
      ),
    );
  }

  Widget _buildAssinaturaSection(TenantAdminSummary tenant) {
    final subscription = _s._subscription;
    final usagePercent = subscription?.usagePercent ?? 0;
    final planIndex = _BackofficeScreenState._planOptions.indexOf(_s._planValue);
    final canDowngrade = planIndex > 0;
    final canUpgrade = _BackofficeScreenState._planOptions.contains(_s._planValue) &&
        planIndex < _BackofficeScreenState._planOptions.length - 1;

    return _DetailCard(
      title: 'Assinatura e cobrança',
      subtitle: 'Plano, situação, limite mensal e ciclo da assinatura desta empresa.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subscription != null && !subscription.active)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF3F1D1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7F1D1D)),
              ),
              child: const Text(
                'Esta empresa está bloqueada. O painel continua visível, mas edição e envio ficam limitados até a reativação.',
                style: TextStyle(color: Color(0xFFFECACA), fontSize: 12),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final fields = <Widget>[
                _DialogSelect(
                  label: 'Plano',
                  value: _s._planValue,
                  items: _BackofficeScreenState._planOptions,
                  labelBuilder: _planLabel,
                  onChanged: (value) => setState(() => _s._planValue = value),
                ),
                _DialogSelect(
                  label: 'Status',
                  value: _s._statusValue,
                  items: _BackofficeScreenState._statusOptions,
                  labelBuilder: _statusLabel,
                  onChanged: (value) => setState(() => _s._statusValue = value),
                ),
                _DialogField(
                  controller: _s._limitCtrl,
                  label: 'Limite mensal',
                  keyboardType: TextInputType.number,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                    const SizedBox(height: 12),
                    fields[2],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: canDowngrade ? () => _s._stepPlan(-1) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                label: const Text('Reduzir plano'),
              ),
              OutlinedButton.icon(
                onPressed: canUpgrade ? () => _s._stepPlan(1) : null,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Aumentar plano'),
              ),
              FilledButton.icon(
                onPressed: _s._savingPlan ? null : _s._savePlan,
                style: _s._fillAccent,
                icon: _s._savingPlan
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kOnAccent,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(_s._savingPlan ? 'Salvando...' : 'Salvar plano'),
              ),
            ],
          ),
          if (subscription != null) ...[
            const SizedBox(height: 16),
            Text(
              '${subscription.usedMessages} / ${subscription.monthlyMessageLimit} mensagens usadas',
              style: const TextStyle(
                color: _kText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: usagePercent,
                backgroundColor: _kInput,
                valueColor: AlwaysStoppedAnimation<Color>(
                  usagePercent >= 0.85 ? _kDanger : _kAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Renovação: ${_s._formatDate(subscription.renewalDate)}',
              style: const TextStyle(color: _kMuted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Restantes: ${subscription.remainingMessages}',
              style: const TextStyle(color: _kSubtle, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWhatsAppDetailSection() {
    return _DetailCard(
      title: 'Contas de WhatsApp',
      subtitle: 'Contas cadastradas nesta empresa. Status real: ativa ou inativa.',
      action: FilledButton.icon(
        onPressed: () => _s._showAccountDialog(),
        style: _s._fillAccent,
        icon: const Icon(Icons.add_link_rounded, size: 16),
        label: const Text('Nova conta'),
      ),
      child: _s._accounts.isEmpty
          ? const _EmptyCardState(
              icon: Icons.mark_chat_unread_outlined,
              title: 'Nenhuma conta configurada',
              message:
                  'Cadastre uma conta WhatsApp para conectar o número da empresa.',
            )
          : Column(
              children: _s._accounts.map((account) {
                final isUpdatingDefault =
                    _s._settingDefaultAccountKey == account.accountKey;
                return _WhatsAppAccountRow(
                  account: account,
                  updatingDefault: isUpdatingDefault,
                  onEdit: () => _s._showAccountDialog(account: account),
                  onSetDefault: account.isDefault || isUpdatingDefault
                      ? null
                      : () => _s._setDefaultAccount(account),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildUsersSection() {
    return _DetailCard(
      title: 'Usuários',
      subtitle: 'Usuários pertencentes à empresa selecionada.',
      action: FilledButton.icon(
        onPressed: _s._showInviteUserDialog,
        style: _s._fillAccent,
        icon: const Icon(Icons.person_add_alt_rounded, size: 16),
        label: const Text('Convidar'),
      ),
      child: _s._users.isEmpty
          ? const _EmptyCardState(
              icon: Icons.group_outlined,
              title: 'Nenhum usuário adicional',
              message:
                  'Convide usuários do time da empresa para acessarem o painel.',
            )
          : Column(
              children: _s._users.map((userItem) {
                final isResetting = _s._resettingUserId == userItem.userId;
                return _UserRow(
                  user: userItem,
                  resetting: isResetting,
                  onManage: () => _s._showEditUserDialog(userItem),
                  onReset: isResetting
                      ? null
                      : () => _s._generateResetForUser(userItem),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildFlowsSection() {
    return _DetailCard(
      title: 'Automações',
      subtitle: 'Visão contextual das automações desta empresa.',
      action: OutlinedButton.icon(
        onPressed: _s._openTenantFlows,
        style: OutlinedButton.styleFrom(
          foregroundColor: _kAccentSoft,
          side: const BorderSide(color: _kAccentSoft),
        ),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text('Abrir editor'),
      ),
      child: _s._flows.isEmpty
          ? const _EmptyCardState(
              icon: Icons.account_tree_outlined,
              title: 'Nenhuma automação',
              message: 'Esta empresa ainda não possui automações salvas.',
            )
          : Column(
              children: _s._flows.map((flow) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _kInput,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        color: AppColors.accentPurple,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              humanizeFlowName(flow.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              flow.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kSubtle,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        flow.startState?.isNotEmpty == true
                            ? flow.startState!
                            : 'Sem início',
                        style: const TextStyle(color: _kMuted, fontSize: 11),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildAuditSection() {
    final entries = _s._auditEntries.take(8).toList(growable: false);
    return _DetailCard(
      title: 'Auditoria recente',
      subtitle: 'Eventos administrativos reais desta empresa.',
      child: entries.isEmpty
          ? const _EmptyCardState(
              icon: Icons.history_toggle_off_rounded,
              title: 'Sem eventos recentes',
              message: 'Não há auditoria disponível para esta empresa.',
            )
          : Column(
              children: entries.map((entry) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kInput,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.summary,
                        style: const TextStyle(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.action} · ${entry.entityType}',
                        style: const TextStyle(color: _kMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.actorEmail ?? 'sistema'} · ${_s._formatDateTime(entry.createdAt)}',
                        style: const TextStyle(color: _kSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _TenantMasterTile extends StatelessWidget {
  const _TenantMasterTile({
    required this.tenant,
    required this.selected,
    required this.isHomeTenant,
    required this.onTap,
  });

  final TenantAdminSummary tenant;
  final bool selected;
  final bool isHomeTenant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: AppMotion.hoverOf(context),
            curve: AppMotion.hoverCurve,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryMuted : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? _kAccent.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kText,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tenant.tenantId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kSubtle, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _planLabel(tenant.plan),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _kMuted, fontSize: 11),
                      ),
                    ),
                    if (isHomeTenant) ...[
                      const _Tag(
                        label: 'Sistema',
                        background: Color(0xFF1E293B),
                        foreground: Color(0xFFBFDBFE),
                      ),
                      const SizedBox(width: 4),
                    ],
                    _Tag(
                      label: _statusLabel(tenant.status),
                      background: tenant.status == 'active'
                          ? const Color(0xFF064E3B)
                          : const Color(0xFF7F1D1D),
                      foreground: tenant.status == 'active'
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFFFCA5A5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTabChip extends StatelessWidget {
  const _DetailTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: AppMotion.hoverOf(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryMuted : const Color(0xFF111727),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _kAccent.withValues(alpha: 0.5) : _kBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _kAccentSoft : _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientesInlineError extends StatelessWidget {
  const _ClientesInlineError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kDanger, size: 28),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kText, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientesSkeletonList extends StatelessWidget {
  const _ClientesSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: _SkeletonBar(height: 64),
      ),
    );
  }
}

class _ClientesSkeletonDetail extends StatelessWidget {
  const _ClientesSkeletonDetail();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _SkeletonBar(height: 18, width: 220),
          SizedBox(height: 12),
          _SkeletonBar(height: 88),
          SizedBox(height: 12),
          _SkeletonBar(height: 88),
          SizedBox(height: 12),
          _SkeletonBar(height: 88),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _WhatsAppAccountRow extends StatelessWidget {
  const _WhatsAppAccountRow({
    required this.account,
    required this.updatingDefault,
    required this.onEdit,
    required this.onSetDefault,
  });

  final WhatsAppAccountModel account;
  final bool updatingDefault;
  final VoidCallback onEdit;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final active = account.status == 'active';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: account.isDefault
              ? _kAccent.withValues(alpha: 0.35)
              : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Tag(
                label: _statusLabel(account.status),
                background:
                    active ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                foreground:
                    active ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
              ),
              if (account.isDefault) ...[
                const SizedBox(width: 6),
                const _Tag(
                  label: 'Principal',
                  background: Color(0xFF163044),
                  foreground: _kAccentSoft,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            account.displayPhoneNumber,
            style: const TextStyle(color: _kText, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'phone_number_id: ${account.phoneNumberId}',
            style: const TextStyle(color: _kSubtle, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            account.maskedAccessToken == null
                ? (account.hasAccessToken ? 'Token salvo' : 'Token não informado')
                : 'Token: ${account.maskedAccessToken}',
            style: const TextStyle(color: _kSubtle, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
              ),
              OutlinedButton.icon(
                onPressed: onSetDefault,
                icon: updatingDefault
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.star_outline_rounded, size: 16),
                label: Text(
                  account.isDefault ? 'Conta principal' : 'Definir principal',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.resetting,
    required this.onManage,
    required this.onReset,
  });

  final TenantUserModel user;
  final bool resetting;
  final VoidCallback onManage;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _Tag(
                label: _roleLabel(user.role),
                background: const Color(0xFF163044),
                foreground: _kAccentSoft,
              ),
              const SizedBox(width: 6),
              _Tag(
                label: _statusLabel(user.status),
                background: user.status == 'active'
                    ? const Color(0xFF064E3B)
                    : const Color(0xFF7F1D1D),
                foreground: user.status == 'active'
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFFFCA5A5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Último acesso: ${user.lastLoginAt == null ? 'Não informado' : DateFormat('dd/MM/yyyy').format(user.lastLoginAt!.toLocal())}',
            style: const TextStyle(color: _kSubtle, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                label: const Text('Gerenciar'),
              ),
              OutlinedButton.icon(
                onPressed: onReset,
                icon: resetting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset_rounded, size: 16),
                label: const Text('Redefinir senha'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
