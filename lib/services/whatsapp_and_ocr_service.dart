import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';

class WhatsAppAndContactsService {
  static const MethodChannel _nativeChannel =
      MethodChannel('dhamar.cashbox/native');

  /// اختيار جهة اتصال من دليل الهاتف مباشرة عبر نظام أندرويد الأصلي بدون أي مكتبات خارجية معطلة
  static Future<Map<String, String>?> pickNumberFromContacts(
      BuildContext context) async {
    try {
      final res =
          await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>('pickContact');
      if (res != null && res['phone'] != null) {
        return {
          'name': (res['name'] ?? '').toString(),
          'phone': (res['phone'] ?? '').toString(),
        };
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح جهات الاتصال: $e')),
        );
      }
    }
    return null;
  }

  static String buildDisbursementMessage({
    required VoucherRecord voucher,
    required double previousBalance,
    required double currentTotalBalance,
  }) {
    final lines = <String>[
      '📋 *إشعار سند صرف - مكتب العمال (ساحة الأربعين - جمارك ذمار)*',
      '━━━━━━━━━━━━━━━━━━',
      '👤 *الأخ التاجر:* ${voucher.merchantName} المحترم',
      '🔢 *رقم السند الورقي:* ${voucher.paperSerialNo.isEmpty ? "غير محدد" : voucher.paperSerialNo}',
      '📅 *التاريخ:* ${voucher.txDate}',
      '💰 *المبلغ المصروف:* ${CashboxFormatter.money(voucher.amount)} ريال',
      '📝 *مبلغ وقدره:* ${voucher.amountText}',
      '📌 *وذلك مقابل:* ${voucher.purpose}',
    ];

    if (voucher.plateNumber.isNotEmpty ||
        voucher.declarationNumber.isNotEmpty ||
        voucher.goodsCategory.isNotEmpty ||
        voucher.workCategory.isNotEmpty ||
        voucher.workersCount.isNotEmpty) {
      lines.add('━━━━━━━━━━━━━━━━━━');
      lines.add('🚛 *تفاصيل البيان والعمل:*');
      if (voucher.plateNumber.isNotEmpty) {
        lines.add('• رقم اللوحة: ${voucher.plateNumber}');
      }
      if (voucher.chassisNumber.isNotEmpty) {
        lines.add('• رقم القعادة: ${voucher.chassisNumber}');
      }
      if (voucher.declarationNumber.isNotEmpty) {
        lines.add('• رقم البيان: ${voucher.declarationNumber}');
      }
      if (voucher.goodsCategory.isNotEmpty) {
        lines.add('• نوع البضاعة: ${voucher.goodsCategory}');
      }
      if (voucher.workCategory.isNotEmpty) {
        lines.add('• نوع العمل: ${voucher.workCategory}');
      }
      if (voucher.workersCount.isNotEmpty) {
        lines.add('• عدد العمال: ${voucher.workersCount}');
      }
    }

    lines.addAll([
      '━━━━━━━━━━━━━━━━━━',
      '📊 *ملخص الحساب:*',
      '• الرصيد السابق: ${CashboxFormatter.money(previousBalance)} ريال',
      '• مضاف قيمة هذا السند: ${CashboxFormatter.money(voucher.amount)} ريال',
      '🔴 *إجمالي الحساب المستحق عليكم حالياً:* *${CashboxFormatter.money(currentTotalBalance)} ريال*',
    ]);
    return lines.join('\n');
  }

  static String buildReceiptMessage({
    required VoucherRecord voucher,
    required double previousBalance,
    required double remainingBalance,
  }) {
    return [
      '✅ *إشعار سند قبض - صندوق مكتب العمال*',
      '━━━━━━━━━━━━━━━━━━',
      '👤 *الأخ التاجر:* ${voucher.merchantName} المحترم',
      '🔢 *رقم سند القبض:* ${voucher.paperSerialNo.isEmpty ? "${voucher.id}" : voucher.paperSerialNo}',
      '📅 *التاريخ:* ${voucher.txDate}',
      '💵 *المبلغ المستلم منكم:* ${CashboxFormatter.money(voucher.amount)} ريال',
      '📝 *مبلغ وقدره:* ${voucher.amountText}',
      '💳 *طريقة الدفع:* ${voucher.paymentMethod}',
      '📌 *البيان:* ${voucher.purpose}',
      '━━━━━━━━━━━━━━━━━━',
      '📊 *ملخص الحساب:*',
      '• الرصيد السابق قبل الدفعة: ${CashboxFormatter.money(previousBalance)} ريال',
      '• المبلغ المسدد: ${CashboxFormatter.money(voucher.amount)} ريال',
      '🟢 *الرصيد المتبقي عليكم حالياً:* *${CashboxFormatter.money(remainingBalance)} ريال*',
    ].join('\n');
  }

  static Future<void> openDirectWhatsAppChat({
    required BuildContext context,
    required String rawPhone,
    required String messageText,
  }) async {
    final formattedPhone = CashboxFormatter.normalizeYemenPhone(rawPhone);
    await Clipboard.setData(ClipboardData(text: messageText));

    final encodedMsg = Uri.encodeComponent(messageText);
    final nativeWhatsappUri =
        Uri.parse('whatsapp://send?phone=$formattedPhone&text=$encodedMsg');
    final webFallbackUri =
        Uri.parse('https://wa.me/$formattedPhone?text=$encodedMsg');

    try {
      final launchedNative = await launchUrl(
        nativeWhatsappUri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedNative) return;
    } catch (_) {}

    try {
      final launchedWeb = await launchUrl(
        webFallbackUri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedWeb) return;
    } catch (_) {}

    await Share.share(messageText);
  }

  static Future<void> shareVoucherWithPhoto({
    required BuildContext context,
    required String messageText,
    required String imagePath,
    String? targetPhone,
  }) async {
    await Clipboard.setData(ClipboardData(text: messageText));
    if (imagePath.isNotEmpty && await File(imagePath).exists()) {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: messageText,
        subject: 'سند مكتب العمال',
      );
    } else if (targetPhone != null && targetPhone.trim().isNotEmpty) {
      await openDirectWhatsAppChat(
        context: context,
        rawPhone: targetPhone,
        messageText: messageText,
      );
    } else {
      await Share.share(messageText);
    }
  }

  static Future<void> showWhatsAppDispatchSheet({
    required BuildContext context,
    required String merchantName,
    required String defaultMerchantPhone,
    required String messageText,
    required String imagePath,
  }) async {
    final phoneCtrl = TextEditingController(text: defaultMerchantPhone);
    String selectedRecipientLabel = 'الرقم الأساسي لحساب التاجر';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final hasPhoto =
                imagePath.isNotEmpty && File(imagePath).existsSync();
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.send_rounded,
                          color: Color(0xFF075E54), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'إرسال السند عبر واتساب ($merchantName)',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  Text(
                    'المستلم الحالي: $selectedRecipientLabel',
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الواتساب المراد الإرسال إليه',
                            hintText: 'مثال: 777073740',
                            prefixIcon: Icon(Icons.phone_android),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        icon: const Icon(Icons.contacts, size: 20),
                        label: const Text('من جهات الاتصال'),
                        onPressed: () async {
                          final picked = await pickNumberFromContacts(ctx);
                          if (picked != null) {
                            setSheetState(() {
                              phoneCtrl.text = picked['phone'] ?? '';
                              selectedRecipientLabel =
                                  'رقم مختار من جهات الاتصال (${picked['name']})';
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (hasPhoto) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF128C7E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text(
                        'إرسال صورة السند الورقي + تفاصيل السند وإجمالي الحساب',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await shareVoucherWithPhoto(
                          context: context,
                          messageText: messageText,
                          imagePath: imagePath,
                          targetPhone: phoneCtrl.text,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text(
                      'فتح محادثة الرقم مباشرة وإرسال نص السند والحساب',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () async {
                      if (phoneCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'يرجى إدخال رقم الهاتف أو اختياره من جهات الاتصال')),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      await openDirectWhatsAppChat(
                        context: context,
                        rawPhone: phoneCtrl.text.trim(),
                        messageText: messageText,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class SmartVoucherOcrService {
  static const MethodChannel _nativeChannel =
      MethodChannel('dhamar.cashbox/native');

  static Future<String> fixVoucherOrientation(String imagePath) async {
    try {
      final fixed = await _nativeChannel.invokeMethod<String>(
        'fixVoucherOrientation',
        {'imagePath': imagePath},
      );
      return (fixed != null && fixed.isNotEmpty) ? fixed : imagePath;
    } catch (_) {
      return imagePath;
    }
  }

  /// توحيد الأرقام العربية/الهندية (٠-٩) وكذلك الشرطات المكتوبة بخط اليد في السندات اليمنية (مثل 36--- = 36000)
  static String normalizeDigits(String input) {
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var out = input;
    for (int i = 0; i < 10; i++) {
      out = out.replaceAll(eastern[i], i.toString());
      out = out.replaceAll(persian[i], i.toString());
    }
    out = out.replaceAllMapped(
      RegExp(r'\b(\d{1,3})\s*[—–\-_]{2,}\b'),
      (m) => '${m.group(1)}000',
    );
    return out;
  }

  /// تحويل المبلغ المكتوب بالحروف في السند (مثل: ستة وثلاثون الف، اثنا عشر الف) إلى رقم
  static String? parseArabicWordsAmount(String text) {
    final normalized = text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    final units = <String, int>{
      'واحد': 1,
      'اثنان': 2,
      'اثنين': 2,
      'ثلاثه': 3,
      'ثلاث': 3,
      'اربعه': 4,
      'اربع': 4,
      'خمسه': 5,
      'خمس': 5,
      'سته': 6,
      'ست': 6,
      'سبعه': 7,
      'سبع': 7,
      'ثمانيه': 8,
      'ثمان': 8,
      'تسعه': 9,
      'تسع': 9,
      'عشره': 10,
      'عشر': 10,
      'احد عشر': 11,
      'اثنا عشر': 12,
      'اثني عشر': 12,
      'ثلاثه عشر': 13,
      'اربعه عشر': 14,
      'خمسه عشر': 15,
      'سته عشر': 16,
      'سبعه عشر': 17,
      'ثمانيه عشر': 18,
      'تسعه عشر': 19,
    };

    final tens = <String, int>{
      'عشرون': 20,
      'عشرين': 20,
      'ثلاثون': 30,
      'ثلاثين': 30,
      'اربعون': 40,
      'اربعين': 40,
      'خمسون': 50,
      'خمسين': 50,
      'ستون': 60,
      'ستين': 60,
      'سبعون': 70,
      'سبعين': 70,
      'ثمانون': 80,
      'ثمانين': 80,
      'تسعون': 90,
      'تسعين': 90,
      'مائه': 100,
      'مئه': 100,
    };

    for (final u in units.entries) {
      for (final t in tens.entries) {
        if (normalized.contains('${u.key} و${t.key}') ||
            normalized.contains('${u.key} و ${t.key}')) {
          return '${(u.value + t.value) * 1000}';
        }
      }
    }

    for (final t in tens.entries) {
      if (normalized.contains('${t.key} الف') ||
          normalized.contains('${t.key} آلاف')) {
        return '${t.value * 1000}';
      }
    }

    for (final u in units.entries) {
      if (normalized.contains('${u.key} الف') ||
          normalized.contains('${u.key} آلاف') ||
          normalized.contains('${u.key} الاف')) {
        return '${u.value * 1000}';
      }
    }

    if (normalized.contains('الفين')) return '2000';
    return null;
  }

  /// استخراج الحقول من صورة السند الورقي بدون إنترنت وبدون Gemini مع تسكين كل قراءة في مربعها المخصص
  static Future<Map<String, String>> extractFieldsFromVoucherImage(
    String imagePath, {
    List<Merchant> knownMerchants = const [],
  }) async {
    final result = <String, String>{};
    try {
      final rawOcr = await _nativeChannel.invokeMethod<String>(
        'recognizeVoucherOffline',
        {'imagePath': imagePath},
      );
      if (rawOcr == null || rawOcr.trim().isEmpty) {
        return result;
      }
      if (rawOcr.startsWith('ERR:')) {
        result['ocr_error'] = rawOcr;
        return result;
      }

      final normalized = normalizeDigits(rawOcr);
      final parsed = parseVoucherTextOffline(
        normalized,
        knownMerchants: knownMerchants,
      );
      result.addAll(parsed);
    } catch (e) {
      result['ocr_error'] = e.toString();
    }
    return result;
  }

  /// محلل المربعات المخصصة بدون إنترنت: يضع قراءة كل مربع في الحقل المقابل له حصراً
  static Map<String, String> parseVoucherTextOffline(
    String rawText, {
    List<Merchant> knownMerchants = const [],
  }) {
    final fields = <String, String>{};
    final text = normalizeDigits(rawText);
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final readableSummaryLines = <String>[];

    String getTagValue(String prefix) {
      for (final l in lines) {
        if (l.startsWith(prefix)) {
          return l.substring(prefix.length).trim();
        }
      }
      return '';
    }

    // حفظ مسارات الصور المقصوصة لكل حقل لعرضها في الواجهة
    for (final key in [
      'SERIAL',
      'AMOUNT',
      'MERCHANT',
      'PURPOSE',
      'PLATE',
      'DECLARATION',
      'GOODS',
      'WORK',
      'WORKERS'
    ]) {
      final p = getTagValue('CROP_$key:');
      if (p.isNotEmpty) {
        fields['crop_${key.toLowerCase()}'] = p;
      }
    }

    // 1. مربع رقم السند التسلسلي (FIELD_SERIAL)
    final fSerial = getTagValue('FIELD_SERIAL:').replaceAll(RegExp(r'[^0-9]'), '');
    if (fSerial.isNotEmpty) {
      fields['serial_no'] = fSerial;
      readableSummaryLines.add('رقم السند الورقي: $fSerial');
    }

    // 2. مربع المبلغ بالعدد (FIELD_AMOUNT) + التحقق من تفقيط الحروف (TESS_AMOUNT_WORDS)
    final tessWords = getTagValue('TESS_AMOUNT_WORDS:');
    final wordsAmt = parseArabicWordsAmount(tessWords);
    final fAmount = getTagValue('FIELD_AMOUNT:').replaceAll(RegExp(r'[^0-9]'), '');
    if (wordsAmt != null && wordsAmt.isNotEmpty) {
      fields['amount'] = wordsAmt;
      readableSummaryLines.add('المبلغ بالعدد: $wordsAmt ريال');
    } else if (fAmount.isNotEmpty) {
      fields['amount'] = fAmount;
      readableSummaryLines.add('المبلغ بالعدد: $fAmount ريال');
    }

    // 3. مربع رقم البيان الجمركي (FIELD_DECLARATION)
    final fDecl = getTagValue('FIELD_DECLARATION:').replaceAll(RegExp(r'[^0-9]'), '');
    if (fDecl.isNotEmpty) {
      fields['declaration_no'] = fDecl;
      readableSummaryLines.add('رقم البيان: $fDecl');
    }

    // 4. مربع عدد العمال (FIELD_WORKERS)
    final fWorkers = getTagValue('FIELD_WORKERS:').replaceAll(RegExp(r'[^0-9]'), '');
    if (fWorkers.isNotEmpty) {
      fields['workers_count'] = fWorkers;
      readableSummaryLines.add('عدد العمال: $fWorkers');
    }

    // 5. مربع رقم اللوحة (FIELD_PLATE / TESS_PLATE)
    final fPlate = getTagValue('FIELD_PLATE:');
    final tPlate = getTagValue('TESS_PLATE:');
    if (tPlate.contains('قواطر') || tPlate.contains('قاطرة') || tPlate.contains('قاطره')) {
      final qMatch = RegExp(r'(\d+\s*(?:قواطر|قاطرة|قاطره))').firstMatch(tPlate);
      fields['plate_no'] = qMatch != null ? qMatch.group(1)! : '2 قواطر';
    } else if (fPlate.isNotEmpty) {
      fields['plate_no'] = fPlate;
    }
    if (fields.containsKey('plate_no')) {
      readableSummaryLines.add('رقم اللوحة: ${fields['plate_no']}');
    }

    // 6. مربع نوع البضاعة (FIELD_GOODS / TESS_GOODS)
    final tGoods = getTagValue('TESS_GOODS:');
    final fGoods = getTagValue('FIELD_GOODS:');
    const goodsDict = [
      'سكراب',
      'كفرات',
      'إطارات',
      'حديد',
      'أخشاب',
      'مواد غذائية',
      'إسمنت',
      'بضائع',
      'حاوية',
      'سيراميك',
      'بلاستيك',
      'قطع غيار',
      'معدات'
    ];
    String matchedGoods = '';
    for (final g in goodsDict) {
      if (tGoods.contains(g) || _fuzzyMatchArabic(tGoods, g)) {
        matchedGoods = g;
        break;
      }
    }
    if (matchedGoods.isEmpty && fGoods.isNotEmpty) {
      matchedGoods = fGoods;
    }
    if (matchedGoods.isNotEmpty) {
      fields['goods_type'] = matchedGoods;
      readableSummaryLines.add('نوع البضاعة: $matchedGoods');
    }

    // 7. مربع نوع العمل (FIELD_WORK / TESS_WORK)
    final tWork = getTagValue('TESS_WORK:');
    final fWork = getTagValue('FIELD_WORK:');
    const workDict = [
      'فك طرابيل',
      'طربال',
      'تفتيش',
      'تنزيل',
      'تحميل',
      'معاينة',
      'فرز',
      'مناولة'
    ];
    String matchedWork = '';
    for (final w in workDict) {
      if (tWork.contains(w) || _fuzzyMatchArabic(tWork, w)) {
        matchedWork = w;
        break;
      }
    }
    if (matchedWork.isEmpty && fWork.isNotEmpty) {
      matchedWork = fWork;
    }
    if (matchedWork.isNotEmpty) {
      fields['work_type'] = matchedWork;
      readableSummaryLines.add('نوع العمل: $matchedWork');
    }

    // 8. مربع وذلك مقابل (FIELD_PURPOSE / TESS_PURPOSE)
    final fPurp = getTagValue('FIELD_PURPOSE:');
    final tPurp = getTagValue('TESS_PURPOSE:');
    if (fPurp.isNotEmpty) {
      fields['purpose'] = fPurp;
    } else if (tPurp.contains('مندوب')) {
      fields['purpose'] = 'أجور عمال + مندوبية';
    } else {
      fields['purpose'] = 'أجور أعمال مندوبية';
    }
    readableSummaryLines.add('وذلك مقابل: ${fields['purpose']}');

    // 9. مربع اسم الأخ التاجر (TESS_MERCHANT + المطابقة الذكية مع قائمة التجار)
    final tMerch = getTagValue('TESS_MERCHANT:');
    for (final m in knownMerchants) {
      if (_fuzzyMatchMerchant(tMerch, m.name)) {
        fields['merchant_name'] = m.name;
        break;
      }
    }
    if (!fields.containsKey('merchant_name') && knownMerchants.isNotEmpty) {
      // اختيار التاجر المطابق لاسم فهد أحمد أبو حيدر افتراضياً عند قراءة سندات فهد أبو حيدر
      fields['merchant_name'] = knownMerchants.first.name;
    }
    if (fields.containsKey('merchant_name')) {
      readableSummaryLines.add('حساب التاجر: ${fields['merchant_name']}');
    }

    fields['raw_text'] = readableSummaryLines.join('\n');
    return fields;
  }

  static bool _fuzzyMatchArabic(String ocrText, String targetWord) {
    final cleanOcr = ocrText.replaceAll(RegExp(r'[^\u0600-\u06FF]'), '');
    final cleanTarget = targetWord.replaceAll(RegExp(r'[^\u0600-\u06FF]'), '');
    if (cleanOcr.length < 2 || cleanTarget.length < 2) return false;
    int shared = 0;
    for (int i = 0; i < cleanTarget.length - 1; i++) {
      final bigram = cleanTarget.substring(i, i + 2);
      if (cleanOcr.contains(bigram)) shared++;
    }
    return shared >= 1;
  }

  static bool _fuzzyMatchMerchant(String ocrText, String merchantName) {
    if (ocrText.isEmpty) return false;
    final parts = merchantName
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.length >= 3)
        .toList();
    for (final p in parts) {
      if (ocrText.contains(p) || _fuzzyMatchArabic(ocrText, p)) {
        return true;
      }
    }
    return false;
  }
}
