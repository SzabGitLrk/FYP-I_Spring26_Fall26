import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseService _service = SupabaseService();
  final user = Supabase.instance.client.auth.currentUser;

  bool _isLoading = true;
  String? _error;

  // User data
  String? _displayName;
  String? _email;
  String? _role;
  DateTime? _memberSince;

  // Favorites and history
  List<Map<String, dynamic>> _favoriteStops = [];
  List<Map<String, dynamic>> _recentTrips = [];

  // Statistics
  int _totalTrips = 0;
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
      // Get user metadata
      // `?? 'Student'` only guards null: an empty-string name (signup with an
      // empty name field) used to reach `_displayName![0]` in build() and
      // crash the screen with a RangeError.
      final rawName = user?.userMetadata?['name'];
      _displayName = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : 'Student';
      _email = user?.email ?? '';
      // Role from the profiles row, never from userMetadata: the badge must
      // show the same enforced value the router used (metadata is
      // client-controlled and goes stale after an admin changes a role).
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user?.id ?? '')
            .maybeSingle();
        _role = profile?['role'] as String? ?? 'student';
      } catch (_) {
        // Non-critical: the badge falls back to the default label.
        _role = 'student';
      }
      // Handle createdAt - Supabase returns it as a String in ISO8601 format
      final createdAtValue = user?.createdAt;
      if (createdAtValue != null) {
        _memberSince = DateTime.tryParse(createdAtValue.toString());
      }

      // Real favourites: this account's active stop subscriptions joined
      // against stop and route names. The old version showed three hard-coded
      // "sample" stops and four fake trips (after a fake 500 ms delay) as if
      // they were the signed-in student's own data.
      final subs = await Supabase.instance.client
          .from('stop_notifications')
          .select('stop_id, route_id')
          .eq('user_id', user?.id ?? '')
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

      if (!mounted) return;
      setState(() {
        _favoriteStops = [
          for (final sub in subRows)
            if (pointNameById[sub['stop_id']] != null)
              {
                'name': pointNameById[sub['stop_id']],
                'route': routeNameById[sub['route_id']] ?? 'Route',
                'notifications': true,
                'stopId': sub['stop_id'],
                'routeId': sub['route_id'],
              },
        ];
        // Students own no trip rows (trips belong to drivers), so there is
        // nothing real to show - an empty list beats the fake "Mar 10, 2026"
        // entries that used to ship.
        _recentTrips = [];

        // Calculate statistics
        _favoriteCount = _favoriteStops.length;
        _totalTrips = _recentTrips.length;
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
                  navigator.pop(); // dismiss the loading dialog
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error logging out: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // RoleRouter rebuilds to the login screen on sign-out, but the
                // loading dialog is a *separate route* on the Navigator —
                // without this pop it would spin forever over the login screen.
                navigator.pop();
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
    final stop = _favoriteStops[index];
    final enable = stop['notifications'] != true;

    // Optimistic flip - rolled back below if the server disagrees, so the
    // bell icon never claims an alert is armed when the write failed.
    setState(() => stop['notifications'] = enable);

    try {
      if (enable) {
        await _service.subscribeToStopNotifications(
          stop['stopId'] as int,
          stop['routeId'] as int,
        );
      } else {
        await _service.unsubscribeFromStopNotifications(stop['stopId'] as int);
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
          _favoriteStops[index]['notifications']
              ? '🔔 Notifications enabled for ${_favoriteStops[index]['name']}'
              : '🔕 Notifications disabled',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: _favoriteStops[index]['notifications']
            ? Colors.green
            : Colors.grey,
      ),
    );
  }

  void _removeFavorite(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Favorite'),
          content: Text(
            'Remove ${_favoriteStops[index]['name']} from favorites?',
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
                    _favoriteStops[index]['stopId'] as int,
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
                  _favoriteStops.removeAt(index);
                  _favoriteCount = _favoriteStops.length;
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
                    'Error: $_error',
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

                    // Statistics Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            Icons.star,
                            '$_favoriteCount',
                            'Favorites',
                            Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            Icons.history,
                            '$_totalTrips',
                            'Total Trips',
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            Icons.notifications_active,
                            '$_notificationCount',
                            'Alerts ON',
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
                    const SizedBox(height: 24),

                    // Recent Trips Section. "View All" was a no-op; trip
                    // history is a driver feature (Trip History screen) and
                    // this student list is always empty.
                    const Text(
                      'Recent Trips',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentTrips.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final trip = _recentTrips[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue[50],
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              trip['university'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${trip['route']} • ${trip['date']}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  trip['time'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                              ],
                            ),
                            onTap: () {
                              // View trip details
                            },
                          );
                        },
                      ),
                    ),
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
