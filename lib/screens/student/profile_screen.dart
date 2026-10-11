import 'package:flutter/material.dart';
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
          .eq('is_active', true);
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

        _isLoading = false;
      });
    } catch (e) {
      // Guard like the success path: pull-to-refresh then pop mid-flight
      // must not call setState on a disposed State.
      if (!mounted) return;
      debugPrint('[profile] load failed: $e');
      setState(() {
        _error = 'Could not load your profile. Pull down to retry.';
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
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
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
    setState(() => stop['notifications'] = enable);

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
          setState(() => stop['notifications'] = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are blocked — enable them for this app in '
                'system settings.',
              ),
              backgroundColor: Colors.red,
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
      setState(() => stop['notifications'] = !enable);
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
    final alertsLabel = _notificationCount == 1 ? 'Alert On' : 'Alerts ON';

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
              }
              // 'Edit Profile' was removed: a no-op entry (its handler was
              // just "// Navigate to edit profile"). Reintroduce it only
              // together with a real edit screen.
            },
            itemBuilder: (BuildContext context) => [
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
                                  'Member since ${_memberSince?.year ?? 2026}',
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
