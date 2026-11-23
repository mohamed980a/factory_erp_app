import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class Session extends ChangeNotifier {
  final Api api = Api();
  Map<String, dynamic>? user;
  List<String> permissions = [];
  bool ready = false;
  String serverUrl = 'http://127.0.0.1:8000';
  Map<String, dynamic>? _meta;

  bool get loggedIn => user != null;
  bool can(String permission) => permissions.contains(permission);

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString('server_url') ?? serverUrl;
    final token = p.getString('token');
    api.baseUrl = serverUrl;
    if (token != null) {
      api.token = token;
      try {
        _apply(await api.get('/me') as Map<String, dynamic>);
      } catch (_) {
        api.token = null;
        await p.remove('token');
      }
    }
    ready = true;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> u) {
    user = u;
    permissions = (u['permissions'] as List).map((e) => e.toString()).toList();
  }

  Future<void> login(String url, String email, String password) async {
    api.baseUrl = url.trim();
    final res = await api.post('/login', {'email': email.trim(), 'password': password}) as Map<String, dynamic>;
    api.token = res['token'] as String;
    _apply(res['user'] as Map<String, dynamic>);
    serverUrl = url.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('server_url', serverUrl);
    await p.setString('token', api.token!);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/logout');
    } catch (_) {}
    api.token = null;
    user = null;
    permissions = [];
    _meta = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    notifyListeners();
  }

  /// يُستدعى بعد تعديل الكتالوج لتحديث القوائم في الشاشات الأخرى.
  void invalidateMeta() => _meta = null;

  /// بيانات ثابتة (أنواع المنتجات، الوحدات، المخازن، الخزائن...) تُحمَّل مرة واحدة.
  Future<Map<String, dynamic>> meta({bool refresh = false}) async {
    if (_meta == null || refresh) {
      _meta = await api.get('/meta') as Map<String, dynamic>;
    }
    return _meta!;
  }
}
