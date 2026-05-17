import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../services/api_service.dart';
import '../services/pdf_receipt_service.dart';

class ReceiptScreen extends StatefulWidget {
  final Entry entry;
  const ReceiptScreen({super.key, required this.entry});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  List<JewelleryItem> _items = [];
  bool _loadingItems = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (widget.entry.id == null) {
      setState(() => _loadingItems = false);
      return;
    }
    try {
      final items = await ApiService().fetchItems(widget.entry.id!);
      setState(() { _items = items; _loadingItems = false; });
    } catch (_) {
      setState(() => _loadingItems = false);
    }
  }

  Future<void> _shareAsPdf() async {
    setState(() => _sharing = true);
    try {
      await PdfReceiptService.shareWithdrawalReceipt(widget.entry, _items);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Error: $e')));
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdrawal Receipt'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          _sharing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share as PDF',
                  onPressed: _loadingItems ? null : _shareAsPdf,
                ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Receipt Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
              ),
              child: Column(
                children: [
                  // Success Badge
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle, color: Colors.green, size: 52),
                  ),
                  const SizedBox(height: 12),
                  const Text('Withdrawal Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 4),
                  Text(entry.srNumber, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  _row('Party', entry.partyName),
                  _row('Start Date', entry.date),
                  _row('Closed Date', entry.closedAt ?? 'Today'),
                  _row('Duration', '${entry.daysElapsed} days'),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _row('Principal', '₹${entry.amount}'),
                  _row('Interest Rate', '${entry.interest}% / month'),
                  const SizedBox(height: 12),
                  // Total Highlight Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Settled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          '₹${entry.totalPayable.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Items section
            if (_loadingItems)
              const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
            else if (_items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Returned Items (${_items.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    ..._items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: item.itemType == 'Gold' ? Colors.amber[50] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(child: Text(item.itemType[0], style: TextStyle(
                              color: item.itemType == 'Gold' ? Colors.amber[800] : Colors.grey[700],
                              fontWeight: FontWeight.bold,
                            ))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (item.weight != null) Text('${item.weight}g', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          )),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingItems ? null : _shareAsPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Download PDF'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.done),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C35D4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Note about PDF
            Text(
              'Tap "Download PDF" to share or print the receipt',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
