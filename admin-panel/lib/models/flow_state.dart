class FlowStateModel {
  FlowStateModel({
    required this.flowName,
    required this.currentState,
    required this.stateData,
    required this.updatedAt,
  });

  final String flowName;
  final String currentState;
  final Map<String, dynamic> stateData;
  final DateTime updatedAt;

  factory FlowStateModel.fromJson(Map<String, dynamic> json) {
    return FlowStateModel(
      flowName: json['flow_name']?.toString() ?? 'start',
      currentState: json['current_state']?.toString() ?? 'greeting',
        stateData: json['state_data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['state_data'] as Map)
          : const {},
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

