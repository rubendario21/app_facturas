import 'package:flutter/material.dart';

import '../data/invoice_repository.dart';
import '../data/issuer_repository.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'business_picker_screen.dart';
import 'home_screen.dart';

/// Inicio de sesión en el servidor. Si el servidor aún no tiene usuarios,
/// se configura el negocio y su administrador.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Aviso opcional (p. ej. "tu sesión ha caducado").
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _business = TextEditingController();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  /// El servidor no tiene administrador: se muestra el alta del negocio.
  bool _setupMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  AuthService get _auth => AuthService.instance;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    final s = _auth.session;
    if (s != null) {
      _server.text = s.serverUrl;
      _user.text = s.user.username;
    } else {
      _auth.store.lastServerUrl().then((url) {
        if (mounted && _server.text.isEmpty) {
          _server.text = url ?? ApiClient.defaultServerUrl;
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_server, _business, _name, _user, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_setupMode) {
        await _auth.setup(
            _server.text, _business.text, _name.text, _user.text, _pass.text);
      } else {
        if (await _auth.needsSetup(_server.text)) {
          setState(() {
            _setupMode = true;
            _busy = false;
            _error = null;
          });
          return;
        }
        await _auth.login(_server.text, _user.text, _pass.text);
      }
      await _offerLocalData();
      if (!mounted) return;
      final several = _auth.session?.hasSeveralBusinesses ?? false;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => several
              ? const BusinessPickerScreen(afterLogin: true)
              : const HomeScreen()));
    } on NetworkException catch (e) {
      _fail('${e.message}\nComprueba la dirección del servidor y tu conexión.');
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  /// Facturas creadas en este dispositivo antes de usar el servidor:
  /// se ofrece subirlas (conservando sus números) o descartarlas.
  Future<void> _offerLocalData() async {
    final invoices = InvoiceRepository();
    final count = await invoices.countLocalOnly();
    if (count == 0 || !mounted) return;
    final upload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Datos de este dispositivo'),
        content: Text(
          'Este dispositivo tiene $count factura(s) creadas antes de conectarse '
          'al servidor. ¿Quieres subirlas para que las vea todo el equipo?\n\n'
          'Se conservan sus números y pagos siempre que no estén ya usados.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Descartarlas')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Subirlas')),
        ],
      ),
    );
    if (upload == true) {
      if (_auth.isAdmin) await IssuerRepository().enqueueAll();
      await invoices.enqueueLocalOnly();
    } else {
      await invoices.discardLocalOnly();
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.receipt_long,
                        size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Facturas',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      _setupMode
                          ? 'El servidor está vacío. Configura tu negocio y crea la cuenta de administrador.'
                          : 'Inicia sesión con tu usuario del equipo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _server,
                      enabled: !_setupMode,
                      decoration: const InputDecoration(
                        labelText: 'Servidor',
                        hintText: ApiClient.defaultServerUrl,
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      validator: _required,
                    ),
                    if (_setupMode) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _business,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del negocio',
                          prefixIcon: Icon(Icons.business),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Tu nombre',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _user,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Introduce el usuario';
                        }
                        if (_setupMode &&
                            !RegExp(r'^[A-Za-z0-9._-]{3,60}$')
                                .hasMatch(v.trim())) {
                          return 'Entre 3 y 60 caracteres: letras, números, punto o guion';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pass,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      textInputAction: _setupMode
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: _setupMode ? null : (_) => _submit(),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Introduce la contraseña';
                        }
                        if (_setupMode && v.length < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    if (_setupMode) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pass2,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                          labelText: 'Repite la contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v != _pass.text
                            ? 'Las contraseñas no coinciden'
                            : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              _setupMode ? 'Crear negocio y entrar' : 'Entrar'),
                    ),
                    if (_setupMode)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _setupMode = false;
                                  _error = null;
                                }),
                        child: const Text('Cambiar de servidor'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
