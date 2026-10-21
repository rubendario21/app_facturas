import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/issuer_repository.dart';
import '../models/issuer.dart';
import '../services/auth_service.dart';
import '../utils/format.dart';

class IssuerSettingsScreen extends StatefulWidget {
  const IssuerSettingsScreen({super.key});

  @override
  State<IssuerSettingsScreen> createState() => _IssuerSettingsScreenState();
}

class _IssuerSettingsScreenState extends State<IssuerSettingsScreen> {
  final _repo = IssuerRepository();
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _taxId = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _bank = TextEditingController();
  final _prefix = TextEditingController();
  final _nextNumber = TextEditingController();
  final _taxRate = TextEditingController();
  final _currency = TextEditingController();

  Uint8List? _logo;
  bool _loading = true;

  static const _maxLogoBytes = 1024 * 1024;

  List<TextEditingController> get _all => [
        _name,
        _taxId,
        _address,
        _city,
        _phone,
        _email,
        _bank,
        _prefix,
        _nextNumber,
        _taxRate,
        _currency,
      ];

  @override
  void initState() {
    super.initState();
    _repo.get().then((i) {
      if (!mounted) return;
      _name.text = i.name;
      _taxId.text = i.taxId;
      _address.text = i.address;
      _city.text = i.city;
      _phone.text = i.phone;
      _email.text = i.email;
      _bank.text = i.bankAccount;
      _prefix.text = i.invoicePrefix;
      _nextNumber.text = i.nextNumber.toString();
      _taxRate.text = fmtQty(i.defaultTaxRate);
      _currency.text = i.currency;
      setState(() {
        _logo = i.logo;
        _loading = false;
      });
    });
  }

  Future<void> _pickLogo() async {
    // Solo PNG y JPG: son los formatos que admite el generador de PDF.
    final file = await FilePicker.pickFile(
      dialogTitle: 'Elegir logo',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxLogoBytes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El logo es demasiado grande (máximo 1 MB).')));
      return;
    }
    setState(() => _logo = bytes);
  }

  bool get _canEdit => AuthService.instance.isAdmin;

  Widget _logoSection() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _logo == null
              ? Icon(Icons.image_outlined, size: 40, color: scheme.outline)
              : Image.memory(_logo!, fit: BoxFit.contain),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _canEdit ? _pickLogo : null,
                icon: const Icon(Icons.upload),
                label: Text(_logo == null ? 'Elegir logo' : 'Cambiar logo'),
              ),
              if (_logo != null && _canEdit)
                TextButton.icon(
                  onPressed: () => setState(() => _logo = null),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar'),
                ),
              Text('PNG o JPG, máx. 1 MB. Aparece en el PDF.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _repo.save(Issuer(
      name: _name.text.trim(),
      taxId: _taxId.text.trim(),
      address: _address.text.trim(),
      city: _city.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      bankAccount: _bank.text.trim(),
      invoicePrefix: _prefix.text.trim(),
      nextNumber: int.parse(_nextNumber.text.trim()),
      defaultTaxRate: parseNum(_taxRate.text)!,
      currency: _currency.text.trim(),
      logo: _logo,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Datos del emisor guardados. Se enviarán al servidor.')));
    Navigator.of(context).pop(true);
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  Widget _field(TextEditingController c, String label,
      {String? Function(String?)? validator,
      TextInputType? keyboard,
      int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        readOnly: !_canEdit,
        decoration: InputDecoration(labelText: label),
        validator: validator,
        keyboardType: keyboard,
        maxLines: maxLines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos del emisor'),
        actions: [
          if (_canEdit)
            IconButton(
                tooltip: 'Guardar',
                icon: const Icon(Icons.save),
                onPressed: _loading ? null : _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_canEdit)
                    const Card(
                      margin: EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Solo lectura'),
                        subtitle: Text(
                            'Los datos del emisor los modifica un administrador.'),
                      ),
                    ),
                  Text('Logo', style: titleStyle),
                  const SizedBox(height: 12),
                  _logoSection(),
                  const SizedBox(height: 24),
                  Text('Empresa / autónomo', style: titleStyle),
                  const SizedBox(height: 12),
                  _field(_name, 'Nombre o razón social *',
                      validator: _required),
                  _field(_taxId, 'Identificación fiscal (NIF/CIF/RFC) *',
                      validator: _required),
                  _field(_address, 'Dirección', maxLines: 2),
                  _field(_city, 'Código postal y ciudad'),
                  _field(_phone, 'Teléfono', keyboard: TextInputType.phone),
                  _field(_email, 'Email', keyboard: TextInputType.emailAddress),
                  _field(_bank, 'Cuenta bancaria / IBAN (aparece en el PDF)'),
                  const SizedBox(height: 12),
                  Text('Facturación', style: titleStyle),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _field(_prefix, 'Prefijo de serie')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          _nextNumber,
                          'Próximo número',
                          keyboard: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            return (n == null || n < 1)
                                ? 'Número no válido'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          _taxRate,
                          'IVA por defecto (%)',
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            final n = parseNum(v ?? '');
                            return (n == null || n < 0)
                                ? 'Valor no válido'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _field(_currency, 'Moneda (símbolo)',
                              validator: _required)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_canEdit)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar'),
                    ),
                ],
              ),
            ),
    );
  }
}
