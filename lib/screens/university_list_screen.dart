import 'package:flutter/material.dart';
import 'package:university_point_locator/models/university.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/services/supabase_service.dart';
import 'package:university_point_locator/services/my_stop_store.dart';
import 'package:university_point_locator/screens/map_screen.dart';
import 'package:university_point_locator/screens/routes_list_screen.dart'; // ← Add this import

class UniversityListScreen extends StatefulWidget {
  const UniversityListScreen({super.key});

  @override
  State<UniversityListScreen> createState() => _UniversityListScreenState();
}

class _UniversityListScreenState extends State<UniversityListScreen> {
  final SupabaseService _service = SupabaseService();
  List<University> _universities = [];
  bool _isLoading = true;
  String? _error;

  /// The student's saved "my stop" (null = none yet). Rendered as a
  /// quick-access card so the daily open skips university -> route -> stop.
  MyStop? _myStop;

  @override
  void initState() {
    super.initState();
    _loadUniversities();
    _loadMyStop();
  }

  Future<void> _loadMyStop() async {
    final stop = await MyStopStore.instance.load();
    if (!mounted) return;
    setState(() => _myStop = stop);
  }

  /// Jumps straight to the map for the saved stop's route, focused on it.
  Future<void> _openMyStop() async {
    final my = _myStop;
    if (my == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final stops = await _service.getPickupPointsForRoute(my.routeId);
      if (!mounted) return;
      // The route may have been deleted, or this stop removed from it,
      // since the card was saved: pushing the map anyway opened a blank
      // map (no stops, no polyline, no focus) with no explanation.
      if (stops.isEmpty || !stops.any((s) => s.id == my.stopId)) {
        await MyStopStore.instance.clear();
        if (!mounted) return;
        setState(() => _myStop = null);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Your saved stop no longer exists on this route - it has '
              'been cleared.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final route = RouteModel(
        id: my.routeId,
        universityId: my.universityId,
        routeName: my.routeName,
        createdAt: DateTime.now(),
      );
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => MapScreen(
            route: route,
            pickupPoints: stops,
            initialFocusStopId: my.stopId,
          ),
        ),
      );
      // Back from the map: the student may have picked a different stop
      // there, so refresh the quick-access card instead of showing the old
      // one (or nothing, the first time they pick one).
      if (mounted) _loadMyStop();
    } catch (e) {
      debugPrint('[universities] open my-stop failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open your stop. Check your connection.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearMyStop() async {
    await MyStopStore.instance.clear();
    if (!mounted) return;
    setState(() => _myStop = null);
  }

  Widget _buildMyStopCard() {
    final my = _myStop!;
    return Card(
      color: Colors.amber.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.amber,
              child: Icon(Icons.star, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your stop',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    my.stopName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    my.routeName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Remove saved stop',
              onPressed: _clearMyStop,
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: _openMyStop,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                // The theme's Size(double.infinity, 48) minimum makes this
                // button demand INFINITE width as a direct Row child: debug
                // asserts "BoxConstraints forces an infinite width" and
                // release collapses the row. Bounded minimum required.
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }

  /// [silent] is the pull-to-refresh path: it must NOT flip [_isLoading],
  /// which swaps the whole list for a full-screen spinner - unmounting the
  /// RefreshIndicator mid-gesture and flashing the screen. On a silent
  /// failure the previous list stays put (the gesture's own indicator
  /// already showed the attempt); only the initial load and Retry use the
  /// full-screen loading/error branch.
  Future<void> _loadUniversities({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final universities = await _service.getUniversities();
      if (!mounted) return;
      setState(() {
        _universities = universities;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Raw exception text (PostgREST/SQL internals) is useless to students
      // and leaks table/column names on screen - keep it in the debug log.
      debugPrint('[universities] load failed: $e');
      if (silent) {
        // Keep the stale list on screen rather than evicting it behind a
        // full-screen error the user did not ask for.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh. Check your connection.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      setState(() {
        _error =
            'Could not load universities. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select University',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUniversities,
            tooltip: 'Refresh',
          ),
          // ✅ LOGOUT BUTTON
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                _showLogoutDialog();
              } else if (value == 'profile') {
                Navigator.pushNamed(context, '/profile');
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Profile'),
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
      body: _buildBody(),
    );
  }

  // Add this method to show logout confirmation
  void _showLogoutDialog() {
    showDialog(
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

                // Show loading indicator. Deliberately NOT awaited: this
                // future only completes when the dialog is popped, below.
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
                  debugPrint('[universities] sign out failed: $e');
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
                // this screen (and the loading dialog) are separate routes on
                // the Navigator - without popping them the university list -
                // and the previous account's menu - would stay stacked over
                // the login screen on a shared phone.
                navigator.popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                // Override the theme's full-width minimum: inside the
                // actions row infinity clamps to the whole dialog width.
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            SizedBox(height: 16),
            Text('Loading universities...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Error Loading Universities',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadUniversities,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_universities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school_outlined,
                color: Colors.orange[700],
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Universities Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'No universities available yet. Please check back later.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadUniversities(silent: true),
      color: Colors.blue,
      child: ListView.builder(
        // Pull-to-refresh must work when the list is shorter than the
        // viewport (one university) - the default physics disables
        // dragging there.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _universities.length + (_myStop != null ? 1 : 0),
        itemBuilder: (context, index) {
          final hasHeader = _myStop != null;
          if (hasHeader && index == 0) {
            return _buildMyStopCard();
          }
          final university = _universities[hasHeader ? index - 1 : index];
          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () async {
                // ✅ NAVIGATION CODE - THIS IS WHAT WAS MISSING!
                final navigator = Navigator.of(context);
                await navigator.push(
                  MaterialPageRoute(
                    builder: (context) =>
                        RoutesListScreen(university: university),
                  ),
                );
                // Returning from map_screen can mean a newly saved "my
                // stop" (or a changed one); reload so the header card is
                // never stale.
                if (mounted) _loadMyStop();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Center(
                        child: Text(
                          (university.name.isNotEmpty ? university.name[0].toUpperCase() : 'U'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            university.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                university.city,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey[400],
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
