import 'package:flutter/foundation.dart';

/// الشاشة الحالية (مصدر واحد للحقيقة) — يستخدمها القائمة الجانبية ولوحة التحكم للانتقال.
class NavState extends ChangeNotifier {
  String current = 'dashboard';

  void goTo(String id) {
    if (id != current) {
      current = id;
      notifyListeners();
    }
  }
}
