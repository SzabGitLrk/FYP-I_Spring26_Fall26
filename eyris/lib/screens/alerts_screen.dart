import 'package:flutter/material.dart';
import '../services/alert_service.dart';
import '../models/alert_model.dart';
import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';
import 'home_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => AlertsScreenState();
}

// Public so HomeScreen can trigger a reload when this tab becomes visible.
class AlertsScreenState extends State<AlertsScreen> {
  final AlertService _alertService = AlertService();
  List<AlertModel> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Public reload — called on init and whenever the Alerts tab is opened.
  Future<void> reload() async {
    final alerts = await _alertService.getAlerts();
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _isLoading = false;
    });
  }

  void _goBackToHome() {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.changeTab(0);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _clearAlerts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text("Clear All Alerts",
            style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to delete all alerts?",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel",
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear",
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _alertService.clearAlerts();
      await reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All alerts cleared")),
      );
    }
  }

  Future<void> _deleteAlert(String id) async {
    await _alertService.deleteAlert(id);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Alert History"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _goBackToHome,
        ),
        actions: [
          if (_alerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: AppColors.danger),
              onPressed: _clearAlerts,
              tooltip: "Clear all",
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? const AppEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: "No Alerts Yet",
                  subtitle:
                      "When obstacles are detected, they will appear here.",
                )
              : RefreshIndicator(
                  onRefresh: reload,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _alerts.length,
                    itemBuilder: (context, index) {
                      final alert = _alerts[index];
                      return Dismissible(
                        key: Key(alert.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                          child: const Icon(Icons.delete_rounded,
                              color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteAlert(alert.id),
                        child: _buildAlertCard(alert),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildAlertCard(AlertModel alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: alert.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(alert.icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.message,
                    style: AppText.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(alert.timestamp, style: AppText.label),
                      const SizedBox(width: 10),
                      AppStatusPill(
                        text: alert.type.toUpperCase(),
                        color: alert.color,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
