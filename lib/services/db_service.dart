import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class OfflineDatabaseService {
  static final OfflineDatabaseService instance = OfflineDatabaseService._();
  OfflineDatabaseService._();

  bool _initialized = false;
  List<Merchant> _merchants = [];
  List<VoucherRecord> _vouchers = [];

  Future<File> _storageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/dhamar_cashbox_store_v1.json');
  }

  Future<void> _ensureLoaded() async {
    if (_initialized) return;
    final file = await _storageFile();
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final mList = (data['merchants'] as List<dynamic>? ?? []);
        final vList = (data['vouchers'] as List<dynamic>? ?? []);
        _merchants = mList
            .map((e) => Merchant.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        _vouchers = vList
            .map((e) =>
                VoucherRecord.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        _initialized = true;
        return;
      } catch (_) {}
    }

    // بيانات ابتدائية مطابقة للسند الورقي المرفق
    _merchants = [
      Merchant(
        id: 1,
        name: 'فهد أحمد أبو حيدر',
        phone: '777073740',
        openingBalance: 0.0,
        notes: 'تاجر / مخلص جمركي - ساحة الأربعين ذمار',
      ),
      Merchant(
        id: 2,
        name: 'فهد أبو حيدر ارحب - ابن سمان',
        phone: '777073740',
        openingBalance: 0.0,
        notes: 'تاجر / مخلص جمركي - ساحة الأربعين ذمار',
      ),
    ];
    _vouchers = [
      VoucherRecord(
        id: 1,
        voucherType: 'disbursement',
        merchantId: 1,
        merchantName: 'فهد أبو حيدر ارحب - ابن سمان',
        paperSerialNo: '0086883',
        txDate: '2026-04-05',
        hijriDate: '1447/10/17',
        amount: 12000.0,
        amountText: 'اثنا عشر ألف ريال فقط لا غير',
        purpose: 'أجور أعمال مندوبية',
        plateNumber: '3854 / 14',
        chassisNumber: '',
        declarationNumber: '9258',
        goodsCategory: 'سكراب',
        workCategory: 'طربال',
        workersCount: '2 عمال',
        supervisorName: 'مدير مكتب العمال',
        paymentMethod: 'نقداً',
        imagePath: '',
      ),
    ];
    _initialized = true;
    await _persistToDisk();
  }

  Future<void> _persistToDisk() async {
    final file = await _storageFile();
    final payload = jsonEncode({
      'merchants': _merchants.map((e) => e.toMap()).toList(),
      'vouchers': _vouchers.map((e) => e.toMap()).toList(),
    });
    await file.writeAsString(payload);
  }

  Future<String> persistVoucherImage(String tempFilePath) async {
    if (tempFilePath.isEmpty) return '';
    final source = File(tempFilePath);
    if (!await source.exists()) return tempFilePath;
    final docsDir = await getApplicationDocumentsDirectory();
    final imagesFolder = Directory('${docsDir.path}/voucher_photos');
    if (!await imagesFolder.exists()) {
      await imagesFolder.create(recursive: true);
    }
    final dotIdx = tempFilePath.lastIndexOf('.');
    final ext = dotIdx != -1 ? tempFilePath.substring(dotIdx) : '.jpg';
    final targetName =
        'voucher_${DateTime.now().millisecondsSinceEpoch}$ext';
    final savedFile = await source.copy('${imagesFolder.path}/$targetName');
    return savedFile.path;
  }

  Future<List<Merchant>> fetchMerchants() async {
    await _ensureLoaded();
    return List<Merchant>.from(_merchants);
  }

  Future<int> saveMerchant(Merchant merchant) async {
    await _ensureLoaded();
    if (merchant.id == 0) {
      final nextId = _merchants.isEmpty
          ? 1
          : (_merchants.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1);
      final created = Merchant(
        id: nextId,
        name: merchant.name,
        phone: merchant.phone,
        openingBalance: merchant.openingBalance,
        notes: merchant.notes,
      );
      _merchants.add(created);
      await _persistToDisk();
      return nextId;
    } else {
      final idx = _merchants.indexWhere((e) => e.id == merchant.id);
      if (idx != -1) {
        _merchants[idx] = merchant;
        await _persistToDisk();
      }
      return merchant.id;
    }
  }

  Future<int> saveVoucher(VoucherRecord record) async {
    await _ensureLoaded();
    final nextId = _vouchers.isEmpty
        ? 1
        : (_vouchers.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1);
    final created = VoucherRecord(
      id: nextId,
      voucherType: record.voucherType,
      merchantId: record.merchantId,
      merchantName: record.merchantName,
      paperSerialNo: record.paperSerialNo,
      txDate: record.txDate,
      hijriDate: record.hijriDate,
      amount: record.amount,
      amountText: record.amountText,
      purpose: record.purpose,
      plateNumber: record.plateNumber,
      chassisNumber: record.chassisNumber,
      declarationNumber: record.declarationNumber,
      goodsCategory: record.goodsCategory,
      workCategory: record.workCategory,
      workersCount: record.workersCount,
      supervisorName: record.supervisorName,
      paymentMethod: record.paymentMethod,
      imagePath: record.imagePath,
    );
    _vouchers.insert(0, created);
    await _persistToDisk();
    return nextId;
  }

  Future<void> removeVoucher(int id) async {
    await _ensureLoaded();
    _vouchers.removeWhere((e) => e.id == id);
    await _persistToDisk();
  }

  Future<List<VoucherRecord>> fetchVouchers({
    int? merchantId,
    String? voucherType,
  }) async {
    await _ensureLoaded();
    return _vouchers.where((v) {
      if (merchantId != null && v.merchantId != merchantId) return false;
      if (voucherType != null &&
          voucherType.isNotEmpty &&
          v.voucherType != voucherType) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<double> computeMerchantBalance(int merchantId) async {
    await _ensureLoaded();
    final mList = _merchants.where((m) => m.id == merchantId).toList();
    final opening = mList.isEmpty ? 0.0 : mList.first.openingBalance;
    double totalDisbursed = 0.0;
    double totalReceived = 0.0;
    for (final v in _vouchers) {
      if (v.merchantId == merchantId) {
        if (v.voucherType == 'disbursement') {
          totalDisbursed += v.amount;
        } else {
          totalReceived += v.amount;
        }
      }
    }
    return opening + totalDisbursed - totalReceived;
  }

  Future<Map<String, double>> computeGlobalSummary() async {
    await _ensureLoaded();
    double totalOpening = 0.0;
    for (final m in _merchants) {
      totalOpening += m.openingBalance;
    }
    double totalDisbursed = 0.0;
    double totalReceived = 0.0;
    for (final v in _vouchers) {
      if (v.voucherType == 'disbursement') {
        totalDisbursed += v.amount;
      } else {
        totalReceived += v.amount;
      }
    }
    return {
      'disbursed': totalDisbursed,
      'received': totalReceived,
      'net_receivable': totalOpening + totalDisbursed - totalReceived,
    };
  }
}
