import 'dart:io';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/whatsapp_and_ocr_service.dart';

class AccountStatementsScreen extends StatefulWidget {
  const AccountStatementsScreen({super.key});

  @override
  State<AccountStatementsScreen> createState() =>
      _AccountStatementsScreenState();
}

class _AccountStatementsScreenState extends State<AccountStatementsScreen> {
  List<Merchant> _merchants = [];
  Merchant? _selectedMerchant;
  String _filterType = '';
  List<VoucherRecord> _vouchers = [];
  Map<String, double> _globalSummary = {
    'disbursed': 0,
    'received': 0,
    'net_receivable': 0
  };
  double _selectedMerchantBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final mList = await OfflineDatabaseService.instance.fetchMerchants();
    final summary =
        await OfflineDatabaseService.instance.computeGlobalSummary();
    if (_selectedMerchant != null) {
      final matches =
          mList.where((m) => m.id == _selectedMerchant!.id).toList();
      _selectedMerchant = matches.isNotEmpty ? matches.first : null;
    }
    final vList = await OfflineDatabaseService.instance.fetchVouchers(
      merchantId: _selectedMerchant?.id,
      voucherType: _filterType.isEmpty ? null : _filterType,
    );
    double mBal = 0.0;
    if (_selectedMerchant != null) {
      mBal = await OfflineDatabaseService.instance
          .computeMerchantBalance(_selectedMerchant!.id);
    }
    if (!mounted) return;
    setState(() {
      _merchants = mList;
      _globalSummary = summary;
      _vouchers = vList;
      _selectedMerchantBalance = mBal;
    });
  }

  Future<void> _sendFullStatementWhatsApp() async {
    if (_selectedMerchant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار تاجر محدد أولاً لإرسال كشف حسابه')),
      );
      return;
    }
    final lines = <String>[
      '📑 *كشف حساب تفصيلي - مكتب العمال (ساحة الأربعين - جمارك ذمار)*',
      '👤 *الأخ التاجر:* ${_selectedMerchant!.name} المحترم',
      '📅 *تاريخ الكشف:* ${DateTime.now().toIso8601String().substring(0, 10)}',
      '━━━━━━━━━━━━━━━━━━',
    ];

    double totalDisb = 0;
    double totalRec = 0;
    for (final v in _vouchers.reversed) {
      if (v.voucherType == 'disbursement') {
        totalDisb += v.amount;
        lines.add(
            '🔴 *سند صرف (${v.paperSerialNo.isEmpty ? v.id : v.paperSerialNo})* | ${v.txDate} | *${CashboxFormatter.money(v.amount)} ريال* | لوحة: ${v.plateNumber} | بيان: ${v.declarationNumber} (${v.goodsCategory})');
      } else {
        totalRec += v.amount;
        lines.add(
            '🟢 *سند قبض (${v.paperSerialNo.isEmpty ? v.id : v.paperSerialNo})* | ${v.txDate} | *${CashboxFormatter.money(v.amount)} ريال* (${v.paymentMethod})');
      }
    }

    lines.addAll([
      '━━━━━━━━━━━━━━━━━━',
      '• الرصيد الافتتاحي: ${CashboxFormatter.money(_selectedMerchant!.openingBalance)} ريال',
      '• إجمالي سندات الصرف المقيدة عليكم: ${CashboxFormatter.money(totalDisb)} ريال',
      '• إجمالي سندات القبض المسددة منكم: ${CashboxFormatter.money(totalRec)} ريال',
      '📌 *صافي الرصيد المستحق عليكم حالياً:* *${CashboxFormatter.money(_selectedMerchantBalance)} ريال*',
    ]);

    await WhatsAppAndContactsService.showWhatsAppDispatchSheet(
      context: context,
      merchantName: _selectedMerchant!.name,
      defaultMerchantPhone: _selectedMerchant!.phone,
      messageText: lines.join('\n'),
      imagePath: '',
    );
  }

  void _previewVoucherDetails(VoucherRecord v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(v.voucherType == 'disbursement'
            ? 'تفاصيل سند صرف رقم (${v.paperSerialNo.isEmpty ? v.id : v.paperSerialNo})'
            : 'تفاصيل سند قبض رقم (${v.paperSerialNo.isEmpty ? v.id : v.paperSerialNo})'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('التاجر: ${v.merchantName}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('التاريخ: ${v.txDate}'),
              Text('المبلغ: ${CashboxFormatter.money(v.amount)} ريال'),
              Text('كتابةً: ${v.amountText}'),
              Text('مقابل: ${v.purpose}'),
              if (v.voucherType == 'disbursement') ...[
                const Divider(),
                Text('رقم اللوحة: ${v.plateNumber}'),
                Text('رقم القعادة: ${v.chassisNumber}'),
                Text('رقم البيان: ${v.declarationNumber}'),
                Text('نوع البضاعة: ${v.goodsCategory}'),
                Text('نوع العمل: ${v.workCategory}'),
                Text('عدد العمال: ${v.workersCount}'),
              ],
              if (v.imagePath.isNotEmpty && File(v.imagePath).existsSync()) ...[
                const SizedBox(height: 10),
                const Text('صورة السند الورقي المرفق:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(v.imagePath)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('حذف', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              await OfflineDatabaseService.instance.removeVoucher(v.id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadData();
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send),
            label: const Text('إعادة إرسال واتساب'),
            onPressed: () async {
              Navigator.pop(ctx);
              final matches =
                  _merchants.where((item) => item.id == v.merchantId).toList();
              final m = matches.isNotEmpty ? matches.first : null;
              final bal = await OfflineDatabaseService.instance
                  .computeMerchantBalance(v.merchantId);
              if (!mounted) return;
              final msg = v.voucherType == 'disbursement'
                  ? WhatsAppAndContactsService.buildDisbursementMessage(
                      voucher: v,
                      previousBalance: bal - v.amount,
                      currentTotalBalance: bal,
                    )
                  : WhatsAppAndContactsService.buildReceiptMessage(
                      voucher: v,
                      previousBalance: bal + v.amount,
                      remainingBalance: bal,
                    );
              await WhatsAppAndContactsService.showWhatsAppDispatchSheet(
                context: context,
                merchantName: v.merchantName,
                defaultMerchantPhone: m?.phone ?? '',
                messageText: msg,
                imagePath: v.imagePath,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _topMetric('إجمالي الصرفيات',
                  _globalSummary['disbursed'] ?? 0, Colors.orangeAccent),
              _topMetric('إجمالي المقبوضات',
                  _globalSummary['received'] ?? 0, Colors.greenAccent),
              _topMetric('صافي الديون لنا',
                  _globalSummary['net_receivable'] ?? 0, Colors.lightBlueAccent),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<Merchant?>(
                      value: _selectedMerchant,
                      decoration: const InputDecoration(
                        labelText: 'تصفية حسب حساب التاجر',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<Merchant?>(
                          value: null,
                          child: Text('جميع التجار (حركة الصندوق الكاملة)'),
                        ),
                        ..._merchants.map(
                          (m) => DropdownMenuItem<Merchant?>(
                            value: m,
                            child: Text(m.name),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedMerchant = val);
                        _loadData();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _filterType,
                      decoration: const InputDecoration(
                        labelText: 'نوع السند',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('الكل')),
                        DropdownMenuItem(
                            value: 'disbursement', child: Text('سندات صرف')),
                        DropdownMenuItem(
                            value: 'receipt', child: Text('سندات قبض')),
                      ],
                      onChanged: (val) {
                        setState(() => _filterType = val ?? '');
                        _loadData();
                      },
                    ),
                  ),
                ],
              ),
              if (_selectedMerchant != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إجمالي المستحق على: ${_selectedMerchant!.name}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${CashboxFormatter.money(_selectedMerchantBalance)} ريال يمني',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.red.shade800),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF128C7E),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _sendFullStatementWhatsApp,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('إرسال الكشف واتساب'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: _vouchers.isEmpty
              ? const Center(
                  child: Text('لا توجد سندات مطابقة للبحث حالياً'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _vouchers.length,
                  itemBuilder: (ctx, i) {
                    final v = _vouchers[i];
                    final isDisb = v.voucherType == 'disbursement';
                    final hasImg =
                        v.imagePath.isNotEmpty && File(v.imagePath).existsSync();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _previewVoucherDetails(v),
                        leading: CircleAvatar(
                          backgroundColor: isDisb
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            isDisb
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: isDisb
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${isDisb ? "سند صرف" : "سند قبض"} #${v.paperSerialNo.isEmpty ? v.id : v.paperSerialNo} - ${v.merchantName}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            Text(
                              '${CashboxFormatter.money(v.amount)} ريال',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDisb
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              isDisb
                                  ? 'التاريخ: ${v.txDate} | لوحة: ${v.plateNumber} | بيان: ${v.declarationNumber} | ${v.goodsCategory} (${v.workCategory})'
                                  : 'التاريخ: ${v.txDate} | ${v.paymentMethod} | ${v.purpose}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (hasImg)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.photo_camera_back,
                                        size: 15, color: Colors.teal.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'مرفق صورة السند الورقي (اضغط للمعاينة أو الإرسال)',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.teal.shade700,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _topMetric(String label, double val, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          '${CashboxFormatter.money(val)} ريال',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}

class MerchantsDirectoryScreen extends StatefulWidget {
  const MerchantsDirectoryScreen({super.key});

  @override
  State<MerchantsDirectoryScreen> createState() =>
      _MerchantsDirectoryScreenState();
}

class _MerchantsDirectoryScreenState extends State<MerchantsDirectoryScreen> {
  List<Merchant> _merchants = [];
  Map<int, double> _balances = {};

  @override
  void initState() {
    super.initState();
    _loadMerchantsWithBalances();
  }

  Future<void> _loadMerchantsWithBalances() async {
    final list = await OfflineDatabaseService.instance.fetchMerchants();
    final map = <int, double>{};
    for (final m in list) {
      map[m.id] =
          await OfflineDatabaseService.instance.computeMerchantBalance(m.id);
    }
    if (!mounted) return;
    setState(() {
      _merchants = list;
      _balances = map;
    });
  }

  Future<void> _openMerchantForm({Merchant? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final openBalCtrl = TextEditingController(
        text: existing != null
            ? existing.openingBalance.toStringAsFixed(0)
            : '0');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            existing == null ? 'إضافة حساب تاجر جديد' : 'تعديل بيانات التاجر'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم التاجر / المخلص *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الواتساب الأساسي',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: const Icon(Icons.contacts),
                    tooltip: 'استيراد من جهات الاتصال',
                    onPressed: () async {
                      final picked = await WhatsAppAndContactsService
                          .pickNumberFromContacts(ctx);
                      if (picked != null) {
                        if (nameCtrl.text.trim().isEmpty) {
                          nameCtrl.text = picked['name'] ?? '';
                        }
                        phoneCtrl.text = picked['phone'] ?? '';
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: openBalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الرصيد الافتتاحي السابق (ريال)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات / عنوان',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await OfflineDatabaseService.instance.saveMerchant(
                Merchant(
                  id: existing?.id ?? 0,
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  openingBalance:
                      double.tryParse(openBalCtrl.text.trim()) ?? 0.0,
                  notes: notesCtrl.text.trim(),
                ),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadMerchantsWithBalances();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMerchantForm(),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة تاجر'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _merchants.length,
        itemBuilder: (ctx, i) {
          final m = _merchants[i];
          final bal = _balances[m.id] ?? 0.0;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _openMerchantForm(existing: m),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1E3A8A),
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                m.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('واتساب: ${m.phone}\n${m.notes}'),
              isThreeLine: m.notes.isNotEmpty,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('إجمالي الحساب عليه',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(
                    '${CashboxFormatter.money(bal)} ريال',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: bal > 0
                          ? Colors.red.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
