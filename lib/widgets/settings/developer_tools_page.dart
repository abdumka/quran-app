import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_update_service.dart';
import '../../services/notification_center.dart';
import '../../services/push_notification_service.dart';

const Color _gold = Color(0xFF8B7355);
const Color _border = Color(0xFFE8DCC8);
const Color _cardBackground = Color(0xFFFBF6EC);

/// Tools for trying things out on a real device — reached by tapping the ℹ️ on
/// «إعدادات متقدمة» seven times, so it stays out of an ordinary reader's way
/// without being hidden from anyone who needs it.
///
/// Deliberately a plain list of sections: add a new [_Section] below the
/// notification one and nothing else needs touching.
class DeveloperToolsPage extends StatefulWidget {
  const DeveloperToolsPage({super.key});

  @override
  State<DeveloperToolsPage> createState() => _DeveloperToolsPageState();
}

class _DeveloperToolsPageState extends State<DeveloperToolsPage> {
  final PushNotificationService _push = PushNotificationService.instance;

  bool? _notificationsAllowed;
  String? _token;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final allowed = await NotificationCenter.instance.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _notificationsAllowed = allowed;
      _token = _push.token;
    });
  }

  void _notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, textDirection: TextDirection.rtl),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _copyToken() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      _notify('لا يوجد معرّف بعد. تأكد من الاتصال بالإنترنت ثم أعد المحاولة.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    _notify('تم نسخ معرّف الجهاز.');
  }

  Future<void> _setTestTopic(bool value) async {
    setState(() => _busy = true);
    final ok = await _push.setTestTopicEnabled(value);
    if (!mounted) return;
    setState(() => _busy = false);
    _notify(
      ok
          ? (value
                ? 'تم اشتراك هذا الجهاز في إشعارات التجربة.'
                : 'تم إلغاء اشتراك هذا الجهاز.')
          : 'تعذّر تنفيذ الطلب الآن. سيُعاد المحاولة عند تشغيل التطبيق لاحقًا.',
    );
  }

  Future<void> _sendLocalTest() async {
    final shown = await _push.showLocalTestNotification();
    if (!mounted) return;
    _notify(
      shown
          ? 'تم إرسال إشعار تجريبي.'
          : 'الإشعارات غير مسموح بها لهذا التطبيق في إعدادات النظام.',
    );
  }

  Future<void> _requestPermission() async {
    await NotificationCenter.instance.requestPermission();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final update = AppUpdateService.instance;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFBF6),
        appBar: AppBar(
          title: const Text('أدوات الاختبار'),
          backgroundColor: _cardBackground,
          foregroundColor: const Color(0xFF6F5A3C),
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'تحديث الحالة',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refresh,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _Section(
              title: 'معلومات البناء',
              children: [
                _InfoRow(
                  label: 'الإصدار',
                  value: update.currentVersion.isEmpty
                      ? '—'
                      : '${update.currentVersion} (${update.currentBuild})',
                ),
              ],
            ),
            _Section(
              title: 'الإشعارات',
              children: [
                _InfoRow(
                  label: 'إذن الإشعارات',
                  value: switch (_notificationsAllowed) {
                    null => '…',
                    true => 'مسموح',
                    false => 'غير مسموح',
                  },
                  trailing: _notificationsAllowed == false
                      ? TextButton(
                          onPressed: _requestPermission,
                          child: const Text('اطلب الإذن'),
                        )
                      : null,
                ),
                _InfoRow(
                  label: 'معرّف الجهاز للإشعارات',
                  value: _token == null || _token!.isEmpty
                      ? 'غير متاح'
                      : '${_token!.substring(0, 12)}…',
                  trailing: TextButton(
                    onPressed: _copyToken,
                    child: const Text('نسخ'),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _push.testTopicEnabled,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      activeThumbColor: _gold,
                      value: enabled,
                      onChanged: _busy ? null : _setTestTopic,
                      title: const Text(
                        'استقبال إشعارات التجربة',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'يستقبل هذا الجهاز الرسائل المرسلة إلى مجموعة «test» وحدها، دون بقية المستخدمين.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF888888),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _sendLocalTest,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('إرسال إشعار تجريبي الآن'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Room for whatever comes next: add another _Section here.
          ],
        ),
      ),
    );
  }
}

/// One titled group of tools.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: _cardBackground,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6F5A3C),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A label with a value, and optionally a button that acts on it.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 12, color: _gold)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
