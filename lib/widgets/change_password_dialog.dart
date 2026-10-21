import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Cambio de la propia contraseña (requiere conexión).
Future<void> showChangePasswordDialog(BuildContext context) => showDialog<void>(
    context: context, builder: (_) => const _ChangePasswordDialog());

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(_current.text, _new.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Contraseña cambiada. Se cerró la sesión en tus otros dispositivos.')));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => (v == null || v.isEmpty) ? 'Obligatoria' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Repite la nueva contraseña'),
              validator: (v) => v != _new.text ? 'No coinciden' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Cambiar')),
      ],
    );
  }
}
