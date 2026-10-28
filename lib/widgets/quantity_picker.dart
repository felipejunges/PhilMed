import 'package:flutter/material.dart';

import '../models.dart';

/// Converte textos como "1/2", "1 1/2", "0,5" ou "2" em número.
double? parseQuantity(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final d = int.parse(mixed[3]!);
    if (d == 0) return null;
    return int.parse(mixed[1]!) + int.parse(mixed[2]!) / d;
  }
  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (frac != null) {
    final d = int.parse(frac[2]!);
    if (d == 0) return null;
    return int.parse(frac[1]!) / d;
  }
  return double.tryParse(t);
}

const _presets = <double>[1 / 4, 1 / 3, 1 / 2, 2 / 3, 3 / 4, 1, 1.5, 2];

/// Seleção da quantidade/proporção tomada: chips com frações comuns e um
/// campo livre (aceita "1/2", "1 1/2", "0,5"...).
class QuantityPicker extends StatefulWidget {
  const QuantityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.unit,
    this.reference,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// Unidade exibida ("comprimido").
  final String? unit;

  /// Dose prevista; quando informada, os chips são proporções dela
  /// (inteira, 1/2, 1/3...) em vez de quantidades absolutas.
  final double? reference;

  @override
  State<QuantityPicker> createState() => _QuantityPickerState();
}

class _QuantityPickerState extends State<QuantityPicker> {
  late final TextEditingController _ctrl =
      TextEditingController(text: formatQuantity(widget.value));

  @override
  void didUpdateWidget(covariant QuantityPicker old) {
    super.didUpdateWidget(old);
    if ((parseQuantity(_ctrl.text) ?? -1) != widget.value) {
      _ctrl.text = formatQuantity(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _same(double a, double b) => (a - b).abs() < 0.0001;

  @override
  Widget build(BuildContext context) {
    final ref = widget.reference;
    final chips = <(String, double)>[];
    if (ref != null && ref > 0) {
      chips.add(('Inteira', ref));
      for (final (n, d) in const [(1, 2), (1, 3), (1, 4), (3, 4), (2, 3)]) {
        chips.add(('$n/$d', ref * n / d));
      }
      chips.add(('Dobro', ref * 2));
    } else {
      for (final q in _presets) {
        chips.add((formatQuantity(q), q));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (label, q) in chips)
              ChoiceChip(
                label: Text(label),
                selected: _same(q, widget.value),
                onSelected: (_) {
                  _ctrl.text = formatQuantity(q);
                  widget.onChanged(q);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantidade',
            helperText: 'Aceita frações: 1/2, 1 1/2, 0,25...',
            suffixText: widget.unit,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (t) {
            final q = parseQuantity(t);
            if (q != null && q > 0) widget.onChanged(q);
          },
        ),
      ],
    );
  }
}
