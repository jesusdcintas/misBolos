import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/fechas_libres.dart';
import '../../core/utils/texto_fechas_libres.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/client_provider.dart';
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

  /// En el mes actual no se puede ir hacia atrás.
  bool get _puedeRetroceder =>
      !DateTime.utc(_mes.year, _mes.month - 1, 1).isBefore(mesInicial());

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

  /// Texto del tooltip de cada día con bolo: el cliente, o cuántos hay.
  Map<DateTime, String> _bolosPorDia(
    List<Gig> gigs,
    Map<String, String> nombres,
  ) {
    final porDia = <DateTime, List<String>>{};
    for (final gig in gigs) {
      if (gig.status == GigStatus.cancelado) continue;
      porDia
          .putIfAbsent(diaClave(gig.fecha), () => [])
          .add(nombres[gig.clientId] ?? 'Cliente');
    }
    return porDia.map((dia, clientes) {
      if (clientes.length == 1) return MapEntry(dia, clientes.first);
      return MapEntry(dia, '${clientes.length} bolos: ${clientes.join(', ')}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final gigs = ref.watch(gigsProvider).valueOrNull ?? const <Gig>[];
    final clientes =
        ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final nombres = {for (final c in clientes) c.id: c.displayName};

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
    final bolos = _bolosPorDia(gigs, nombres);

    return Scaffold(
      appBar: AppBar(title: const Text('Fechas libres')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final anchura = constraints.maxWidth >= _anchoDosColumnas;

          final izquierda = _TarjetaDias(
            mes: _mes,
            puedeRetroceder: _puedeRetroceder,
            onAnterior: _mesAnterior,
            onSiguiente: _mesSiguiente,
            diasSemana: _diasSemana,
            onPatron: _cambiarDiasSemana,
            onDiaSemana: _alternarDiaSemana,
            marcados: libres.toSet(),
            bolosPorDia: bolos,
            onTocarDia: _tocarDia,
            hayRetoques: _hayRetoques,
            compacto: !anchura,
          );

          final derecha = _TarjetaTexto(
            mes: _mes,
            cuantas: libres.length,
            cabecera: _cabecera,
            onCabecera: (v) => setState(() => _cabecera = v),
            texto: texto,
            // En móvil las acciones van fijas abajo.
            mostrarAcciones: anchura,
            onCopiar: hayLibres ? () => _copiar(texto) : null,
            onCompartir: hayLibres ? () => _compartir(texto) : null,
          );

          if (!anchura) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [izquierda, const SizedBox(height: 16), derecha],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _anchoMaximo),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: izquierda),
                    const SizedBox(width: 24),
                    SizedBox(width: _anchoColumnaTexto, child: derecha),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width >=
              _anchoDosColumnas
          ? null
          : _AccionesFijas(
              onCopiar: hayLibres ? () => _copiar(texto) : null,
              onCompartir: hayLibres ? () => _compartir(texto) : null,
            ),
    );
  }
}

bool _mismoConjunto(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

/// Ancho a partir del cual la pantalla pasa a dos columnas.
const double _anchoDosColumnas = 700;
const double _anchoMaximo = 1160;
const double _anchoColumnaTexto = 380;

class _Tarjeta extends StatelessWidget {
  final Widget child;

  const _Tarjeta({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.6),
      ),
      child: child,
    );
  }
}

/// Etiqueta pequeña en mayúsculas.
class _Rotulo extends StatelessWidget {
  final String texto;

  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _TarjetaDias extends StatelessWidget {
  final DateTime mes;
  final bool puedeRetroceder;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;
  final Set<int> diasSemana;
  final ValueChanged<Set<int>> onPatron;
  final ValueChanged<int> onDiaSemana;
  final Set<DateTime> marcados;
  final Map<DateTime, String> bolosPorDia;
  final ValueChanged<DateTime> onTocarDia;
  final bool hayRetoques;
  final bool compacto;

  const _TarjetaDias({
    required this.mes,
    required this.puedeRetroceder,
    required this.onAnterior,
    required this.onSiguiente,
    required this.diasSemana,
    required this.onPatron,
    required this.onDiaSemana,
    required this.marcados,
    required this.bolosPorDia,
    required this.onTocarDia,
    required this.hayRetoques,
    required this.compacto,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nombre = nombreDeMes(mes.year, mes.month);

    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${nombre[0].toUpperCase()}${nombre.substring(1)} '
                  '${mes.year}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _FlechaMes(
                icono: Icons.chevron_left,
                tooltip: 'Mes anterior',
                onTocar: puedeRetroceder ? onAnterior : null,
              ),
              const SizedBox(width: 8),
              _FlechaMes(
                icono: Icons.chevron_right,
                tooltip: 'Mes siguiente',
                onTocar: onSiguiente,
              ),
            ],
          ),
          const SizedBox(height: 20),

          const _Rotulo('Días a comprobar'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final patron in _patrones)
                _ChipPatron(
                  etiqueta: patron.etiqueta,
                  activo: _mismoConjunto(diasSemana, patron.dias),
                  onTocar: () => onPatron(Set.of(patron.dias)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (dia, inicial) in _inicialesSemana)
                Expanded(
                  child: Center(
                    child: _BotonDiaSemana(
                      inicial: inicial,
                      activo: diasSemana.contains(dia),
                      diametro: compacto ? 40 : 36,
                      onTocar: () => onDiaSemana(dia),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          MiniCalendarioMes(
            year: mes.year,
            month: mes.month,
            marcados: marcados,
            bolosPorDia: bolosPorDia,
            altoCelda: compacto ? 46 : 52,
            onTocarDia: onTocarDia,
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 20,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const LeyendaMiniCalendario(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  hayRetoques
                      ? 'Tienes días retocados a mano. Si cambias el patrón o '
                            'los días de la semana, se pierden.'
                      : 'Toca un día para añadirlo o quitarlo.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: hayRetoques ? colors.warning : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaTexto extends StatelessWidget {
  final DateTime mes;
  final int cuantas;
  final bool cabecera;
  final ValueChanged<bool> onCabecera;
  final String texto;
  final bool mostrarAcciones;
  final VoidCallback? onCopiar;
  final VoidCallback? onCompartir;

  const _TarjetaTexto({
    required this.mes,
    required this.cuantas,
    required this.cabecera,
    required this.onCabecera,
    required this.texto,
    required this.mostrarAcciones,
    this.onCopiar,
    this.onCompartir,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu texto',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            switch (cuantas) {
              0 => 'Ninguna fecha libre',
              1 => '1 fecha libre',
              _ => '$cuantas fechas libres',
            },
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cuantas > 0 ? colors.success : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Incluir cabecera'),
            subtitle: Text(
              'Fechas libres en ${nombreDeMes(mes.year, mes.month)}:',
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
            value: cabecera,
            onChanged: onCabecera,
          ),
          const SizedBox(height: 12),
          _VistaPrevia(texto: texto, conCabecera: cabecera && cuantas > 0),
          if (mostrarAcciones) ...[
            const SizedBox(height: 16),
            _Acciones(onCopiar: onCopiar, onCompartir: onCompartir),
          ],
        ],
      ),
    );
  }
}

/// Vista previa del texto, con la cabecera en negrita.
class _VistaPrevia extends StatelessWidget {
  final String texto;
  final bool conCabecera;

  const _VistaPrevia({required this.texto, required this.conCabecera});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lineas = texto.split('\n');
    final cuerpo = TextStyle(
      fontSize: 13.5,
      height: 1.55,
      color: colors.textPrimary,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: 0.6),
      ),
      child: SelectableText.rich(
        TextSpan(
          children: [
            if (conCabecera && lineas.isNotEmpty) ...[
              TextSpan(
                text: lineas.first,
                style: cuerpo.copyWith(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: '\n${lineas.skip(1).join('\n')}', style: cuerpo),
            ] else
              TextSpan(text: texto, style: cuerpo),
          ],
        ),
      ),
    );
  }
}

class _Acciones extends StatelessWidget {
  final VoidCallback? onCopiar;
  final VoidCallback? onCompartir;

  const _Acciones({this.onCopiar, this.onCompartir});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCopiar,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copiar'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onCompartir,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Compartir'),
          ),
        ),
      ],
    );
  }
}

/// Copiar y Compartir fijos abajo, en móvil.
class _AccionesFijas extends StatelessWidget {
  final VoidCallback? onCopiar;
  final VoidCallback? onCompartir;

  const _AccionesFijas({this.onCopiar, this.onCompartir});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: _Acciones(onCopiar: onCopiar, onCompartir: onCompartir),
        ),
      ),
    );
  }
}

class _FlechaMes extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback? onTocar;

  const _FlechaMes({
    required this.icono,
    required this.tooltip,
    this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activo = onTocar != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTocar,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Icon(
            icono,
            size: 20,
            color: activo ? colors.textPrimary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ChipPatron extends StatelessWidget {
  final String etiqueta;
  final bool activo;
  final VoidCallback onTocar;

  const _ChipPatron({
    required this.etiqueta,
    required this.activo,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTocar,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: activo ? primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activo ? primary : colors.border,
            width: activo ? 1.4 : 0.8,
          ),
        ),
        child: Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
            color: activo ? primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BotonDiaSemana extends StatelessWidget {
  final String inicial;
  final bool activo;
  final double diametro;
  final VoidCallback onTocar;

  const _BotonDiaSemana({
    required this.inicial,
    required this.activo,
    required this.diametro,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTocar,
      customBorder: const CircleBorder(),
      child: Container(
        width: diametro,
        height: diametro,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? primary : colors.surfaceContainer,
          shape: BoxShape.circle,
          border: activo ? null : Border.all(color: colors.border, width: 0.8),
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
