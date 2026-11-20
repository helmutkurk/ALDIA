import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/geocoder_service.dart';
import 'report_flow_widgets.dart';

/// Explicit, debounced demo geocoding; stale responses never replace new input.
class AddressSearch extends StatefulWidget {
  const AddressSearch({super.key, required this.onSelected});
  final ValueChanged<AddressResult> onSelected;
  @override
  State<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<AddressSearch> {
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
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
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
      if (_searchMessage != null) FlowNotice(_searchMessage!),
      for (final address in _addresses)
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.place_outlined),
          title: Text(address.label),
          onTap: () {
            widget.onSelected(address);
            setState(() => _addresses = const []);
            FocusScope.of(context).unfocus();
          },
        ),
    ],
  );
}
