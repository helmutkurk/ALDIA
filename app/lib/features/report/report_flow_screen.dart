import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/config.dart';
import '../../core/strings.dart';
import '../../core/text_x.dart';
import '../../core/theme.dart';
import '../../data/report_repository.dart';
import '../../services/location_service.dart';
import '../../services/geocoder_service.dart';
import '../../services/haptics.dart';
import '../../services/photo_service.dart';
import '../../widgets/bottom_padding.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/map_layers_button.dart';
import '../../widgets/neutral_map_pin.dart';
import '../../widgets/status_chips.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';
import 'report_flow_controller.dart';

class ReportFlowScreen extends StatelessWidget {
  const ReportFlowScreen({super.key, this.draft});
  final DraftRecord? draft;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) {
      final controller = ReportFlowController(
        repository: context.read<ReportRepository>(),
        location: context.read<LocationService>(),
        photos: context.read<PhotoService>(),
        drafts: context.read<DraftStore?>(),
        outbox: context.read<OutboxService?>(),
      );
      unawaited(controller.loadCategories());
      if (draft != null) unawaited(controller.restore(draft!));
      return controller;
    },
    child: const _FlowView(),
  );
}

class _FlowView extends StatefulWidget {
  const _FlowView();
  @override
  State<_FlowView> createState() => _FlowViewState();
}

class _FlowViewState extends State<_FlowView> with WidgetsBindingObserver {
  final _heading = FocusNode();
  ReportFlowController? _controller;
  String? _lastHeading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<ReportFlowController>()
      ..addListener(_focusHeading);
  }

  void _focusHeading() {
    final c = _controller!;
    final key = '${c.step.name}:${c.submitState.name}';
    if (_lastHeading == key) return;
    _lastHeading = key;
    switch (c.submitState) {
      case SubmitState.done:
        unawaited(
          c.result?.status == 'rejected'
              ? HapticsHelper.error()
              : HapticsHelper.success(),
        );
      case SubmitState.queued ||
          SubmitState.manualSaved ||
          SubmitState.followed:
        unawaited(HapticsHelper.success());
      case SubmitState.failed:
        unawaited(HapticsHelper.error());
      default:
        break;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _heading.requestFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.checkPhotoIntegrity());
    } else {
      unawaited(_controller?.saveDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_focusHeading);
    unawaited(_controller?.saveDraft());
    _heading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ReportFlowController>();
    _focusHeading();
    final outcome = c.submitState;
    final result =
        outcome == SubmitState.done ||
        outcome == SubmitState.queued ||
        outcome == SubmitState.manualSaved ||
        outcome == SubmitState.followed;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.newReport),
        actions: [
          IconButton(
            tooltip: 'Ayuda para reportar',
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Tu reporte, paso a paso'),
                  content: const Text(
                    'Confirma el lugar y elige una categoría. Luego toma una foto en el momento y revisa los datos antes de enviar.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(S.close),
                    ),
                  ],
                ),
              );
            },
          ),
          if (Navigator.of(context).canPop())
            IconButton(
              tooltip: S.close,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      bottomNavigationBar: result || outcome == SubmitState.sending
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.step.index > 0)
                      OutlinedButton(
                        onPressed: c.back,
                        child: const Text(S.back),
                      ),
                    FilledButton(
                      onPressed: c.canAdvance
                          ? (c.isLastStep ? c.submit : c.next)
                          : null,
                      child: Text(
                        c.isLastStep
                            ? S.send
                            : c.step == FlowStep.location
                            ? S.confirmLocation
                            : c.step == FlowStep.photo
                            ? S.usePhoto
                            : S.next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16)
                  .copyWith(bottom: BottomPadding.of(context)),
              children: [
                if (!result) ...[
                  _SummaryRow(controller: c),
                  const SizedBox(height: 16),
                  Text(
                    S.stepProgress(c.step.index + 1, FlowStep.values.length),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AldiaSpace.s),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: (c.step.index + 1) / FlowStep.values.length,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Focus(
                  focusNode: _heading,
                  child: Semantics(
                    header: true,
                    child: Text(
                      result ? _resultTitle(c) : _title(c.step),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (c.storageError) const _Notice(S.storageError),
                if (outcome == SubmitState.sending) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(S.sending),
                ] else if (result)
                  _ResultView(controller: c)
                else ...[
                  switch (c.step) {
                    FlowStep.photo => _PhotoStep(controller: c),
                    FlowStep.location => _LocationStep(controller: c),
                    FlowStep.category => _CategoryStep(controller: c),
                    FlowStep.note => _NoteStep(controller: c),
                    FlowStep.review => _ReviewStep(controller: c),
                  },
                  if (c.submitState == SubmitState.failed)
                    const _Notice(S.sendError),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _title(FlowStep step) => switch (step) {
  FlowStep.photo => S.stepPhoto,
  FlowStep.location => S.stepLocation,
  FlowStep.category => S.stepCategory,
  FlowStep.note => S.stepNote,
  FlowStep.review => S.stepReview,
};

String _resultTitle(ReportFlowController c) => switch (c.submitState) {
  SubmitState.queued => S.waitingNetwork,
  SubmitState.manualSaved => S.draft,
  SubmitState.followed => S.following,
  _ => switch (c.result?.status) {
    'verified' =>
      '${S.resultVerified}${c.result?.verification?.isStub == true ? ' (prueba)' : ''}',
    'rejected' =>
      '${S.resultRejected}${c.result?.verification?.isStub == true ? ' (prueba)' : ''}',
    _ => S.resultPending,
  },
};

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.controller});
  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final place = c.placeLabel.isUsable
        ? c.placeLabel!
        : (c.locationConfirmed
              ? '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}'
              : 'Elige el lugar del problema');
    final category = c.categories
        .where((item) => item.id == c.categoryId)
        .firstOrNull;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AldiaSpace.m),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                c.photo == null
                    ? Icons.add_a_photo_outlined
                    : Icons.photo_camera,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.step == FlowStep.location
                        ? '¿Es este el lugar correcto?'
                        : 'Tu reporte',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(place),
                  if (category != null) Text(category.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(S.photoRequired),
      if (controller.missingPhoto) const _Notice(S.missingPhoto),
      if (controller.photoError) const _Notice(S.photoError),
      if (controller.photo != null) ...[
        const SizedBox(height: 12),
        Image.memory(
          controller.photo!.bytes,
          height: 220,
          fit: BoxFit.contain,
          semanticLabel: S.photoAlternative,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image, semanticLabel: S.imageReason),
        ),
      ],
      const SizedBox(height: 12),
      if (controller.photo == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Semantics(
              button: true,
              label: 'Abrir cámara para tomar la foto',
              child: Tooltip(
                message: 'Abrir cámara',
                child: Material(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: controller.takePhoto,
                    child: SizedBox(
                      width: 176,
                      height: 176,
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: controller.takePhoto,
        icon: const Icon(Icons.camera_alt),
        label: Text(controller.photo == null ? S.takePhoto : S.retakePhoto),
      ),
    ],
  );
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.controller});
  final ReportFlowController controller;
  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final _map = MapController();
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  bool _invalid = false;
  bool _showAccuracy = true;
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _searching = false;
  String? _searchMessage;
  List<AddressResult> _addresses = const [];

  void _searchAddress() {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _search.text.trim();
    if (query.length < 3) {
      setState(
        () => _searchMessage = 'Escribe al menos tres letras de la dirección.',
      );
      return;
    }
    // Only an explicit Search/Enter triggers the demo's public geocoder.
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final geocoder = context.read<GeocoderService?>();
      setState(() {
        _searching = true;
        _searchMessage = null;
      });
      try {
        final results = await geocoder?.search(query) ?? <AddressResult>[];
        if (!mounted || generation != _generation) return;
        setState(() {
          _addresses = results;
          _searching = false;
          _searchMessage = results.isEmpty
              ? 'No encontramos esa dirección. Prueba con calle y municipio o elige el punto en el mapa.'
              : null;
        });
      } catch (_) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _searching = false;
          _searchMessage = 'No se pudo buscar la dirección. Puedes elegir el punto en el mapa.';
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(
      text: '${widget.controller.position.latitude}',
    );
    _lon = TextEditingController(
      text: '${widget.controller.position.longitude}',
    );
  }

  @override
  void didUpdateWidget(covariant _LocationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _map.move(widget.controller.position, _map.camera.zoom);
    _lat.text = '${widget.controller.position.latitude}';
    _lon.text = '${widget.controller.position.longitude}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _map.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _apply() {
    final lat = double.tryParse(_lat.text);
    final lon = double.tryParse(_lon.text);
    setState(
      () => _invalid =
          lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180,
    );
    if (!_invalid) widget.controller.setPosition(LatLng(lat!, lon!));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final issue = switch (c.locationIssue) {
      LocationIssue.denied => S.locationDenied,
      LocationIssue.deniedForever => S.locationDeniedForever,
      LocationIssue.serviceOff => S.locationServiceOff,
      LocationIssue.unavailable => S.locationUnavailable,
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Buscar dirección',
            hintText: 'Calle y municipio',
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchAddress(),
          onChanged: (_) {
            _debounce?.cancel();
            _generation++;
            setState(() {
              _addresses = const [];
              _searchMessage = null;
              _searching = false;
            });
          },
        ),
        TextButton.icon(
          onPressed: _searchAddress,
          icon: const Icon(Icons.search),
          label: const Text('Buscar dirección en el mapa'),
        ),
        if (_searching) const LinearProgressIndicator(),
        if (_searchMessage != null) _Notice(_searchMessage!),
        for (final address in _addresses)
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.place_outlined),
            title: Text(address.label.orPlaceholder()),
            onTap: () {
              c.setPosition(address.position, label: address.label);
              setState(() => _addresses = const []);
              FocusScope.of(context).unfocus();
            },
          ),
        const Text(S.locationHint),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: Semantics(
            label: S.pinAlternative,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: c.position,
                initialZoom: 16,
                onTap: (_, point) => c.setPosition(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.tileUrl,
                  tileProvider: context.read<TileProvider>(),
                  userAgentPackageName: AppConfig.userAgentPackage,
                ),
                if (_showAccuracy &&
                    c.accuracy != null &&
                    c.gpsPosition != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: c.gpsPosition!,
                        radius: c.accuracy!,
                        useRadiusInMeter: true,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .15),
                        borderColor: Theme.of(context).colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: c.position,
                      width: 48,
                      height: 48,
                      child: const NeutralMapPin(
                        size: 48,
                        child: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Card(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MapLayersButton(
                          overlay: 'Precisión del GPS',
                          visible: _showAccuracy,
                          onChanged: (value) =>
                              setState(() => _showAccuracy = value),
                        ),
                        IconButton(
                          tooltip: 'Acercar mapa',
                          onPressed: () => _map.move(
                            _map.camera.center,
                            (_map.camera.zoom + 1).clamp(3, 19),
                          ),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Alejar mapa',
                          onPressed: () => _map.move(
                            _map.camera.center,
                            (_map.camera.zoom - 1).clamp(3, 19),
                          ),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: S.useMyLocation,
                          onPressed: c.locating ? null : c.useMyLocation,
                          icon: const Icon(Icons.my_location),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Text(
          '© OpenStreetMap contributors · búsqueda y mapa',
          style: TextStyle(fontSize: 12),
        ),
        if (c.locating) const _Notice(S.locating),
        if (issue != null) _Notice(issue),
        if (c.locationIssue == LocationIssue.deniedForever)
          OutlinedButton(
            onPressed: c.openLocationSettings,
            child: const Text(S.openSettings),
          ),
        if (c.accuracy != null) Text(S.accuracy(c.accuracy!)),
        if ((c.accuracy ?? 0) > 50) const _Notice(S.poorAccuracy),
        TextButton.icon(
          onPressed: c.locating ? null : c.useMyLocation,
          icon: const Icon(Icons.my_location),
          label: const Text(S.useMyLocation),
        ),
        const Text(S.confirmPinHint),
        TextField(
          controller: _lat,
          decoration: const InputDecoration(labelText: S.latitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: _lon,
          decoration: const InputDecoration(labelText: S.longitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _apply(),
        ),
        if (_invalid) const _Notice(S.coordinatesInvalid),
        TextButton(onPressed: _apply, child: const Text(S.applyCoordinates)),
      ],
    );
  }
}

class _CategoryStep extends StatefulWidget {
  const _CategoryStep({required this.controller});
  final ReportFlowController controller;
  @override
  State<_CategoryStep> createState() => _CategoryStepState();
}

class _CategoryStepState extends State<_CategoryStep> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories
        .where((c) => c.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final groups = categories.map((c) => c.group).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(S.chooseCategory),
        const SizedBox(height: AldiaSpace.m),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar categoría',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (categories.isEmpty)
          const _Notice(
            'No encontramos esa categoría. Prueba con otra palabra.',
          ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Semantics(
              header: true,
              child: Text(
                categoryGroupLabel(group),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final category in categories.where((c) => c.group == group))
            Padding(
              padding: const EdgeInsets.only(bottom: AldiaSpace.s),
              child: _CategoryRow(
                category: category,
                selected: widget.controller.categoryId == category.id,
                onTap: () => widget.controller.setCategory(category.id),
              ),
            ),
        ],
      ],
    );
  }
}

/// Large selectable row: icon, label and a check when chosen.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final ReportCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AldiaSpace.l,
                vertical: AldiaSpace.m,
              ),
              child: Row(
                children: [
                  Icon(category.icon, size: 28, color: scheme.primary),
                  const SizedBox(width: AldiaSpace.l),
                  Expanded(
                    child: Text(
                      category.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteStep extends StatelessWidget {
  const _NoteStep({required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.photo != null)
        Image.memory(
          controller.photo!.bytes,
          height: 90,
          semanticLabel: S.photoAlternative,
          errorBuilder: (_, _, _) => const Icon(Icons.photo),
        ),
      TextFormField(
        initialValue: controller.note,
        maxLength: AppConfig.maxNoteLength,
        minLines: 3,
        maxLines: 8,
        onChanged: controller.setNote,
        decoration: const InputDecoration(
          labelText: S.noteLabel,
          hintText: S.noteHint,
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.photo != null)
          Image.memory(
            c.photo!.bytes,
            height: 180,
            semanticLabel: S.photoAlternative,
            errorBuilder: (_, _, _) => const Icon(Icons.photo),
          ),
        TextButton(
          onPressed: () => c.edit(FlowStep.photo),
          child: const Text('${S.edit}: ${S.stepPhoto}'),
        ),
        Text(
          c.placeLabel.isUsable
              ? c.placeLabel!
              : '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}',
        ),
        TextButton(
          onPressed: () => c.edit(FlowStep.location),
          child: const Text('${S.edit}: ${S.stepLocation}'),
        ),
        Text(categoryById(c.categoryId!).label),
        TextButton(
          onPressed: () => c.edit(FlowStep.category),
          child: const Text('${S.edit}: ${S.stepCategory}'),
        ),
        Text(c.note),
        TextButton(
          onPressed: () => c.edit(FlowStep.note),
          child: const Text('${S.edit}: ${S.stepNote}'),
        ),
        Text(
          S.uploadSize((c.photo?.bytes.length ?? 0) + 1024 + c.note.length * 4),
        ),
        const _Notice(S.publicPhotoNotice),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final report = c.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.submitState == SubmitState.queued)
          const _Notice(S.waitingNetworkHelp),
        if (c.submitState == SubmitState.manualSaved)
          const _Notice(S.manualSaved),
        if (report != null) ...[
          Text(S.reference(report.id)),
          StatusChips(report: report),
          if (report.status == 'pending') const _Notice(S.pendingHelp),
          if (report.status == 'rejected') ...[
            if (c.photo != null)
              Stack(
                children: [
                  Image.memory(
                    c.photo!.bytes,
                    height: 140,
                    semanticLabel: S.photoAlternative,
                    errorBuilder: (_, _, _) => const Icon(Icons.photo),
                  ),
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(Icons.error, semanticLabel: S.resultRejected),
                  ),
                ],
              ),
            if (report.verification != null)
              ChecksList(
                verification: report.verification!,
                category: categoryById(report.category).label,
              ),
            if (report.verification?.checks.any(
                  (v) => v.name == 'duplicate' && !v.passed,
                ) ==
                true)
              _DuplicateResult(controller: c),
            OutlinedButton(
              onPressed: c.retakePhoto,
              child: const Text(S.retakePhoto),
            ),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.category),
              child: const Text(S.changeCategory),
            ),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.location),
              child: const Text(S.adjustLocation),
            ),
            if (c.canManualReview)
              OutlinedButton(
                onPressed: c.saveForManualReview,
                child: const Text(S.manualReview),
              ),
          ],
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.close),
        ),
      ],
    );
  }
}

class _DuplicateResult extends StatefulWidget {
  const _DuplicateResult({required this.controller});
  final ReportFlowController controller;
  @override
  State<_DuplicateResult> createState() => _DuplicateResultState();
}

class _DuplicateResultState extends State<_DuplicateResult> {
  late final Future<List<dynamic>> _future;
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    final repo = context.read<ReportRepository>();
    _future = c.result?.duplicateOf != null
        ? repo.get(c.result!.duplicateOf!).then((r) => [r])
        : repo.duplicates(c.position, c.categoryId!);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) => Column(
      children: [
        for (final report in snapshot.data ?? [])
          Column(
            children: [
              ReportTile(
                report: report,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportDetailScreen(report: report),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => widget.controller.follow(report),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border),
                    SizedBox(width: 8),
                    Flexible(child: Text(S.followReport)),
                  ],
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
