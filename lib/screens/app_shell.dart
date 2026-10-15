part of '../main.dart';

class AlMuhasibApp extends StatefulWidget {
  const AlMuhasibApp({super.key});

  @override
  State<AlMuhasibApp> createState() => _AlMuhasibAppState();
}

class _AlMuhasibAppState extends State<AlMuhasibApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android does not provide a reliable callback for force-stop/swipe-away.
    // Paused is the practical signal that the UI has left the foreground.
    // WorkManager runs the queued backup independently of the UI process.
    if (state == AppLifecycleState.paused) {
      unawaited(AutoBackupService.scheduleBackupOnExit());
      unawaited(InstantBackupService.flushIfPending());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دفتر المحاسب الشامل',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', ''),
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        fontFamily: 'Cairo',
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.gold,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.gold,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.primary),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        useMaterial3: false,
      ),
      home: const AppLockGate(child: HomeScreen()),
    );
  }
}

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  const GradientAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.solidBlue,
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        toolbarHeight: toolbarHeight,
        foregroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
}

class LogoCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String shape;

  const LogoCropScreen({
    super.key,
    required this.imageBytes,
    required this.shape,
  });

  @override
  State<LogoCropScreen> createState() => _LogoCropScreenState();
}

class _LogoCropScreenState extends State<LogoCropScreen> {
  ui.Image? _image;
  double _zoom = 1.0;
  Offset _offset = Offset.zero;
  double _startZoom = 1.0;
  Offset _startOffset = Offset.zero;
  bool _saving = false;
  double _viewportSize = 320;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double _baseScale(Size size) {
    final image = _image!;
    return (size.width / image.width > size.height / image.height)
        ? size.width / image.width
        : size.height / image.height;
  }

  Offset _clampOffset(Offset value, Size size, double zoom) {
    final image = _image!;
    final scale = _baseScale(size) * zoom;
    final width = image.width * scale;
    final height = image.height * scale;
    final maxX = (width - size.width) / 2;
    final maxY = (height - size.height) / 2;
    return Offset(
      maxX <= 0 ? 0 : value.dx.clamp(-maxX, maxX).toDouble(),
      maxY <= 0 ? 0 : value.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  Future<void> _confirmCrop() async {
    if (_image == null || _saving) return;
    setState(() => _saving = true);
    try {
      const outputSize = 1024;
      final renderSize = Size(outputSize.toDouble(), outputSize.toDouble());
      final scale = _baseScale(renderSize) * _zoom;
      final image = _image!;
      final drawnWidth = image.width * scale;
      final drawnHeight = image.height * scale;
      final left = (outputSize - drawnWidth) / 2 + _offset.dx * (outputSize / _viewportSize);
      final top = (outputSize - drawnHeight) / 2 + _offset.dy * (outputSize / _viewportSize);
      final sourceRect = Rect.fromLTWH(
        (0 - left) / scale,
        (0 - top) / scale,
        outputSize / scale,
        outputSize / scale,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        image,
        sourceRect,
        Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(outputSize, outputSize);
      picture.dispose();
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (data == null) throw Exception('تعذر تجهيز الصورة');
      if (mounted) material.Navigator.of(context).pop(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قص الصورة: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحديد الشعار'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'حرّك الصورة بإصبعك، واستخدم إصبعين للتكبير والتصغير. ضع الجزء المطلوب داخل الإطار.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.maxWidth < constraints.maxHeight
                        ? constraints.maxWidth - 28
                        : constraints.maxHeight - 28;
                    final size = side.clamp(220.0, 360.0).toDouble();
                    _viewportSize = size;
                    if (image == null) {
                      return const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(),
                      );
                    }
                    return SizedBox(
                      width: size,
                      height: size,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) {
                          _startZoom = _zoom;
                          _startOffset = _offset;
                        },
                        onScaleUpdate: (details) {
                          final nextZoom = (_startZoom * details.scale).clamp(1.0, 8.0).toDouble();
                          setState(() {
                            _zoom = nextZoom;
                            _offset = _clampOffset(
                              _startOffset + details.focalPointDelta,
                              Size(size, size),
                              nextZoom,
                            );
                          });
                        },
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _LogoCropPainter(
                              image: image,
                              zoom: _zoom,
                              offset: _offset,
                              circular: widget.shape == 'circle',
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => material.Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _saving ? null : _confirmCrop,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('تأكيد وحفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoCropPainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final Offset offset;
  final bool circular;

  _LogoCropPainter({
    required this.image,
    required this.zoom,
    required this.offset,
    required this.circular,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseScale = (size.width / image.width > size.height / image.height)
        ? size.width / image.width
        : size.height / image.height;
    final scale = baseScale * zoom;
    final width = image.width * scale;
    final height = image.height * scale;
    final imageRect = Rect.fromLTWH(
      (size.width - width) / 2 + offset.dx,
      (size.height - height) / 2 + offset.dy,
      width,
      height,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    final frame = circular
        ? (Path()..addOval(Offset.zero & size))
        : (Path()..addRect(Offset.zero & size));
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(frame, Offset.zero);
    canvas.drawPath(outside, Paint()..color = Colors.black.withOpacity(0.56));
    canvas.drawPath(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.zoom != zoom ||
      oldDelegate.offset != offset ||
      oldDelegate.circular != circular;
}

class PersonalDataScreen extends StatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  State<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends State<PersonalDataScreen> {
  final List<TextEditingController> _lineControllers =
      List.generate(6, (_) => TextEditingController());
  final List<String> _lineColors = List<String>.filled(6, '#000000');
  final List<double> _lineSizes = List<double>.filled(6, 10.0);

  static const Map<String, String> _colorNames = {
    '#000000': 'أسود',
    '#1E3A5F': 'أزرق داكن',
    '#1565C0': 'أزرق',
    '#008577': 'أخضر مزرق',
    '#008000': 'أخضر',
    '#E65100': 'برتقالي',
    '#C62828': 'أحمر',
    '#7B1FA2': 'بنفسجي',
    '#6D4C41': 'بني',
    '#757575': 'رمادي',
  };

  String? _logoBase64;
  String _logoShape = 'circle';
  bool _loading = true;

  String _sideKey(int index) => index < 3 ? 'right' : 'left';
  int _lineNumber(int index) => index < 3 ? index + 1 : index - 2;
  String _textKey(int index) => '${_sideKey(index)}Line${_lineNumber(index)}';
  String _colorKey(int index) => '${_sideKey(index)}Color${_lineNumber(index)}';
  String _sizeKey(int index) => '${_sideKey(index)}Size${_lineNumber(index)}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _lineControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await PersonalDataService.getData();
    final logo = await PersonalDataService.getLogoBase64();
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _lineControllers.length; i++) {
        _lineControllers[i].text = (data[_textKey(i)] ?? '').toString();
        _lineColors[i] = (data[_colorKey(i)] ?? '#000000').toString();
        _lineSizes[i] = (data[_sizeKey(i)] as num?)?.toDouble() ?? 10.0;
      }
      _logoShape = data['logoShape'] as String;
      _logoBase64 = logo;
      _loading = false;
    });
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (img == null || !mounted) return;

    final shape = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('شكل الشعار'),
        content: const Text('اختر شكل إطار القص الذي تريد استخدامه للشعار.'),
        actions: [
          TextButton(
            onPressed: () => material.Navigator.pop(ctx, 'circle'),
            child: const Text('دائري'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () => material.Navigator.pop(ctx, 'square'),
            child: const Text('مربع'),
          ),
        ],
      ),
    );
    if (shape == null || !mounted) return;

    final sourceBytes = await img.readAsBytes();
    if (!mounted) return;
    final croppedBytes = await material.Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => LogoCropScreen(imageBytes: sourceBytes, shape: shape),
      ),
    );
    if (croppedBytes == null || !mounted) return;

    final base64Data = base64Encode(croppedBytes);
    try {
      await PersonalDataService.saveLogoBase64(base64Data);
      await PersonalDataService.saveData(logoShape: shape);
      if (!mounted) return;
      setState(() {
        _logoBase64 = base64Data;
        _logoShape = shape;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الشعار المحدد')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الشعار: $e')),
      );
    }
  }

  Future<void> _deleteLogo() async {
    await PersonalDataService.saveLogoBase64(null);
    if (!mounted) return;
    setState(() => _logoBase64 = null);
  }

  Future<void> _save() async {
    final lineTexts = <String, String>{};
    final lineColors = <String, String>{};
    final lineSizes = <String, double>{};
    for (var i = 0; i < _lineControllers.length; i++) {
      lineTexts[_textKey(i)] = _lineControllers[i].text.trim();
      lineColors[_colorKey(i)] = _lineColors[i];
      lineSizes[_sizeKey(i)] = _lineSizes[i];
    }
    await PersonalDataService.saveData(
      lineTexts: lineTexts,
      lineColors: lineColors,
      lineSizes: lineSizes,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ تم حفظ البيانات'),
        backgroundColor: AppColors.green,
      ));
      material.Navigator.pop(context);
    }
  }

  Widget _buildLineEditor(int index, String lineLabel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _lineControllers[index],
              decoration: InputDecoration(
                labelText: lineLabel,
                hintText: lineLabel,
                prefixIcon: const Icon(Icons.edit),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _lineColors[index],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'لون الخط',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _colorNames.entries.map((entry) {
                      final colorValue = int.parse(entry.key.substring(1), radix: 16);
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(0xFF000000 | colorValue),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(child: Text(entry.value, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _lineColors[index] = value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<double>(
                    value: _lineSizes[index],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'حجم الخط',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: const [8, 9, 10, 11, 12, 14, 16, 18, 20]
                        .map((size) => DropdownMenuItem<double>(
                              value: size.toDouble(),
                              child: Text('$size'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _lineSizes[index] = value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('البيانات الشخصية'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => material.Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: _logoBase64 != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(
                        _logoShape == 'circle' ? 100 : 12),
                    child: Image.memory(
                      base64Decode(_logoBase64!),
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickLogo,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.image),
                label: const Text('تغيير الشعار'),
              ),
              const SizedBox(width: 10),
              if (_logoBase64 != null)
                ElevatedButton.icon(
                  onPressed: _deleteLogo,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  icon: const Icon(Icons.delete),
                  label: const Text('حذف الشعار'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'البيانات التي تظهر في ترويسة التقارير',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          const Text('يمين الصفحة', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 10),
          _buildLineEditor(0, 'السطر الأول'),
          _buildLineEditor(1, 'السطر الثاني'),
          _buildLineEditor(2, 'السطر الثالث'),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          const Text('يسار الصفحة', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 10),
          _buildLineEditor(3, 'السطر الأول'),
          _buildLineEditor(4, 'السطر الثاني'),
          _buildLineEditor(5, 'السطر الثالث'),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.save),
            label: const Text('حفظ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ==================== HomeScreen ====================
