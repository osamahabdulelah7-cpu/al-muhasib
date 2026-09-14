import 'package:flutter/material.dart';

void main() {
  runApp(const AccountantApp());
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'المحاسب',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      theme: ThemeData(
        primaryColor: const Color(0xFF1976D2), // لون أزرق جديد
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF1976D2),
          secondary: const Color(0xFF388E3C), // لون أخضر للعمليات
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحاسب'),
          backgroundColor: Theme.of(context).primaryColor,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'عام (37)'),
              Tab(text: 'البقايل (66)'),
              Tab(text: 'العائلة (22)'),
              Tab(text: 'منوع (4)'),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: () {}),
          ],
        ),
        drawer: const NavigationDrawer(),
        body: const TabBarView(
          children: [
            AccountsList(),
            AccountsList(),
            AccountsList(),
            AccountsList(),
          ],
        ),
        bottomNavigationBar: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('له: 820,850', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('عليه: 1,308,883', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Theme.of(context).primaryColor,
          child: const Icon(Icons.add),
          onPressed: () {},
        ),
      ),
    );
  }
}

class AccountsList extends StatelessWidget {
  const AccountsList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text('حساب ${index + 1}'),
            subtitle: const Text('تفاصيل الحساب'),
            trailing: const Text('1,500', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}

class NavigationDrawer extends StatelessWidget {
  const NavigationDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Text('تطبيق المحاسب', style: TextStyle(color: Colors.white, fontSize: 22)),
          ),
          ListTile(leading: const Icon(Icons.person), title: const Text('البيانات الشخصية'), onTap: () {}),
          ListTile(leading: const Icon(Icons.settings), title: const Text('الإعدادات'), onTap: () {}),
          ListTile(leading: const Icon(Icons.category), title: const Text('إدارة التصنيفات'), onTap: () {}),
          ListTile(leading: const Icon(Icons.cloud_upload), title: const Text('حفظ واسترجاع البيانات'), onTap: () {}),
        ],
      ),
    );
  }
}
