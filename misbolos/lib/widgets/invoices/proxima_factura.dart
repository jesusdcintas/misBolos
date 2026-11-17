import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../models/invoice.dart';
import '../../models/invoice_counter.dart';
import '../../providers/invoice_provider.dart';

/// El número que le tocará a la siguiente factura del año, con un atajo para
/// cambiarlo.
///
/// Se usa igual en Ajustes y encima de la lista de Facturas.
class ProximaFacturaLinea extends ConsumerWidget {
  final int year;

  const ProximaFacturaLinea({super.key, required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final proximo = ref.watch(nextInvoiceNumberProvider(year));

    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Próxima factura: '),
                TextSpan(
                  text: proximo.when(
                    data: (numero) => numeroVisualFactura(
                      serie: serieDeFactura(InvoiceType.normal),
                      year: year,
                      numero: numero,
                    ),
                    loading: () => '…',
                    error: (_, __) => '—',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => mostrarDialogoProximaFactura(context, ref, year),
          child: const Text('Cambiar'),
        ),
      ],
    );
  }
}

/// Pregunta el número de la siguiente factura y lo fija.
Future<void> mostrarDialogoProximaFactura(
  BuildContext context,
  WidgetRef ref,
  int year,
) async {
  Hapticos.toque();
  final actual = ref.read(nextInvoiceNumberProvider(year)).valueOrNull;
  final controlador = TextEditingController(text: actual?.toString() ?? '');
  final messenger = ScaffoldMessenger.of(context);

  final numero = await showDialog<int>(
    context: context,
    builder: (ctx) =>
        _DialogoProximaFactura(year: year, controlador: controlador),
  );
  if (numero == null) return;

  try {
    await ref
        .read(invoicesProvider.notifier)
        .fijarProximoNumero(year: year, numero: numero);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'La siguiente factura será la '
          '${numeroVisualFactura(serie: serieDeFactura(InvoiceType.normal), year: year, numero: numero)}',
        ),
      ),
    );
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _DialogoProximaFactura extends StatefulWidget {
  final int year;
  final TextEditingController controlador;

  const _DialogoProximaFactura({required this.year, required this.controlador});

  @override
  State<_DialogoProximaFactura> createState() => _DialogoProximaFacturaState();
}

class _DialogoProximaFacturaState extends State<_DialogoProximaFactura> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Número de la siguiente factura de ${widget.year}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No puede ser igual ni menor que el de una factura que ya exista '
            'de este año: la numeración no puede repetirse ni retroceder.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controlador,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Número',
              prefixText:
                  '${serieDeFactura(InvoiceType.normal)}-${widget.year}-',
              errorText: _error,
            ),
            onSubmitted: (_) => _aceptar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _aceptar, child: const Text('Guardar')),
      ],
    );
  }

  void _aceptar() {
    final numero = int.tryParse(widget.controlador.text.trim());
    if (numero == null || numero <= 0) {
      setState(() => _error = 'Escribe un número mayor que cero.');
      return;
    }
    Navigator.pop(context, numero);
  }
}
