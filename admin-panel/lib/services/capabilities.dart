/// Product RBAC capabilities — keep aligned with backend `access.capabilities_for`.
class UserCapabilities {
  const UserCapabilities({
    required this.canManageAutomations,
    required this.canManageActions,
    required this.canManageTemplates,
    required this.canManageTeam,
    required this.canManageGroups,
    required this.canManageBilling,
    required this.canManageWhatsApp,
    required this.canManageQuickReplies,
    required this.canAccessBackoffice,
    required this.canViewConversations,
    required this.canReplyConversations,
    required this.canAssumeConversations,
    required this.canTransferConversations,
    required this.canViewOverview,
  });

  final bool canManageAutomations;
  final bool canManageActions;
  final bool canManageTemplates;
  final bool canManageTeam;
  final bool canManageGroups;
  final bool canManageBilling;
  final bool canManageWhatsApp;
  final bool canManageQuickReplies;
  final bool canAccessBackoffice;
  final bool canViewConversations;
  final bool canReplyConversations;
  final bool canAssumeConversations;
  final bool canTransferConversations;
  final bool canViewOverview;

  static const UserCapabilities guest = UserCapabilities(
    canManageAutomations: false,
    canManageActions: false,
    canManageTemplates: false,
    canManageTeam: false,
    canManageGroups: false,
    canManageBilling: false,
    canManageWhatsApp: false,
    canManageQuickReplies: false,
    canAccessBackoffice: false,
    canViewConversations: false,
    canReplyConversations: false,
    canAssumeConversations: false,
    canTransferConversations: false,
    canViewOverview: false,
  );

  static const Set<String> superadminRoles = <String>{
    'superadmin',
    'system-admin',
    'system_admin',
    'systemadmin',
  };

  static const Set<String> tenantAdminRoles = <String>{
    'owner',
    'manager',
    'admin',
    'tenant_admin',
    'tenant-admin',
  };

  static const Set<String> agentRoles = <String>{
    'agent',
    'member',
    'atendente',
  };

  factory UserCapabilities.fromRole(String? role) {
    final normalized = (role ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return guest;

    if (superadminRoles.contains(normalized)) {
      return const UserCapabilities(
        canManageAutomations: true,
        canManageActions: true,
        canManageTemplates: true,
        canManageTeam: true,
        canManageGroups: true,
        canManageBilling: true,
        canManageWhatsApp: true,
        canManageQuickReplies: true,
        canAccessBackoffice: true,
        canViewConversations: true,
        canReplyConversations: true,
        canAssumeConversations: true,
        canTransferConversations: true,
        canViewOverview: true,
      );
    }

    final isTenantAdmin = tenantAdminRoles.contains(normalized);
    // Unknown roles default to agent-like access (conversations + quick replies).
    return UserCapabilities(
      canManageAutomations: isTenantAdmin,
      canManageActions: isTenantAdmin,
      canManageTemplates: isTenantAdmin,
      canManageTeam: isTenantAdmin,
      canManageGroups: isTenantAdmin,
      canManageBilling: isTenantAdmin,
      canManageWhatsApp: isTenantAdmin,
      canManageQuickReplies: true,
      canAccessBackoffice: false,
      canViewConversations: true,
      canReplyConversations: true,
      canAssumeConversations: true,
      canTransferConversations: true,
      canViewOverview: true,
    );
  }

  bool get isTenantAdmin =>
      canManageTeam && canManageBilling && !canAccessBackoffice;

  bool get isAgentOnly =>
      !canManageAutomations &&
      !canManageTeam &&
      !canAccessBackoffice &&
      canViewConversations;
}
