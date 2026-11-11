import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/whatsapp_and_ocr_service.dart';

class ReceiptVoucherScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const ReceiptVoucherScreen({super.key, required this.onSaved});

  @override
  State<ReceiptVoucherScreen> createState() => _ReceiptVoucherScreenState();
}

class _ReceiptVoucherScreenState extends State<ReceiptVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Merchant> _merchants = [];
  Merchant? _selectedMerchant;
  double _currentMerchantDebt = 0.0;

  final _serialCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _amountCtrl = TextEditingController();
  final _amountWordsCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController(text: 'دفعة تسديد من الحساب');
  String _paymentMethod = 'نقداً';
  String _imagePath = '';
  bool _isScanningOcr = false;

  @override
  void initState() {
    super.initState();
    _loadMerchants();
    _amountCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _serialCtrl.dispose();
    _dateCtrl.dispose();
    _amountCtrl.dispose();
    _amountWordsCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
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
      await _refreshDebt(_selectedMerchant!.id);
    }
  }

  Future<void> _refreshDebt(int merchantId) async {
    final bal =
        await OfflineDatabaseService.instance.computeMerchantBalance(merchantId);
    if (!mounted) return;
    setState(() => _currentMerchantDebt = bal);
  }

  Future<void> _pickReceiptImage(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;
    final saved =
        await OfflineDatabaseService.instance.persistVoucherImage(xfile.path);
    setState(() {
      _imagePath = saved;
      _isScanningOcr = true;
    });
    final extracted =
        await SmartVoucherOcrService.extractFieldsFromVoucherImage(
      saved,
      knownMerchants: _merchants,
    );
    if (!mounted) return;
    setState(() {
      _isScanningOcr = false;
      if (extracted['serial_no'] != null && _serialCtrl.text.trim().isEmpty) {
        _serialCtrl.text = extracted['serial_no']!;
      }
      if (extracted['date'] != null) {
        _dateCtrl.text = extracted['date']!;
      }
      if (extracted['amount'] != null && _amountCtrl.text.trim().isEmpty) {
        _amountCtrl.text =
            extracted['amount']!.replaceAll(RegExp(r'[^0-9.]'), '');
      }
    });
  }

  Future<void> _saveReceipt({required bool sendWhatsApp}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMerchant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار التاجر أولاً')),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final prevDebt = _currentMerchantDebt;
    final remainingDebt = prevDebt - amount;

    final record = VoucherRecord(
      id: 0,
      voucherType: 'receipt',
      merchantId: _selectedMerchant!.id,
      merchantName: _selectedMerchant!.name,
      paperSerialNo: _serialCtrl.text.trim(),
      txDate: _dateCtrl.text.trim(),
      amount: amount,
      amountText: _amountWordsCtrl.text.trim(),
      purpose: _purposeCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      imagePath: _imagePath,
    );

    await OfflineDatabaseService.instance.saveVoucher(record);
    await _refreshDebt(_selectedMerchant!.id);
    widget.onSaved();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF15803D),
        content: Text('تم حفظ سند القبض وخصم المبلغ من حساب التاجر بنجاح'),
      ),
    );

    if (sendWhatsApp) {
      final msg = WhatsAppAndContactsService.buildReceiptMessage(
        voucher: record,
        previousBalance: prevDebt,
        remainingBalance: remainingDebt,
      );
      await WhatsAppAndContactsService.showWhatsAppDispatchSheet(
        context: context,
        merchantName: _selectedMerchant!.name,
        defaultMerchantPhone: _selectedMerchant!.phone,
        messageText: msg,
        imagePath: record.imagePath,
      );
    }

    setState(() {
      _serialCtrl.clear();
      _amountCtrl.clear();
      _amountWordsCtrl.clear();
      _imagePath = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final paidNow = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final remainingAfterPay = _currentMerchantDebt - paidNow;

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
                  colors: [Color(0xFF15803D), Color(0xFF0F766E)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.savings_outlined, color: Colors.white, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نافذة سند القبض (استلام دفعات من التجار)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'تسجيل المبالغ المقبوضة من التجار وتخفيض رصيد مديونيتهم للصندوق',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
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
                    DropdownButtonFormField<Merchant>(
                      value: _selectedMerchant,
                      decoration: const InputDecoration(
                        labelText: 'استلمنا من الأخ التاجر',
                        prefixIcon: Icon(Icons.person),
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
                          _refreshDebt(val.id);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statCol('إجمالي ما عليه سابقاً',
                              _currentMerchantDebt, Colors.red.shade700),
                          _statCol('المبلغ المقبوض الآن', paidNow,
                              Colors.green.shade800),
                          _statCol('المتبقي عليه بعد القبض', remainingAfterPay,
                              Colors.indigo.shade900),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _serialCtrl,
                            decoration: const InputDecoration(
                              labelText: 'رقم سند القبض / الإشعار',
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
                              labelText: 'التاريخ',
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
                          color: Color(0xFF15803D)),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المستلم (ريال) *',
                        prefixIcon: Icon(Icons.attach_money),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null ||
                            v.trim().isEmpty ||
                            (double.tryParse(v.trim()) ?? 0) <= 0) {
                          return 'يرجى إدخال المبلغ المستلم';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amountWordsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ كتابةً (تلقائي)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الاستلام',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'نقداً', child: Text('نقداً في الصندوق')),
                        DropdownMenuItem(
                            value: 'حوالة صرافة',
                            child: Text('حوالة مالية / صرافة')),
                        DropdownMenuItem(
                            value: 'إيداع كريمي / محفظة',
                            child: Text('إيداع كريمي / محفظة إلكترونية')),
                      ],
                      onChanged: (v) =>
                          setState(() => _paymentMethod = v ?? 'نقداً'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _purposeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'البيان / ملاحظات القبض',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _pickReceiptImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('تصوير إشعار التوريد (قراءة تلقائية)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _pickReceiptImage(ImageSource.gallery),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('من الاستوديو'),
                          ),
                        ),
                      ],
                    ),
                    if (_isScanningOcr)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_imagePath.isNotEmpty &&
                        File(_imagePath).existsSync()) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_imagePath),
                            height: 130, fit: BoxFit.cover),
                      ),
                    ],
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
                    onPressed: () => _saveReceipt(sendWhatsApp: false),
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ القبض',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _saveReceipt(sendWhatsApp: true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('حفظ وإرسال واتساب',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String label, double val, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          '${CashboxFormatter.money(val)} ريال',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: color),
        ),
      ],
    );
  }
}
