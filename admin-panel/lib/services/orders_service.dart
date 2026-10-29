import 'api_client.dart';

String formatMoney(int cents) {
  final reais = (cents ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buffer.write('.');
    buffer.write(reais[i]);
  }
  return 'R\$ $buffer,${(cents % 100).toString().padLeft(2, '0')}';
}

int? parseMoney(String text) {
  final cleaned = text.replaceAll('R\$', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  final normalized = cleaned.contains(',')
      ? cleaned.replaceAll('.', '').replaceAll(',', '.')
      : cleaned;
  final value = double.tryParse(normalized);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

const Map<String, String> kOrderStatusLabels = <String, String>{
  'aguardando_loja': 'Aguardando confirmação da loja',
  'aguardando_cliente': 'Aguardando aceite do cliente',
  'novo': 'Novo',
  'confirmado': 'Confirmado',
  'em_preparo': 'Em preparo',
  'saiu_para_entrega': 'Saiu para entrega',
  'pronto_para_retirada': 'Pronto para retirada',
  'entregue': 'Entregue',
  'retirado': 'Retirado',
  'cancelado': 'Cancelado',
};

const Map<String, String> kNotificationLabels = <String, String>{
  'sent': 'Cliente notificado',
  'sent_template': 'Notificado por modelo',
  'skipped_outside_window': 'Não notificado (fora da janela de 24h)',
  'blocked_billing': 'Não notificado (bloqueado pelo billing)',
  'failed': 'Falha ao notificar',
  'not_requested': 'Sem notificação',
  'not_applicable': '',
};

class OrderItem {
  const OrderItem({
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  final String productName;
  final String variantName;
  final int quantity;
  final int unitPriceCents;
  final int lineTotalCents;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        productName: json['product_name'] as String? ?? '',
        variantName: json['variant_name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPriceCents: (json['unit_price_cents'] as num?)?.toInt() ?? 0,
        lineTotalCents: (json['line_total_cents'] as num?)?.toInt() ?? 0,
      );
}

class OrderHistoryEntry {
  const OrderHistoryEntry({
    required this.toStatus,
    required this.toLabel,
    required this.actorType,
    required this.actorName,
    required this.note,
    required this.notificationStatus,
    required this.createdAt,
  });

  final String toStatus;
  final String toLabel;
  final String actorType;
  final String actorName;
  final String note;
  final String notificationStatus;
  final String createdAt;

  factory OrderHistoryEntry.fromJson(Map<String, dynamic> json) =>
      OrderHistoryEntry(
        toStatus: json['to_status'] as String? ?? '',
        toLabel: json['to_label'] as String? ?? '',
        actorType: json['actor_type'] as String? ?? '',
        actorName: json['actor_name'] as String? ?? '',
        note: json['note'] as String? ?? '',
        notificationStatus: json['notification_status'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class StoreOrder {
  const StoreOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.allowedNext,
    required this.customerName,
    required this.customerPhone,
    required this.fulfillment,
    required this.address,
    required this.notes,
    required this.totalCents,
    required this.subtotalCents,
    required this.deliveryFeeCents,
    required this.totalPending,
    required this.itemCount,
    required this.source,
    required this.createdAt,
    this.items = const <OrderItem>[],
    this.history = const <OrderHistoryEntry>[],
  });

  final int id;
  final int orderNumber;
  final String status;
  final String statusLabel;
  final List<String> allowedNext;
  final String customerName;
  final String customerPhone;
  final String fulfillment;
  final String address;
  final String notes;
  final int totalCents;
  final int subtotalCents;
  final int? deliveryFeeCents;
  final bool totalPending;
  final int itemCount;
  final String source;
  final String createdAt;
  final List<OrderItem> items;
  final List<OrderHistoryEntry> history;

  bool get isDelivery => fulfillment == 'entrega';
  bool get isClosed => allowedNext.isEmpty;

  factory StoreOrder.fromJson(Map<String, dynamic> json) => StoreOrder(
        id: (json['id'] as num).toInt(),
        orderNumber: (json['order_number'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'novo',
        statusLabel: json['status_label'] as String? ?? '',
        allowedNext: ((json['allowed_next'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        customerName: json['customer_name'] as String? ?? '',
        customerPhone: json['customer_phone'] as String? ?? '',
        fulfillment: json['fulfillment'] as String? ?? 'retirada',
        address: json['address'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        totalCents: (json['total_cents'] as num?)?.toInt() ?? 0,
        subtotalCents: (json['subtotal_cents'] as num?)?.toInt() ?? 0,
        deliveryFeeCents: (json['delivery_fee_cents'] as num?)?.toInt(),
        totalPending: json['total_pending'] as bool? ?? false,
        itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
        source: json['source'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        items: ((json['items'] as List?) ?? const [])
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: ((json['history'] as List?) ?? const [])
            .map((e) => OrderHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProductVariant {
  const ProductVariant({required this.name, required this.priceCents});

  final String name;
  final int priceCents;

  Map<String, dynamic> toJson() => {'name': name, 'price_cents': priceCents};

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        name: json['name'] as String? ?? '',
        priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      );
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.active,
    required this.productCount,
  });

  final int id;
  final String name;
  final bool active;
  final int productCount;

  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        productCount: (json['product_count'] as num?)?.toInt() ?? 0,
      );
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.priceCents,
    required this.variants,
    required this.available,
  });

  final int id;
  final String name;
  final String description;
  final int? categoryId;
  final String categoryName;
  final int? priceCents;
  final List<ProductVariant> variants;
  final bool available;

  String get priceLabel {
    if (variants.isNotEmpty) {
      return variants
          .map((v) => '${v.name} ${formatMoney(v.priceCents)}')
          .join(' · ');
    }
    return priceCents == null ? '—' : formatMoney(priceCents!);
  }

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        categoryId: (json['category_id'] as num?)?.toInt(),
        categoryName: json['category_name'] as String? ?? '',
        priceCents: (json['price_cents'] as num?)?.toInt(),
        variants: ((json['variants'] as List?) ?? const [])
            .map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
            .toList(),
        available: json['available'] as bool? ?? true,
      );
}

class OrdersService {
  const OrdersService();

  Future<bool> fetchOrdersEnabled() async {
    final data = await apiClient.get('/api/v1/orders/meta') as Map<String, dynamic>;
    return data['orders_enabled'] as bool? ?? false;
  }

  Future<bool> setOrdersEnabled(String tenantId, bool enabled) async {
    final data = await apiClient.patch(
      '/api/v1/tenants/$tenantId/settings',
      body: {'orders_enabled': enabled},
    ) as Map<String, dynamic>;
    return data['orders_enabled'] as bool? ?? enabled;
  }

  Future<List<StoreOrder>> listOrders({String? status, bool activeOnly = false}) async {
    final params = <String>['limit=200'];
    if (status != null) params.add('status=$status');
    if (activeOnly) params.add('active_only=true');
    final data = await apiClient.get('/api/v1/orders?${params.join('&')}') as List<dynamic>;
    return data.map((e) => StoreOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StoreOrder> getOrder(int id) async {
    final data = await apiClient.get('/api/v1/orders/$id') as Map<String, dynamic>;
    return StoreOrder.fromJson(data);
  }

  Future<(StoreOrder, String)> updateStatus(
    int id,
    String status, {
    required bool notify,
    String? note,
  }) async {
    final data = await apiClient.post(
      '/api/v1/orders/$id/status',
      body: {'status': status, 'notify': notify, if (note != null && note.isNotEmpty) 'note': note},
    ) as Map<String, dynamic>;
    return (
      StoreOrder.fromJson(data['order'] as Map<String, dynamic>),
      data['notification_status'] as String? ?? '',
    );
  }

  Future<(StoreOrder, String)> setDeliveryFee(int id, int feeCents, {required bool notify}) async {
    final data = await apiClient.post(
      '/api/v1/orders/$id/delivery-fee',
      body: {'fee_cents': feeCents, 'notify': notify},
    ) as Map<String, dynamic>;
    return (
      StoreOrder.fromJson(data['order'] as Map<String, dynamic>),
      data['notification_status'] as String? ?? '',
    );
  }

  Future<List<CatalogCategory>> listCategories() async {
    final data = await apiClient.get('/api/v1/catalog/categories') as List<dynamic>;
    return data.map((e) => CatalogCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createCategory(String name) async {
    await apiClient.post('/api/v1/catalog/categories', body: {'name': name});
  }

  Future<void> deleteCategory(int id) async {
    await apiClient.delete('/api/v1/catalog/categories/$id');
  }

  Future<List<CatalogProduct>> listProducts() async {
    final data = await apiClient.get('/api/v1/catalog/products') as List<dynamic>;
    return data.map((e) => CatalogProduct.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveProduct({
    int? id,
    required String name,
    required String description,
    required int? categoryId,
    required int? priceCents,
    required List<ProductVariant> variants,
    required bool available,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'description': description,
      'category_id': categoryId,
      'price_cents': variants.isEmpty ? priceCents : null,
      'variants': variants.map((v) => v.toJson()).toList(),
      'available': available,
    };
    if (id == null) {
      body.removeWhere((key, value) => value == null);
      await apiClient.post('/api/v1/catalog/products', body: body);
    } else {
      await apiClient.patch('/api/v1/catalog/products/$id', body: body);
    }
  }

  Future<void> setAvailability(int id, bool available) async {
    await apiClient.patch('/api/v1/catalog/products/$id', body: {'available': available});
  }

  Future<void> deleteProduct(int id) async {
    await apiClient.delete('/api/v1/catalog/products/$id');
  }
}

const ordersService = OrdersService();
