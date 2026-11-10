import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/fechas_libres.dart';
import '../../core/utils/texto_fechas_libres.dart';
import '../../providers/gig_provider.dart';
import '../../widgets/calendar/mini_calendario_mes.dart';

/// Clave del último patrón de días de la semana. Solo local, no se sincroniza.
const String fechasLibresDiasSemanaKey = 'fechas_libres_dias_semana';

/// Patrón rápido de días de la semana.
class _PatronRapido {
  final String etiqueta;
  final Set<int> dias;

  const _PatronRapido(this.etiqueta, this.dias);
}

const _patrones = [
  _PatronRapido('Jue a dom', {
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  }),
  _PatronRapido('Vie a dom', {
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  }),
  _PatronRapido('Vie y sáb', {DateTime.friday, DateTime.saturday}),
];

const _inicialesSemana = [
  (DateTime.monday, 'L'),
  (DateTime.tuesday, 'M'),
  (DateTime.wednesday, 'X'),
  (DateTime.thursday, 'J'),
  (DateTime.friday, 'V'),
  (DateTime.saturday, 'S'),
  (DateTime.sunday, 'D'),
];

/// Genera el texto con las fechas libres de un mes.
class FechasLibresScreen extends ConsumerStatefulWidget {
  /// Mes con el que abrir, normalmente el que se ve en la Agenda. Un mes ya
  /// pasado abre el mes actual.
  final DateTime? mes;

  const FechasLibresScreen({super.key, this.mes});

  @override
  ConsumerState<FechasLibresScreen> createState() => _FechasLibresScreenState();
}

class _FechasLibresScreenState extends ConsumerState<FechasLibresScreen> {
  late DateTime _mes;
  Set<int> _diasSemana = {DateTime.friday, DateTime.saturday};
  final Set<DateTime> _anadidos = {};
  final Set<DateTime> _quitados = {};
  bool _cabecera = true;
  bool _hayRetoques = false;

  @override
  void initState() {
    super.initState();
    _mes = mesInicial(fecha: widget.mes);
    _cargarPatronGuardado();
  }

  Future<void> _cargarPatronGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getStringList(fechasLibresDiasSemanaKey);
    if (guardado == null || guardado.isEmpty || !mounted) return;
    final dias = guardado
        .map(int.tryParse)
        .whereType<int>()
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet();
    if (dias.isEmpty) return;
    setState(() => _diasSemana = dias);
  }

  Future<void> _guardarPatron() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      fechasLibresDiasSemanaKey,
      _diasSemana.map((d) => '$d').toList(),
    );
  }

  /// Cambiar el patrón o los días de la semana borra los retoques del mes.
  void _cambiarDiasSemana(Set<int> dias) {
    setState(() {
      _diasSemana = dias;
      _anadidos.clear();
      _quitados.clear();
      _hayRetoques = false;
    });
    _guardarPatron();
  }

  void _alternarDiaSemana(int dia) {
    final dias = Set<int>.from(_diasSemana);
    if (!dias.remove(dia)) dias.add(dia);
    _cambiarDiasSemana(dias);
  }

  void _tocarDia(DateTime fecha) {
    setState(() {
      final delPatron = _diasSemana.contains(fecha.weekday);
      final marcado =
          (delPatron || _anadidos.contains(fecha)) &&
          !_quitados.contains(fecha);
      if (marcado) {
        _anadidos.remove(fecha);
        _quitados.add(fecha);
      } else {
        _quitados.remove(fecha);
        _anadidos.add(fecha);
      }
      _hayRetoques = _anadidos.isNotEmpty || _quitados.isNotEmpty;
    });
  }

  void _mesAnterior() {
    final anterior = DateTime.utc(_mes.year, _mes.month - 1, 1);
    if (anterior.isBefore(mesInicial())) return;
    setState(() {
      _mes = anterior;
      _anadidos.clear();
      _quitados.clear();
      _hayRetoques = false;
    });
  }

  void _mesSiguiente() {
    setState(() {
      _mes = DateTime.utc(_mes.year, _mes.month + 1, 1);
      _anadidos.clear();
      _quitados.clear();
      _hayRetoques = false;
    });
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fechas copiadas'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _compartir(String texto) =>
      SharePlus.instance.share(ShareParams(text: texto));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gigsAsync = ref.watch(gigsProvider);
    final gigs = gigsAsync.valueOrNull ?? const [];

    final ocupacion = ocupacionPorDia(gigs);
    final libres = diasLibres(
      year: _mes.year,
      month: _mes.month,
      diasSemana: _diasSemana,
      anadidos: _anadidos,
      quitados: _quitados,
      ocupacion: ocupacion,
    );
    final texto = textoFechasLibres(
      libres,
      year: _mes.year,
      month: _mes.month,
      cabecera: _cabecera,
    );
    final hayLibres = libres.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Fechas libres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SelectorDeMes(
            mes: _mes,
            puedeRetroceder: !DateTime.utc(
              _mes.year,
              _mes.month - 1,
              1,
            ).isBefore(mesInicial()),
            onAnterior: _mesAnterior,
            onSiguiente: _mesSiguiente,
          ),
          const SizedBox(height: 20),

          Text(
            'Días que compruebo',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final patron in _patrones)
                ChoiceChip(
                  label: Text(patron.etiqueta),
                  selected: _mismoConjunto(_diasSemana, patron.dias),
                  onSelected: (_) => _cambiarDiasSemana(Set.of(patron.dias)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (dia, inicial) in _inicialesSemana)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _BotonDiaSemana(
                      inicial: inicial,
                      activo: _diasSemana.contains(dia),
                      onTocar: () => _alternarDiaSemana(dia),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          MiniCalendarioMes(
            year: _mes.year,
            month: _mes.month,
            marcados: libres.toSet(),
            ocupados: ocupacion.keys
                .where((d) => d.year == _mes.year && d.month == _mes.month)
                .toSet(),
            onTocarDia: _tocarDia,
          ),
          const SizedBox(height: 8),
          Text(
            _hayRetoques
                ? 'Tienes días retocados a mano. Si cambias el patrón o los '
                      'días de la semana, se pierden.'
                : 'Toca un día del calendario para añadirlo o quitarlo. '
                      'Cambiar el patrón borra esos retoques.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: _hayRetoques ? colors.warning : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir cabecera'),
            subtitle: Text(
              'Fechas libres en ${nombreDeMes(_mes.year, _mes.month)}:',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            value: _cabecera,
            onChanged: (v) => setState(() => _cabecera = v),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border, width: 0.6),
            ),
            child: SelectableText(
              texto,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: hayLibres ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hayLibres ? () => _copiar(texto) : null,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hayLibres ? () => _compartir(texto) : null,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

bool _mismoConjunto(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

class _SelectorDeMes extends StatelessWidget {
  final DateTime mes;
  final bool puedeRetroceder;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;

  const _SelectorDeMes({
    required this.mes,
    required this.puedeRetroceder,
    required this.onAnterior,
    required this.onSiguiente,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nombre = nombreDeMes(mes.year, mes.month);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          tooltip: 'Mes anterior',
          color: puedeRetroceder ? null : colors.border,
          onPressed: puedeRetroceder ? onAnterior : null,
        ),
        Expanded(
          child: Text(
            '${nombre[0].toUpperCase()}${nombre.substring(1)} ${mes.year}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 28),
          tooltip: 'Mes siguiente',
          onPressed: onSiguiente,
        ),
      ],
    );
  }
}

class _BotonDiaSemana extends StatelessWidget {
  final String inicial;
  final bool activo;
  final VoidCallback onTocar;

  const _BotonDiaSemana({
    required this.inicial,
    required this.activo,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTocar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? primary : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          inicial,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: activo ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
