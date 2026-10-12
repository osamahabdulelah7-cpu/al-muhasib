part of '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String searchQuery = '';
  bool isSearching = false;
  Timer? _autoBackupTimer;
  TextEditingController? searchController;
  TabController? _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _drawerLogoBase64;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBackup();
      _loadDrawerLogo();
      _autoBackupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _checkAutoBackup();
      });
    });
  }

  @override
  void dispose() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    // Disposing a screen is not a backup trigger. Running backups here races
    // the minute timer, startup checks, WorkManager, and the exact alarm.
    _tabController?.dispose();
    searchController?.dispose();
    super.dispose();
  }

  Future<void> _loadDrawerLogo() async {
    final logo = await PersonalDataService.getLogoBase64();
    if (!mounted) return;
    setState(() {
      _drawerLogoBase64 = logo;
    });
  }

  void _startSearch() {
    setState(() {
      isSearching = true;
      searchController = TextEditingController();
      searchQuery = '';
    });
  }

  void _stopSearch() {
    setState(() {
      isSearching = false;
      searchController?.dispose();
      searchController = null;
      searchQuery = '';
    });
  }

  Future<void> _checkAutoBackup() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final wasEnabled = settings['enabled'] as bool;
      final lastBackupBefore = settings['lastBackup'] as String;
      final error = await AutoBackupService.checkAndRunBackup();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠️ فشل النسخ التلقائي: $error'),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 5),
        ));
      } else if (error == null && wasEnabled && mounted) {
        final newSettings = await AutoBackupService.getSettings();
        final newLastBackup = newSettings['lastBackup'] as String;
        if (newLastBackup.isNotEmpty && newLastBackup != lastBackupBefore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Row(children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ تم النسخ الاحتياطي بنجاح'),
              ]),
              backgroundColor: AppColors.green,
              duration: Duration(seconds: 4),
            ));
          }
        }
      }
      await _checkDriveBackup();
    } catch (e) {
      debugPrint('❌ خطأ في فحص النسخ: $e');
    }
  }

  Future<void> _checkDriveBackup() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final wasEnabled = settings['driveEnabled'] as bool;
      final lastBackupBefore = settings['driveLastBackup'] as String;
      final error = await AutoBackupService.checkAndRunDriveBackup();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠️ فشل النسخ على Drive: $error'),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 5),
        ));
      } else if (error == null && wasEnabled && mounted) {
        final newSettings = await AutoBackupService.getSettings();
        final newLastBackup = newSettings['driveLastBackup'] as String;
        if (newLastBackup.isNotEmpty && newLastBackup != lastBackupBefore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Row(children: [
                Icon(Icons.cloud_done, color: Colors.white),
                SizedBox(width: 8),
                Text('☁️ تم النسخ على Google Drive'),
              ]),
              backgroundColor: AppColors.drive,
              duration: Duration(seconds: 4),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص Drive: $e');
    }
  }

  Future<void> _importFromExcel(BuildContext context) async {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    if (provider.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد تصنيفات. أضف تصنيفاً أولاً'),
          backgroundColor: AppColors.red));
      return;
    }
    int selectedCategoryId =
        int.parse(provider.categories.first['id'].toString());
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.folder_open, color: AppColors.primary),
            SizedBox(width: 8),
            Text('اختر التصنيف'),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('في أي تصنيف تريد إضافة الحسابات المستوردة؟',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 15),
                DropdownButtonFormField<int>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                      labelText: 'التصنيف', prefixIcon: Icon(Icons.folder)),
                  items: provider.categories.map((c) {
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(
                        value: cId, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCategoryId = val);
                    }
                  },
                ),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (result == null || result.files.single.path == null) return;
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => WillPopScope(
            onWillPop: () async => false,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: 15),
                    Text('جاري الاستيراد...'),
                  ]),
                ),
              ),
            ),
          ),
        );
      }
      File excelFile = File(result.files.single.path!);
      final stats = await provider.importFromExcel(excelFile,
          categoryId: selectedCategoryId);
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Row(children: [
              Icon(Icons.check_circle, color: AppColors.green),
              SizedBox(width: 8),
              Text('تم الاستيراد بنجاح'),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((stats['accountName'] as String).isNotEmpty) ...[
                    Text('📁 ${stats['accountName']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const Divider(),
                  ],
                  Text('✅ حسابات جديدة: ${stats['customers']}',
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 5),
                  Text('✅ معاملات: ${stats['transactions']}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.green)),
                  if ((stats['skipped'] as int) > 0) ...[
                    const SizedBox(height: 5),
                    Text('⚠️ تم تجاهل: ${stats['skipped']} صف',
                        style: const TextStyle(color: Colors.orange)),
                  ],
                ]),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تم'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.settings.name != null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 8)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final categories = provider.categories;
    if (categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('دفتر المحاسب الشامل')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('لا توجد تصنيفات مضافة'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                icon: const Icon(Icons.category),
                label: const Text('إدارة التصنيفات'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tabController == null ||
        _tabController!.length != categories.length) {
      _tabController?.dispose();
      _tabController = TabController(length: categories.length, vsync: this);
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: Container(
              color: AppColors.solidBlue,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  height: 56,
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.menu,
                          color: Colors.black, size: 26),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const Spacer(),
                    if (!isSearching) ...[
                      Row(children: const [
                        Icon(Icons.menu_book, color: Colors.black, size: 24),
                        SizedBox(width: 8),
                        Text('المحاسب',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ] else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.black),
                            decoration: const InputDecoration(
                              hintText: 'ابحث في هذا التصنيف...',
                              hintStyle: TextStyle(color: Colors.black54),
                              border: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.black)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.black)),
                              isDense: true,
                            ),
                            onChanged: (val) =>
                                setState(() => searchQuery = val),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (!isSearching)
                      IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.black, size: 26),
                        onPressed: _startSearch,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.black, size: 26),
                        onPressed: _stopSearch,
                      ),
                    const SizedBox(width: 4),
                  ]),
                ),
                SizedBox(
                  height: 48,
                  child: TabBar(                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.black54,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    tabs: categories
                        .map((cat) => Tab(text: cat['name'].toString()))
                        .toList(),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      drawerEnableOpenDragGesture: false,
      drawer: Drawer(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 25),
            color: AppColors.solidBlue,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 3),
                    ),
                    child: ClipOval(
                      child: _drawerLogoBase64 != null
                          ? Image.memory(
                              base64Decode(_drawerLogoBase64!),
                              fit: BoxFit.cover,
                              width: 90,
                              height: 90,
                            )
                          : Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.cover,
                              width: 90,
                              height: 90,
                            ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text('تطبيق المحاسب',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('المهندس : اسامه الاضرعي',
                      style: TextStyle(color: Colors.black54, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(children: const [
                    Icon(Icons.phone, color: AppColors.goldDark, size: 16),
                    SizedBox(width: 6),
                    Text('770638276',
                        style:
                            TextStyle(color: Colors.black54, fontSize: 14)),
                  ]),
                ]),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.category, color: AppColors.primary),
            ),
            title: const Text('إدارة التصنيفات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child:
                  const Icon(Icons.attach_money, color: AppColors.goldDark),
            ),
            title: const Text('إدارة العملات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CurrenciesScreen())),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.person, color: Colors.purple),
            ),
            title: const Text('البيانات الشخصية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PersonalDataScreen())).then((_) {
                _loadDrawerLogo();
              });
            },
          ),
          const Divider(height: 20, indent: 20, endIndent: 20),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.upload_file, color: Colors.teal),
            ),
            title: const Text('استيراد من Excel',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              _importFromExcel(context);
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.cloud_sync, color: AppColors.green),
            ),
            title: const Text('النسخ الاحتياطي والاستعادة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BackupOptionsScreen()));
            },
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            child: const Text('دفتر المحاسب © 2026',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: categories.map((cat) {
              final int currentCatId = int.parse(cat['id'].toString());
              final categoryCustomers = provider.customers.where((c) {
                final int customerCatId =
                    int.parse(c['category_id'].toString());
                final name = (c['name'] ?? '').toString();
                final phone = (c['phone'] ?? '').toString();
                return customerCatId == currentCatId &&
                    (name.contains(searchQuery) || phone.contains(searchQuery));
              }).toList();

              // لا يجوز جمع أرصدة بعملات مختلفة في إجمالي واحد.
              // لذلك نحسب الإجماليات بشكل مستقل لكل عملة.
              final Map<String, Map<String, double>> currencyTotals = {};
              for (var cust in categoryCustomers) {
                final int cId = int.parse(cust['id'].toString());
                final String currency =
                    (cust['currency'] ?? 'غير محددة').toString();
                final double bal = provider.customerBalances[cId] ?? 0.0;
                final totals = currencyTotals.putIfAbsent(
                    currency, () => {'give': 0.0, 'take': 0.0});
                if (bal > 0) {
                  totals['give'] = (totals['give'] ?? 0) + bal;
                } else if (bal < 0) {
                  totals['take'] = (totals['take'] ?? 0) + bal.abs();
                }
              }

              return Column(children: [
                Expanded(
                  child: categoryCustomers.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Icon(Icons.inbox,
                                  size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 15),
                              Text('لا توجد حسابات مضافة',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 15)),
                            ]))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: categoryCustomers.length,
                          itemBuilder: (ctx, i) => _buildCustomerCard(
                              context, provider, categoryCustomers[i]),
                        ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                          onTap: () {
                            final activeIndex = _tabController!.index;
                            final activeCategoryId = int.parse(
                                categories[activeIndex]['id'].toString());
                            _showAddCustomerDialog(context, activeCategoryId);
                          },
                          child: const Center(
                            child: Icon(Icons.add,
                                color: AppColors.gold, size: 30),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.solidBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: currencyTotals.entries.map((entry) {
                            final currency = entry.key;
                            final totalGive = entry.value['give'] ?? 0.0;
                            final totalTake = entry.value['take'] ?? 0.0;
                            final netBalance = totalGive - totalTake;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currency,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'عليه: ${formatNumber(totalTake)}',
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                      Text(
                                        'له: ${formatNumber(totalGive)}',
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    height: 1,
                                    color: Colors.black.withOpacity(0.2),
                                  ),
                                  const SizedBox(height: 2),
                                  Center(
                                    child: Text(
                                      '${netBalance == 0 ? "الرصيد" : (netBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(netBalance.abs())}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]);
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildCustomerCard(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
    final int cId = int.parse(customer['id'].toString());
    final String custName = (customer['name'] ?? 'حساب').toString();
    final double bal = provider.customerBalances[cId] ?? 0.0;

    Color sideColor;
    Color circleColor;
    if (bal > 0) {
      sideColor = const Color(0xFF81C784);
      circleColor = AppColors.greenLight;
    } else if (bal < 0) {
      sideColor = AppColors.redDark;
      circleColor = AppColors.redLight;
    } else {
      sideColor = const Color(0xFF81C784);
      circleColor = AppColors.greenLight;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          CustomerDetailsScreen(customer: customer)))
              .then((_) => provider.loadCustomers()),
          onLongPress: () =>
              _showCustomerOptionsModal(context, provider, customer),
          child: Stack(children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                    color: sideColor,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                SizedBox(
                  height: 70,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: circleColor, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(Icons.person, color: sideColor, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(custName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textDarkest),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                SizedBox(
                  height: 70,
                  child: Center(
                    child: Text(
                      formatNumber(bal.abs()),
                      style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ]),
            ),
          ]),
        ),
      ),
    );
  }



  void _showCustomerOptionsModal(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
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
            title: const Text('تعديل الحساب',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(ctx);
              _showEditCustomerDialog(context, customer);
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
            title: const Text('حذف الحساب',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteCustomer(context, provider,
                  int.parse(customer['id'].toString()));
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  void _showEditCustomerDialog(
      BuildContext context, Map<String, dynamic> customer) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController(text: customer['name'].toString());
    final phoneCtrl =
        TextEditingController(text: customer['phone']?.toString() ?? '');
    String selectedCurrency = customer['currency'].toString();
    int selectedCat = int.parse(customer['category_id'].toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.edit, color: AppColors.primary),
            SizedBox(width: 8),
            Text('تعديل الحساب'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الحساب/العميل')),
              const SizedBox(height: 10),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: provider.currencies
                        .any((c) => c['name'].toString() == selectedCurrency)
                    ? selectedCurrency
                    : (provider.currencies.isNotEmpty
                        ? provider.currencies.first['name'].toString()
                        : 'ريال يمني'),
                decoration: const InputDecoration(labelText: 'العملة'),
                items: provider.currencies
                    .map((c) => DropdownMenuItem<String>(
                        value: c['name'].toString(),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCurrency = val);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: provider.categories.any(
                        (c) => int.parse(c['id'].toString()) == selectedCat)
                    ? selectedCat
                    : (provider.categories.isNotEmpty
                        ? int.parse(provider.categories.first['id'].toString())
                        : selectedCat),
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: provider.categories
                    .map((c) => DropdownMenuItem<int>(
                        value: int.parse(c['id'].toString()),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCat = val);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await provider.updateCustomer(
                    int.parse(customer['id'].toString()),
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    selectedCurrency,
                    selectedCat,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(e.toString().replaceFirst('Bad state: ', '')),
                      backgroundColor: AppColors.red,
                    ));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCustomer(
      BuildContext context, AppAccountProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AppColors.red),
          SizedBox(width: 8),
          Text('تأكيد الحذف'),
        ]),
        content: const Text('هل أنت متأكد من عملية الحذف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () async {
              final ok = await provider.deleteCustomer(id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يمكن حذف حساب يحتوي على عمليات. احذف الحساب فقط بعد إزالة عملياته أو احتفظ به للأرشفة.'),
                  backgroundColor: AppColors.red,
                ));
              }
            },
            child: const Text('حذف'),
          )
        ],
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, int defaultCatId) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedCurrency = provider.currencies.isNotEmpty
        ? provider.currencies.first['name'].toString()
        : 'ريال يمني';
    int selectedCat = defaultCatId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.person_add, color: AppColors.primary),
            SizedBox(width: 8),
            Text('إضافة حساب جديد'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الحساب/العميل')),
              const SizedBox(height: 10),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedCurrency,
                decoration: const InputDecoration(labelText: 'العملة'),
                items: provider.currencies
                    .map((c) => DropdownMenuItem<String>(
                        value: c['name'].toString(),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCurrency = val);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: selectedCat,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: provider.categories
                    .map((c) => DropdownMenuItem<int>(
                        value: int.parse(c['id'].toString()),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCat = val);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  provider.addCustomer(nameCtrl.text.trim(),
                      phoneCtrl.text.trim(), selectedCurrency, selectedCat);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== BackupOptionsScreen ====================
