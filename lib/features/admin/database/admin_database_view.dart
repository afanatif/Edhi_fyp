import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/firestore_service.dart';

class AdminDatabaseView extends StatefulWidget {
  const AdminDatabaseView({super.key});
  @override
  State<AdminDatabaseView> createState() => _AdminDatabaseViewState();
}

class _AdminDatabaseViewState extends State<AdminDatabaseView> {
  String _collection = 'users';
  String _search = '';
  final _lookup = TextEditingController();
  late Stream<Map<String, Map<String, dynamic>>> _records;
  @override
  void initState() {
    super.initState();
    _records = context.read<FirestoreService>().watchAdminRecords(_collection);
  }

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _edit(String? id, Map<String, dynamic> data) async {
    final service = context.read<FirestoreService>();
    final collection = _collection;
    final idController = TextEditingController(text: id ?? '');
    final body = TextEditingController(
      text: FirestoreService.adminRecordJson(data),
    );
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text('${id == null ? 'Add' : 'Edit'} $collection'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: idController,
                    readOnly: id != null,
                    decoration: const InputDecoration(labelText: 'Document ID'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'JSON fields retain Firestore types using __type tags. Saving replaces this document. User profiles do not create Firebase Auth accounts.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: body,
                    minLines: 12,
                    maxLines: 22,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Document fields (JSON)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      refresh(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await service.saveAdminRecord(
                          collection,
                          idController.text.trim(),
                          body.text,
                          create: id == null,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          refresh(() {
                            error = '$e';
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save document'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog's closing animation releases its fields.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    idController.dispose();
    body.dispose();
  }

  Future<void> _delete(String id) async {
    final service = context.read<FirestoreService>();
    final collection = _collection;
    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Delete database record?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Permanently delete $collection/$id. Type the document ID to confirm. Deleting a profile does not delete its Firebase Auth account.',
              ),
              TextField(
                controller: confirmation,
                onChanged: (_) => refresh(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep record'),
            ),
            FilledButton(
              onPressed: confirmation.text == id
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await service.deleteAdminRecord(collection, id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    confirmation.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Database management',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Browse live records, inspect every field, add, edit, and delete. Audit history is read-only. The list shows the first 200 IDs; exact lookup can open any record.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _collection,
              decoration: const InputDecoration(
                labelText: 'Collection',
                border: OutlineInputBorder(),
              ),
              items: FirestoreService.adminCollections
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _collection = value;
                    _search = '';
                    _lookup.clear();
                    _records = context
                        .read<FirestoreService>()
                        .watchAdminRecords(value);
                  });
                }
              },
            ),
          ),
          SizedBox(
            width: 250,
            child: TextField(
              controller: _lookup,
              decoration: const InputDecoration(labelText: 'Exact document ID'),
              onSubmitted: (_) => _openExact(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _openExact,
            icon: const Icon(Icons.search),
            label: const Text('Open ID'),
          ),
          if (_collection != 'audit_events')
            FilledButton.icon(
              onPressed: () => _edit(null, {}),
              icon: const Icon(Icons.add),
              label: const Text('Add document'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: ValueKey(_collection),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.filter_list),
          labelText: 'Filter loaded records by ID or field value',
        ),
        onChanged: (value) => setState(() => _search = value.toLowerCase()),
      ),
      const SizedBox(height: 12),
      StreamBuilder<Map<String, Map<String, dynamic>>>(
        stream: _records,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'Database access failed: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!.entries
              .where(
                (entry) =>
                    _search.isEmpty ||
                    entry.key.toLowerCase().contains(_search) ||
                    FirestoreService.adminRecordJson(
                      entry.value,
                    ).toLowerCase().contains(_search),
              )
              .toList();
          if (entries.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching records.'),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: ExpansionTile(
                  title: Text(entry.key),
                  subtitle: Text('${entry.value.length} fields'),
                  trailing: _collection == 'audit_events'
                      ? const Icon(Icons.lock_outline)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit document',
                              onPressed: () => _edit(entry.key, entry.value),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete document',
                              onPressed: () => _delete(entry.key),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          FirestoreService.adminRecordJson(entry.value),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ],
  );

  Future<void> _openExact() async {
    if (_lookup.text.trim().isEmpty) {
      return;
    }
    try {
      final id = _lookup.text.trim();
      final data = await context.read<FirestoreService>().getAdminRecord(
        _collection,
        id,
      );
      if (!mounted) {
        return;
      }
      if (data == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Document not found.')));
        return;
      }
      if (_collection == 'audit_events') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(id),
            content: SingleChildScrollView(
              child: SelectableText(FirestoreService.adminRecordJson(data)),
            ),
          ),
        );
      } else {
        await _edit(id, data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
