# STLBudget

**Versión estable: 0.4.2** · Aplicación nativa para macOS desarrollada en SwiftUI.

STLBudget ayuda a organizar pedidos de impresión 3D, calcular sus costes de fabricación y preparar presupuestos PDF para clientes. Funciona de forma local e independiente del sistema de control de la impresora: **no necesita Klipper, Moonraker ni servicios de monitorización**.

> **Estado:** v0.4.2 probada en la instalación macOS del proyecto. El código fuente de este repositorio se compila con Xcode; el archivo `.app` debe generarse en macOS.

## Funcionalidades

- **Proyectos y pedidos:** agrupa varias piezas, colores y cantidades en un mismo encargo y consulta el progreso de fabricación.
- **G-codes de referencia:** importa un G-code individual por tipo de pieza y obtiene los datos de tiempo estimado y cantidad de filamento proporcionados por el archivo de OrcaSlicer.
- **Variantes por bobina:** elige la bobina y cantidad de cada pieza. El color se obtiene de los datos de la bobina, sin escribirlo de nuevo.
- **Presupuesto económico:** desglosa material, electricidad de la impresora, electricidad del secador opcional, amortización, mantenimiento, mano de obra, consumibles, embalaje y reserva por fallos.
- **Detalle de precio:** gráfico circular de costes, precio recomendado, precio acordado y beneficio estimado.
- **Seguimiento:** registra cuántas unidades de cada variante están terminadas.
- **Documentos PDF:** presupuesto comercial sin costes internos e informe privado con detalle económico y gráfico circular.
- **Presupuestos emitidos:** permite congelar una oferta para mantener los importes y condiciones acordados.
- **Histórico y reutilización:** conserva presupuestos locales y permite duplicar proyectos.
- **Configuración opcional de documentos:** nombre del emisor, contacto, validez y condiciones.

## Flujo de trabajo

1. Crea un proyecto con nombre y destinatario.
2. Importa uno o varios **G-codes individuales de referencia**, generados con el perfil real de OrcaSlicer.
3. Selecciona las bobinas y cantidades solicitadas de cada pieza; usa otra variante cuando cambie el color.
4. Comprueba el filamento, tiempo estimado y desglose en **Detalle de precio**.
5. Ajusta los minutos de trabajo manual y, si corresponde, activa el uso del secador durante la impresión.
6. Introduce el precio final acordado y, cuando esté listo, emite el presupuesto.
7. Exporta el PDF del cliente o el informe interno y actualiza las cantidades fabricadas.

**Nota sobre los tiempos:** sumar tiempos de impresión individual sirve para obtener una estimación del pedido; imprimir piezas juntas en una bandeja puede dar una duración diferente.

## Requisitos

- macOS **14.0 o superior**, según el Deployment Target recomendado para esta versión del proyecto.
- Xcode compatible con tu versión de macOS y SwiftUI.
- G-codes exportados desde OrcaSlicer para aprovechar los metadatos de impresión compatibles.

No se requiere Docker, una base de datos externa ni conexión al servidor de la impresora. STLBudget puede importar datos de bobinas desde Spoolman, pero **no controla impresiones ni depende de Spoolman para monitorizarlas**.

## Compilar y exportar `STLBudget.app` desde Xcode (paso a paso)

Esta guía sirve para generar una copia ejecutable desde Finder y preparar el archivo de una release de GitHub. **La compilación y exportación se hacen en un Mac con Xcode.**

### A. Preparar el proyecto y el icono

1. Abre `STLBudget.xcodeproj` en Xcode y selecciona **STLBudget** en **TARGETS** (no en PROJECT).
2. En **General → Identity**, establece **Version: `0.4.2`** y **Build: `1`** (o aumenta el Build si recompilas esta misma versión).
3. En **General → Minimum Deployments**, selecciona **macOS 14.0**. Si aparece el aviso sobre `LSMinimumSystemVersion` 13.0, cambia esa entrada a 14.0 en `Info.plist`, si existe, o elimina la entrada manual si la gestiona automáticamente Xcode. El valor debe concordar con `MACOSX_DEPLOYMENT_TARGET`.
4. Comprueba que en el proyecto existe `Assets.xcassets → AppIcon` con el icono verde. El catálogo puede estar dentro de `Resources/`; no necesita estar en la raíz.
5. En **TARGETS → STLBudget → Build Settings**, selecciona **All** y busca `ASSETCATALOG_COMPILER_APPICON_NAME` (o `appicon`). Establece **`AppIcon`** en Debug y Release. Verifica que el catálogo se incorpore al target.
6. Detén cualquier ejecución en curso y ejecuta **Product → Clean Build Folder** (`⇧⌘K`), seguido de **Product → Build** (`⌘B`). Corrige los errores antes de exportar.

### B. Exportación recomendada: Archive

1. En la barra superior, en el destino del esquema `STLBudget`, selecciona **Any Mac** / **Any Mac (Apple Silicon, Intel)**, si está disponible. Si solo necesitas compilar para tu Mac, usa el destino compatible que ofrezca tu Xcode.
2. Abre **Product → Archive**. Espera a que termine la compilación de distribución.
3. Si no se abre, entra en **Window → Organizer → Archives**. Selecciona el archivo de STLBudget v0.4.2 recién creado.
4. Pulsa **Distribute App**. Las opciones dependen de la versión de Xcode y la configuración de firma: selecciona **Custom → Copy App** o la opción equivalente de **Copy App / Export**, cuando esté disponible para tu archivo.
5. Selecciona una carpeta de destino (por ejemplo `Releases/STLBudget-v0.4.2/`) y completa el asistente. Comprueba que el resultado contiene **`STLBudget.app`**.
6. Ábrela desde **Finder**, fuera de Xcode, y comprueba icono, versión en **Obtener información**, apertura de proyectos y exportación PDF.

> **Firma y distribución:** una app sin firma/notarización adecuada puede generar avisos de seguridad en otros Mac. Para compartirla ampliamente, revisa las opciones de **Developer ID** y notarización de Apple; copiar una `.app` local no equivale a notarizarla.

### C. Alternativa para uso personal: copiar el producto compilado

Si **Archive** o **Copy App** no están disponibles:

1. En **Product → Scheme → Edit Scheme… → Run**, selecciona **Build Configuration: Release** y cierra el cuadro.
2. Compila (`⌘B`).
3. Abre **Product → Show Build Folder in Finder** si existe en tu Xcode, o localiza la app desde el grupo **Products → STLBudget.app → Show in Finder**. También puedes buscarla dentro de `~/Library/Developer/Xcode/DerivedData/` bajo `Build/Products/Release/`.
4. Copia **`STLBudget.app`** como una unidad (sin entrar en su contenido) a la carpeta que prefieras y ábrela desde Finder para verificarla.
5. Recuerda devolver **Run → Build Configuration** a Debug si quieres continuar desarrollando y depurando habitualmente.

### D. Preparar la release de GitHub

1. Copia el proyecto fuente y actualiza `README.md` y `CHANGELOG.md`.
2. Comprueba que **no subes** proyectos y presupuestos personales desde `~/Library/Application Support/STLBudget/`, ni secretos o rutas locales privadas.
3. Comprime **`STLBudget.app`** (clic derecho en Finder → **Comprimir**) para obtener un ZIP que conserve la estructura del paquete de macOS.
4. En GitHub, publica una **Release** con la etiqueta **`v0.4.2`** y adjunta ese ZIP. Indica que macOS 14 o superior es el mínimo configurado.

## Dónde se guardan los datos

Los datos se almacenan localmente en:

`~/Library/Application Support/STLBudget/`

Allí se encuentran los proyectos, histórico, ajustes económicos, catálogo de bobinas, ajustes de documentos y copias de G-codes que guarde la aplicación. **Haz copia de esa carpeta antes de actualizar o restaurar versiones.** No subas tus datos personales ni presupuestos de clientes a GitHub.

## Parámetros de referencia

La aplicación permite editar las tarifas y potencias en Configuración. Como referencias medidas en una prueba PETG de una hora se obtuvieron:

| Dispositivo | Potencia media aproximada |
|---|---:|
| Ender 3 V2 imprimiendo PETG | 99,6 W |
| Secador de filamento PETG | 59,1 W |

Estos valores son propios de las condiciones de esa prueba: no son especificaciones universales de la impresora ni del secador. En proyectos nuevos se proponen **10 minutos** de trabajo manual editable, no un cargo mínimo obligatorio.

## Limitaciones conocidas

- Los consumos y tiempos proceden de estimaciones del laminador, no de telemetría de impresión en tiempo real.
- No se calcula automáticamente el tiempo exacto de una bandeja combinada a partir de las referencias individuales.
- Las ofertas emitidas se congelan por proyecto; para preparar una nueva oferta, duplica el proyecto.
- Los PDF comerciales son **presupuestos**, no facturas fiscales, y presentan importes antes de impuestos.

## Historial

Consulta [CHANGELOG.md](CHANGELOG.md) para los cambios por versión.

## Licencia

Pendiente de definir por el propietario del repositorio. Hasta que se añada un archivo `LICENSE`, no se debe presumir una licencia de código abierto.
