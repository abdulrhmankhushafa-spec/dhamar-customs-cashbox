class Merchant {
  final int id;
  final String name;
  final String phone;
  final double openingBalance;
  final String notes;

  Merchant({
    required this.id,
    required this.name,
    required this.phone,
    this.openingBalance = 0.0,
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'opening_balance': openingBalance,
        'notes': notes,
      };

  factory Merchant.fromMap(Map<String, dynamic> m) => Merchant(
        id: (m['id'] ?? 0) as int,
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        openingBalance: ((m['opening_balance'] ?? 0) as num).toDouble(),
        notes: (m['notes'] ?? '') as String,
      );

  @override
  bool operator ==(Object other) => other is Merchant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class VoucherRecord {
  final int id;
  final String voucherType; // 'disbursement' (سند صرف) | 'receipt' (سند قبض)
  final int merchantId;
  final String merchantName;
  final String paperSerialNo; // الرقم التسلسلي في السند الورقي مثل 0086883
  final String txDate; // التاريخ الميلادي مثل 2026-04-05
  final String hijriDate;
  final double amount;
  final String amountText;
  final String purpose;
  final String plateNumber; // رقم اللوحة مثل 3854/14
  final String chassisNumber; // رقم القعادة
  final String declarationNumber; // رقم البيان مثل 9258
  final String goodsCategory; // نوع البضاعة مثل سكراب
  final String workCategory; // نوع العمل مثل طربال
  final String workersCount; // عدد العمال مثل 2 عمال
  final String supervisorName;
  final String paymentMethod;
  final String imagePath;

  VoucherRecord({
    required this.id,
    required this.voucherType,
    required this.merchantId,
    required this.merchantName,
    required this.paperSerialNo,
    required this.txDate,
    this.hijriDate = '',
    required this.amount,
    required this.amountText,
    this.purpose = 'أجور أعمال مندوبية',
    this.plateNumber = '',
    this.chassisNumber = '',
    this.declarationNumber = '',
    this.goodsCategory = '',
    this.workCategory = '',
    this.workersCount = '',
    this.supervisorName = '',
    this.paymentMethod = 'نقداً',
    this.imagePath = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'voucher_type': voucherType,
        'merchant_id': merchantId,
        'merchant_name': merchantName,
        'paper_serial_no': paperSerialNo,
        'tx_date': txDate,
        'hijri_date': hijriDate,
        'amount': amount,
        'amount_text': amountText,
        'purpose': purpose,
        'plate_number': plateNumber,
        'chassis_number': chassisNumber,
        'declaration_number': declarationNumber,
        'goods_category': goodsCategory,
        'work_category': workCategory,
        'workers_count': workersCount,
        'supervisor_name': supervisorName,
        'payment_method': paymentMethod,
        'image_path': imagePath,
      };

  factory VoucherRecord.fromMap(Map<String, dynamic> m) => VoucherRecord(
        id: (m['id'] ?? 0) as int,
        voucherType: (m['voucher_type'] ?? 'disbursement') as String,
        merchantId: (m['merchant_id'] ?? 0) as int,
        merchantName: (m['merchant_name'] ?? '') as String,
        paperSerialNo: (m['paper_serial_no'] ?? '') as String,
        txDate: (m['tx_date'] ?? '') as String,
        hijriDate: (m['hijri_date'] ?? '') as String,
        amount: ((m['amount'] ?? 0) as num).toDouble(),
        amountText: (m['amount_text'] ?? '') as String,
        purpose: (m['purpose'] ?? 'أجور أعمال مندوبية') as String,
        plateNumber: (m['plate_number'] ?? '') as String,
        chassisNumber: (m['chassis_number'] ?? '') as String,
        declarationNumber: (m['declaration_number'] ?? '') as String,
        goodsCategory: (m['goods_category'] ?? '') as String,
        workCategory: (m['work_category'] ?? '') as String,
        workersCount: (m['workers_count'] ?? '') as String,
        supervisorName: (m['supervisor_name'] ?? '') as String,
        paymentMethod: (m['payment_method'] ?? 'نقداً') as String,
        imagePath: (m['image_path'] ?? '') as String,
      );
}

class CashboxFormatter {
  static String money(double value) {
    final rounded = value.round();
    final negative = rounded < 0;
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return negative ? '-${buffer.toString()}' : buffer.toString();
  }

  static String normalizeYemenPhone(String rawInput) {
    String cleaned = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }
    if (cleaned.startsWith('07') && cleaned.length == 10) {
      cleaned = '967${cleaned.substring(1)}';
    } else if (cleaned.length == 9 && cleaned.startsWith('7')) {
      cleaned = '967$cleaned';
    }
    return cleaned;
  }

  static String tafqeetYemeniRiyal(double val) {
    final int number = val.round();
    if (number <= 0) return '';
    return '${_spellArabicInt(number)} ريال فقط لا غير';
  }

  static String _spellArabicInt(int n) {
    const units = [
      '',
      'واحد',
      'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
      'عشرة',
      'أحد عشر',
      'اثنا عشر',
      'ثلاثة عشر',
      'أربعة عشر',
      'خمسة عشر',
      'ستة عشر',
      'سبعة عشر',
      'ثمانية عشر',
      'تسعة عشر'
    ];
    const tens = [
      '',
      '',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون'
    ];
    const hundreds = [
      '',
      'مائة',
      'مائتان',
      'ثلاثمائة',
      'أربعمائة',
      'خمسمائة',
      'ستمائة',
      'سبعمائة',
      'ثمانمائة',
      'تسعمائة'
    ];

    if (n < 20) return units[n];
    if (n < 100) {
      final u = n % 10;
      final t = n ~/ 10;
      return u == 0 ? tens[t] : '${units[u]} و${tens[t]}';
    }
    if (n < 1000) {
      final h = n ~/ 100;
      final rem = n % 100;
      return rem == 0 ? hundreds[h] : '${hundreds[h]} و${_spellArabicInt(rem)}';
    }
    if (n < 1000000) {
      final th = n ~/ 1000;
      final rem = n % 1000;
      String thText;
      if (th == 1) {
        thText = 'ألف';
      } else if (th == 2) {
        thText = 'ألفان';
      } else if (th >= 3 && th <= 10) {
        thText = '${units[th]} آلاف';
      } else {
        thText = '${_spellArabicInt(th)} ألف';
      }
      return rem == 0 ? thText : '$thText و${_spellArabicInt(rem)}';
    }
    final mil = n ~/ 1000000;
    final rem = n % 1000000;
    final milText = mil == 1
        ? 'مليون'
        : (mil == 2 ? 'مليونان' : '${_spellArabicInt(mil)} مليون');
    return rem == 0 ? milText : '$milText و${_spellArabicInt(rem)}';
  }
}
