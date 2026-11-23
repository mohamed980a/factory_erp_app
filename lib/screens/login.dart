import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _url;
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<Session>().serverUrl);
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'اكتب البريد الإلكتروني وكلمة المرور.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_url.text, _email.text, _pass.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (_error!.contains('تعذّر الاتصال')) _showServer = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _brandPanel() {
    Widget feature(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white70, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 15))),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [AppColors.navy, AppColors.brand])),
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.precision_manufacturing, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 24),
        const Text('ERP المصنع', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('نظام متكامل لإدارة المخزون والتصنيع والحسابات', style: TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 36),
        feature('مخزون بالرولات والمقاسات والألوان'),
        feature('أوامر تصنيع بتكلفة فعلية وحساب الهالك'),
        feature('حسابات العملاء والموردين والخزينة'),
        feature('قفل شهري وتقارير جاهزة للمراجعة'),
      ]),
    );
  }

  Widget _form() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('تسجيل الدخول', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.navy)),
        const SizedBox(height: 6),
        const Text('أهلًا بك، سجّل دخولك للمتابعة', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 26),
        TextField(
          controller: _email,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.mail_outline)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pass,
          obscureText: _hide,
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
          ),
        ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.danger.withValues(alpha: 0.3))),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _busy ? null : _login,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('دخول', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 14),
        if (_showServer)
          TextField(controller: _url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'عنوان السيرفر', prefixIcon: Icon(Icons.dns_outlined)))
        else
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _showServer = true),
              icon: const Icon(Icons.settings_ethernet, size: 18),
              label: Text('السيرفر: ${_url.text}  (تغيير)', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5)),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > 900;
        return Row(children: [
          if (wide) Expanded(flex: 5, child: _brandPanel()),
          Expanded(flex: 4, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: _form()))),
        ]);
      }),
    );
  }
}
