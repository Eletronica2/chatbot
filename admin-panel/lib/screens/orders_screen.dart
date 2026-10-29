import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/orders_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';
import '../widgets/ui_kit.dart';

/// Pedidos — pedidos recebidos pelo WhatsApp, status e catálogo de produtos.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  static const double _kSplit = 1100;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _tab = 'orders';
  bool? _enabled;
  bool _toggling = false;

  List<StoreOrder> _orders = const [];
  bool _loadingOrders = true;
  String? _ordersError;
  String _filter = 'active';
  StoreOrder? _selected;
  bool _loadingDetail = false;
  bool _compactDetailOpen = false;
  bool _notify = true;
  String? _updatingTo;
  String? _detailMessage;
  final TextEditingController _feeCtrl = TextEditingController();
  bool _sendingFee = false;
  Timer? _poll;

  List<CatalogCategory> _categories = const [];
  List<CatalogProduct> _products = const [];
  bool _loadingCatalog = false;
  String? _catalogError;

  bool get _canManageCatalog => authService.capabilities.canManageCatalog;
  bool get _canUpdate => authService.capabilities.canUpdateOrders;

  @override
  void initState() {
    super.initState();
    _loadEnabled();
    _reloadOrders();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _tab == 'orders') _reloadOrders(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEnabled() async {
    try {
      final enabled = await ordersService.fetchOrdersEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final tenantId = authService.tenantId;
    if (tenantId == null) return;
    setState(() => _toggling = true);
    try {
      final enabled = await ordersService.setOrdersEnabled(tenantId, value);
      if (!mounted) return;
      setState(() => _enabled = enabled);
      _snack(enabled
          ? 'Pedidos ativado: a IA passa a registrar pedidos confirmados pelo cliente.'
          : 'Pedidos desativado: o atendimento volta ao fluxo normal.');
    } catch (e) {
      _snack('Não foi possível alterar: $e');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _reloadOrders({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingOrders = true;
        _ordersError = null;
      });
    }
    try {
      final list = await ordersService.listOrders(
        status: _filter == 'active' || _filter == 'all' ? null : _filter,
        activeOnly: _filter == 'active',
      );
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loadingOrders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOrders = false;
        if (!silent) _ordersError = 'Não foi possível carregar os pedidos.';
      });
    }
  }

  Future<void> _openOrder(StoreOrder order) async {
    setState(() {
      _selected = order;
      _loadingDetail = true;
      _compactDetailOpen = true;
      _detailMessage = null;
    });
    try {
      final detail = await ordersService.getOrder(order.id);
      if (mounted) setState(() => _selected = detail);
    } catch (e) {
      if (mounted) setState(() => _detailMessage = 'Erro ao carregar o pedido: $e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _changeStatus(StoreOrder order, String target) async {
    if (target == 'cancelado') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: Text('Cancelar pedido #${order.orderNumber}?',
              style: const TextStyle(color: AppColors.text)),
          content: const Text('O pedido será encerrado como Cancelado.',
              style: TextStyle(color: AppColors.textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar pedido', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _updatingTo = target;
      _detailMessage = null;
    });
    try {
      final (updated, notification) =
          await ordersService.updateStatus(order.id, target, notify: _notify);
      if (!mounted) return;
      setState(() {
        _selected = updated;
        _detailMessage = 'Status: ${updated.statusLabel}. '
            '${kNotificationLabels[notification] ?? notification}';
      });
      await _reloadOrders(silent: true);
    } catch (e) {
      if (mounted) setState(() => _detailMessage = 'Não foi possível atualizar: $e');
    } finally {
      if (mounted) setState(() => _updatingTo = null);
    }
  }

  Future<void> _sendDeliveryFee(StoreOrder order) async {
    final cents = parseMoney(_feeCtrl.text);
    if (cents == null) {
      setState(() => _detailMessage = 'Informe a taxa de entrega (ex.: 8,00).');
      return;
    }
    setState(() {
      _sendingFee = true;
      _detailMessage = null;
    });
    try {
      final (updated, notification) =
          await ordersService.setDeliveryFee(order.id, cents, notify: _notify);
      if (!mounted) return;
      _feeCtrl.clear();
      setState(() {
        _selected = updated;
        _detailMessage = 'Total final ${formatMoney(updated.totalCents)} enviado para o cliente aceitar. '
            '${kNotificationLabels[notification] ?? notification}';
      });
      await _reloadOrders(silent: true);
    } catch (e) {
      if (mounted) setState(() => _detailMessage = 'Não foi possível enviar a taxa: $e');
    } finally {
      if (mounted) setState(() => _sendingFee = false);
    }
  }

  Future<void> _reloadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final results = await Future.wait([ordersService.listCategories(), ordersService.listProducts()]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<CatalogCategory>;
        _products = results[1] as List<CatalogProduct>;
        _loadingCatalog = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _catalogError = 'Não foi possível carregar o catálogo.';
      });
    }
  }

  void _selectTab(String tab) {
    setState(() => _tab = tab);
    if (tab == 'catalog' && _products.isEmpty) _reloadCatalog();
    if (tab == 'orders') _reloadOrders(silent: true);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(child: _tab == 'orders' ? _buildOrdersTab() : _buildCatalogTab()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final enabled = _enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PremiumFilterChip(
                label: 'Pedidos',
                icon: Icons.receipt_long_rounded,
                selected: _tab == 'orders',
                onTap: () => _selectTab('orders'),
              ),
              if (_canManageCatalog)
                PremiumFilterChip(
                  label: 'Catálogo',
                  icon: Icons.restaurant_menu_rounded,
                  selected: _tab == 'catalog',
                  onTap: () => _selectTab('catalog'),
                ),
              if (enabled != null && !_canManageCatalog)
                AppBadge(
                  label: enabled ? 'Pedidos ativo' : 'Pedidos desativado',
                  tone: enabled ? AppBadgeTone.success : AppBadgeTone.warning,
                ),
            ],
          ),
          if (_canManageCatalog && enabled != null) ...[
            const SizedBox(height: 10),
            PremiumSwitchRow(
              title: 'Módulo Pedidos',
              subtitle: enabled
                  ? 'Ativo: a IA identifica a intenção de compra, monta o pedido com o catálogo e só registra após o cliente confirmar.'
                  : 'Desativado: nenhum pedido é registrado pela IA; o atendimento segue o fluxo atual.',
              value: enabled,
              icon: Icons.shopping_bag_rounded,
              loading: _toggling,
              onChanged: _toggling ? null : _toggleEnabled,
            ),
          ],
        ],
      ),
    );
  }

  // ── Pedidos ─────────────────────────────────────────────────────────────────

  Widget _buildOrdersTab() {
    final split = MediaQuery.sizeOf(context).width >= OrdersScreen._kSplit;
    if (split) {
      return Row(
        children: [
          SizedBox(width: 380, child: _buildOrderList()),
          Container(width: 1, color: AppColors.divider),
          Expanded(child: _buildOrderDetail(showBack: false)),
        ],
      );
    }
    if (_compactDetailOpen && _selected != null) return _buildOrderDetail(showBack: true);
    return _buildOrderList();
  }

  Widget _buildOrderList() {
    final filters = <(String, String)>[
      ('active', 'Em andamento'),
      ('all', 'Todos'),
      ...kOrderStatusLabels.entries.map((e) => (e.key, e.value)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Pedidos',
                    style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Atualizar',
                visualDensity: VisualDensity.compact,
                onPressed: _reloadOrders,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (value, label) in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PremiumFilterChip(
                    label: label,
                    selected: _filter == value,
                    onTap: () {
                      setState(() => _filter = value);
                      _reloadOrders();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: _buildOrderListBody()),
      ],
    );
  }

  Widget _buildOrderListBody() {
    if (_loadingOrders) return const Center(child: CircularProgressIndicator());
    if (_ordersError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: _ordersError!,
        message: 'Verifique a conexão e tente novamente.',
        action: OutlinedButton(onPressed: _reloadOrders, child: const Text('Tentar novamente')),
      );
    }
    if (_orders.isEmpty) {
      return PremiumEmptyPanel(
        icon: Icons.receipt_long_outlined,
        title: 'Nenhum pedido aqui',
        description: _enabled == true
            ? 'Os pedidos confirmados pelos clientes no WhatsApp aparecem aqui automaticamente.'
            : 'Ative o módulo Pedidos para a IA registrar pedidos confirmados pelos clientes.',
        accent: AppColors.primary,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        final selected = order.id == _selected?.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openOrder(order),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: AppMotion.hoverOf(context),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryMuted : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.primary.withValues(alpha: 0.45) : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      order.isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${order.orderNumber} · ${order.customerName.isEmpty ? order.customerPhone : order.customerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${order.totalPending ? '${formatMoney(order.subtotalCents)} + taxa' : formatMoney(order.totalCents)} · ${order.itemCount} '
                            '${order.itemCount == 1 ? 'item' : 'itens'} · ${_time(order.createdAt)}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: order.status, label: order.statusLabel),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderDetail({required bool showBack}) {
    final order = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _compactDetailOpen = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Voltar'),
            ),
          ),
        Expanded(
          child: order == null
              ? const Center(
                  child: Text('Selecione um pedido para ver os detalhes.',
                      style: TextStyle(color: AppColors.textMuted)))
              : _buildOrderDetailBody(order),
        ),
      ],
    );
  }

  Widget _buildOrderDetailBody(StoreOrder order) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Pedido #${order.orderNumber}',
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (_loadingDetail)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                _StatusBadge(status: order.status, label: order.statusLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text('Recebido em ${_time(order.createdAt)} · ${order.source == 'whatsapp' ? 'WhatsApp' : order.source}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            if (_detailMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(_detailMessage!, style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 16),
            AppPanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.person_outline_rounded, 'Cliente',
                      order.customerName.isEmpty ? '—' : order.customerName),
                  _infoRow(Icons.phone_rounded, 'WhatsApp', '+${order.customerPhone}'),
                  _infoRow(order.isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                      'Atendimento', order.isDelivery ? 'Entrega' : 'Retirada na loja'),
                  if (order.isDelivery) _infoRow(Icons.place_outlined, 'Endereço', order.address),
                  if (order.notes.isNotEmpty) _infoRow(Icons.notes_rounded, 'Observações', order.notes),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppPanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Itens',
                      style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity}x ${item.productName}'
                              '${item.variantName.isEmpty ? '' : ' (${item.variantName})'}',
                              style: const TextStyle(color: AppColors.text, fontSize: 13),
                            ),
                          ),
                          Text(formatMoney(item.lineTotalCents),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                  const Divider(color: AppColors.border),
                  if (order.isDelivery) ...[
                    _valueRow('Subtotal dos produtos', formatMoney(order.subtotalCents)),
                    _valueRow('Taxa de entrega',
                        order.deliveryFeeCents == null ? 'a confirmar pela loja' : formatMoney(order.deliveryFeeCents!)),
                  ],
                  _valueRow(order.isDelivery ? 'Total final' : 'Total',
                      order.totalPending ? 'pendente' : formatMoney(order.totalCents),
                      strong: true),
                ],
              ),
            ),
            if (_canUpdate && (order.status == 'aguardando_loja' || order.status == 'aguardando_cliente')) ...[
              const SizedBox(height: 16),
              Text(
                order.status == 'aguardando_loja'
                    ? 'Informe a taxa de entrega'
                    : 'Aguardando o cliente aceitar o total final (pode corrigir a taxa)',
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _feeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Taxa', prefixText: 'R\$ ', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PremiumAccentButton(
                    label: _sendingFee ? 'Enviando…' : 'Enviar total ao cliente',
                    icon: _sendingFee ? null : Icons.send_rounded,
                    onPressed: _sendingFee ? null : () => _sendDeliveryFee(order),
                    dense: true,
                  ),
                ],
              ),
            ],
            if (_canUpdate && !order.isClosed) ...[
              const SizedBox(height: 16),
              const Text('Atualizar status',
                  style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final next in order.allowedNext)
                    next == 'cancelado'
                        ? OutlinedButton.icon(
                            onPressed: _updatingTo != null ? null : () => _changeStatus(order, next),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Cancelar pedido'),
                          )
                        : PremiumAccentButton(
                            label: _updatingTo == next ? 'Atualizando…' : kOrderStatusLabels[next] ?? next,
                            icon: _updatingTo == next ? null : Icons.arrow_forward_rounded,
                            onPressed: _updatingTo != null ? null : () => _changeStatus(order, next),
                            dense: true,
                          ),
                ],
              ),
              CheckboxListTile(
                value: _notify,
                onChanged: (v) => setState(() => _notify = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Avisar o cliente pelo WhatsApp',
                    style: TextStyle(color: AppColors.text, fontSize: 13)),
                subtitle: const Text(
                    'Enviado como mensagem se o cliente falou com a loja nas últimas 24h; fora dessa janela, só com modelo aprovado.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Histórico',
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final entry in order.history.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.circle, size: 8, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.toLabel,
                              style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              _time(entry.createdAt),
                              entry.actorType == 'assistant'
                                  ? 'Assistente WhatsApp'
                                  : (entry.actorName.isEmpty ? 'Loja' : entry.actorName),
                              if ((kNotificationLabels[entry.notificationStatus] ?? '').isNotEmpty)
                                kNotificationLabels[entry.notificationStatus]!,
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          if (entry.note.isNotEmpty && entry.note != 'Pedido criado')
                            Text(entry.note, style: const TextStyle(color: AppColors.textSoft, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _valueRow(String label, String value, {bool strong = false}) {
    final style = TextStyle(
      color: AppColors.text,
      fontSize: strong ? 15 : 13,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(child: SelectableText(value, style: const TextStyle(color: AppColors.text, fontSize: 13))),
        ],
      ),
    );
  }

  // ── Catálogo ────────────────────────────────────────────────────────────────

  Widget _buildCatalogTab() {
    if (_loadingCatalog && _products.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_catalogError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: _catalogError!,
        message: 'Verifique a conexão e tente novamente.',
        action: OutlinedButton(onPressed: _reloadCatalog, child: const Text('Tentar novamente')),
      );
    }
    final groups = <String, List<CatalogProduct>>{};
    for (final category in _categories) {
      groups[category.name] = <CatalogProduct>[];
    }
    for (final product in _products) {
      groups.putIfAbsent(product.categoryName.isEmpty ? 'Sem categoria' : product.categoryName, () => []).add(product);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Produtos e preços usados pela IA para montar os pedidos.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            OutlinedButton.icon(
              onPressed: _createCategory,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('Categoria'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _editProduct(null),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Produto'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_products.isEmpty && _categories.isEmpty)
          const PremiumEmptyPanel(
            icon: Icons.restaurant_menu_rounded,
            title: 'Catálogo vazio',
            description: 'Cadastre categorias e produtos com preço (ou opções, como tamanhos) para a IA montar pedidos.',
            accent: AppColors.primary,
          ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(entry.key,
                      style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (entry.value.isEmpty)
                  TextButton(
                    onPressed: () => _deleteCategory(entry.key),
                    child: const Text('Remover categoria', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
              ],
            ),
          ),
          AppTableSurface(
            child: Column(
              children: [
                if (entry.value.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Nenhum produto nesta categoria.',
                        style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                  ),
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.border),
                  _productRow(entry.value[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _productRow(CatalogProduct product) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: TextStyle(
                      color: product.available ? AppColors.text : AppColors.textSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(product.priceLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Text(product.available ? 'Disponível' : 'Indisponível',
              style: TextStyle(color: product.available ? AppColors.success : AppColors.warning, fontSize: 11)),
          Switch(value: product.available, onChanged: (v) => _setAvailability(product, v)),
          IconButton(
            tooltip: 'Editar',
            onPressed: () => _editProduct(product),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: () => _deleteProduct(product),
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Future<void> _setAvailability(CatalogProduct product, bool available) async {
    try {
      await ordersService.setAvailability(product.id, available);
      await _reloadCatalog();
    } catch (e) {
      _snack('Não foi possível alterar: $e');
    }
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialogFrame(
        title: 'Nova categoria',
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Criar')),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome (ex.: Pizzas, Bebidas)'),
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await ordersService.createCategory(name);
      await _reloadCatalog();
    } catch (e) {
      _snack('Não foi possível criar: $e');
    }
  }

  Future<void> _deleteCategory(String name) async {
    final category = _categories.where((c) => c.name == name).firstOrNull;
    if (category == null) return;
    try {
      await ordersService.deleteCategory(category.id);
      await _reloadCatalog();
    } catch (e) {
      _snack('Não foi possível remover: $e');
    }
  }

  Future<void> _deleteProduct(CatalogProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Excluir produto', style: TextStyle(color: AppColors.text)),
        content: Text('Excluir "${product.name}"? Pedidos antigos continuam com o item registrado.',
            style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ordersService.deleteProduct(product.id);
      await _reloadCatalog();
    } catch (e) {
      _snack('Não foi possível excluir: $e');
    }
  }

  Future<void> _editProduct(CatalogProduct? product) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(product: product, categories: _categories),
    );
    if (saved == true) await _reloadCatalog();
  }

  static String _time(String iso) {
    if (iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z');
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'novo' || 'aguardando_loja' || 'aguardando_cliente' => AppBadgeTone.warning,
      'confirmado' || 'em_preparo' => AppBadgeTone.primary,
      'saiu_para_entrega' || 'pronto_para_retirada' => AppBadgeTone.ai,
      'entregue' || 'retirado' => AppBadgeTone.success,
      'cancelado' => AppBadgeTone.danger,
      _ => AppBadgeTone.neutral,
    };
    return AppBadge(label: label.isEmpty ? (kOrderStatusLabels[status] ?? status) : label, tone: tone);
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.product, required this.categories});

  final CatalogProduct? product;
  final List<CatalogCategory> categories;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  final List<(TextEditingController, TextEditingController)> _variants = [];
  int? _categoryId;
  bool _available = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _price = TextEditingController(
        text: product?.priceCents == null ? '' : formatMoney(product!.priceCents!).replaceAll('R\$ ', ''));
    for (final variant in product?.variants ?? const <ProductVariant>[]) {
      _variants.add((
        TextEditingController(text: variant.name),
        TextEditingController(text: formatMoney(variant.priceCents).replaceAll('R\$ ', '')),
      ));
    }
    _categoryId = product?.categoryId ?? (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _available = product?.available ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    for (final (name, price) in _variants) {
      name.dispose();
      price.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do produto.');
      return;
    }
    final variants = <ProductVariant>[];
    for (final (variantName, variantPrice) in _variants) {
      if (variantName.text.trim().isEmpty && variantPrice.text.trim().isEmpty) continue;
      final cents = parseMoney(variantPrice.text);
      if (variantName.text.trim().isEmpty || cents == null) {
        setState(() => _error = 'Cada opção precisa de nome e preço (ex.: Grande — 62,90).');
        return;
      }
      variants.add(ProductVariant(name: variantName.text.trim(), priceCents: cents));
    }
    final price = parseMoney(_price.text);
    if (variants.isEmpty && price == null) {
      setState(() => _error = 'Informe o preço ou adicione opções com preço.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ordersService.saveProduct(
        id: widget.product?.id,
        name: name,
        description: _description.text.trim(),
        categoryId: _categoryId,
        priceCents: price,
        variants: variants,
        available: _available,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      title: widget.product == null ? 'Novo produto' : 'Editar produto',
      width: 520,
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        const SizedBox(width: 8),
        PremiumAccentButton(
          label: _saving ? 'Salvando…' : 'Salvar',
          icon: _saving ? null : Icons.save_rounded,
          onPressed: _saving ? null : _save,
          dense: true,
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome *')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Sem categoria')),
                  for (final category in widget.categories)
                    DropdownMenuItem<int?>(value: category.id, child: Text(category.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
              ),
              const SizedBox(height: 12),
              if (_variants.isEmpty)
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço *', prefixText: 'R\$ '),
                ),
              const SizedBox(height: 12),
              Text(
                _variants.isEmpty
                    ? 'Opções (tamanhos, sabores) — opcional; cada opção tem o próprio preço.'
                    : 'Opções — o cliente escolhe uma; o preço vem da opção.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < _variants.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _variants[i].$1,
                          decoration: const InputDecoration(labelText: 'Opção', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _variants[i].$2,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ ', isDense: true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover opção',
                        onPressed: () => setState(() {
                          final (name, price) = _variants.removeAt(i);
                          name.dispose();
                          price.dispose();
                        }),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _variants.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Adicionar opção'),
                ),
              ),
              SwitchListTile(
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Disponível para pedidos', style: TextStyle(color: AppColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
