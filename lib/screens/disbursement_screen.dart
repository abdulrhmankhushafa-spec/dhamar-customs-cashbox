import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/whatsapp_and_ocr_service.dart';

class DisbursementVoucherScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const DisbursementVoucherScreen({super.key, required this.onSaved});

  @override
  State<DisbursementVoucherScreen> createState() =>
      _DisbursementVoucherScreenState();
}

class _DisbursementVoucherScreenState extends State<DisbursementVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Merchant> _merchants = [];
  Merchant? _selectedMerchant;
  double _previousBalance = 0.0;

  final _serialCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _hijriCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _amountWordsCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController(text: 'أجور أعمال مندوبية');
  final _plateCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();
  final _declarationCtrl = TextEditingController();
  final _goodsCtrl = TextEditingController();
  final _workTypeCtrl = TextEditingController();
  final _workersCountCtrl = TextEditingController();
  final _supervisorCtrl = TextEditingController(text: 'مدير مكتب العمال');

  String _capturedImagePath = '';
  String _lastRawOcrText = '';
  Map<String, String> _fieldCrops = {};
  bool _isScanningOcr = false;

  static const _quickGoods = ['كفرات', 'سكراب', 'حديد', 'أخشاب', 'مواد غذائية', 'إسمنت'];
  static const _quickWorks = ['تفتيش', 'طربال', 'تنزيل', 'تحميل', 'معاينة', 'فرز'];

  @override
  void initState() {
    super.initState();
    _loadMerchants();
    _amountCtrl.addListener(_updateTafqeet);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_updateTafqeet);
    _serialCtrl.dispose();
    _dateCtrl.dispose();
    _hijriCtrl.dispose();
    _amountCtrl.dispose();
    _amountWordsCtrl.dispose();
    _purposeCtrl.dispose();
    _plateCtrl.dispose();
    _chassisCtrl.dispose();
    _declarationCtrl.dispose();
    _goodsCtrl.dispose();
    _workTypeCtrl.dispose();
    _workersCountCtrl.dispose();
    _supervisorCtrl.dispose();
    super.dispose();
  }

  void _updateTafqeet() {
    final val = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    _amountWordsCtrl.text = CashboxFormatter.tafqeetYemeniRiyal(val);
    setState(() {});
  }

  Future<void> _loadMerchants() async {
    final list = await OfflineDatabaseService.instance.fetchMerchants();
    if (!mounted) return;
    setState(() {
      _merchants = list;
      if (_selectedMerchant == null && list.isNotEmpty) {
        _selectedMerchant = list.first;
      } else if (_selectedMerchant != null) {
        final found = list.where((m) => m.id == _selectedMerchant!.id).toList();
        _selectedMerchant = found.isNotEmpty
            ? found.first
            : (list.isNotEmpty ? list.first : null);
      }
    });
    if (_selectedMerchant != null) {
      await _refreshMerchantBalance(_selectedMerchant!.id);
    }
  }

  Future<void> _refreshMerchantBalance(int merchantId) async {
    final bal =
        await OfflineDatabaseService.instance.computeMerchantBalance(merchantId);
    if (!mounted) return;
    setState(() => _previousBalance = bal);
  }

  Future<void> _pickVoucherImage(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;
    final rawSavedPath =
        await OfflineDatabaseService.instance.persistVoucherImage(xfile.path);
    final savedPath =
        await SmartVoucherOcrService.fixVoucherOrientation(rawSavedPath);
    await FileImage(File(savedPath)).evict();
    setState(() {
      _capturedImagePath = savedPath;
      _lastRawOcrText = '';
    });
    // قراءة السند تلقائياً فور اختيار أو التقاط الصورة بدون إنترنت
    await _runAutoExtractFromImage();
  }

  Future<void> _runAutoExtractFromImage() async {
    if (_capturedImagePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تصوير السند الورقي أولاً')),
      );
      return;
    }
    setState(() => _isScanningOcr = true);
    final extracted =
        await SmartVoucherOcrService.extractFieldsFromVoucherImage(
      _capturedImagePath,
      knownMerchants: _merchants,
    );
    if (!mounted) return;

    final crops = <String, String>{};
    for (final k in ['serial', 'amount', 'merchant', 'purpose', 'plate', 'declaration', 'goods', 'work', 'workers']) {
      final cp = extracted['crop_$k'] ?? '';
      if (cp.isNotEmpty) {
        await FileImage(File(cp)).evict();
        crops[k] = cp;
      }
    }

    int filledCount = 0;
    setState(() {
      _isScanningOcr = false;
      _fieldCrops = crops;
      _lastRawOcrText = extracted['raw_text'] ?? '';

      if (extracted['serial_no'] != null) {
        _serialCtrl.text = extracted['serial_no']!;
        filledCount++;
      }
      if (extracted['date'] != null) {
        _dateCtrl.text = extracted['date']!;
        filledCount++;
      }
      if (extracted['amount'] != null) {
        _amountCtrl.text =
            extracted['amount']!.replaceAll(RegExp(r'[^0-9.]'), '');
        filledCount++;
      }
      if (extracted['purpose'] != null) {
        _purposeCtrl.text = extracted['purpose']!;
        filledCount++;
      }
      if (extracted['plate_no'] != null) {
        _plateCtrl.text = extracted['plate_no']!;
        filledCount++;
      }
      if (extracted['chassis_no'] != null) {
        _chassisCtrl.text = extracted['chassis_no']!;
        filledCount++;
      }
      if (extracted['declaration_no'] != null) {
        _declarationCtrl.text = extracted['declaration_no']!;
        filledCount++;
      }
      if (extracted['goods_type'] != null) {
        _goodsCtrl.text = extracted['goods_type']!;
        filledCount++;
      }
      if (extracted['work_type'] != null) {
        _workTypeCtrl.text = extracted['work_type']!;
        filledCount++;
      }
      if (extracted['workers_count'] != null) {
        _workersCountCtrl.text = extracted['workers_count']!;
        filledCount++;
      }
      if (extracted['merchant_name'] != null) {
        final targetName = extracted['merchant_name']!;
        for (final m in _merchants) {
          if (m.name.contains(targetName) || targetName.contains(m.name)) {
            _selectedMerchant = m;
            _refreshMerchantBalance(m.id);
            filledCount++;
            break;
          }
        }
      }
    });

    final ocrErr = extracted['ocr_error'] ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor:
            filledCount > 0 ? const Color(0xFF0F766E) : Colors.orange.shade800,
        content: Text(
          filledCount > 0
              ? 'تم استخراج وتعبئة ($filledCount) حقول من السند الورقي بدون إنترنت!'
              : (ocrErr.isNotEmpty
                  ? 'تنبيه القارئ المحلي: $ocrErr'
                  : (_lastRawOcrText.isNotEmpty
                      ? 'تمت قراءة نص من الصورة: ($_lastRawOcrText) - اضغط على (مراجعة النص المقروء) بالأسفل لتعيينه.'
                      : 'تعذر قراءة نص واضح من الصورة، يرجى تقريب الكاميرا وتوضيح الإضاءة.')),
        ),
      ),
    );
  }

  void _openRawOcrInspectorSheet() {
    if (_lastRawOcrText.trim().isEmpty) return;
    final tokens = _lastRawOcrText
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'النص المقروء من السند (اضغط على أي سطر لتعيينه في حقل محدد)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tokens.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final line = tokens[i];
                    final cleanVal = line.contains(':')
                        ? line.substring(line.indexOf(':') + 1).trim()
                        : line.trim();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline,
                          color: Color(0xFF0F766E), size: 20),
                      title: Text(line,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.input, color: Color(0xFF1E3A8A)),
                        tooltip: 'تعيين إلى حقل',
                        onSelected: (field) {
                          setState(() {
                            final digitsOnly =
                                cleanVal.replaceAll(RegExp(r'[^0-9.]'), '');
                            switch (field) {
                              case 'serial':
                                _serialCtrl.text =
                                    digitsOnly.isNotEmpty ? digitsOnly : cleanVal;
                                break;
                              case 'amount':
                                _amountCtrl.text = digitsOnly;
                                break;
                              case 'plate':
                                _plateCtrl.text = cleanVal;
                                break;
                              case 'decl':
                                _declarationCtrl.text =
                                    digitsOnly.isNotEmpty ? digitsOnly : cleanVal;
                                break;
                              case 'goods':
                                _goodsCtrl.text = cleanVal;
                                break;
                              case 'work':
                                _workTypeCtrl.text = cleanVal;
                                break;
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'serial', child: Text('رقم السند الورقي')),
                          PopupMenuItem(
                              value: 'amount', child: Text('المبلغ بالعدد')),
                          PopupMenuItem(
                              value: 'plate', child: Text('رقم اللوحة')),
                          PopupMenuItem(
                              value: 'decl', child: Text('رقم البيان')),
                          PopupMenuItem(
                              value: 'goods', child: Text('نوع البضاعة')),
                          PopupMenuItem(
                              value: 'work', child: Text('نوع العمل')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _quickAddMerchantDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة تاجر جديد سريعاً'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم التاجر / المخلص',
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
                      labelText: 'رقم الواتساب',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  icon: const Icon(Icons.contacts),
                  tooltip: 'اختيار من جهات الاتصال',
                  onPressed: () async {
                    final picked =
                        await WhatsAppAndContactsService.pickNumberFromContacts(
                            ctx);
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final newId = await OfflineDatabaseService.instance.saveMerchant(
                Merchant(
                  id: 0,
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                ),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              await _loadMerchants();
              final matches =
                  _merchants.where((m) => m.id == newId).toList();
              if (matches.isNotEmpty) {
                setState(() => _selectedMerchant = matches.first);
                await _refreshMerchantBalance(newId);
              }
            },
            child: const Text('حفظ التاجر'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitVoucher({required bool sendToWhatsApp}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMerchant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار التاجر أولاً')),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final prevBal = _previousBalance;
    final newTotalBal = prevBal + amount;

    final record = VoucherRecord(
      id: 0,
      voucherType: 'disbursement',
      merchantId: _selectedMerchant!.id,
      merchantName: _selectedMerchant!.name,
      paperSerialNo: _serialCtrl.text.trim(),
      txDate: _dateCtrl.text.trim(),
      hijriDate: _hijriCtrl.text.trim(),
      amount: amount,
      amountText: _amountWordsCtrl.text.trim(),
      purpose: _purposeCtrl.text.trim(),
      plateNumber: _plateCtrl.text.trim(),
      chassisNumber: _chassisCtrl.text.trim(),
      declarationNumber: _declarationCtrl.text.trim(),
      goodsCategory: _goodsCtrl.text.trim(),
      workCategory: _workTypeCtrl.text.trim(),
      workersCount: _workersCountCtrl.text.trim(),
      supervisorName: _supervisorCtrl.text.trim(),
      imagePath: _capturedImagePath,
    );

    await OfflineDatabaseService.instance.saveVoucher(record);
    await _refreshMerchantBalance(_selectedMerchant!.id);
    widget.onSaved();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF0F766E),
        content: Text('تم حفظ سند الصرف وتحديث حساب التاجر بنجاح'),
      ),
    );

    if (sendToWhatsApp) {
      final msg = WhatsAppAndContactsService.buildDisbursementMessage(
        voucher: record,
        previousBalance: prevBal,
        currentTotalBalance: newTotalBal,
      );
      await WhatsAppAndContactsService.showWhatsAppDispatchSheet(
        context: context,
        merchantName: _selectedMerchant!.name,
        defaultMerchantPhone: _selectedMerchant!.phone,
        messageText: msg,
        imagePath: record.imagePath,
      );
    }

    _clearFieldsAfterSave();
  }

  void _clearFieldsAfterSave() {
    setState(() {
      _serialCtrl.clear();
      _amountCtrl.clear();
      _amountWordsCtrl.clear();
      _plateCtrl.clear();
      _chassisCtrl.clear();
      _declarationCtrl.clear();
      _goodsCtrl.clear();
      _workTypeCtrl.clear();
      _workersCountCtrl.clear();
      _capturedImagePath = '';
      _lastRawOcrText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final newTotalBalance = _previousBalance + currentAmount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF0F766E)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الجمهورية اليمنية\nمكتب جمارك ورقابة ذمار',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('مكتب العمال\nساحة الأربعين',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Icon(Icons.receipt_long, color: Colors.amber, size: 32),
                    ],
                  ),
                  SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      child: Text(
                        'تسجيل سند صرف (مقابل سند قبض أجور العمال الورقي)',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.camera_enhance, color: Color(0xFF1E3A8A)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '1. تصوير السند الورقي (قراءة تلقائية مجانية بدون إنترنت)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                _pickVoucherImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('تصوير بالكاميرا'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _pickVoucherImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('من الاستوديو'),
                          ),
                        ),
                      ],
                    ),
                    if (_capturedImagePath.isNotEmpty &&
                        File(_capturedImagePath).existsSync()) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_capturedImagePath),
                          height: 165,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                        ),
                        onPressed:
                            _isScanningOcr ? null : _runAutoExtractFromImage,
                        icon: _isScanningOcr
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.document_scanner_outlined),
                        label: Text(_isScanningOcr
                            ? 'جاري قراءة بيانات السند بدون إنترنت...'
                            : 'إعادة قراءة وتعبئة بيانات السند تلقائياً (بدون نت)'),
                      ),
                      if (_lastRawOcrText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: _openRawOcrInspectorSheet,
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text(
                              'مراجعة النص المقروء وتوزيعه يدوياً بضغطة واحدة'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Merchant>(
                            value: _selectedMerchant,
                            decoration: const InputDecoration(
                              labelText: 'حساب الأخ التاجر (المقيد عليه السند)',
                              prefixIcon: Icon(Icons.person_pin),
                              border: OutlineInputBorder(),
                            ),
                            items: _merchants
                                .map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text('${m.name} (${m.phone})'),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() => _selectedMerchant = val);
                              if (val != null) {
                                _refreshMerchantBalance(val.id);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E)),
                          onPressed: _quickAddMerchantDialog,
                          icon: const Icon(Icons.person_add),
                          tooltip: 'إضافة تاجر جديد',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _balanceBadge(
                              'الرصيد السابق', _previousBalance, Colors.black87),
                          _balanceBadge('سند الصرف الحالي', currentAmount,
                              Colors.orange.shade800),
                          _balanceBadge('إجمالي الحساب المستحق',
                              newTotalBalance, Colors.red.shade800),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '2. بيانات السند الورقي والمبلغ المصروف',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _serialCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'رقم السند الورقي (مثل 0086883)',
                              prefixIcon: Icon(Icons.tag, color: Colors.red),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _dateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'التاريخ الميلادي',
                              prefixIcon: Icon(Icons.calendar_today),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A8A)),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ بالعدد (ريال) *',
                        hintText: 'مثال: 12000',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null ||
                            v.trim().isEmpty ||
                            (double.tryParse(v.trim()) ?? 0) <= 0) {
                          return 'يرجى إدخال مبلغ السند';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amountWordsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'مبلغ وقدره (يتعبأ تلقائياً بالحروف)',
                        prefixIcon: Icon(Icons.short_text),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _purposeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'وذلك مقابل',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '3. بيانات البيان الجمركي والسيارة والعمال (مطابق للسند الورقي)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _plateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'رقم اللوحة (مثل 3854/14)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _chassisCtrl,
                            decoration: const InputDecoration(
                              labelText: 'رقم القعادة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _declarationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'رقم البيان (مثل 9258)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _workersCountCtrl,
                            decoration: const InputDecoration(
                              labelText: 'عدد العمال (مثل 2 عمال)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _goodsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نوع البضاعة (مثل: سكراب)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: _quickGoods
                          .map((g) => ActionChip(
                                label: Text(g,
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () =>
                                    setState(() => _goodsCtrl.text = g),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _workTypeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نوع العمل (مثل: طربال)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: _quickWorks
                          .map((w) => ActionChip(
                                label: Text(w,
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () =>
                                    setState(() => _workTypeCtrl.text = w),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _submitVoucher(sendToWhatsApp: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text(
                      'حفظ السند',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF128C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _submitVoucher(sendToWhatsApp: true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text(
                      'حفظ وإرسال واتساب',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _balanceBadge(String title, double val, Color color) {
    return Column(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 3),
        Text(
          '${CashboxFormatter.money(val)} ريال',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: color),
        ),
      ],
    );
  }
}
