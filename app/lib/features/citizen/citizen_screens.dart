import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key, required this.onOpen});
  final void Function(Report) onOpen;
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  bool _loading = false;
  bool _failed = false;
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await context.read<ReportRepository>().mine();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ReportRepository>();
    return AnimatedBuilder(
      animation: repository.local,
      builder: (context, _) {
        final notices = repository.local.notices;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AldiaSpace.l),
            children: [
              const Text(
                'Aquí aparecen los cambios de estado que Aldia detecta al actualizar tus reportes en este dispositivo. Los avisos push todavía no están disponibles.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar avisos'),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_failed)
                const Text(
                  'No se pudo actualizar. Los avisos guardados siguen disponibles.',
                ),
              if (notices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none, size: 56),
                      SizedBox(height: 16),
                      Text(
                        'Todavía no tienes avisos.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final notice in notices)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    minTileHeight: 64,
                    leading: Icon(citizenStateFor(notice.state).icon),
                    title: Text(categoryById(notice.category).label),
                    subtitle: Text(
                      '${citizenStateFor(notice.state).label}\n${notice.at.day}/${notice.at.month}/${notice.at.year} · ${S.reference(notice.reportId)}',
                    ),
                    isThreeLine: false,
                    onTap: () async {
                      try {
                        final report = await repository.get(notice.reportId);
                        if (mounted) widget.onOpen(report);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text(S.loadError)),
                          );
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onCleared});
  final VoidCallback onCleared;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _deleting = false;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar mis datos de este dispositivo?'),
        content: const Text(
          'Se borrarán borradores y sus fotos, reportes por enviar, seguimientos, avisos y la lista de tus reportes. Los reportes ya enviados seguirán siendo públicos en el servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar datos locales'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = context.read<ReportRepository>();
    final drafts = context.read<DraftStore?>();
    final outbox = context.read<OutboxService?>();
    setState(() => _deleting = true);
    try {
      // Outbox operations serialize with an in-flight send before forgetting ids.
      for (final entry in outbox?.entries ?? const <OutboxEntry>[]) {
        await outbox!.remove(entry.draft.id);
      }
      for (final draft in await drafts?.loadAll() ?? []) {
        await drafts!.delete(draft.id);
      }
      await repository.clearLocalData();
      if (!mounted) return;
      widget.onCleared();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Datos locales borrados.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron borrar todos los datos. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = context.read<ReportRepository>().local;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: AnimatedBuilder(
          animation: local,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(AldiaSpace.xl),
            children: [
              const CircleAvatar(
                radius: 40,
                child: Icon(Icons.person_outline, size: 48),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  'Tu perfil en Aldia',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 16),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.phone_outlined),
                title: Text('Número de teléfono'),
                subtitle: Text(
                  'Sin registrar. El acceso con código por teléfono estará disponible más adelante. Puedes reportar sin cuenta.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar mi nombre'),
                subtitle: const Text(
                  'Preferencia guardada en este dispositivo. No se publica ningún nombre mientras no tengas una cuenta.',
                ),
                value: local.showName,
                onChanged: (value) async {
                  try {
                    await local.setShowName(value);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(S.storageError)),
                      );
                    }
                  }
                },
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.language),
                title: Text('Idioma'),
                subtitle: Text('Español (Guatemala)'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('Versión de Aldia'),
                subtitle: Text('0.1.0+1'),
              ),
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Borrar mis datos'),
              ),
              if (_deleting) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
