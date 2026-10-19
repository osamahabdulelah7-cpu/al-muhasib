part of '../main.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  bool _isSearchingTransactions = false;
  final TextEditingController _transactionSearchController = TextEditingController();
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => Provider.of<AppAccountProvider>(context,
            listen: false)
        .loadTransactions(int.parse(widget.customer['id'].toString())));
  }

  @override
  void dispose() {
    _transactionSearchController.dispose();
    super.dispose();
  }

  Map<String, String> _formatDateTime(String rawDateTime) {
    try {
      DateTime dt = DateTime.parse(rawDateTime);
      String dateStr = "${dt.year}-${dt.month}-${dt.day}";
      int hour = dt.hour;
      String period = hour >= 12 ? 'م' : 'ص';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      String timeStr =
          "$hour:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} $period";
      return {'date': dateStr, 'time': timeStr};
    } catch (e) {
      List<String> parts = rawDateTime.split(' ');
      if (parts.length >= 2) {
        return {'date': parts[0], 'time': parts.sublist(1).join(' ')};
      }
      return {'date': rawDateTime, 'time': ''};
    }
  }

  void _showTransactionOptionsModal(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 15),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.edit, color: AppColors.primary),
            ),
            title: const Text('تعديل العملية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              material.Navigator.pop(ctx);
              _showEditTransactionDialog(context, tx);
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete, color: AppColors.red),
            ),
            title: const Text('حذف العملية',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.red)),
            onTap: () async {
              material.Navigator.pop(ctx);
              await provider.deleteTransaction(
                int.parse(tx['id'].toString()),
                int.parse(widget.customer['id'].toString()),
              );
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  OverlayEntry? _showSuggestionsOverlay({
    required BuildContext parentContext,
    required GlobalKey anchorKey,
    required List<String> suggestions,
    required TextEditingController controller,
    required VoidCallback onSelected,
    required VoidCallback onDismiss,
  }) {
    if (suggestions.isEmpty) return null;
    final anchorContext = anchorKey.currentContext;
    final overlay = Overlay.of(parentContext);
    if (anchorContext == null) return null;
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final fieldTop = renderObject.localToGlobal(Offset.zero).dy;
    final fieldLeft = renderObject.localToGlobal(Offset.zero).dx;
    final fieldWidth = renderObject.size.width;
    final visibleCount = suggestions.length < 5 ? suggestions.length : 5;
    final listHeight = visibleCount * 48.0;
    final top = (fieldTop - listHeight - 6).clamp(8.0, double.infinity).toDouble();
    final entry = OverlayEntry(builder: (overlayContext) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
        left: fieldLeft,
        top: top,
        width: fieldWidth,
        child: Material(
          elevation: 8,
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: listHeight),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) => InkWell(
                onTap: () {
                  controller.value = TextEditingValue(
                    text: suggestions[i],
                    selection: TextSelection.collapsed(offset: suggestions[i].length),
                  );
                  onSelected();
                },
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Icon(Icons.history, size: 19,
                          color: AppColors.primary.withOpacity(0.65)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(suggestions[i],
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14, color: AppColors.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
          ),
        ],
      );
    });
    overlay.insert(entry);
    return entry;
  }

  void _showEditTransactionDialog(BuildContext context, Map<String, dynamic> tx) {
    double amt = (tx['amount'] as num).toDouble();
    String amtStr = amt == amt.roundToDouble()
        ? amt.toInt().toString()
        : amt.toString();
    final amountCtrl = TextEditingController(text: amtStr);
    amountCtrl.selection = TextSelection(
        baseOffset: 0, extentOffset: amountCtrl.text.length);
    final detailsCtrl =
        TextEditingController(text: tx['details']?.toString() ?? '');
    DateTime selectedDate;
    try {
      selectedDate = DateTime.parse(tx['date'].toString().substring(0, 10));
    } catch (_) {
      selectedDate = DateTime.now();
    }
    String? selectedImageBase64 = tx['image_data']?.toString();
    final dateCtrl = TextEditingController(
        text: '${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}');

    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    Timer? suggestionDebounce;
    int suggestionRequest = 0;
    OverlayEntry? suggestionsOverlay;
    final detailsFieldKey = GlobalKey();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(children: [
            IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => material.Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
            const Spacer(),
            const Text('تعديل العملية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.edit, color: AppColors.primary),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      onTap: () {
                        amountCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: amountCtrl.text.length);
                      },
                      decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = picked;
                            dateCtrl.text =
                                '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: dateCtrl,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                              labelText: 'التاريخ',
                              border: UnderlineInputBorder()),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 15),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      key: detailsFieldKey,
                      controller: detailsCtrl,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'التفاصيل / البيان',
                          border: UnderlineInputBorder()),
                      onChanged: (val) {
                        suggestionDebounce?.cancel();
                        final request = ++suggestionRequest;
                        if (val.trim().length < 2) {
                          suggestionsOverlay?.remove();
                          suggestionsOverlay = null;
                          return;
                        }
                        suggestionDebounce = Timer(const Duration(milliseconds: 250), () async {
                          final allDetails = await provider.getDistinctDetails(query: val.trim());
                          if (request != suggestionRequest || detailsCtrl.text.trim() != val.trim()) return;
                          // Preserve the original suggestion order while including
                          // both prefix and partial-text matches.
                          final combined = allDetails
                              .where((d) => d.contains(val.trim()) && d != val.trim())
                              .toList();
                          if (!context.mounted) return;
                          suggestionsOverlay?.remove();
                          suggestionsOverlay = null;
                          if (combined.isNotEmpty) {
                            suggestionsOverlay = _showSuggestionsOverlay(
                              parentContext: context,
                              anchorKey: detailsFieldKey,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onDismiss: () {
                                suggestionsOverlay?.remove();
                                suggestionsOverlay = null;
                              },
                              onSelected: () {
                                suggestionsOverlay?.remove();
                                suggestionsOverlay = null;
                                setDialogState(() {});
                              },
                            );
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (imageCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: const Text('اختر مصدر الصورة'),
                          content: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.camera_alt,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الكاميرا'),
                                onPressed: () async {
                                  material.Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.photo_library,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الهاتف'),
                                onPressed: () async {
                                  material.Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },                    child: selectedImageBase64 == null
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.camera_alt,
                                color: Colors.grey, size: 28))
                        : GestureDetector(
                            onTap: () => _showImageOptionsSheet(
                                context, provider, tx),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                  base64Decode(selectedImageBase64!),
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover),
                            ),
                          ),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final original = DateTime.tryParse(tx['date']?.toString() ?? '');
                        final time = original ?? DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        await provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'take',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        material.Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('عليه',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final original = DateTime.tryParse(tx['date']?.toString() ?? '');
                        final time = original ?? DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        await provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'give',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        material.Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('له',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      suggestionDebounce?.cancel();
      suggestionRequest++;
      suggestionsOverlay?.remove();
      suggestionsOverlay = null;
      detailsCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
    });
  }

  void _showAddTransactionDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedImageBase64;
    final dateCtrl = TextEditingController(
        text: '${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}');

    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    Timer? suggestionDebounce;
    int suggestionRequest = 0;
    OverlayEntry? suggestionsOverlay;
    final detailsFieldKey = GlobalKey();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(children: [
            IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => material.Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
            const Spacer(),
            const Text('إضافة عملية جديدة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.add_circle_outline, color: AppColors.primary),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = picked;
                            dateCtrl.text =
                                '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: dateCtrl,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                              labelText: 'التاريخ',
                              border: UnderlineInputBorder()),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 15),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      key: detailsFieldKey,
                      controller: detailsCtrl,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'التفاصيل / البيان',
                          border: UnderlineInputBorder()),
                      onChanged: (val) {
                        suggestionDebounce?.cancel();
                        final request = ++suggestionRequest;
                        if (val.trim().length < 2) {
                          suggestionsOverlay?.remove();
                          suggestionsOverlay = null;
                          return;
                        }
                        suggestionDebounce = Timer(const Duration(milliseconds: 250), () async {
                          final allDetails = await provider.getDistinctDetails(query: val.trim());
                          if (request != suggestionRequest || detailsCtrl.text.trim() != val.trim()) return;
                          // Preserve the original suggestion order while including
                          // both prefix and partial-text matches.
                          final combined = allDetails
                              .where((d) => d.contains(val.trim()) && d != val.trim())
                              .toList();
                          if (!context.mounted) return;
                          suggestionsOverlay?.remove();
                          suggestionsOverlay = null;
                          if (combined.isNotEmpty) {
                            suggestionsOverlay = _showSuggestionsOverlay(
                              parentContext: context,
                              anchorKey: detailsFieldKey,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onDismiss: () {
                                suggestionsOverlay?.remove();
                                suggestionsOverlay = null;
                              },
                              onSelected: () {
                                suggestionsOverlay?.remove();
                                suggestionsOverlay = null;
                                setDialogState(() {});
                              },
                            );
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (imageCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: const Text('اختر مصدر الصورة'),
                          content: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.camera_alt,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الكاميرا'),
                                onPressed: () async {
                                  material.Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.photo_library,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الهاتف'),
                                onPressed: () async {
                                  material.Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: selectedImageBase64 == null
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.camera_alt,
                                color: Colors.grey, size: 28))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                                base64Decode(selectedImageBase64!),
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover),
                          ),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        await provider.addTransaction(
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'take',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        if (ctx.mounted) material.Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('عليه',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        await provider.addTransaction(
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'give',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        if (ctx.mounted) material.Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('له',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      suggestionDebounce?.cancel();
      suggestionRequest++;
      suggestionsOverlay?.remove();
      suggestionsOverlay = null;
      detailsCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
    });
  }

  Future<void> _showTransactionDetailsDialog(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) async {
    final bool isGive = tx['type'] == 'give';
    final double amt = (tx['amount'] as num).toDouble();
    final String details = tx['details']?.toString() ?? '';
    final String dateStr = tx['date'].toString();
    String? imageData = tx['image_data']?.toString();
    if ((imageData == null || imageData.isEmpty) &&
        (tx['image_path']?.toString().isNotEmpty ?? false)) {
      final bytes = await ImageStorageService.readRelative(tx['image_path']?.toString());
      if (bytes != null) imageData = base64Encode(bytes);
    }
    final dialogTx = {...tx, if (imageData != null) 'image_data': imageData};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(16),
        title: Row(children: [
          Icon(isGive ? Icons.arrow_downward : Icons.arrow_upward,
              color: isGive ? AppColors.green : AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.customer['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailRow('المبلغ :', formatNumber(amt)),
                const Divider(),
                _detailRow('التاريخ :', dateStr.split(' ')[0]),
                const Divider(),
                _detailRow('التفاصيل :', details.isEmpty ? '-' : details),
                if (imageData != null && imageData.isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showImageOptionsSheet(ctx, provider, dialogTx),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(base64Decode(imageData),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                  ),
                ],
              ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              material.Navigator.pop(ctx);
              _showEditTransactionDialog(context, tx);
            },
            child: const Text('تعديل',
                style: TextStyle(color: AppColors.goldDark, fontSize: 15)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
            onPressed: () => material.Navigator.pop(ctx),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ]),
    );
  }

  void _showImageOptionsSheet(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) {
    final int txId = int.parse(tx['id'].toString());
    final String? imageData = tx['image_data']?.toString();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (imageData != null && imageData.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.visibility, color: AppColors.green),
              title: const Text('فتح الصورة'),
              onTap: () {
                material.Navigator.pop(ctx);
                _showFullImage(context, imageData);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.red),
              title: const Text('حذف الصورة'),
              onTap: () async {
                material.Navigator.pop(ctx);
                await _updateTransactionImage(provider, txId, null);
                if (context.mounted) material.Navigator.pop(context);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppColors.primary),
            title: const Text('الكاميرا'),
            onTap: () async {
              material.Navigator.pop(ctx);
              final img = await ImagePicker().pickImage(
                  source: ImageSource.camera, imageQuality: 60, maxWidth: 1600, maxHeight: 1600);
              if (img != null) {
                final bytes = await img.readAsBytes();
                await _updateTransactionImage(
                    provider, txId, base64Encode(bytes));
                if (context.mounted) material.Navigator.pop(context);
              }
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('الهاتف'),
            onTap: () async {
              material.Navigator.pop(ctx);
              final img = await ImagePicker().pickImage(
                  source: ImageSource.gallery, imageQuality: 60, maxWidth: 1600, maxHeight: 1600);
              if (img != null) {
                final bytes = await img.readAsBytes();
                await _updateTransactionImage(
                    provider, txId, base64Encode(bytes));
                if (context.mounted) material.Navigator.pop(context);
              }
            },
          ),
        ]),
      ),
    );
  }

  void _showFullImage(BuildContext context, String base64Data) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(base64Decode(base64Data)),
        ),
      ),
    );
  }

  Future<void> _updateTransactionImage(
      AppAccountProvider provider, int txId, String? imageData) async {
    final db = await AppDBHelper.instance.database;
    final existing = await db.query('transactions',
        where: 'id = ?', whereArgs: [txId], limit: 1);
    if (existing.isEmpty) return;
    final oldPath = existing.first['image_path']?.toString();
    String? newPath;
    try {
      if (imageData != null && imageData.trim().isNotEmpty) {
        newPath = await ImageStorageService.saveBase64(imageData, 'tx_$txId');
        if (newPath == null) throw Exception('تعذر حفظ صورة العملية');
      }
      await db.update('transactions',
          {'image_data': null, 'image_path': newPath},
          where: 'id = ?', whereArgs: [txId]);
    } catch (_) {
      if (newPath != null) await ImageStorageService.deleteRelative(newPath);
      rethrow;
    }
    InstantBackupService.markChanged();
    if (oldPath != null && oldPath != newPath) {
      await ImageStorageService.deleteRelative(oldPath);
    }
    await provider.loadTransactions(int.parse(widget.customer['id'].toString()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final rawTransactions = provider.currentTransactions;

    double cumulative = 0.0, totalGive = 0.0, totalTake = 0.0;
    List<Map<String, dynamic>> processedTransactions = [];
    final customerCurrency = (widget.customer['currency'] ?? '').toString();
    for (var tx in rawTransactions) {
      final txCurrency = (tx['currency'] ?? '').toString();
      if (txCurrency != customerCurrency) continue;
      double amt = (tx['amount'] as num).toDouble();
      if (tx['type'] == 'give') {
        cumulative += amt;
        totalGive += amt;
      } else {
        cumulative -= amt;
        totalTake += amt;
      }
      processedTransactions.add({...tx, 'running_balance': cumulative});
    }
    final double finalBalance = cumulative;
    final allDisplayTransactions = processedTransactions.reversed.toList();
    final query = _transactionSearchController.text.trim().toLowerCase();
    final displayTransactions = query.isEmpty
        ? allDisplayTransactions
        : allDisplayTransactions.where((tx) =>
            (tx['details'] ?? '').toString().toLowerCase().contains(query)).toList();

    return Scaffold(
      appBar: GradientAppBar(
        title: _isSearchingTransactions
            ? TextField(
                controller: _transactionSearchController,
                autofocus: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  hintText: 'بحث في التفاصيل...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.black54),
                ),
                onChanged: (_) => setState(() {}),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.customer['name'].toString(),
                      style: const TextStyle(fontSize: 18, color: Colors.black)),
                  if (widget.customer['phone'] != null &&
                      widget.customer['phone'].toString().trim().isNotEmpty)
                    Text(widget.customer['phone'].toString(),
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => material.Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
            tooltip: 'التقارير PDF وExcel',
            onPressed: () => _showReportsDialog(
                processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.black, size: 26),
            tooltip: 'إرسال رسالة للعميل عبر واتساب',
            onPressed: () => _sendWhatsApp(
                widget.customer['phone']?.toString(), finalBalance),
          ),
          IconButton(
            icon: Icon(_isSearchingTransactions ? Icons.close : Icons.search,
                color: Colors.black),
            tooltip: _isSearchingTransactions ? 'إغلاق البحث' : 'بحث في التفاصيل',
            onPressed: () {
              setState(() {
                _isSearchingTransactions = !_isSearchingTransactions;
                _transactionSearchController.clear();
              });
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: displayTransactions.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.receipt_long,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 15),
                      Text('لا توجد عمليات مسجلة',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 15)),
                    ]))
              : Column(children: [
                  Container(
                    color: AppColors.solidBlue,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 4),
                    child: const Row(children: [
                      Expanded(
                          flex: 3,
                          child: Text('التاريخ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 2,
                          child: Text('المبلغ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 4,
                          child: Text('التفاصيل',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 2,
                          child: Text('الرصيد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                    ]),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: displayTransactions.length,
                      separatorBuilder: (ctx, index) => const Divider(
                          height: 1, color: Color(0xFFEEEEEE)),
                      itemBuilder: (ctx, i) {
                        final tx = displayTransactions[i];
                        final bool isGive = tx['type'] == 'give';
                        final double runBal = tx['running_balance'];
                        final double amt = (tx['amount'] as num).toDouble();
                        final dateTimeFormatted =
                            _formatDateTime(tx['date'].toString());
                        Color amtBg =
                            isGive ? AppColors.green : AppColors.red;
                        Color balBg = runBal >= 0
                            ? AppColors.green
                            : AppColors.red;

                        return InkWell(
                          onTap: () => _showTransactionDetailsDialog(
                              context, provider, tx),
                          onLongPress: () =>
                              _showTransactionOptionsModal(context, provider, tx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 4),
                            color: i.isEven
                                ? Colors.white
                                : const Color(0xFFF9FAFB),
                            child: Row(children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(dateTimeFormatted['date']!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textDark)),
                                      if (dateTimeFormatted['time']!
                                          .isNotEmpty)
                                        Text(dateTimeFormatted['time']!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textMuted)),
                                    ]),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 2),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 2),
                                  decoration: BoxDecoration(
                                      color: amtBg,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(formatNumber(amt),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Text(
                                      (tx['details'] ?? '').toString(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textDark)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 2),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 2),
                                  decoration: BoxDecoration(
                                      color: balBg,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(formatNumber(runBal.abs()),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: AppColors.background,
          child: Row(children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => _showAddTransactionDialog(context),
                  child: const Center(
                      child: Icon(Icons.add, color: AppColors.gold, size: 30)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.solidBlue,
                    borderRadius: BorderRadius.circular(8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('عليه: ${formatNumber(totalTake)}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        Text('له: ${formatNumber(totalGive)}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ]),
                  const SizedBox(height: 3),
                  Container(
                      height: 1, color: Colors.black.withOpacity(0.2)),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                        '${finalBalance == 0 ? "الرصيد" : (finalBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(finalBalance.abs())}',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _showReportsDialog(
      List<Map<String, dynamic>> allTxs,
      double totalGive,
      double totalTake,
      double finalBalance) async {
    DateTime start = _reportStartDate ?? DateTime(DateTime.now().year, 1, 1);
    DateTime end = _reportEndDate ?? DateTime(DateTime.now().year, 12, 31);
    bool usePeriod = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('التقارير', textAlign: TextAlign.center),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تحديد تاريخ الفترة'),
                value: usePeriod,
                onChanged: (value) => setDialogState(() => usePeriod = value ?? false),
              ),
              if (usePeriod) ...[
                Row(children: [
                  Expanded(child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('من'),
                    subtitle: Text('${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: start,
                        firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => start = picked);
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إلى'),
                    subtitle: Text('${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: end,
                        firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => end = picked);
                    },
                  )),
                ]),
              ],
              const Divider(),
              Row(children: [
                Expanded(child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text('PDF'),
                  onTap: () { material.Navigator.pop(dialogContext); _runReportExport(allTxs, start, end, usePeriod, true); },
                )),
                const SizedBox(width: 16),
                Expanded(child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.table_view, color: Colors.green),
                  title: const Text('Excel'),
                  onTap: () { material.Navigator.pop(dialogContext); _runReportExport(allTxs, start, end, usePeriod, false); },
                )),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat, color: Colors.green, size: 30),
                title: const Text('مشاركة عبر واتساب'),
                subtitle: const Text('اختر PDF أو Excel'),
                onTap: () {
                  material.Navigator.pop(dialogContext);
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        title: const Text('PDF'),
                        onTap: () { material.Navigator.pop(ctx); _runReportExport(allTxs, start, end, usePeriod, true, shareFile: true); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.table_view, color: Colors.green),
                        title: const Text('Excel'),
                        onTap: () { material.Navigator.pop(ctx); _runReportExport(allTxs, start, end, usePeriod, false, shareFile: true); },
                      ),
                    ])),
                  );
                },
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => material.Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      ),
    );
  }

  Future<void> _runReportExport(List<Map<String, dynamic>> allTxs,
      DateTime start, DateTime end, bool usePeriod, bool pdf,
      {bool shareFile = false}) async {
    if (usePeriod && start.isAfter(end)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاريخ البداية يجب ألا يكون بعد تاريخ النهاية')));
      return;
    }
    final selected = usePeriod ? allTxs.where((tx) {
      try {
        final dt = DateTime.parse(tx['date'].toString());
        final day = DateTime(dt.year, dt.month, dt.day);
        return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
            !day.isAfter(DateTime(end.year, end.month, end.day));
      } catch (_) { return false; }
    }).toList() : List<Map<String, dynamic>>.from(allTxs);
    double give = 0, take = 0, balance = 0;
    for (final tx in selected) {
      final amount = (tx['amount'] as num).toDouble();
      if (tx['type'] == 'give') { give += amount; balance += amount; }
      else { take += amount; balance -= amount; }
    }
    _reportStartDate = start;
    _reportEndDate = end;
    if (pdf) {
      await _exportToPdf(selected, give, take, balance, shareFile: shareFile);
    } else {
      await _exportToExcel(selected, give, take, balance, shareFile: shareFile);
    }
  }

  // Convert whole amounts to integer Excel cells so they never display a decimal point.
  excel_lib.CellValue _createNumberCell(double value) {
    if (value == value.roundToDouble()) {
      return excel_lib.IntCellValue(value.toInt());
    }
    return excel_lib.DoubleCellValue(value);
  }

  // ============ تصدير كشف الحساب إلى Excel ============
  Future<void> _exportToExcel(
      List<Map<String, dynamic>> txs,
      double totalGive,
      double totalTake,
      double finalBal, {bool shareFile = false}) async {
    try {
      if (txs.isEmpty) {
        throw Exception('لا توجد حركات لتصديرها في هذا الحساب أو ضمن الفترة المحددة');
      }
      final workbook = excel_lib.Excel.createExcel();
      final sheet = workbook['كشف الحساب'];
      try { workbook.delete('Sheet1'); } catch (_) {}

      final blue = excel_lib.ExcelColor.fromHexString('#0000FF');
      final black = excel_lib.ExcelColor.fromHexString('#000000');
      final border = excel_lib.Border(
        borderStyle: excel_lib.BorderStyle.Thin, borderColorHex: black);
      final strongBorder = excel_lib.Border(
        borderStyle: excel_lib.BorderStyle.Medium, borderColorHex: black);
      final titleStyle = excel_lib.CellStyle(
        bold: true, fontSize: 16, fontColorHex: blue,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center);
      final headerStyle = excel_lib.CellStyle(
        bold: true, fontSize: 12, fontColorHex: blue,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        topBorder: strongBorder, bottomBorder: strongBorder,
        leftBorder: border, rightBorder: border);
      final dataStyle = excel_lib.CellStyle(
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        topBorder: border, bottomBorder: border,
        leftBorder: border, rightBorder: border);
      final totalStyle = excel_lib.CellStyle(
        bold: true, fontColorHex: blue,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        topBorder: strongBorder, bottomBorder: strongBorder,
        leftBorder: border, rightBorder: border);

      // Use a format without a decimal separator for whole numbers. Some
      // spreadsheet viewers display a trailing point with '#,##0.##'.
      excel_lib.CellStyle numberCellStyle(double value, {bool total = false}) {
        final whole = value == value.roundToDouble();
        return excel_lib.CellStyle(
          bold: total,
          fontColorHex: total ? blue : black,
          horizontalAlign: excel_lib.HorizontalAlign.Center,
          verticalAlign: excel_lib.VerticalAlign.Center,
          numberFormat: excel_lib.NumFormat.custom(
            formatCode: whole ? '#,##0' : '#,##0.##',
          ),
          topBorder: total ? strongBorder : border,
          bottomBorder: total ? strongBorder : border,
          leftBorder: border,
          rightBorder: border,
        );
      }

      sheet.appendRow([
        excel_lib.TextCellValue('كشف حساب - ${widget.customer['name']}'),
        excel_lib.TextCellValue(''), excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''), excel_lib.TextCellValue(''),
      ]);
      sheet.merge(excel_lib.CellIndex.indexByString('A1'),
          excel_lib.CellIndex.indexByString('E1'));
      // Column mapping requested: A=الرصيد, B=له, C=عليه, D=التفاصيل, E=التاريخ.
      sheet.appendRow([
        excel_lib.TextCellValue('الرصيد'),
        excel_lib.TextCellValue('له'),
        excel_lib.TextCellValue('عليه'),
        excel_lib.TextCellValue('التفاصيل'),
        excel_lib.TextCellValue('التاريخ'),
      ]);

      double runningBalance = 0;
      for (final tx in txs) {
        final isGive = tx['type'] == 'give';
        final amount = (tx['amount'] as num).toDouble();
        runningBalance += isGive ? amount : -amount;
        String dateOnly = (tx['date'] ?? '').toString().split(' ').first;
        try {
          final dt = DateTime.parse(tx['date'].toString());
          dateOnly = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {}
        sheet.appendRow([
          _createNumberCell(runningBalance.abs()),
          _createNumberCell(isGive ? amount : 0),
          _createNumberCell(isGive ? 0 : amount),
          excel_lib.TextCellValue((tx['details'] ?? '').toString()),
          excel_lib.TextCellValue(dateOnly),
        ]);
      }

      final totalRow = txs.length + 3;
      sheet.appendRow([
        _createNumberCell(finalBal.abs()),
        _createNumberCell(totalGive),
        _createNumberCell(totalTake),
        excel_lib.TextCellValue('إجمالي العمليات'),
        excel_lib.TextCellValue(''),
      ]);
      final balanceRow = totalRow + 1;
      final balanceLabel = finalBal == 0 ? 'الرصيد الإجمالي' :
          (finalBal > 0 ? 'الرصيد الإجمالي - له' : 'الرصيد الإجمالي - عليه');
      sheet.appendRow([
        _createNumberCell(finalBal.abs()),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(balanceLabel),
        excel_lib.TextCellValue(''),
      ]);
      sheet.merge(excel_lib.CellIndex.indexByString('D${balanceRow}'),
          excel_lib.CellIndex.indexByString('E${balanceRow}'));

      for (var col = 0; col < 5; col++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = titleStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1)).cellStyle = headerStyle;
      }
      for (var row = 2; row < txs.length + 2; row++) {
        for (var col = 0; col < 5; col++) {
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).cellStyle = dataStyle;
        }
      }
      for (var col = 0; col < 5; col++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalRow - 1)).cellStyle = totalStyle;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: balanceRow - 1)).cellStyle = totalStyle;
      }

      // Override numeric cells with integer/decimal-specific formats.
      double styledRunningBalance = 0;
      for (var row = 0; row < txs.length; row++) {
        final tx = txs[row];
        final amount = (tx['amount'] as num).toDouble();
        final isGive = tx['type'] == 'give';
        styledRunningBalance += isGive ? amount : -amount;
        final values = [styledRunningBalance.abs(), isGive ? amount : 0.0, isGive ? 0.0 : amount];
        for (var col = 0; col < values.length; col++) {
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 2)).cellStyle = numberCellStyle(values[col]);
        }
      }
      final totalValues = [finalBal.abs(), totalGive, totalTake, finalBal.abs()];
      for (var col = 0; col < 3; col++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalRow - 1)).cellStyle = numberCellStyle(totalValues[col], total: true);
      }
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: balanceRow - 1)).cellStyle = numberCellStyle(totalValues[3], total: true);
      sheet.setColumnWidth(0, 16); // A: الرصيد
      sheet.setColumnWidth(1, 14); // B: له
      sheet.setColumnWidth(2, 14); // C: عليه
      sheet.setColumnWidth(3, 30); // D: التفاصيل
      sheet.setColumnWidth(4, 16); // E: التاريخ
      sheet.setRowHeight(0, 30);
      sheet.setRowHeight(1, 25);

      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) throw Exception('فشل إنشاء محتوى ملف Excel');
      final tempDir = Directory(p.join((await getTemporaryDirectory()).path, 'excel'));
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final safeName = widget.customer['name'].toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File(p.join(tempDir.path, 'كشف_${safeName}_${DateTime.now().millisecondsSinceEpoch}.xlsx'));
      await file.writeAsBytes(bytes, flush: true);
      if (!await file.exists() || await file.length() <= 0) throw Exception('لم تُحفظ بيانات ملف Excel بشكل صحيح');
      if (shareFile) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          text: 'كشف حساب ${widget.customer['name']}',
          subject: 'كشف حساب ${widget.customer['name']}',
        );
      } else {
        final openResult = await OpenFile.open(file.path, type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (openResult.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم إنشاء ملف Excel لكن تعذر فتحه مباشرة: ${openResult.message}'),
          backgroundColor: AppColors.red));
        }
      }
    } catch (e, st) {
      debugPrint('Excel export error: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذر تصدير Excel: $e'), backgroundColor: AppColors.red));
    }
  }

  // ============ PDF محسّن مع حذف تلقائي ============
  Future<void> _exportToPdf(List<Map<String, dynamic>> txs, double totalGive,
      double totalTake, double finalBal, {bool shareFile = false}) async {
    ShapedFont? ownedShapedFontRegular;
    ShapedFont? ownedShapedFontBold;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 15),
                Text('جاري إنتاج PDF...'),
              ]),
            ),
          ),
        ),
      );
    }

    try {
      final fontDataRegular =
          await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontRegular = pw.Font.ttf(fontDataRegular);
      final fontDataBold =
          await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final fontBold = pw.Font.ttf(fontDataBold);

      // Shape Arabic table text with HarfBuzz while preserving original Unicode.
      final shapedFontRegular = ShapedFont.fromBytes(
        fontDataRegular.buffer.asUint8List(),
        name: 'Cairo Regular',
      );
      final shapedFontBold = ShapedFont.fromBytes(
        fontDataBold.buffer.asUint8List(),
        name: 'Cairo Bold',
      );
      ownedShapedFontRegular = shapedFontRegular;
      ownedShapedFontBold = shapedFontBold;

      final personalData = await PersonalDataService.getData();
      final logoBase64 = await PersonalDataService.getLogoBase64();
      final logoShape = personalData['logoShape'] as String;

      Uint8List? logoBytes;
      if (logoBase64 != null && logoBase64.isNotEmpty) {
        logoBytes = base64Decode(logoBase64);
      } else {
        try {
          final data = await rootBundle.load('assets/icon.png');
          logoBytes = data.buffer.asUint8List();
        } catch (_) {}
      }

      // Shrink oversized custom logos before embedding them in the PDF.
      // The header repeats on every page, so reuse one image provider as well.
      if (logoBytes != null) {
        try {
          final decodedLogo = img.decodeImage(logoBytes);
          if (decodedLogo != null &&
              (decodedLogo.width > 256 || decodedLogo.height > 256)) {
            final resizedLogo = img.copyResize(
              decodedLogo,
              width: decodedLogo.width >= decodedLogo.height
                  ? 256
                  : null,
              height: decodedLogo.height > decodedLogo.width
                  ? 256
                  : null,
              interpolation: img.Interpolation.average,
            );
            logoBytes = Uint8List.fromList(img.encodePng(resizedLogo, level: 9));
          }
        } catch (e) {
          debugPrint('PDF logo optimization skipped: $e');
        }
      }
      final pw.ImageProvider? logoImage =
          logoBytes == null ? null : pw.MemoryImage(logoBytes);

      final pdf = pw.Document(
          theme: pw.ThemeData.withFont(
              base: fontRegular, bold: fontBold));

      final darkBlue = PdfColor.fromHex("#1E3A5F");
      final greenTotal = PdfColor.fromHex("#00A000");
      final redTotal = PdfColor.fromHex("#F00000");
      final headerBg = PdfColor.fromHex("#CCCCCC");
      final totalBg = PdfColor.fromHex("#E0E0E0");
      final lightGreen = PdfColor.fromHex("#D9F7D9");
      final lightRed = PdfColor.fromHex("#FFE0E0");
      final black = PdfColors.black;

      // Build the PDF in bounded chunks instead of retaining every TableRow
      // and then copying the entire row list into sublists.
      const int rowsPerPdfTable = 100;
      final List<pw.Widget> dataTables = [];
      var chunkRows = <pw.TableRow>[];
      double newFinalBal = 0;
      double newTotalGive = 0;
      double newTotalTake = 0;

      for (final tx in txs) {
        final bool isGive = tx['type'] == 'give';
        final double amt = (tx['amount'] as num).toDouble();
        if (isGive) {
          newFinalBal += amt;
          newTotalGive += amt;
        } else {
          newFinalBal -= amt;
          newTotalTake += amt;
        }

        String dateOnly = tx['date'].toString().split(' ').first;
        try {
          final dt = DateTime.parse(tx['date'].toString());
          dateOnly =
              "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
        } catch (_) {}

        final PdfColor balanceNumberColor = newFinalBal < 0
            ? redTotal
            : (newFinalBal > 0 ? greenTotal : black);

        // Only the balance column is colored. "له" and "عليه" remain black.
        chunkRows.add(pw.TableRow(children: [
          _pdfCell(formatNumber(newFinalBal.abs()), shapedFontBold, 12, balanceNumberColor),
          _pdfCell(isGive ? formatNumber(amt) : '-', shapedFontBold, 12, black),
          _pdfCell(isGive ? '-' : formatNumber(amt), shapedFontBold, 12, black),
          _pdfCell((tx['details'] ?? '').toString(), shapedFontRegular, 12, black),
          _pdfCell(dateOnly, shapedFontRegular, 12, black),
        ]));

        if (chunkRows.length == rowsPerPdfTable) {
          dataTables.add(pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(3.5),
              4: const pw.FlexColumnWidth(2.2),
            },
            children: chunkRows,
          ));
          chunkRows = <pw.TableRow>[];
        }
      }

      if (chunkRows.isNotEmpty) {
        dataTables.add(pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.8),
            1: const pw.FlexColumnWidth(1.8),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FlexColumnWidth(3.5),
            4: const pw.FlexColumnWidth(2.2),
          },
          children: chunkRows,
        ));
      }

      final double balanceDiff = newTotalGive - newTotalTake;
      final String balanceText = balanceDiff == 0
          ? 'الرصيد الإجمالي'
          : (balanceDiff > 0 ? 'الرصيد الإجمالي - له' : 'الرصيد الإجمالي - عليه');
      final double balanceValue = balanceDiff.abs();
      final bool isOnHim = balanceDiff < 0;
      final PdfColor balanceRowColor = balanceDiff < 0 ? lightRed : lightGreen;

      pw.Widget buildHeader() {
        final rightItems = <pw.Widget>[];
        final leftItems = <pw.Widget>[];

        for (var i = 1; i <= 3; i++) {
          final rightText = (personalData['rightLine$i'] ?? '').toString();
          if (rightText.isNotEmpty) {
            final colorHex = (personalData['rightColor$i'] ?? '#000000').toString();
            final size = (personalData['rightSize$i'] as num?)?.toDouble() ?? 10.0;
            rightItems.add(
              pw.Container(
                width: double.infinity,
                alignment: pw.Alignment.centerRight,
                child: ArabicText(
                  rightText,
                  font: i == 1 ? shapedFontBold : shapedFontRegular,
                  fontSize: size,
                  color: PdfColor.fromHex(colorHex),
                  align: ShapedTextAlign.end,
                ),
              ),
            );
          }

          final leftText = (personalData['leftLine$i'] ?? '').toString();
          if (leftText.isNotEmpty) {
            final colorHex = (personalData['leftColor$i'] ?? '#000000').toString();
            final size = (personalData['leftSize$i'] as num?)?.toDouble() ?? 10.0;
            leftItems.add(
              pw.Container(
                width: double.infinity,
                alignment: pw.Alignment.centerLeft,
                child: ArabicText(
                  leftText,
                  font: i == 1 ? shapedFontBold : shapedFontRegular,
                  fontSize: size,
                  color: PdfColor.fromHex(colorHex),
                  align: ShapedTextAlign.end,
                ),
              ),
            );
          }
        }

        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(children: [
            // MultiPage is RTL: first Expanded is on the physical right.
            // Keep rightItems at the right page margin and leftItems at left.
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rightItems,
                  ),
                ),
                pw.SizedBox(
                  width: 60,
                  child: pw.Center(
                    child: logoImage != null
                        ? pw.Container(
                            width: 50,
                            height: 50,
                            child: pw.ClipRRect(
                              horizontalRadius:
                                  logoShape == 'circle' ? 25 : 4,
                              verticalRadius:
                                  logoShape == 'circle' ? 25 : 4,
                              child: pw.Image(logoImage,
                                  fit: pw.BoxFit.cover),
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: leftItems,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: darkBlue, thickness: 1.5),
            pw.SizedBox(height: 4),
            pw.Center(
              child: ArabicText(
                'كشف حساب : ${widget.customer['name']}',
                font: shapedFontBold,
                fontSize: 14,
                color: darkBlue,
                align: ShapedTextAlign.center,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.8),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(1.8),
                3: const pw.FlexColumnWidth(3.5),
                4: const pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: headerBg),
                  children: [
                    _pdfCell('الرصيد', shapedFontBold, 12, black),
                    _pdfCell('له', shapedFontBold, 12, black),
                    _pdfCell('عليه', shapedFontBold, 12, black),
                    _pdfCell('التفاصيل', shapedFontBold, 12, black),
                    _pdfCell('التاريخ', shapedFontBold, 12, black),
                  ],
                ),
              ],
            ),
          ]),
        );
      }

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        header: (pw.Context ctx) => buildHeader(),
        footer: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(children: [
            pw.Divider(color: black),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  ArabicText('تطبيق المحاسب',
                      font: shapedFontRegular,
                      fontSize: 10,
                      color: black,
                      align: ShapedTextAlign.end),
                  pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                      style: pw.TextStyle(
                          font: fontRegular, fontSize: 10, color: black),
                      textDirection: pw.TextDirection.rtl),
                  ArabicText('المهندس : اسامه الاضرعي',
                      font: shapedFontRegular,
                      fontSize: 10,
                      color: black,
                      align: ShapedTextAlign.end),
                ]),
          ]),
        ),
        build: (pw.Context context) => [
          pw.SizedBox(height: 5),
          ...dataTables,
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(3.5),
              4: const pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: totalBg),
                children: [
                  _pdfCell('', shapedFontBold, 14, black),
                  _pdfCell(formatNumber(newTotalGive), shapedFontBold, 14, greenTotal),
                  _pdfCell(formatNumber(newTotalTake), shapedFontBold, 14, redTotal),
                  _pdfCell('إجمالي العمليات', shapedFontBold, 14, black),
                  _pdfCell('', shapedFontBold, 14, black),
                ],
              ),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: balanceRowColor),
                children: [
                  _pdfCell('', shapedFontBold, 14, black),
                  _pdfCell(!isOnHim ? formatNumber(balanceValue) : '', shapedFontBold, 14, !isOnHim ? greenTotal : black),
                  _pdfCell(isOnHim ? formatNumber(balanceValue) : '', shapedFontBold, 14, isOnHim ? redTotal : black),
                  _pdfCell(balanceText, shapedFontBold, 14, black),
                  _pdfCell('', shapedFontBold, 14, black),
                ],
              ),
            ],
          ),
        ],
      ));

      final bytes = await pdf.save();
      if (mounted) material.Navigator.of(context, rootNavigator: true).pop();
      final tempDir = Directory(p.join((await getTemporaryDirectory()).path, 'pdf'));
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final fileName =
          'كشف_${widget.customer['name']}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(p.join(tempDir.path, fileName));
      await file.writeAsBytes(bytes);
      if (shareFile) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: 'كشف حساب ${widget.customer['name']}',
          subject: 'كشف حساب ${widget.customer['name']}',
        );
      } else {
        await OpenFile.open(file.path);
      }
      if (!shareFile) Future.delayed(const Duration(minutes: 10), () async {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      });
    } catch (e, st) {
      if (mounted) material.Navigator.of(context, rootNavigator: true).pop();
      debugPrint('PDF Error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذر إنتاج PDF: $e'),
            backgroundColor: AppColors.red));
      }
    } finally {
      // ShapedFont owns native HarfBuzz resources; always release them,
      // including when PDF generation or file sharing fails.
      ownedShapedFontRegular?.dispose();
      ownedShapedFontBold?.dispose();
    }
  }

  pw.Widget _pdfCell(
      String text, ShapedFont font, double size, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: ArabicText(
        text,
        font: font,
        fontSize: size,
        color: color,
        align: ShapedTextAlign.center,
      ),
    );
  }

  Future<void> _sendWhatsApp(String? rawPhone, double balance) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا يوجد رقم هاتف مضاف لهذا الحساب'),
          backgroundColor: AppColors.red));
      return;
    }
    String phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    String status = balance >= 0 ? "لك في حسابنا" : "عليكم لحسابنا";
    String message = "كشف حساب:\n"
        "العميل: ${widget.customer['name']}\n"
        "المبلغ الحالي: ${formatNumber(balance.abs())} ${widget.customer['currency']} ($status)";
    final Uri url =
        Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}

// ==================== CategoriesScreen ====================
