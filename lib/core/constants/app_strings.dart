class AppStrings {
  AppStrings._();

  static const String appName = 'MisBolos';
  
  // Navegación
  static const String dashboard = 'Dashboard';
  static const String calendario = 'Calendario';
  static const String clientes = 'Clientes';
  static const String facturas = 'Facturas';
  static const String estadisticas = 'Estadísticas';
  static const String ajustes = 'Ajustes';

  // Bolos
  static const String nuevoBolo = 'Nuevo bolo';
  static const String editarBolo = 'Editar bolo';
  static const String detalleBolo = 'Detalle del bolo';
  static const String fecha = 'Fecha';
  static const String cliente = 'Cliente';
  static const String cachet = 'Caché (€)';
  static const String notas = 'Notas';
  static const String facturable = '¿Es facturable?';
  static const String si = 'SÍ';
  static const String no = 'NO';

  // Estados de bolo
  static const String pendiente = 'Pendiente';
  static const String facturaGenerada = 'Factura generada';
  static const String facturaEnviada = 'Pdte cobro';
  static const String pagado = 'Cobrado';
  static const String cancelado = 'Cancelado';
  static const String cobradoEnB = 'Cobrado en B';

  // Acciones
  static const String generarFactura = 'Generar factura';
  static const String marcarEnviada = 'Marcar como pendiente';
  static const String marcarPagado = 'Marcar como cobrado';
  static const String marcarCobradoEnB = 'Marcar como cobrado en B';
  static const String cancelarBolo = 'Cancelar bolo';
  static const String verPDF = 'Ver PDF';
  static const String compartirPDF = 'Compartir PDF';
  static const String guardar = 'Guardar';
  static const String eliminar = 'Eliminar';
  static const String cancelar = 'Cancelar';

  // Facturas
  static const String nuevaFactura = 'Nueva factura';
  static const String factura = 'Factura';
  static const String todas = 'Todas';
  static const String borrador = 'Borrador';
  static const String enviada = 'Pendiente';
  static const String pagada = 'Cobrada';
  static const String subtotal = 'Subtotal';
  static const String iva = 'IVA';
  static const String total = 'TOTAL';

  // Clientes
  static const String nuevoCliente = 'Nuevo cliente';
  static const String editarCliente = 'Editar cliente';
  static const String nombre = 'Nombre';
  static const String cifNif = 'CIF/NIF';
  static const String direccion = 'Dirección';
  static const String ciudad = 'Ciudad';
  static const String codigoPostal = 'Código postal';
  static const String email = 'Email';
  static const String telefono = 'Teléfono';

  // Dashboard
  static const String ingresosOficiales = 'Ingresos oficiales';
  static const String ingresosEnB = 'Ingresos en B';
  static const String cobradoEsteMes = 'Cobrado este mes';
  static const String pendienteCobro = 'Pendiente';
  static const String facturasEnviadas = 'Facturas pendientes';
  static const String cobradoEnBEsteMes = 'Cobrado en B este mes';
  static const String pendienteCobroB = 'Pendiente cobrar en B';
  static const String totalBolosMes = 'Bolos este mes';
  static const String proximoBolo = 'Próximo bolo';
  static const String ultimosBolos = 'Últimos bolos';

  // Estadísticas
  static const String oficial = 'Oficial';
  static const String enB = 'En B';
  static const String global = 'Global';

  // Ajustes
  static const String misDatos = 'Mis datos';
  static const String logo = 'Logo';
  static const String ivaPorDefecto = 'IVA por defecto';
  static const String notificaciones = 'Notificaciones';
  static const String diasRecordatorio = 'Días para recordatorio';
  static const String sincronizar = 'Sincronizar';
  static const String backup = 'Backup';
  static const String exportarCSV = 'Exportar CSV';
  static const String avisoLegal = 'Todos tus datos, incluidos los ingresos no facturados, se sincronizan de forma segura. Solo tú puedes acceder a ellos.';

  // Mensajes
  static const String boloCreado = 'Bolo creado correctamente';
  static const String boloActualizado = 'Bolo actualizado';
  static const String facturaCreada = 'Factura generada correctamente';
  static const String clienteCreado = 'Cliente creado correctamente';
  static const String clienteActualizado = 'Cliente actualizado';
  static const String errorGeneral = 'Ha ocurrido un error. Inténtalo de nuevo.';
  static const String campoObligatorio = 'Este campo es obligatorio';
  static const String emailInvalido = 'Email no válido';
  static const String sinBolos = 'No hay bolos registrados';
  static const String sinClientes = 'No hay clientes registrados';
  static const String sinFacturas = 'No hay facturas generadas';

  // PDF
  static const String emisor = 'EMISOR';
  static const String facturarA = 'FACTURAR A';
  static const String informacionPago = 'Información de pago';
  static const String cantidad = 'Cantidad';
  static const String descripcion = 'Descripción';
  static const String precioUnidad = 'Precio por unidad';
  static const String totalLinea = 'Total de línea';
  static const String impuestoVentas = 'Impuesto sobre las ventas al';
  static const String numeroFactura = 'N.º de factura';
}
