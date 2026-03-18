import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await InvoiceStorage.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pharmacy Billing',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const InvoiceScreen(),
    );
  }
}

class ProductItem {
  String name;
  String hsn;
  int quantity;
  String batchNo;
  DateTime? expiry;
  double mrp;
  double rate;
  double gstPercent;

  ProductItem({
    this.name = '',
    this.hsn = '',
    this.quantity = 1,
    this.batchNo = '',
    this.expiry,
    this.mrp = 0,
    this.rate = 0,
    this.gstPercent = 0,
  });

  double get amount => quantity * rate;

  double get gstAmount => amount * gstPercent / 100;

  double get totalWithGst => amount + gstAmount;

  Map<String, dynamic> toJson() => {
        'name': name,
        'hsn': hsn,
        'quantity': quantity,
        'batchNo': batchNo,
        'expiry': expiry?.toIso8601String(),
        'mrp': mrp,
        'rate': rate,
        'gstPercent': gstPercent,
      };

  factory ProductItem.fromJson(Map<String, dynamic> json) => ProductItem(
        name: json['name'] ?? '',
        hsn: json['hsn'] ?? '',
        quantity: json['quantity'] ?? 1,
        batchNo: json['batchNo'] ?? '',
        expiry: json['expiry'] != null ? DateTime.parse(json['expiry']) : null,
        mrp: (json['mrp'] ?? 0).toDouble(),
        rate: (json['rate'] ?? 0).toDouble(),
        gstPercent: (json['gstPercent'] ?? 0).toDouble(),
      );
}

class InvoiceModel {
  int? id;
  String pharmacyName;
  String address;
  String gstin;
  String drugLicense;
  String invoiceNumber;
  DateTime date;
  String customerName;
  String doctorName;
  String supplyType;
  double discount;
  List<ProductItem> products;

  InvoiceModel({
    this.id,
    this.pharmacyName = '',
    this.address = '',
    this.gstin = '',
    this.drugLicense = '',
    required this.invoiceNumber,
    required this.date,
    this.customerName = '',
    this.doctorName = '',
    this.supplyType = 'CGST/SGST',
    this.discount = 0,
    required this.products,
  });

  double get subtotal => products.fold(0, (p, element) => p + element.amount);

  double get taxTotal => products.fold(0, (p, element) => p + element.gstAmount);

  double get total => products.fold(0, (p, element) => p + element.totalWithGst) - discount;

  String get amountInWords => NumberToWords.convert(total);

  Map<String, dynamic> toJson() => {
        'id': id,
        'pharmacyName': pharmacyName,
        'address': address,
        'gstin': gstin,
        'drugLicense': drugLicense,
        'invoiceNumber': invoiceNumber,
        'date': date.toIso8601String(),
        'customerName': customerName,
        'doctorName': doctorName,
        'supplyType': supplyType,
        'discount': discount,
        'products': products.map((e) => e.toJson()).toList(),
      };

  factory InvoiceModel.fromJson(Map<String, dynamic> json) => InvoiceModel(
        id: json['id'],
        pharmacyName: json['pharmacyName'] ?? '',
        address: json['address'] ?? '',
        gstin: json['gstin'] ?? '',
        drugLicense: json['drugLicense'] ?? '',
        invoiceNumber: json['invoiceNumber'] ?? '',
        date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
        customerName: json['customerName'] ?? '',
        doctorName: json['doctorName'] ?? '',
        supplyType: json['supplyType'] ?? 'CGST/SGST',
        discount: (json['discount'] ?? 0).toDouble(),
        products: (json['products'] as List<dynamic>).map((e) => ProductItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class InvoiceStorage {
  static final InvoiceStorage instance = InvoiceStorage._init();
  static Database? _db;

  InvoiceStorage._init();

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'pharmacy_invoices.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE invoices(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pharmacyName TEXT,
          address TEXT,
          gstin TEXT,
          drugLicense TEXT,
          invoiceNumber TEXT,
          date TEXT,
          customerName TEXT,
          doctorName TEXT,
          supplyType TEXT,
          discount REAL,
          products TEXT
        )''');
    });
  }

  Future<int> saveInvoice(InvoiceModel invoice) async {
    final db = _db!;
    final id = await db.insert('invoices', {
      'pharmacyName': invoice.pharmacyName,
      'address': invoice.address,
      'gstin': invoice.gstin,
      'drugLicense': invoice.drugLicense,
      'invoiceNumber': invoice.invoiceNumber,
      'date': invoice.date.toIso8601String(),
      'customerName': invoice.customerName,
      'doctorName': invoice.doctorName,
      'supplyType': invoice.supplyType,
      'discount': invoice.discount,
      'products': invoice.products.map((e) => e.toJson()).toList().toString(),
    });
    return id;
  }
}

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pharmacyNameController = TextEditingController(text: 'SHREE ANNAPURNA PHARMA');
  final _addressController = TextEditingController(text: 'Shop No. 4 & 10, ...');
  final _gstinController = TextEditingController();
  final _drugLicenseController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _doctorNameController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  DateTime _invoiceDate = DateTime.now();
  String _supplyType = 'CGST/SGST';
  final ScreenshotController _screenshotController = ScreenshotController();

  List<ProductItem> _products = [];

  @override
  void initState() {
    super.initState();
    _invoiceNumberController.text = _generateInvoiceNumber();
    _products = [ProductItem()];
  }

  String _generateInvoiceNumber() {
    final datePart = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
    return 'INV/$datePart';
  }

  double get _subtotal => _products.fold(0, (prev, item) => prev + item.amount);
  double get _gstTotal => _products.fold(0, (prev, item) => prev + item.gstAmount);
  double get _grandTotal => _products.fold(0, (prev, item) => prev + item.totalWithGst) - double.tryParse(_discountController.text.trim()) ?? 0;

  void _addProduct() {
    setState(() {
      _products.add(ProductItem());
    });
  }

  void _removeProduct(int index) {
    setState(() {
      if (_products.length > 1) _products.removeAt(index);
    });
  }

  void _pickExpiry(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _products[index].expiry ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _products[index].expiry = picked;
      });
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _invoiceDate = picked;
      });
    }
  }

  Future<void> _saveInvoice() async {
    final invoice = InvoiceModel(
      invoiceNumber: _invoiceNumberController.text,
      date: _invoiceDate,
      pharmacyName: _pharmacyNameController.text,
      address: _addressController.text,
      gstin: _gstinController.text,
      drugLicense: _drugLicenseController.text,
      customerName: _customerNameController.text,
      doctorName: _doctorNameController.text,
      supplyType: _supplyType,
      discount: double.tryParse(_discountController.text) ?? 0,
      products: _products,
    );
    await InvoiceStorage.instance.saveInvoice(invoice);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice saved locally')));
    }
  }

  Future<void> _previewPdf() async {
    final pdf = await _generateInvoicePdf();
    await Printing.layoutPdf(onLayout: (format) => pdf);
  }

  Future<Uint8List> _generateInvoicePdf() async {
    return Printing.convertHtml(format: PdfPageFormat.a4, html: _invoiceHtml(),);
  }

  String _invoiceHtml() {
    final rows = _products.map((item) {
      final exp = item.expiry != null ? DateFormat('dd-MM-yyyy').format(item.expiry!) : '';
      return '''
<tr>
  <td>${item.name}</td>
  <td>${item.hsn}</td>
  <td>${item.quantity}</td>
  <td>${item.batchNo}</td>
  <td>$exp</td>
  <td>${item.mrp.toStringAsFixed(2)}</td>
  <td>${item.rate.toStringAsFixed(2)}</td>
  <td>${item.amount.toStringAsFixed(2)}</td>
</tr>
''';
    }).join();

    return '''
<html><body style="font-family: Arial; font-size: 12px;">
<h2>SHREE ANNAPURNA PHARMA</h2>
<p>${_addressController.text}<br>GSTIN: ${_gstinController.text}<br>DL: ${_drugLicenseController.text}</p>
<p>Invoice: ${_invoiceNumberController.text} | Date: ${DateFormat('dd-MM-yyyy').format(_invoiceDate)}</p>
<p>Customer: ${_customerNameController.text} | Doctor: ${_doctorNameController.text}</p>
<table border='1' cellspacing='0' cellpadding='4' width='100%'>
<tr><th>Product</th><th>HSN</th><th>Qty</th><th>Batch</th><th>Exp</th><th>MRP</th><th>Rate</th><th>Amt</th></tr>
$rows
</table>
<p>Subtotal: ${_subtotal.toStringAsFixed(2)}<br>GST: ${_gstTotal.toStringAsFixed(2)}<br>Discount: ${double.tryParse(_discountController.text) ?? 0}<br><b>Grand Total: ${_grandTotal.toStringAsFixed(2)}</b></p>
<p>Amount in Words: ${NumberToWords.convert(_grandTotal)}</p>
</body></html>
''';
  }

  Future<void> _screenshotInvoice() async {
    final bytes = await _screenshotController.capture();
    if (bytes != null) {
      await Printing.sharePdf(bytes: bytes, filename: 'invoice.png');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacy Billing System')),
      body: Screenshot(
        controller: _screenshotController,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Header Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(controller: _pharmacyNameController, decoration: const InputDecoration(labelText: 'Pharmacy Name'),),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address'),),
              TextFormField(controller: _gstinController, decoration: const InputDecoration(labelText: 'GSTIN'),),
              TextFormField(controller: _drugLicenseController, decoration: const InputDecoration(labelText: 'Drug License Number'),),
              TextFormField(controller: _invoiceNumberController, decoration: const InputDecoration(labelText: 'Invoice Number'), readOnly: true,),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text('Date: ${DateFormat('dd-MM-yyyy').format(_invoiceDate)}', style: const TextStyle(fontSize: 16))),
                ElevatedButton(onPressed: _pickDate, child: const Text('Edit Date')),
              ]),
              TextFormField(controller: _customerNameController, decoration: const InputDecoration(labelText: 'Customer / Party Name'),),
              TextFormField(controller: _doctorNameController, decoration: const InputDecoration(labelText: 'Doctor Name'),),
              const SizedBox(height: 12),
              const Text('Product Entry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(children: [
                const Text('Supply Type:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _supplyType,
                  items: const [DropdownMenuItem(value: 'CGST/SGST', child: Text('CGST/SGST')), DropdownMenuItem(value: 'IGST', child: Text('IGST'))],
                  onChanged: (value) => setState(() => _supplyType = value!),
                )
              ]),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final p = _products[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('Item ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(onPressed: () => _removeProduct(index), icon: const Icon(Icons.delete, color: Colors.red))
                        ]),
                        TextFormField(initialValue: p.name, decoration: const InputDecoration(labelText: 'Product Name'), onChanged: (v) => p.name = v),
                        TextFormField(initialValue: p.hsn, decoration: const InputDecoration(labelText: 'HSN Code'), onChanged: (v) => p.hsn = v),
                        Row(children: [
                          Expanded(child: TextFormField(initialValue: p.quantity.toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'), onChanged: (v) => setState(() => p.quantity = int.tryParse(v) ?? 1),)),
                          const SizedBox(width: 8),
                          Expanded(child: TextFormField(initialValue: p.batchNo, decoration: const InputDecoration(labelText: 'Batch No'), onChanged: (v) => p.batchNo = v)),
                        ]),
                        Row(children: [
                          Expanded(child: Text('Expiry: ${p.expiry != null ? DateFormat('dd-MM-yyyy').format(p.expiry!) : 'Not set'}')),
                          ElevatedButton(onPressed: () => _pickExpiry(index), child: const Text('Pick Date'))
                        ]),
                        Row(children: [
                          Expanded(child: TextFormField(initialValue: p.mrp.toStringAsFixed(2), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'MRP'), onChanged: (v) => setState(() => p.mrp = double.tryParse(v) ?? 0),)),
                          const SizedBox(width: 8),
                          Expanded(child: TextFormField(initialValue: p.rate.toStringAsFixed(2), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Rate'), onChanged: (v) => setState(() => p.rate = double.tryParse(v) ?? 0),)),
                          const SizedBox(width: 8),
                          Expanded(child: TextFormField(initialValue: p.gstPercent.toStringAsFixed(2), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'GST %'), onChanged: (v) => setState(() => p.gstPercent = double.tryParse(v) ?? 0),)),
                        ]),
                        const SizedBox(height: 4),
                        Text('Line Amount: ${p.amount.toStringAsFixed(2)} | GST: ${p.gstAmount.toStringAsFixed(2)} | Total: ${p.totalWithGst.toStringAsFixed(2)}'),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              ElevatedButton.icon(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Add Product')),
              const SizedBox(height: 12),
              TextFormField(controller: _discountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Discount (optional)'), onChanged: (s) => setState(() {}),),
              const SizedBox(height: 12),
              Card(margin: const EdgeInsets.symmetric(vertical: 8), child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Subtotal: ${_subtotal.toStringAsFixed(2)}'),
                Text('Total GST: ${_gstTotal.toStringAsFixed(2)}'),
                Text('Grand Total: ${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Amount in Words: ${NumberToWords.convert(_grandTotal)}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ]))),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ElevatedButton(onPressed: _saveInvoice, child: const Text('Save Invoice')),
                ElevatedButton(onPressed: _previewPdf, child: const Text('Preview/Generate PDF')),
                ElevatedButton(onPressed: _screenshotInvoice, child: const Text('Screenshot & Share')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class NumberToWords {
  static const List<String> _oneToNineteen = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'
  ];
  static const List<String> _tens = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];

  static String convert(double value) {
    final rupees = value.floor();
    final paise = ((value - rupees) * 100).round();
    final rupeesText = rupees == 0 ? 'Zero' : _convertInteger(rupees);
    final paiseText = paise > 0 ? ' and ${_convertInteger(paise)} Paise' : '';
    return '$rupeesText Rupees$paiseText Only';
  }

  static String _convertInteger(int value) {
    if (value == 0) return 'Zero';
    if (value < 20) return _oneToNineteen[value];
    if (value < 100) {
      return '${_tens[value ~/ 10]}${value % 10 != 0 ? ' ' + _oneToNineteen[value % 10] : ''}';
    }
    if (value < 1000) {
      return '${_oneToNineteen[value ~/ 100]} Hundred${value % 100 != 0 ? ' and ${_convertInteger(value % 100)}' : ''}';
    }
    if (value < 100000) {
      return '${_convertInteger(value ~/ 1000)} Thousand${value % 1000 != 0 ? ' ${_convertInteger(value % 1000)}' : ''}';
    }
    if (value < 10000000) {
      return '${_convertInteger(value ~/ 100000)} Lakh${value % 100000 != 0 ? ' ${_convertInteger(value % 100000)}' : ''}';
    }
    return '${_convertInteger(value ~/ 10000000)} Crore${value % 10000000 != 0 ? ' ${_convertInteger(value % 10000000)}' : ''}';
  }
}
