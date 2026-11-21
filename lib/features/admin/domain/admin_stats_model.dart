class AdminDashboardStats {
  final int totalUsers;
  final int totalProviders;
  final int pendingProviders;
  final int pendingPayments;
  final int activeRequests;
  final int completedRequests;
  final int openReports;
  final int revenue30dFcfa;

  const AdminDashboardStats({
    required this.totalUsers,
    required this.totalProviders,
    required this.pendingProviders,
    this.pendingPayments = 0,
    required this.activeRequests,
    required this.completedRequests,
    this.openReports = 0,
    this.revenue30dFcfa = 0,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStats(
      totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
      totalProviders: (json['total_providers'] as num?)?.toInt() ?? 0,
      pendingProviders: (json['pending_providers'] as num?)?.toInt() ?? 0,
      pendingPayments: (json['pending_payments'] as num?)?.toInt() ?? 0,
      activeRequests: (json['active_requests'] as num?)?.toInt() ?? 0,
      completedRequests: (json['completed_requests'] as num?)?.toInt() ?? 0,
      openReports: (json['open_reports'] as num?)?.toInt() ?? 0,
      revenue30dFcfa: (json['revenue_30d_fcfa'] as num?)?.toInt() ?? 0,
    );
  }
}
