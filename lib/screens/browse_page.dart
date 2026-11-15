import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../theme.dart';
import 'capture_dialog.dart';

/// Browse + search the server catalog (the OFF-derived Moroccan namespace).
/// Read-only over the network; tapping a row opens the capture form prefilled
/// so the owner can author/edit it as an owner override. Degrades gracefully
/// when the server is unreachable (shows an error, no crash).
class BrowsePage extends StatefulWidget {
  final bool localOnly;
  final void Function(Map<String, dynamic>)? onSelect;
  const BrowsePage({super.key, this.localOnly = false, this.onSelect});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<dynamic> _products = [];
  int _total = 0;
  int _offset = 0;
  static const _pageSize = 50;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onQueryChanged);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(reset: true);
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _products = [];
      setState(() => _loading = true);
    }
    final provider = context.read<CatalogProvider>();
    final result = widget.localOnly
        ? await provider.browseLocal(
            q: _search.text.trim(),
            limit: _pageSize,
            offset: _offset,
          )
        : await provider.browseServer(
            q: _search.text.trim(),
            limit: _pageSize,
            offset: _offset,
          );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _error = 'Cannot reach the catalog server.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _total = (result['total'] as num?)?.toInt() ?? 0;
      final page = (result['products'] as List?) ?? [];
      if (reset) {
        _products = page;
      } else {
        _products = [..._products, ...page];
      }
      _offset += page.length;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_products.length >= _total) return;
    setState(() => _loadingMore = true);
    await _load(reset: false);
    if (!mounted) return;
    setState(() => _loadingMore = false);
  }

  Future<void> _openProduct(dynamic p) async {
    final map = p as Map<String, dynamic>;
    if (widget.onSelect != null) {
      widget.onSelect!(map);
      if (mounted) Navigator.of(context).pop(map);
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => CaptureDialog(
        barcode: map['barcode'] as String,
        prefill: map,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse catalog')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name or brand',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _search.clear(),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  _total > 0 ? '$_total products' : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading && _products.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _products.isEmpty
                        ? const Center(child: Text('No products.'))
                        : RefreshIndicator(
                            onRefresh: () => _load(reset: true),
                            child: ListView.separated(
                              controller: _scroll,
                              itemCount:
                                  _products.length + (_loadingMore ? 1 : 0),
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                if (i >= _products.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  );
                                }
                                final p =
                                    _products[i] as Map<String, dynamic>;
                                final name =
                                    (p['name'] as String?) ?? '';
                                final brand = p['brand'] as String?;
                                final cat = p['category'] as String?;
                                final origin = p['origin'] as String?;
                                final isOwner = origin == 'owner';
                                return ListTile(
                                  leading: _Thumb(
                                    url: p['image_url'] as String?,
                                    photoBase64: p['photo_base64'] as String?,
                                  ),
                                  title: Text(name.isEmpty ? '(no name)' : name),
                                  subtitle: Text([
                                    if (brand != null && brand.isNotEmpty)
                                      brand,
                                    if (cat != null && cat.isNotEmpty) cat,
                                    if (isOwner) 'yours',
                                  ].join('  •  ')),
                                  trailing: isOwner
                                      ? Icon(Icons.check_circle,
                                          size: 18, color: Theme.of(context).extension<AppColors>()!.success)
                                      : null,
                                  onTap: () => _openProduct(p),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Branded market glyph used as the no-image placeholder in catalog rows.
/// (Brand teal from the active [ThemeData.colorScheme.secondary].)
class _ProductGlyph extends StatelessWidget {
  const _ProductGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.store, color: Colors.white, size: 20),
    );
  }
}

/// Small thumbnail with a graceful placeholder.
///
/// Precedence: local catalog photo (`Image.memory`) → server/off-network
/// `image_url` (`Image.network`) → branded glyph.
class _Thumb extends StatelessWidget {
  final String? url;
  final String? photoBase64;
  const _Thumb({this.url, this.photoBase64});

  @override
  Widget build(BuildContext context) {
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          base64Decode(photoBase64!),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const _ProductGlyph(),
        ),
      );
    }
    if (url == null || url!.isEmpty) {
      return const _ProductGlyph();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const _ProductGlyph(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: 44,
            height: 44,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }
}
