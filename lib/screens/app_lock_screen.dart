part of '../main.dart';

/// Local-only app lock. Passwords and hints are stored as salted SHA-256 hashes.
class AppLockService {
  static const _enabledKey = 'app_lock_enabled_v1';
  static const _passwordHashKey = 'app_lock_password_hash_v1';
  static const _passwordSaltKey = 'app_lock_password_salt_v1';
  static const _hintHashKey = 'app_lock_hint_hash_v1';
  static const _hintSaltKey = 'app_lock_hint_salt_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) == true &&
        (prefs.getString(_passwordHashKey) ?? '').isNotEmpty;
  }

  static Future<bool> hasHint() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_hintHashKey) ?? '').isNotEmpty;
  }

  static String _makeSalt() =>
      '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch}';

  static String _hash(String value, String salt) =>
      crypto.sha256.convert(utf8.encode('$salt:$value')).toString();

  static Future<void> configure({
    required String password,
    String? hint,
    required bool enableHint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final passwordSalt = _makeSalt();
    await prefs.setString(_passwordSaltKey, passwordSalt);
    await prefs.setString(_passwordHashKey, _hash(password, passwordSalt));
    await prefs.setBool(_enabledKey, true);
    if (enableHint && hint != null && hint.isNotEmpty) {
      final hintSalt = _makeSalt();
      await prefs.setString(_hintSaltKey, hintSalt);
      await prefs.setString(_hintHashKey, _hash(hint, hintSalt));
    } else {
      await prefs.remove(_hintSaltKey);
      await prefs.remove(_hintHashKey);
    }
  }

  static Future<bool> verifyPassword(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_passwordSaltKey);
    final expected = prefs.getString(_passwordHashKey);
    if (salt == null || expected == null) return false;
    return _hash(value, salt) == expected;
  }

  static Future<bool> verifyHint(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_hintSaltKey);
    final expected = prefs.getString(_hintHashKey);
    if (salt == null || expected == null) return false;
    return _hash(value, salt) == expected;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }
}

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _locked = false;
  bool _lockConfigured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLockState(initial: true);
  }

  Future<void> _refreshLockState({bool initial = false}) async {
    final enabled = await AppLockService.isEnabled();
    if (!mounted) return;
    setState(() {
      _lockConfigured = enabled;
      if (enabled && initial) _locked = true;
      _loading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_lockConfigured) setState(() => _locked = true);
    }
  }

  void _unlock() {
    if (mounted) setState(() => _locked = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_locked && _lockConfigured) {
      return AppLockScreen(onUnlocked: _unlock);
    }
    return widget.child;
  }
}

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _hintController = TextEditingController();
  bool _enabled = false;
  bool _hasHint = false;
  bool _addHint = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AppLockService.isEnabled();
    final hasHint = await AppLockService.hasHint();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hasHint = hasHint;
      _addHint = hasHint;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.trim().isEmpty) {
      _message('أدخل كلمة المرور الجديدة');
      return;
    }
    if (password != confirm) {
      _message('كلمتا المرور غير متطابقتين');
      return;
    }
    if (_addHint && _hintController.text.isEmpty && !_hasHint) {
      _message('أدخل التلميح أو أوقف خيار التلميح');
      return;
    }
    if (_addHint && _hintController.text.isEmpty && _hasHint) {
      // Existing hint remains unchanged when the user leaves the field blank.
      final prefs = await SharedPreferences.getInstance();
      final passwordSalt = '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('app_lock_password_salt_v1', passwordSalt);
      await prefs.setString('app_lock_password_hash_v1',
          crypto.sha256.convert(utf8.encode('$passwordSalt:$password')).toString());
      await prefs.setBool('app_lock_enabled_v1', true);
    } else {
      await AppLockService.configure(
        password: password,
        hint: _hintController.text,
        enableHint: _addHint,
      );
    }
    if (!mounted) return;
    setState(() {
      _enabled = true;
      _hasHint = _addHint;
      _saving = false;
    });
    _message('تم حفظ إعدادات الحماية');
    Navigator.pop(context, true);
  }

  Future<void> _disable() async {
    final password = _passwordController.text;
    if (!await AppLockService.verifyPassword(password)) {
      _message('أدخل كلمة المرور الحالية لإيقاف الحماية');
      return;
    }
    await AppLockService.disable();
    if (!mounted) return;
    setState(() => _enabled = false);
    _message('تم إيقاف الحماية');
    Navigator.pop(context, true);
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحماية بكلمة مرور'),
        backgroundColor: AppColors.solidBlue,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            const Text(
              'تُحفظ إعدادات الحماية على هذا الهاتف فقط. لا يتم تشفير قاعدة البيانات أو النسخ الاحتياطية.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: _enabled ? 'كلمة المرور الجديدة' : 'كلمة المرور',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إضافة تلميح بديل لفتح التطبيق'),
              subtitle: const Text('اختياري؛ سيعمل التلميح ككلمة مرور بديلة'),
              value: _addHint,
              onChanged: (value) => setState(() => _addHint = value),
            ),
            if (_addHint) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _hintController,
                decoration: InputDecoration(
                  labelText: _hasHint ? 'تلميح جديد (اتركه فارغًا للإبقاء على الحالي)' : 'التلميح البديل',
                  helperText: 'يمكن أن يكون حرفًا أو كلمة أو جملة. يجب إدخاله لاحقًا كما هو.',
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                try {
                  await _save();
                } catch (e) {
                  if (mounted) setState(() => _saving = false);
                  _message('تعذر حفظ الإعدادات: $e');
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('حفظ إعدادات الحماية'),
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _disable,
                icon: const Icon(Icons.lock_open),
                label: const Text('إيقاف الحماية'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _entryController = TextEditingController();
  bool _useHint = false;
  bool _busy = false;
  String? _error;
  int _failedAttempts = 0;

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _entryController.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final valid = _useHint
        ? await AppLockService.verifyHint(_entryController.text)
        : await AppLockService.verifyPassword(_entryController.text);
    if (!mounted) return;
    if (valid) {
      widget.onUnlocked();
    } else {
      _failedAttempts++;
      setState(() {
        _error = 'الإدخال غير صحيح. حاول مرة أخرى.';
        _entryController.clear();
      });
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 72, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text('تطبيق المحاسب محمي',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_useHint ? 'أدخل التلميح البديل' : 'أدخل كلمة المرور'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _entryController,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: _useHint ? 'التلميح' : 'كلمة المرور',
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('فتح التطبيق'),
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: AppLockService.hasHint(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) return const SizedBox.shrink();
                        return TextButton(
                          onPressed: _busy ? null : () => setState(() {
                            _useHint = !_useHint;
                            _entryController.clear();
                            _error = null;
                          }),
                          child: Text(_useHint ? 'استخدام كلمة المرور' : 'نسيت كلمة المرور؟ إدخال التلميح'),
                        );
                      },
                    ),
                    if (_failedAttempts >= 5)
                      const Text(
                        'تذكّر اختيار كلمة مرور وتلميح لا يعرفهما الآخرون.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.red),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
