import 'dart:developer';

import '../models/subscription_info.dart';
import 'api_client.dart';

class SubscriptionService {
  SubscriptionService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<SubscriptionInfo> fetchSubscription(String tenantId) async {
    try {
      final data = await _apiClient.get('/api/v1/subscriptions/$tenantId');
      if (data is Map<String, dynamic>) {
        return SubscriptionInfo.fromJson(data);
      }
    } catch (err) {
      log('fetchSubscription fallback: $err');
    }
    return SubscriptionInfo(
      tenantId: tenantId,
      plan: 'starter',
      status: 'active',
      renewalDate: null,
      monthlyMessageLimit: 1000,
      active: true,
      usedMessages: 0,
      remainingMessages: 1000,
    );
  }

  Future<SubscriptionInfo> updateSubscription({
    required String tenantId,
    String? plan,
    String? status,
    int? monthlyMessageLimit,
  }) async {
    final body = <String, dynamic>{
      if (plan != null) 'plan': plan,
      if (status != null) 'status': status,
      if (monthlyMessageLimit != null) 'monthly_message_limit': monthlyMessageLimit,
    };
    final data = await _apiClient.patch('/api/v1/subscriptions/$tenantId', body: body);
    return SubscriptionInfo.fromJson(data as Map<String, dynamic>);
  }
}

final subscriptionService = SubscriptionService(apiClient: apiClient);
