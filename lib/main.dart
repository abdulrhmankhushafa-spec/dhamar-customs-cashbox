import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/disbursement_screen.dart';
import 'screens/receipt_screen.dart';
import 'screens/statement_and_merchants_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DhamarCustomsCashboxApp());
}

class DhamarCustomsCashboxApp extends StatelessWidget {
  const DhamarCustomsCashboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صندوق مكتب العمال - جمارك ذمار',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [Locale('ar', 'YE'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E3A8A),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const CashboxMainShell(),
    );
  }
}

class CashboxMainShell extends StatefulWidget {
  const CashboxMainShell({super.key});

  @override
  State<CashboxMainShell> createState() => _CashboxMainShellState();
}

class _CashboxMainShellState extends State<CashboxMainShell> {
  int _currentIndex = 0;

  void _showOfflineOcrInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.offline_bolt_rounded, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'القارئ الضوئي المحلي (بدون إنترنت)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'يعمل نظام قراءة السندات في هذا التطبيق مجاناً وبالكامل بدون إنترنت (Offline OCR) ولا يحتاج إلى أي مفتاح خارجي.\n\n'
          '• صوّر السند الورقي بإضاءة واضحة وبشكل مستقيم.\n'
          '• اضغط على زر (قراءة وتعبئة بيانات السند تلقائياً).\n'
          '• يمكنك أيضاً مراجعة النص المستخرج وتوزيع أي كلمة أو رقم بضغطة واحدة إلى الحقل المناسب.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DisbursementVoucherScreen(onSaved: () => setState(() {})),
      ReceiptVoucherScreen(onSaved: () => setState(() {})),
      const AccountStatementsScreen(),
      const MerchantsDirectoryScreen(),
    ];

    const titles = [
      'سند صرف (قيد السند الورقي)',
      'سند قبض (تحصيل من تاجر)',
      'كشوفات الحسابات والتقارير',
      'حسابات التجار وجهات الاتصال',
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            titles[_currentIndex],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.offline_bolt_outlined),
              tooltip: 'معلومات القراءة الضوئية بدون إنترنت',
              onPressed: _showOfflineOcrInfoDialog,
            ),
          ],
        ),
        body: pages[_currentIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.outbox_outlined),
              selectedIcon: Icon(Icons.outbox, color: Color(0xFF1E3A8A)),
              label: 'سند صرف',
            ),
            NavigationDestination(
              icon: Icon(Icons.move_to_inbox_outlined),
              selectedIcon: Icon(Icons.move_to_inbox, color: Color(0xFF15803D)),
              label: 'سند قبض',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF0F766E)),
              label: 'كشف حساب',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt, color: Color(0xFF1E3A8A)),
              label: 'التجار',
            ),
          ],
        ),
      ),
    );
  }
}
