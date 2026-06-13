import 'package:flutter/material.dart';
import '../../models/reader_bookmark.dart';
class BookmarkPickerResult {
  final int? selectedSlot;
  final int? deletedSlot;

  const BookmarkPickerResult._({
    this.selectedSlot,
    this.deletedSlot,
  });

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

  const BookmarkPickerDialog({super.key, 
    required this.title,
    required this.onlySaved,
    required this.bookmarks,
    required this.displayNameBuilder,
    required this.surahNameForBookmark,
    required this.onRename,
    required this.onDelete,
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

  @override
  Widget build(BuildContext context) {
    final slots = List<int>.generate(5, (index) => index + 1)
        .where((slot) => !widget.onlySaved || _bookmarks.containsKey(slot))
        .toList(growable: false);

    if (slots.isEmpty) {
      return AlertDialog(
        title: Text(widget.title, textDirection: TextDirection.rtl),
        content: const Text(
          'لا توجد علامات محفوظة حاليًا.',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      );
    }

    final editingSlot = _editingSlot;
    if (editingSlot != null) {
      return AlertDialog(
        title: Text(
          'إعادة تسمية ${widget.displayNameBuilder(editingSlot, _bookmarks[editingSlot])}',
          textDirection: TextDirection.rtl,
        ),
        content: TextField(
          controller: _renameController,
          textDirection: TextDirection.rtl,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'اسم مختصر للعلامة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSavingRename ? null : _cancelRename,
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: _isSavingRename ? null : _saveRename,
            child: Text(_isSavingRename ? 'جارٍ الحفظ...' : 'حفظ'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(widget.title, textDirection: TextDirection.rtl),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      content: SizedBox(
        width: 360,
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
                color: !isSaved 
                  ? Colors.white          // فارغة = أبيض
                  : const Color(0xFFFFF8EC),    // محفوظة = كريمي دافئ
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !isSaved
                    ? const Color(0xFFEEEEEE)
                    : const Color(0xFF8B7355),  // محفوظة = حد ذهبي
                  width: !isSaved ? 0.5 : 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
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
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: !isSaved
                              ? const Color(0xFFF0F0F0)
                              : const Color(0xFF8B7355),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            !isSaved
                              ? Icons.bookmark_outline
                              : Icons.bookmark,
                            color: !isSaved
                              ? Colors.grey
                              : Colors.white,
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
                                'العلامة $slot',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: !isSaved
                                    ? const Color(0xFF999999)
                                    : const Color(0xFF2C2C2C),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                !isSaved
                                  ? 'فارغة — اضغط للحفظ'
                                  : 'صفحة ${bookmark!.page + 1} • ${widget.surahNameForBookmark(bookmark!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: !isSaved
                                    ? const Color(0xFFBBBBBB)
                                    : const Color(0xFF8B7355),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // أزرار التعديل والحذف (فقط للمحفوظة)
                        if (isSaved) ...[
                          IconButton(
                            onPressed: () => _startRename(slot),
                            icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF8B7355), size: 24)), // Increased size
                          IconButton(
                            onPressed: isDeleting ? null : () => _deleteSlot(slot),
                            icon: isDeleting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.delete_outline,
                              color: Color(0xFFCC4444), size: 24)), // Increased size
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
    );
  }
}
