import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AddItemScreen extends StatefulWidget {
  final Entry entry;
  const AddItemScreen({super.key, required this.entry});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  String _itemType = 'Gold';
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _noteController = TextEditingController();
  
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;

  final List<String> _types = ['Gold', 'Silver', 'Other'];

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item name is required')));
      return;
    }
    
    // Weight is required for Gold and Silver
    if (_itemType != 'Other' && _weightController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Weight is required for $_itemType items')),
      );
      return;
    }
    
    // Weight must be a valid number if provided
    if (_weightController.text.trim().isNotEmpty && double.tryParse(_weightController.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight must be a valid number')));
      return;
    }

    setState(() => _loading = true);
    try {
      final uniqueNegativeId = -(DateTime.now().millisecondsSinceEpoch % 1000000000);
      final item = JewelleryItem(
        id: uniqueNegativeId,
        syncId: const Uuid().v4(),
        // Use the entry's actual ID (could be negative for offline entries)
        entry: widget.entry.id ?? -1,
        itemType: _itemType,
        name: _nameController.text,
        weight: double.tryParse(_weightController.text),
        note: _noteController.text,
        image: _imageFile?.path,
      );

      // Pass the entry's syncId so SyncManager can resolve the parent later
      await LocalDbService.saveItem(item, entrySyncId: widget.entry.syncId);
      
      if (mounted) Navigator.pop(context, true);

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Item')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              value: _itemType,
              decoration: const InputDecoration(labelText: 'Item Type', prefixIcon: Icon(Icons.category)),
              items: _types.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _itemType = v);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Item Name *', prefixIcon: Icon(Icons.diamond)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _itemType == 'Other' ? 'Weight (grams) - Optional' : 'Weight (grams) *',
                prefixIcon: const Icon(Icons.scale),
                hintText: _itemType == 'Other' ? 'Leave blank if not applicable' : 'e.g. 10.5',
                helperText: _itemType != 'Other' ? 'Required for $_itemType items' : null,
                helperStyle: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Identifying Marks / Notes', prefixIcon: Icon(Icons.notes)),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            
            // Image Picker Section
            Text('Item Photo (Optional)', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_imageFile!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 40, color: Colors.grey[500]),
                          const SizedBox(height: 8),
                          Text('Tap to add photo', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
              ),
            ),
            if (_imageFile != null)
              TextButton.icon(
                onPressed: () => setState(() => _imageFile = null),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
              ),
              
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Item'),
            ),
          ],
        ),
      ),
    );
  }
}
