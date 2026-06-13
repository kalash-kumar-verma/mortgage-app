import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../services/settings_service.dart';

class PdfReceiptService {
  /// Generate and share a withdrawal receipt as PDF
  static Future<void> shareWithdrawalReceipt(Entry entry, List<JewelleryItem> items) async {
    final pdf = pw.Document();
    final businessName = SettingsService.businessName;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        businessName,
                        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('Jewellery Mortgage Management', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('WITHDRAWAL RECEIPT', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      pw.SizedBox(height: 4),
                      pw.Text(entry.srNumber, style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.purple800, thickness: 2),
              pw.SizedBox(height: 16),

              // Party & Date Info
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Customer Name', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.Text(entry.partyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Closed On', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.Text(entry.closedAt ?? 'Today', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Transaction Details
              pw.Text('Transaction Details', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              _buildRow('Start Date', entry.date),
              _buildRow('Duration', '${entry.daysElapsed} days'),
              _buildRow('Principal Amount', '₹${entry.amount}'),
              _buildRow('Monthly Interest Rate', '${entry.interest}%'),
              pw.Divider(color: PdfColors.grey300),
              _buildRow('Total Amount to Settle', '₹${entry.totalPayable.toStringAsFixed(2)}', bold: true, highlight: true),
              pw.SizedBox(height: 24),

              // Items Section
              if (items.isNotEmpty) ...[
                pw.Text('Pledged Jewellery Items', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _tableHeader('Item Name'),
                        _tableHeader('Type'),
                        _tableHeader('Weight'),
                      ],
                    ),
                    ...items.map((item) => pw.TableRow(
                      children: [
                        _tableCell(item.name),
                        _tableCell(item.itemType),
                        _tableCell(item.weight != null ? '${item.weight}g' : '-'),
                      ],
                    )),
                  ],
                ),
                pw.SizedBox(height: 24),
              ],

              // Signature Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 120, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Customer Signature', style: pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 120, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Shop Owner / Staff', style: pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 24),
              pw.Divider(color: PdfColors.grey300),
              pw.Center(
                child: pw.Text(
                  'Thank you for your business. Items have been returned to the customer.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'receipt_${entry.srNumber}.pdf',
    );
  }

  /// Generate and preview a PDF receipt
  static Future<void> previewWithdrawalReceipt(context, Entry entry, List<JewelleryItem> items) async {
    await Printing.layoutPdf(
      onLayout: (_) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            build: (ctx) => pw.Text('Receipt for ${entry.srNumber}'),
          ),
        );
        return pdf.save();
      },
    );
  }

  static pw.Widget _buildRow(String label, String value, {bool bold = false, bool highlight = false}) {
    return pw.Container(
      color: highlight ? PdfColors.green50 : null,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 12, fontWeight: bold ? pw.FontWeight.bold : null),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );
  }

  static Future<void> shareAuditRegisterPdf(
      String rangeLabel,
      List<Entry> newPledges,
      List<Entry> releasedLoans,
      Map<int, String> partyNames,
      Map<int, String> partyPhones,
      Map<int, String> entryItems) async {
    final pdf = pw.Document();
    final businessName = SettingsService.businessName;

    pw.Widget buildSectionHeader(String title) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
        child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
      );
    }

    pw.Widget buildTable(List<Entry> entries, bool isReleased) {
      if (entries.isEmpty) return pw.Text('No records found for this period.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey));

      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.2),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2.5),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _tableHeader(isReleased ? 'Release Date' : 'Pledge Date'),
              _tableHeader('SR No.'),
              _tableHeader('Customer Details'),
              _tableHeader('Items'),
              _tableHeader(isReleased ? 'Principal + Interest' : 'Principal (₹)'),
              _tableHeader('Status'),
            ],
          ),
          ...entries.map((e) {
            final name = partyNames[e.party] ?? e.partyName;
            final phone = partyPhones[e.party] ?? '';
            final items = entryItems[e.id ?? 0] ?? '';
            
            String dateCol = isReleased ? (e.closedAt ?? e.date) : e.date;
            String amountCol = isReleased ? '₹${e.amount} + ₹${e.effectiveTotalPaid - (double.tryParse(e.amount) ?? 0)}' : '₹${e.amount}';

            return pw.TableRow(
              children: [
                _tableCell(dateCol),
                _tableCell(e.srNumber),
                _tableCell('$name\n$phone'),
                _tableCell(items),
                _tableCell(amountCol),
                _tableCell(e.status),
              ],
            );
          }),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(businessName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Audit Register (Khatabook)', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated: ${DateTime.now().toString().split('.')[0]}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    pw.Text('Period: $rangeLabel', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            buildSectionHeader('Section 1: New Pledges (Cash Out)'),
            buildTable(newPledges, false),
            pw.SizedBox(height: 24),
            buildSectionHeader('Section 2: Released Loans (Cash In)'),
            buildTable(releasedLoans, true),
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'audit_register_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
