import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/services/notification_service.dart';
import 'package:university_point_locator/services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseService _service = SupabaseService();

  bool _isLoading = true;
  String? _error;

  // User data
  String? _displayName;
  String? _email;
  String? _role;
  DateTime? _memberSince;

  // Favorites. There is no `user` field on purpose: it captured
  // `auth.currentUser` once when this State was created and outlived
  // sign-out, so a stale account could be rendered after re-entry.
  // `_loadUserData` always reads the CURRENT user instead.
  List<Map<String, dynamic>> _favoriteStops = [];

  // Statistics. Both are derived from `_favoriteStops` - real data for THIS
  // user. `_recentTrips`/`_totalTrips` are gone: students own no trip rows
  // (trips belong to drivers), so they were always a fabricated 0 / empty
  // "Recent Trips" list.
  int _favoriteCount = 0;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      // Read the CURRENT signed-in user at load time - never a snapshot
      // captured when this State was created. Otherwise a profile pushed
      // before a sign-out could keep rendering the previous account.
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // Signed out mid-flight (or a restored session already gone): say so
        // instead of rendering a half-empty profile of nobody.
        if (!mounted) return;
        setState(() {
          _error = 'You are signed out. Please sign in again.';
          _isLoading = false;
        });
        return;
      }
      // Get user metadata
      // `?? 'Student'` only guards null: an empty-string name (signup with an
      // empty name field) used to reach `_displayName![0]` in build() and
      // crash the screen with a RangeError.
      final rawName = user.userMetadata?['name'];
      _displayName = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : 'Student';
      _email = user.email ?? '';
      // Role from the profiles row, never from userMetadata: the badge must
      // show the same enforced value the router used (metadata is
      // client-controlled and goes stale after an admin changes a role).
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        _role = profile?['role'] as String? ?? 'student';
      } catch (_) {
        // Non-critical: the badge falls back to the default label.
        _role = 'student';
      }
      // Supabase returns createdAt as a non-nullable ISO8601 String.
      _memberSince = DateTime.tryParse(user.createdAt);

      // Real favourites: this account's active stop subscriptions joined
      // against stop and route names. The old version showed three hard-coded
      // "sample" stops and four fake trips (after a fake 500 ms delay) as if
      // they were the signed-in student's own data.
      final subs = await Supabase.instance.client
          .from('stop_notifications')
          .select('stop_id, route_id')
          .eq('user_id', user.id)
          .eq('is_active', true)
          // Stable, most-recently-toggled first: without an order the list
          // re-shuffled between loads. nullsFirst: legacy rows predate the
          // updated_at writes and must not float to the top.
          .order('updated_at', ascending: false, nullsFirst: false);
      final subRows = List<Map<String, dynamic>>.from(subs as List);
      final stopIds = [
        for (final s in subRows)
          if (s['stop_id'] is int) s['stop_id'] as int,
      ];
      final routeIds = [
        for (final s in subRows)
          if (s['route_id'] is int) s['route_id'] as int,
      ];

      final points = stopIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('pickup_points')
                  .select('id, point_name')
                  .inFilter('id', stopIds) as List,
            );
      final routes = routeIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('routes')
                  .select('id, route_name')
                  .inFilter('id', routeIds) as List,
            );
      final pointNameById = {
        for (final p in points) p['id']: p['point_name'],
      };
      final routeNameById = {
        for (final r in routes) r['id']: r['route_name'],
      };

      // Dedupe by stop id: `unsubscribe` only flips is_active and never
      // deletes, so on schemas without a unique (user_id, stop_id)
      // constraint a sync edge can leave two active rows for one stop and
      // it would show - and toggle - twice.
      final seenStopIds = <int>{};
      final favorites = <Map<String, dynamic>>[];
      for (final sub in subRows) {
        final stopId = sub['stop_id'];
        if (stopId is! int) continue;
        if (!seenStopIds.add(stopId)) continue;
        final pointName = pointNameById[stopId];
        if (pointName == null) continue;
        favorites.add({
          'name': pointName,
          'route': routeNameById[sub['route_id']] ?? 'Route',
          'notifications': true,
          'stopId': stopId,
          'routeId': sub['route_id'],
        });
      }

      if (!mounted) return;
      setState(() {
        _favoriteStops = favorites;

        // Calculate statistics - both real, both derived from the list above.
        _favoriteCount = _favoriteStops.length;
        _notificationCount = _favoriteStops
            .where((s) => s['notifications'] == true)
            .length;

        // A successful retry must clear the stale error, otherwise one
        // failed load left this screen on the error branch forever.
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      // Guard like the success path: pull-to-refresh then pop mid-flight
      // must not call setState on a disposed State.
      if (!mounted) return;
      debugPrint('[profile] load failed: $e');
      setState(() {
        // The error branch has no RefreshIndicator - point at what IS
        // there (the Retry button below) instead of a gesture that does
        // nothing.
        _error = 'Could not load your profile. Tap Retry to try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showLogoutDialog() async {
    return showDialog(
      context: context,
      // Named `dialogContext` instead of `context` on purpose: the State's own
      // `context` must stay visible below, because the dialog's context is
      // deactivated the moment the dialog pops and must not be used again
      // after the `await`.
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Capture stable references first — both outlive the dialog
                // and the await below, unlike the dialog's own context.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop(); // Close confirm dialog

                // Show loading. Deliberately NOT awaited: this future only
                // completes when the dialog is popped, which happens below.
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  // barrierDismissible only blocks taps - Android back still
                  // pops the dialog, which would send the follow-up
                  // `navigator.pop` below to the route underneath it.
                  builder: (_) => const PopScope(
                    canPop: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );

                try {
                  await _service.signOut();
                } catch (e) {
                  // Raw exception text is for the log, not the screen.
                  debugPrint('[profile] sign out failed: $e');
                  navigator.pop(); // dismiss the loading dialog
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not log out. Check your connection and try again.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // RoleRouter rebuilds to the login screen on sign-out, but
                // this ProfileScreen is a PUSHED route on top of `home:` -
                // the loading dialog AND the signed-out profile (name,
                // e-mail, favourite stops) would stay stacked over the login
                // screen on a shared phone. pop to the first route so only
                // the login screen remains.
                navigator.popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                // Override the theme's full-width minimum (actions row).
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  /// Opens a dialog to edit the display name, then persists it.
  Future<void> _showEditProfileDialog() async {
    final controller = TextEditingController(text: _displayName ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Please enter a name';
              if (t.length > 60) return 'Name is too long';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            style: ElevatedButton.styleFrom(
              // Override the theme's full-width minimum (actions row).
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _updateDisplayName(controller.text.trim());
    }
    controller.dispose();
  }

  /// Persists a new display name to auth metadata (the source the profile
  /// reads on load) and best-effort syncs it to the `profiles` row.
  Future<void> _updateDisplayName(String newName) async {
    if (newName.isEmpty || newName == _displayName) return;
    final messenger = ScaffoldMessenger.of(context);
    final oldName = _displayName;
    var assignmentUnlinked = false;
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'name': newName}),
      );
      // Best-effort: keep profiles.name in sync so the admin view and any
      // role-aware read agree with the header. Fails harmlessly if the
      // column/permission is absent.
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'name': newName})
              .eq('id', user.id);
        } catch (e) {
          debugPrint('[profile] profiles.name sync skipped: $e');
        }

        // Bus assignments are keyed on the free-text buses.driver_name: a
        // driver's self-rename used to silently UNLINK their assignment -
        // the next dashboard load said "no bus is assigned" although the
        // row existed. Follow the rename server-side when RLS permits it
        // (the admin rename path does the same); when it refuses (buses
        // writes are admin-only), tell the DRIVER to involve their admin
        // instead of failing silently. Students own no bus rows, so the
        // whole step is skipped for them.
        String? role;
        try {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
          role = row?['role'] as String?;
        } catch (e) {
          debugPrint('[profile] role lookup for rename skipped: $e');
        }
        if (role == 'driver' && oldName != null && oldName.isNotEmpty) {
          try {
            await Supabase.instance.client
                .from('buses')
                .update({'driver_name': newName})
                .eq('driver_name', oldName);
          } catch (e) {
            debugPrint('[profile] bus follow-rename refused: $e');
            assignmentUnlinked = true;
          }
        }
      }
      if (!mounted) return;
      setState(() => _displayName = newName);
      messenger.showSnackBar(
        assignmentUnlinked
            ? const SnackBar(
                content: Text(
                  'Name updated - but your bus assignment still points at '
                  'your old name. Ask your administrator to re-save it.',
                ),
                backgroundColor: Colors.orange,
              )
            : const SnackBar(
                content: Text('Name updated'),
                backgroundColor: Colors.green,
              ),
      );
    } on AuthException catch (e) {
      debugPrint('[profile] name update failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message.isEmpty ? 'Could not update name' : e.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('[profile] name update failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not update name. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Opens a dialog to set a new password (with confirmation), then applies it.
  Future<void> _showChangePasswordDialog() async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    (v ?? '').length < 6 ? 'At least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (v) =>
                    v != controller.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            style: ElevatedButton.styleFrom(
              // Override the theme's full-width minimum (actions row).
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _changePassword(controller.text);
    }
    controller.dispose();
    confirmController.dispose();
  }

  Future<void> _changePassword(String newPassword) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } on AuthException catch (e) {
      debugPrint('[profile] password change failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(e.message.isEmpty ? 'Could not change password' : e.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('[profile] password change failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not change password. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleNotification(int index) async {
    // Everything the callback needs is captured BEFORE the first await: the
    // list can be reloaded/removed while a request is in flight, and
    // re-reading `_favoriteStops[index]` afterwards produced the wrong stop's
    // name or a RangeError outside this try/catch.
    final stop = _favoriteStops[index];
    final stopId = stop['stopId'] as int;
    // Legacy rows can have stop_notifications.route_id NULL, so this must be
    // a nullable cast - `as int` threw a TypeError and made ENABLE always
    // fail while disable worked.
    final routeId = stop['routeId'] as int?;
    final name = '${stop['name']}';
    final enable = stop['notifications'] != true;

    // Optimistic flip - rolled back below if the server disagrees, so the
    // bell icon never claims an alert is armed when the write failed.
    setState(() {
      stop['notifications'] = enable;
      // Keep the "Alerts ON" stat honest while the bell flips - here and
      // in both rollback paths below.
      _notificationCount = _favoriteStops
          .where((s) => s['notifications'] == true)
          .length;
    });

    try {
      if (enable) {
        // OS-level check FIRST: a persisted subscription whose notification
        // can never be delivered is a silent no-op the student would trust.
        final granted = await NotificationService().ensurePermission();
        if (!granted) {
          debugPrint(
            '[profile] notification permission denied by the OS - '
            'not subscribing to stop $stopId',
          );
          if (!mounted) return;
          setState(() {
            stop['notifications'] = false;
            _notificationCount = _favoriteStops
                .where((s) => s['notifications'] == true)
                .length;
          });
          // Actionable: "go enable them" without a route to the Settings
          // page is a dead end for most users.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Notifications are blocked — enable them for this app in '
                'system settings.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'SETTINGS',
                textColor: Colors.white,
                onPressed: () {
                  // Fire-and-forget: opens the OS app-settings page.
                  Geolocator.openAppSettings().catchError((Object e) {
                    debugPrint('[profile] openAppSettings failed: $e');
                    return false;
                  });
                },
              ),
            ),
          );
          return;
        }
        await _service.subscribeToStopNotifications(
          stopId,
          routeId: routeId,
        );
      } else {
        await _service.unsubscribeFromStopNotifications(stopId);
      }
    } catch (e) {
      debugPrint('[profile] notification toggle failed: $e');
      if (!mounted) return;
      setState(() {
        stop['notifications'] = !enable;
        _notificationCount = _favoriteStops
            .where((s) => s['notifications'] == true)
            .length;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update notifications. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enable
              ? '🔔 Notifications enabled for $name'
              : '🔕 Notifications disabled for $name',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: enable ? Colors.green : Colors.grey,
      ),
    );
  }

  void _removeFavorite(int index) {
    // Captured now: the list may be reloaded between the dialog opening and
    // the server call returning, so the callback must not re-index it later.
    final stop = _favoriteStops[index];
    final name = '${stop['name']}';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Favorite'),
          content: Text(
            'Remove $name from favorites?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Captured before the pop - both outlive the await, unlike
                // the dialog's own context.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop();

                // Remove server-side too: unsubscribe flips is_active so the
                // row stays gone on the next load (the old local-only remove
                // was silently restored by every pull-to-refresh).
                try {
                  await _service.unsubscribeFromStopNotifications(
                    stop['stopId'] as int,
                  );
                } catch (e) {
                  debugPrint('[profile] remove favorite failed: $e');
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Could not remove - please try again'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (!mounted) return;
                setState(() {
                  // By identity, not index: a refresh while the request was
                  // in flight would have shifted (or dropped) this index.
                  _favoriteStops.remove(stop);
                  _favoriteCount = _favoriteStops.length;
                  _notificationCount = _favoriteStops
                      .where((s) => s['notifications'] == true)
                      .length;
                });
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Removed from favorites'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = _role == 'driver' ? 'Driver' : 'Student';
    final Color primaryColor = _role == 'driver' ? Colors.green : Colors.blue;
    // Plural-aware labels: "1 Favorites" reads as a bug on a launch build.
    final favoriteLabel = _favoriteCount == 1 ? 'Favorite' : 'Favorites';
    // Zero-aware: "Alerts ON" over a 0 read as a bug on a launch build.
    final alertsLabel = _notificationCount == 0
        ? 'Alerts Off'
        : (_notificationCount == 1 ? 'Alert On' : 'Alerts ON');

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // Logout button with confirmation
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                _showLogoutDialog();
              } else if (value == 'edit') {
                _showEditProfileDialog();
              } else if (value == 'password') {
                _showChangePasswordDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Edit profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Change password'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    // `_error` only ever holds friendly, user-facing copy -
                    // the raw cause goes to debugPrint above.
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadUserData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadUserData,
              color: primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile Header Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Profile Avatar
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 45,
backgroundColor: primaryColor.withValues(alpha: 0.1),
                                      child: CircleAvatar(
                                        radius: 40,
backgroundColor: primaryColor.withValues(alpha: 0.2),
                                        child: Text(
                                          _displayName![0].toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                            color: primaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: _showEditProfileDialog,
                                        child: Tooltip(
                                          message: 'Edit name',
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: primaryColor,
                                                width: 2,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.edit,
                                              size: 16,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 20),
                                // Profile Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _displayName!,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _email!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
color: primaryColor.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _role == 'driver'
                                                  ? Icons.directions_bus
                                                  : Icons.school,
                                              size: 16,
                                              color: primaryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              role,
                                              style: TextStyle(
                                                color: primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Member Since
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  // No fabricated year when the signup stamp
                                  // is missing - a guess the app cannot back.
                                  _memberSince == null
                                      ? 'Member since —'
                                      : 'Member since ${_memberSince!.year}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Statistics Cards. Both cards are real numbers for THIS
                    // user. The old third card ("Total Trips: 0") was
                    // fabricated - students own no trip rows - so it is gone
                    // rather than lying with a 0.
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            Icons.star,
                            '$_favoriteCount',
                            favoriteLabel,
                            Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            Icons.notifications_active,
                            '$_notificationCount',
                            alertsLabel,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Account settings: the concrete "adjust my profile"
                    // actions, kept discoverable (not just in the header
                    // overflow) so students can actually manage their account.
                    const Text(
                      'Account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.edit_outlined,
                              color: Colors.blue,
                            ),
                            title: const Text('Edit name'),
                            subtitle: Text(_displayName ?? ''),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _showEditProfileDialog,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.lock_outline,
                              color: Colors.blue,
                            ),
                            title: const Text('Change password'),
                            subtitle: const Text('Update your login password'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _showChangePasswordDialog,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Favorite Stops Section. The old "View All" button was a
                    // no-op - and pointless besides: the list below already
                    // renders every favourite, so there is nothing to page to.
                    const Text(
                      'Favorite Stops',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _favoriteStops.isEmpty
                        ? Card(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.star_border,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No favorite stops yet',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap ★ on any stop to add it here',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _favoriteStops.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final stop = _favoriteStops[index];
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
backgroundColor: Colors.amber.withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    stop['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(stop['route']),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          stop['notifications']
                                              ? Icons.notifications_active
                                              : Icons.notifications_none,
                                          color: stop['notifications']
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                        onPressed: () =>
                                            _toggleNotification(index),
                                        tooltip: stop['notifications']
                                            ? 'Disable notifications'
                                            : 'Enable notifications',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        onPressed: () => _removeFavorite(index),
                                        color: Colors.red,
                                        tooltip: 'Remove from favorites',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    // The "Recent Trips" section was removed: students own
                    // no trip rows, so it was a heading over an always-empty
                    // card - fabricated data on a launch build. Trip history
                    // is a driver feature (see the Trip History screen).
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
