import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🔴 REPLACE WITH YOUR ACTUAL SUPABASE CREDENTIALS
const String supabaseUrl = 'https://wstuufgiapgkskkcrdjx.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndzdHV1ZmdpYXBna3Nra2NyZGp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MjI3MzIsImV4cCI6MjA4ODE5ODczMn0.LLDQ1PPFJJRVowZ_PaOWMBNeNJVepVC6W8LTmpZX6pg';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase Test',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  String _status = 'Initializing...';
  List<dynamic> _universities = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeSupabase();
  }

  Future<void> _initializeSupabase() async {
    try {
      // Initialize Supabase
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      
      setState(() {
        _status = '✅ Connected to Supabase!';
      });
      
      // Fetch data
      await _fetchUniversities();
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _status = '❌ Connection failed';
      });
    }
  }

  Future<void> _fetchUniversities() async {
    try {
      final response = await Supabase.instance.client
          .from('universities')
          .select()
          .order('name');
      
      setState(() {
        _universities = response;
        _isLoading = false;
        _status = '✅ Found  universities';
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _status = '❌ Failed to fetch data';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase Connection Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status Card
            Card(
              color: _status.contains('✅') ? Colors.green[50] :
                     _status.contains('❌') ? Colors.red[50] :
                     Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _status.contains('✅') ? Icons.check_circle :
                      _status.contains('❌') ? Icons.error :
                      Icons.info,
                      color: _status.contains('✅') ? Colors.green :
                             _status.contains('❌') ? Colors.red :
                             Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Error Display
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  'Error: ',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Data Section
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _universities.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Universities Found',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add data to your universities table',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _universities.length,
                          itemBuilder: (context, index) {
                            final uni = _universities[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[100],
                                  child: Text(
                                    uni['name']?.toString().substring(0, 1) ?? '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  uni['name']?.toString() ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text('City: '),
                                trailing: Text('ID: '),
                              ),
                            );
                          },
                        ),
            ),
            
            // Refresh Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton.icon(
                onPressed: _fetchUniversities,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Data'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
