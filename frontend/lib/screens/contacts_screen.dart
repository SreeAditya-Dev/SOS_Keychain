import 'package:dt/models/emergency_contact.dart';
import 'package:dt/services/storage_service.dart';
import 'package:dt/widgets/contact_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.storageService,
  });

  final StorageService storageService;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await widget.storageService.getContacts();
    if (mounted) {
      setState(() => _contacts = contacts);
    }
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool sendSMS = true;
    bool sendWhatsApp = true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Add Emergency Contact'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone (+91...)'),
                    ),
                    CheckboxListTile(
                      value: sendSMS,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send SMS'),
                      onChanged: (v) => setLocalState(() => sendSMS = v ?? true),
                    ),
                    CheckboxListTile(
                      value: sendWhatsApp,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send WhatsApp'),
                      onChanged: (v) => setLocalState(() => sendWhatsApp = v ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty ||
                        phoneController.text.trim().isEmpty) {
                      return;
                    }
                    final updated = [
                      ..._contacts,
                      EmergencyContact(
                        id: const Uuid().v4(),
                        name: nameController.text.trim(),
                        phone: phoneController.text.trim(),
                        sendSMS: sendSMS,
                        sendWhatsApp: sendWhatsApp,
                      ),
                    ];
                    await widget.storageService.saveContacts(updated);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    await _loadContacts();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final updated = _contacts.where((c) => c.id != contact.id).toList();
    await widget.storageService.saveContacts(updated);
    await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: _contacts.isEmpty
                ? const Center(child: Text('No contacts added yet'))
                : ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];
                      return ContactCard(
                        contact: contact,
                        onDelete: () => _deleteContact(contact),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
