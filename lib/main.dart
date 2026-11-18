import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String baseUrl = 'https://rajekampong.dprd.beltim.go.id/api';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Background Firebase init error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: initSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    // Tampilkan notifikasi saat aplikasi sedang dibuka (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'raje_kampong_channel',
              'Notifikasi Raje Kampong',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  } catch (e) {
    debugPrint('Inisialisasi Firebase/Notifikasi gagal: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');

  runApp(RajeKampongApp(isLoggedIn: token != null));
}

class RajeKampongApp extends StatelessWidget {
  final bool isLoggedIn;
  const RajeKampongApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Si Raje Kampong',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const DashboardPage() : const LoginPage(),
    );
  }
}

// ==================== HALAMAN LOGIN ====================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Accept': 'application/json'},
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('user_name', data['user']['name']);
        await prefs.setString('user_role', data['user']['role']);
        await prefs.setInt('user_id', data['user']['id']);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      } else {
        _showError(data['message'] ?? 'Login gagal');
      }
    } catch (e) {
      _showError('Gagal terhubung ke server: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance, size: 72, color: Colors.teal),
                const SizedBox(height: 16),
                const Text(
                  'Si Raje Kampong',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Text('DPRD Kabupaten Belitung Timur'),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Masuk'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== HALAMAN DAFTAR PENGADUAN ====================
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<dynamic> _pengaduanList = [];
  bool _loading = true;
  String _userName = '';
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _initUserAndFcm();
    _fetchPengaduan();
  }

  Future<void> _initUserAndFcm() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? '';
      _userRole = prefs.getString('user_role') ?? '';
    });

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final fcmToken = await messaging.getToken();
      final authToken = prefs.getString('auth_token');

      if (fcmToken != null && authToken != null) {
        await http.post(
          Uri.parse('$baseUrl/fcm-token'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
          body: {'fcm_token': fcmToken},
        );
      }
    } catch (e) {
      debugPrint('Gagal registrasi FCM token: $e');
    }
  }

  Future<void> _fetchPengaduan() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/pengaduan'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _pengaduanList = data['data'] ?? []);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aduan & Aspirasi', style: TextStyle(fontSize: 18)),
            Text('$_userName ($_userRole)', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPengaduan),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchPengaduan,
              child: ListView.builder(
                itemCount: _pengaduanList.length,
                itemBuilder: (context, index) {
                  final item = _pengaduanList[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(
                        '${item['kode'] ?? '-'} • ${item['nama_pengirim'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        item['isi'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailPengaduanPage(pengaduanId: item['id']),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ==================== HALAMAN DETAIL & DISPOSISI ====================
class DetailPengaduanPage extends StatefulWidget {
  final int pengaduanId;
  const DetailPengaduanPage({super.key, required this.pengaduanId});

  @override
  State<DetailPengaduanPage> createState() => _DetailPengaduanPageState();
}

class _DetailPengaduanPageState extends State<DetailPengaduanPage> {
  Map<String, dynamic>? _pengaduan;
  List<dynamic> _disposisiList = [];
  List<dynamic> _pejabatList = [];
  int? _selectedPejabatId;
  final _instruksiController = TextEditingController();
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final resDetail = await http.get(
        Uri.parse('$baseUrl/pengaduan/${widget.pengaduanId}'),
        headers: headers,
      );
      final resPejabat = await http.get(
        Uri.parse('$baseUrl/pejabat'),
        headers: headers,
      );

      if (resDetail.statusCode == 200) {
        final d = jsonDecode(resDetail.body);
        _pengaduan = d['pengaduan'];
        _disposisiList = d['disposisi'] ?? [];
      }
      if (resPejabat.statusCode == 200) {
        final p = jsonDecode(resPejabat.body);
        _pejabatList = p['data'] ?? [];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kirimDisposisi() async {
    if (_selectedPejabatId == null || _instruksiController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tujuan dan isi instruksi disposisi')),
      );
      return;
    }

    setState(() => _sending = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/disposisi'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {
          'kirim_id': widget.pengaduanId.toString(),
          'kepada_user_id': _selectedPejabatId.toString(),
          'instruksi': _instruksiController.text.trim(),
        },
      );

      if (res.statusCode == 200) {
        _instruksiController.clear();
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disposisi berhasil dikirim')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail & Disposisi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kode: ${_pengaduan?['kode'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pengaduan?['nama_pengirim'] ?? '',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text('Alamat: ${_pengaduan?['alamat'] ?? '-'}'),
                  Text('Telp: ${_pengaduan?['telepon'] ?? '-'}'),
                  const Divider(height: 24),
                  const Text('Isi Pengaduan:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_pengaduan?['isi'] ?? ''),
                  const Divider(height: 32),
                  const Text('Riwayat Disposisi:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_disposisiList.isEmpty)
                    const Text('Belum ada disposisi.', style: TextStyle(color: Colors.grey)),
                  ..._disposisiList.map((disp) => Card(
                        color: Colors.teal.shade50,
                        child: ListTile(
                          title: Text(
                            'Dari: ${disp['pengirim']?['name']} → Ke: ${disp['penerima']?['name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(disp['instruksi'] ?? ''),
                        ),
                      )),
                  const Divider(height: 32),
                  const Text('Kirim Disposisi Baru:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _selectedPejabatId,
                    decoration: const InputDecoration(
                      labelText: 'Teruskan Kepada',
                      border: OutlineInputBorder(),
                    ),
                    items: _pejabatList.map<DropdownMenuItem<int>>((u) {
                      return DropdownMenuItem<int>(
                        value: u['id'],
                        child: Text('${u['name']} (${u['role']})'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedPejabatId = val),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _instruksiController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Catatan / Instruksi Disposisi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _kirimDisposisi,
                      icon: const Icon(Icons.send),
                      label: Text(_sending ? 'Mengirim...' : 'Kirim Disposisi'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
