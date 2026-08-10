import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/models/app_settings.dart';
import 'package:misbolos/models/client.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/services/pdf_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<Directory> getApplicationDocumentsDirectory() async {
    final dir = Directory.systemTemp.createTempSync('misbolos_pdf_test');
    return dir;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.createTempSync('misbolos_pdf_test').path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  test('genera un PDF multipágina cuando hay muchas líneas de concepto', () async {
    final service = PdfService();
    final client = Client(
      nombre: 'Cliente de prueba',
      cifNif: 'B12345678',
      direccion: 'Calle Prueba 123',
      ciudad: 'Madrid',
      provincia: 'Madrid',
      codigoPostal: '28001',
      email: 'cliente@ejemplo.com',
      telefono: '600000000',
    );
    final settings = AppSettings(
      emisorNombre: 'Mis Bolos SL',
      emisorNIF: 'B98765432',
      emisorDireccion: 'Avenida del Sol 45',
      emisorCiudad: 'Valencia',
      emisorProvincia: 'Valencia',
      emisorCodigoPostal: '46001',
      emisorEmail: 'info@misbolos.test',
      emisorTelefono: '961000000',
      iban: 'ES12 3456 7890 1234 5678 9012',
      pdfTheme: 'clasico',
    );

    final items = List.generate(25, (index) {
      return InvoiceLineItem(
        cantidad: 1,
        descripcion:
            'Concepto de prueba muy largo para verificar el salto de página ${index + 1} y asegurar que el contenido de la tabla se distribuye en varias hojas sin perder información.',
        precioUnitario: 120.0 + index,
      );
    });

    final invoice = Invoice(
      numero: 1001,
      fecha: DateTime(2026, 8, 10),
      clientId: 'client-1',
      gigId: 'gig-1',
      items: items,
      subtotal: 25 * 120.0 + 25 * 24.0 / 2,
      ivaRate: 0.21,
      ivaAmount: 0,
      irpfRate: 0.0,
      total: 0,
    );

    final file = await service.generateInvoicePdf(
      invoice: invoice,
      client: client,
      settings: settings,
    );

    expect(await file.exists(), isTrue);

    final pdfBytes = await file.readAsBytes();
    final pdfText = latin1.decode(pdfBytes);
    final pageCountMatches = RegExp(r'/Count\s+(\d+)').allMatches(pdfText);

    expect(pageCountMatches, isNotEmpty, reason: 'El PDF no contiene un árbol de páginas válido.');

    final pageCount = int.parse(pageCountMatches.first.group(1)!);
    expect(pageCount, greaterThan(1));
  });

  test('una factura de 12 líneas ocupa como máximo dos páginas', () async {
    final service = PdfService();
    final client = Client(
      nombre: 'Cliente de prueba',
      cifNif: 'B12345678',
      direccion: 'Calle Prueba 123',
      ciudad: 'Madrid',
      provincia: 'Madrid',
      codigoPostal: '28001',
      email: 'cliente@ejemplo.com',
      telefono: '600000000',
    );
    final settings = AppSettings(
      emisorNombre: 'Mis Bolos SL',
      emisorNIF: 'B98765432',
      emisorDireccion: 'Avenida del Sol 45',
      emisorCiudad: 'Valencia',
      emisorProvincia: 'Valencia',
      emisorCodigoPostal: '46001',
      emisorEmail: 'info@misbolos.test',
      emisorTelefono: '961000000',
      iban: 'ES12 3456 7890 1234 5678 9012',
      pdfTheme: 'clasico',
    );

    final items = List.generate(12, (index) {
      return InvoiceLineItem(
        cantidad: 1,
        descripcion:
            'Concepto compacto ${index + 1} para validar la densidad de la tabla y comprobar que la factura cabe en una o dos páginas.',
        precioUnitario: 45.0 + index,
      );
    });

    final invoice = Invoice(
      numero: 41,
      fecha: DateTime(2026, 8, 10),
      clientId: 'client-1',
      gigId: 'gig-1',
      items: items,
      subtotal: 12 * 45.0,
      ivaRate: 0.21,
      ivaAmount: 0,
      irpfRate: 0.0,
      total: 0,
    );

    final file = await service.generateInvoicePdf(
      invoice: invoice,
      client: client,
      settings: settings,
    );

    final pdfBytes = await file.readAsBytes();
    final pdfText = latin1.decode(pdfBytes);
    final pageCountMatches = RegExp(r'/Count\s+(\d+)').allMatches(pdfText);

    expect(pageCountMatches, isNotEmpty);

    final pageCount = int.parse(pageCountMatches.first.group(1)!);
    expect(pageCount, lessThanOrEqualTo(2));
  });
}
