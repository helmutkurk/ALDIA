import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/citizen_auth_service.dart';
import '../../services/identity_services.dart';

Future<bool> showCitizenLogin(BuildContext context, AuthService auth) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CitizenLoginSheet(auth: auth),
    ) ??
    false;

/// Phone/code input is transient and disposed when the sheet closes.
class CitizenLoginSheet extends StatefulWidget {
  const CitizenLoginSheet({super.key, required this.auth});
  final AuthService auth;
  @override
  State<CitizenLoginSheet> createState() => _CitizenLoginSheetState();
}

class _CitizenLoginSheetState extends State<CitizenLoginSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _alias = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _aliasPublic = false;
  int _seconds = 0;
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _alias.dispose();
    super.dispose();
  }

  void _cooldown() {
    _timer?.cancel();
    _seconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds == 0) timer.cancel();
    });
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = normalizeCitizenPhone(_phone.text);
      await widget.auth.requestCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code.clear();
        _cooldown();
      });
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo solicitar el código. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyCode(
        phone: normalizeCitizenPhone(_phone.text),
        code: _code.text.trim(),
        alias: _alias.text,
        aliasPublic: _aliasPublic,
      );
      if (!widget.auth.isSignedIn) {
        throw const CitizenAuthException(
          'No se pudo verificar el número. Inténtalo de nuevo.',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on CitizenAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo verificar el número. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Para recibir avisos de tu reporte verifica tu número',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tu número no será público. El acceso dura 90 días en este dispositivo. Los avisos se consultan en Aldia; las notificaciones push aún no están disponibles.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('citizen-phone'),
            controller: _phone,
            enabled: !_busy && !_sent,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              labelText: 'Número de teléfono',
              prefixText: '+502 ',
              helperText: 'Guatemala · 8 dígitos',
            ),
          ),
          if (_sent) ...[
            const SizedBox(height: 16),
            const Text(
              'Si la solicitud fue aceptada, podrás usar el código de 6 dígitos. Vence en 10 minutos.',
            ),
            TextField(
              key: const Key('citizen-code'),
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Código de verificación',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _alias,
              enabled: !_busy,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Nombre para mostrar (opcional)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar mi nombre en reportes nuevos'),
              subtitle: const Text('Solo se publicará si activas esta opción.'),
              value: _aliasPublic,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _aliasPublic = value),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: _busy ? null : (_sent ? _verify : _request),
            child: Text(_sent ? 'Verificar número' : 'Solicitar código'),
          ),
          if (_sent) ...[
            TextButton(
              onPressed: _busy || _seconds > 0 ? null : _request,
              child: Text(
                _seconds > 0 ? 'Reenviar en $_seconds s' : 'Reenviar código',
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _timer?.cancel();
                      setState(() {
                        _sent = false;
                        _error = null;
                        _code.clear();
                      });
                    },
              child: const Text('Cambiar número'),
            ),
          ],
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    ),
  );
}
