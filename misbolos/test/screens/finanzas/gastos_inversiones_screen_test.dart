import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:misbolos/core/services/hapticos.dart';
import 'package:misbolos/core/theme/app_theme.dart';
import 'package:misbolos/models/asset.dart';
import 'package:misbolos/models/expense.dart';
import 'package:misbolos/providers/assets_provider.dart';
import 'package:misbolos/providers/expenses_provider.dart';
import 'package:misbolos/screens/finanzas/gastos_inversiones_screen.dart';

/// Gastos de mentira, sin base de datos ni nube.
class _GastosDePrueba extends ExpensesNotifier {
  final List<Expense> _gastos;

  _GastosDePrueba(this._gastos);

  @override
  Future<List<Expense>> build() async => _gastos;

  @override
  Future<void> enterScreen() async {}

  @override
  void leaveScreen() {}
}

class _InversionesDePrueba extends AssetsNotifier {
  final List<Asset> _inversiones;

  _InversionesDePrueba(this._inversiones);

  @override
  Future<List<Asset>> build() async => _inversiones;

  @override
  Future<void> enterScreen() async {}

  @override
  void leaveScreen() {}
}

Expense _gasto() => Expense(
  id: 1,
  fecha: DateTime(2026, 11, 3),
  concepto: 'Cables XLR',
  importeBase: 100,
  ivaRate: 21,
  ivaAmount: 21,
  total: 121,
  categoria: ExpenseCategory.equipo,
  createdAt: DateTime(2026, 11, 3),
);

Asset _inversion() => Asset(
  id: 1,
  descripcion: 'Altavoces',
  fechaCompra: DateTime(2026, 11, 10),
  importeTotal: 2000,
  vidaUtilAnos: 5,
  categoria: AssetCategory.equipoDj,
  createdAt: DateTime(2026, 11, 10),
);

Future<void> _montar(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expensesProvider.overrideWith(() => _GastosDePrueba([_gasto()])),
        assetsProvider.overrideWith(() => _InversionesDePrueba([_inversion()])),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const GastosInversionesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_ES');
  });

  setUp(() => Hapticos.fijarActivadosEnTests(false));

  testWidgets('la lista se pinta con un gasto y una inversión', (tester) async {
    await _montar(tester);

    // Si el Dismissible está mal montado, esto no llega ni a pintarse:
    // Flutter revienta con «secondaryBackground == null || background != null».
    expect(tester.takeException(), isNull);
    expect(find.text('Gastos e Inversiones'), findsOneWidget);
    expect(find.text('Cables XLR'), findsOneWidget);
    expect(find.text('Altavoces'), findsOneWidget);
    expect(find.text('Inversión'), findsOneWidget);
  });

  testWidgets('solo el gasto se puede deslizar para borrar', (tester) async {
    await _montar(tester);

    final deslizables = tester.widgetList<Dismissible>(
      find.byType(Dismissible),
    );

    // Las inversiones son de solo lectura: no se deslizan.
    expect(deslizables.length, 1);

    final gasto = deslizables.first;
    expect(gasto.direction, DismissDirection.endToStart);
    // La regla de Flutter: con fondo secundario tiene que haber principal.
    expect(
      gasto.secondaryBackground == null || gasto.background != null,
      isTrue,
      reason: 'un Dismissible así rompe la lista entera al pintarse',
    );
    expect(gasto.background, isNotNull);
  });
}
