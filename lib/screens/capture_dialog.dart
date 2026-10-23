import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/catalog_entry.dart';
import '../providers/catalog_provider.dart';
import '../data/photo_processor.dart';
import '../data/translation_service.dart';
import 'package:provider/provider.dart';

/// Capture/edit form. Opens either blank (new barcode) or pre-filled (existing
/// entry). On save returns true; caller decides what to do next.
///
/// Naming model: [name] is the French/Latin primary. The English field
/// auto-copies French and is only saved if it differs. The Arabic field is the
/// Arabic-script rendering, suggested by the "Suggest Arabic" button and always
/// editable. Source-language is fixed to French here (the primary).
class CaptureDialog extends StatefulWidget {
  final String barcode;
  final CatalogEntry? existing;
  /// Prefill from a server catalog hit (scan-resolve). Used when there's no
  /// local `existing` entry. Keys: name, name_ar, name_en, category.
  final Map<String, dynamic>? prefill;
  const CaptureDialog(
      {super.key, required this.barcode, this.existing, this.prefill});

  @override
  State<CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<CaptureDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _category;
  Uint8List? _photo;
  bool _saving = false;
  bool _suggesting = false;
  final _translator = TranslationService();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // Prefer an existing local entry; else seed from a server prefill.
    final p = widget.prefill;
    final name = e?.name ?? (p?['name'] as String?) ?? '';
    final nameAr = e?.nameAr ?? (p?['name_ar'] as String?) ?? '';
    final nameEn = e?.nameEn ?? (p?['name_en'] as String?) ?? '';
    final category = e?.category ?? (p?['category'] as String?) ?? '';
    _name = TextEditingController(text: name);
    _nameAr = TextEditingController(text: nameAr);
    // English defaults to French (they're normally identical).
    _nameEn = TextEditingController(text: nameEn.isNotEmpty ? nameEn : name);
    _category = TextEditingController(text: category);
    _photo = e?.photo;
  }

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _category.dispose();
    _translator.close();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, maxWidth: 1280);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final processed = processPhoto(bytes);
    if (!mounted) return;
    if (processed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo too large — saved without it')),
      );
      return;
    }
    setState(() => _photo = processed);
  }

  /// Capture-time assist: suggest the Arabic-script rendering of the French
  /// name. Network happens here only — reads stay fully offline. Never
  /// overwrites a value the owner already typed.
  Future<void> _suggestArabic() async {
    final french = _name.text.trim();
    if (french.isEmpty) return;
    setState(() => _suggesting = true);
    final suggestion = await _translator.suggestArabic(french);
    if (!mounted) return;
    setState(() => _suggesting = false);
    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggestion unavailable — enter Arabic manually')),
      );
      return;
    }
    setState(() => _nameAr.text = suggestion.arabic);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<CatalogProvider>().save(
          barcode: widget.barcode,
          name: _name.text,
          nameAr: _nameAr.text,
          nameEn: _nameEn.text,
          category: _category.text,
          photo: _photo,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit product' : 'New product'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.barcode,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name (French) *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _nameEn,
                decoration:
                    const InputDecoration(labelText: 'Name (English)'),
              ),
              TextFormField(
                controller: _nameAr,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'Name (Arabic)',
                  suffixIcon: _suggesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.translate),
                          tooltip: 'Suggest Arabic',
                          onPressed: _suggestArabic,
                        ),
                ),
              ),
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_photo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_photo!,
                          width: 56, height: 56, fit: BoxFit.cover),
                    )
                  else
                    Container(
                      width: 56,
                      height: 56,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    tooltip: 'Take photo',
                    onPressed: () => _pickPhoto(ImageSource.camera),
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_library),
                    tooltip: 'Choose photo',
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
