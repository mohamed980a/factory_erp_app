import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class Api {
  String baseUrl = '';
  String? token;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    final q = <String, String>{};
    if (query != null) {
      query.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
      });
    }
    return Uri.parse('$b/api$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _run(Future<http.Response> f) async {
    try {
      return await f.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException('انتهت مهلة الاتصال بالسيرفر.');
    } catch (_) {
      throw ApiException('تعذّر الاتصال بالسيرفر. تأكد من العنوان والشبكة.');
    }
  }

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    if (r.statusCode == 401) throw ApiException('انتهت الجلسة. سجّل الدخول من جديد.', 401);
    if (r.statusCode == 403) throw ApiException('ليس لديك صلاحية لهذه العملية.', 403);
    var msg = 'حدث خطأ (${r.statusCode}).';
    if (body is Map) {
      final errors = body['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map && (errors.first as Map).containsKey('message')) {
        // أخطاء استيراد: سطر لكل صف
        final lines = errors.take(25).map((e) => (e['row'] == null || e['row'] == 0) ? '${e['message']}' : 'سطر ${e['row']}: ${e['message']}').join('\n');
        throw ApiException(lines + (errors.length > 25 ? '\n... و${errors.length - 25} أخطاء أخرى' : ''), r.statusCode);
      }
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        msg = 'بيانات غير صحيحة: ${first is List && first.isNotEmpty ? first.first : first}';
      } else if (body['message'] != null) {
        msg = body['message'].toString();
      }
    }
    throw ApiException(msg, r.statusCode);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _decode(await _run(http.get(_uri(path, query), headers: _headers)));

  // مفاتيح منع التكرار التلقائية: نفس (المسار + البيانات) = نفس المفتاح طالما نتيجة المحاولة السابقة "غير معروفة"
  // (انقطاع شبكة / مهلة / خطأ 5xx) أو الطلب لسه شغال (ضغطتين). بعد أي رد نهائي (نجاح أو رفض واضح) المفتاح يُنسى،
  // فتكرار نفس السند عمدًا بعد نجاحه يُنفَّذ طبيعي ولا يُتجاهل بصمت.
  final Map<String, String> _pendingKeys = {};

  /// [idempotencyKey]: مفتاح ثابت للنموذج الواحد (للشاشات اللي بتديه). لو لم يُمرَّر يُولَّد مفتاح تلقائي كما فوق،
  /// فكل عمليات الإنشاء (سندات، تحويلات، عهدة، جرد، إنتاج...) محمية من التكرار.
  Future<dynamic> post(String path, [Map<String, dynamic>? body, String? idempotencyKey]) async {
    final fp = '$path|${jsonEncode(body ?? {})}';
    final key = idempotencyKey ?? (_pendingKeys[fp] ??= _autoKey());
    try {
      final r = await _run(http.post(
        _uri(path),
        headers: {..._headers, 'Idempotency-Key': key},
        body: jsonEncode(body ?? {}),
      ));
      if (r.statusCode < 500) _pendingKeys.remove(fp);
      final out = _decode(r);
      if (r.statusCode == 202 && out is Map && out['pending_approval'] == true) {
        // العملية لم تُنفَّذ بعد: تنتظر موافقة صاحب المصنع. نوقف الشاشة عن اعتبارها نجاحًا.
        throw ApiException('⏳ ${out['message']}', 202);
      }
      return out;
    } on ApiException catch (e) {
      // e.status == null  => لا رد من السيرفر (شبكة/مهلة): النتيجة مجهولة فنُبقي المفتاح لإعادة المحاولة الآمنة.
      if (e.status != null && e.status! < 500) _pendingKeys.remove(fp);
      rethrow;
    }
  }

  static int _seq = 0;
  String _autoKey() => 'a${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  Future<dynamic> put(String path, Map<String, dynamic> body) async =>
      _decode(await _run(http.put(_uri(path), headers: _headers, body: jsonEncode(body))));

  Future<dynamic> delete(String path) async => _decode(await _run(http.delete(_uri(path), headers: _headers)));

  Future<List<int>> download(String path, {Map<String, dynamic>? query}) async {
    final r = await _run(http.get(_uri(path, query), headers: _headers));
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    _decode(r);
    return <int>[];
  }
}
