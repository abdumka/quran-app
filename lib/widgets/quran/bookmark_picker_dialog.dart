import 'package:flutter/material.dart';
import '../../models/reader_bookmark.dart';
import '../../theme/app_surfaces.dart';

enum _ExportChoice { share, saveLocally }

class BookmarkPickerResult {
  final int? selectedSlot;
  final int? deletedSlot;

  const BookmarkPickerResult._({this.selectedSlot, this.deletedSlot});

  const BookmarkPickerResult.select(int slot) : this._(selectedSlot: slot);
  const BookmarkPickerResult.delete(int slot) : this._(deletedSlot: slot);
}

class BookmarkPickerDialog extends StatefulWidget {
  final String title;
  final bool onlySaved;
  final Map<int, ReaderBookmark> bookmarks;
  final String Function(int, ReaderBookmark?) displayNameBuilder;
  final String Function(ReaderBookmark) surahNameForBookmark;
  final Future<void> Function(int slot, String? label) onRename;
  final Future<void> Function(int slot) onDelete;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onSaveLocally;
  final Future<Map<int, ReaderBookmark>?> Function()? onImport;

  /// Highest bookmark slot number offered by the picker. Shared with the
  /// import merge logic in quran_pages.dart so imported bookmarks are never
  /// placed in a slot the picker itself would refuse to show.
  static const int maxSlots = 30;

  const BookmarkPickerDialog({
    super.key,
    required this.title,
    required this.onlySaved,
    required this.bookmarks,
    required this.displayNameBuilder,
    required this.surahNameForBookmark,
    required this.onRename,
    required this.onDelete,
    this.onExport,
    this.onSaveLocally,
    this.onImport,
  });

  @override
  State<BookmarkPickerDialog> createState() => BookmarkPickerDialogState();
}

class BookmarkPickerDialogState extends State<BookmarkPickerDialog> {
  late Map<int, ReaderBookmark> _bookmarks;
  TextEditingController? _renameController;
  int? _editingSlot;
  bool _isSavingRename = false;
  int? _deletingSlot;

  @override
  void initState() {
    super.initState();
    _bookmarks = Map<int, ReaderBookmark>.from(widget.bookmarks);
  }

  @override
  void dispose() {
    _renameController?.dispose();
    super.dispose();
  }

  void _startRename(int slot) {
    _renameController?.dispose();
    _renameController = TextEditingController(
      text: _bookmarks[slot]?.label ?? '',
    );
    setState(() {
      _editingSlot = slot;
    });
  }

  void _cancelRename() {
    _renameController?.dispose();
    _renameController = null;
    setState(() {
      _editingSlot = null;
      _isSavingRename = false;
    });
  }

  Future<void> _saveRename() async {
    final slot = _editingSlot;
    final controller = _renameController;
    if (slot == null || controller == null) return;

    final normalized = controller.text.trim();
    setState(() {
      _isSavingRename = true;
    });

    await widget.onRename(slot, normalized.isEmpty ? null : normalized);
    if (!mounted) return;

    final existing = _bookmarks[slot];
    if (existing != null) {
      _bookmarks[slot] = existing.copyWith(
        label: normalized.isEmpty ? null : normalized,
        clearLabel: normalized.isEmpty,
      );
    }

    _cancelRename();
  }

  Future<void> _deleteSlot(int slot) async {
    setState(() {
      _deletingSlot = slot;
    });
    await widget.onDelete(slot);
    if (!mounted) return;
    setState(() {
      _bookmarks.remove(slot);
      _deletingSlot = null;
    });
    // Removed Navigator.pop to keep the dialog open after deletion.
  }

  /// Up to [_maxSlots] bookmarks. The first [_baseSlots] are always offered;
  /// beyond that, only saved slots plus the next (lowest) empty slot appear,
  /// so the list grows one slot at a time as the user fills it. Gaps between
  /// saved slots beyond the lowest empty one are not shown — e.g. with 1-5
  /// and 7 and 10 saved, slot 6 is offered but 8 and 9 stay hidden.
  static const int _baseSlots = 5;

  List<int> _visibleSlots() {
    int? lowestEmpty;
    for (int slot = 1; slot <= BookmarkPickerDialog.maxSlots; slot++) {
      if (!_bookmarks.containsKey(slot)) {
        lowestEmpty = slot;
        break;
      }
    }
    final visible = <int>{
      for (int slot = 1; slot <= _baseSlots; slot++) slot,
      ..._bookmarks.keys.where(
        (slot) => slot >= 1 && slot <= BookmarkPickerDialog.maxSlots,
      ),
      ?lowestEmpty,
    }.toList()..sort();
    return visible;
  }

  bool get _showBackupActions =>
      widget.onlySaved &&
      (widget.onExport != null ||
          widget.onSaveLocally != null ||
          widget.onImport != null);

  Future<void> _handleExport() async {
    final onExport = widget.onExport;
    if (onExport == null) return;
    await onExport();
  }

  Future<void> _handleSaveLocally() async {
    final onSaveLocally = widget.onSaveLocally;
    if (onSaveLocally == null) return;
    await onSaveLocally();
  }

  Future<void> _handleImport() async {
    final onImport = widget.onImport;
    if (onImport == null) return;
    final merged = await onImport();
    if (!mounted || merged == null) return;
    setState(() {
      _bookmarks = merged;
    });
  }

  Widget _buildBackupActions() {
    final s = AppSurfaces.maybeOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onImport != null)
          IconButton(
            tooltip: 'استيراد من ملف',
            visualDensity: VisualDensity.compact,
            onPressed: _handleImport,
            icon: Icon(
              Icons.folder_open_outlined,
              color: s?.icon ?? const Color(0xFF8B7355),
              size: 20,
            ),
          ),
        if (widget.onExport != null || widget.onSaveLocally != null)
          PopupMenuButton<_ExportChoice>(
            tooltip: 'مشاركة نسخة احتياطية',
            color: s?.card,
            icon: Icon(
              Icons.ios_share,
              color: s?.icon ?? const Color(0xFF8B7355),
              size: 20,
            ),
            onSelected: (choice) {
              switch (choice) {
                case _ExportChoice.share:
                  _handleExport();
                  break;
                case _ExportChoice.saveLocally:
                  _handleSaveLocally();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (widget.onExport != null)
                const PopupMenuItem(
                  value: _ExportChoice.share,
                  child: Text('مشاركة', textDirection: TextDirection.rtl),
                ),
              if (widget.onSaveLocally != null)
                const PopupMenuItem(
                  value: _ExportChoice.saveLocally,
                  child: Text(
                    'حفظ على الجهاز',
                    textDirection: TextDirection.rtl,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = _visibleSlots()
        .where((slot) => !widget.onlySaved || _bookmarks.containsKey(slot))
        .toList(growable: false);

    // null in the previous look and in night mode: the theme's dialog and the
    // old card colours stay
    final s = AppSurfaces.maybeOf(context);
    final dialogShape = s == null
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSurfaces.radius),
          );
    final titleStyle = s == null
        ? null
        : Theme.of(context).textTheme.headlineSmall?.copyWith(color: s.text);
    final textButtonStyle = s == null
        ? null
        : TextButton.styleFrom(foregroundColor: s.accent);

    if (slots.isEmpty) {
      return AlertDialog(
        backgroundColor: s?.sheet,
        shape: dialogShape,
        titleTextStyle: titleStyle,
        title: _showBackupActions
            ? Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(widget.title, textDirection: TextDirection.rtl),
                  ),
                  _buildBackupActions(),
                ],
              )
            : Text(widget.title, textDirection: TextDirection.rtl),
        content: Text(
          'لا توجد علامات محفوظة حاليًا.',
          textDirection: TextDirection.rtl,
          style: s == null ? null : TextStyle(color: s.muted),
        ),
        actions: [
          TextButton(
            style: textButtonStyle,
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      );
    }

    final editingSlot = _editingSlot;
    if (editingSlot != null) {
      return AlertDialog(
        backgroundColor: s?.sheet,
        shape: dialogShape,
        titleTextStyle: titleStyle,
        title: Text(
          'إعادة تسمية ${widget.displayNameBuilder(editingSlot, _bookmarks[editingSlot])}',
          textDirection: TextDirection.rtl,
        ),
        content: TextField(
          controller: _renameController,
          textDirection: TextDirection.rtl,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'اسم مختصر للعلامة'),
        ),
        actions: [
          TextButton(
            style: textButtonStyle,
            onPressed: _isSavingRename ? null : _cancelRename,
            child: const Text('إلغاء'),
          ),
          TextButton(
            style: textButtonStyle,
            onPressed: _isSavingRename ? null : _saveRename,
            child: Text(_isSavingRename ? 'جارٍ الحفظ...' : 'حفظ'),
          ),
        ],
      );
    }

    final cardRadius = s == null ? 14.0 : AppSurfaces.cardRadius;
    return AlertDialog(
      backgroundColor: s?.sheet,
      shape: dialogShape,
      titleTextStyle: titleStyle,
      title: _showBackupActions
          ? Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(widget.title, textDirection: TextDirection.rtl),
                ),
                _buildBackupActions(),
              ],
            )
          : Text(widget.title, textDirection: TextDirection.rtl),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          // Keep the dialog compact; with many slots the list scrolls.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: slots.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final slot = slots[index];
              final bookmark = _bookmarks[slot];
              final isSaved = bookmark != null;
              final isDeleting = _deletingSlot == slot;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  // the new look: every slot is a card with a hairline
                  color: s?.card ??
                      (!isSaved
                          ? Colors
                                .white // فارغة = أبيض
                          : const Color(0xFFFFF8EC)), // محفوظة = كريمي دافئ
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: s?.border ??
                        (!isSaved
                            ? const Color(0xFFEEEEEE)
                            : const Color(0xFF8B7355)), // محفوظة = حد ذهبي
                    width: s != null ? 1.0 : (!isSaved ? 0.5 : 1.0),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(cardRadius),
                    onTap: () => Navigator.pop(
                      context,
                      BookmarkPickerResult.select(slot),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          // أيقونة العلامة
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: !isSaved
                                  ? s?.buttonQuiet ?? const Color(0xFFF0F0F0)
                                  : s?.tile ?? const Color(0xFF8B7355),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              !isSaved
                                  ? Icons.bookmark_outline
                                  : Icons.bookmark,
                              color: !isSaved
                                  ? s?.muted ?? Colors.grey
                                  : s?.accent ?? Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // المعلومات
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              textDirection: TextDirection.rtl,
                              children: [
                                Text(
                                  // Saved slots show their custom name (falls
                                  // back to "العلامة N" when unnamed).
                                  isSaved
                                      ? widget.displayNameBuilder(
                                          slot,
                                          bookmark,
                                        )
                                      : 'العلامة $slot',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: s == null
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: !isSaved
                                        ? s?.muted ?? const Color(0xFF999999)
                                        : s?.text ?? const Color(0xFF2C2C2C),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  !isSaved
                                      ? 'فارغة — اضغط للحفظ'
                                      : 'صفحة ${bookmark.page + 1} • ${widget.surahNameForBookmark(bookmark)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: !isSaved
                                        ? s?.muted ?? const Color(0xFFBBBBBB)
                                        : s?.muted ?? const Color(0xFF8B7355),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // أزرار التعديل والحذف (فقط للمحفوظة)
                          if (isSaved) ...[
                            IconButton(
                              onPressed: () => _startRename(slot),
                              icon: Icon(
                                Icons.edit_outlined,
                                color: s?.muted ?? const Color(0xFF8B7355),
                                size: 24,
                              ),
                            ), // Increased size
                            IconButton(
                              onPressed: isDeleting
                                  ? null
                                  : () => _deleteSlot(slot),
                              icon: isDeleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      Icons.delete_outline,
                                      color: s?.muted ?? const Color(0xFFCC4444),
                                      size: 24,
                                    ),
                            ), // Increased size
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
