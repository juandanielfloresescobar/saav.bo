// ==========================================
// 1. CONFIGURACIÓN SUPABASE
// ==========================================
const SUPABASE_URL = 'https://kaupgsmmkqszohkgtczy.supabase.co'; 
const SUPABASE_KEY = 'sb_publishable_D98W0toeGYyKiLSDDI8FCg_RDdN_MCw'; 

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// ==========================================
// 2. VARIABLES GLOBALES
// ==========================================
const charts = { mensual: null, locacion: null, cliente: null, ingresos: null };
const elementos = {};
let dataCompleta = [];
let dataFiltrada = []; 
let fechasDisponibles = [];
let ingresosMensuales = [];
let TASA_CAMBIO_INGRESOS = 6.96;

const estado = {
  fecha: null,
  cliente: '',
  filtroMes: '',
  filtroLoc: '',
  pareto: '80',
  mostrarGraficoCliente: false,
  mesIngresos: ''
};

let calendarioAbierto = false;

// ==========================================
// 3. INICIALIZACIÓN
// ==========================================
document.addEventListener('DOMContentLoaded', initDashboard);

async function initDashboard() {
  const loader = document.getElementById('loader');
  const errorBanner = document.getElementById('error-message');

  try {
    console.log("📡 Iniciando dashboard...");

    // A. Cuentas por Cobrar
    let { data: rawCuentas, error: errorCuentas } = await supabase.from('cuentas_por_cobrar').select('*');
    if (errorCuentas) console.warn("Aviso Cuentas:", errorCuentas.message);
    dataCompleta = (rawCuentas || []).map(normalizarFilaCuenta);

    // B. Ingresos
    let { data: rawIngresos, error: errorIngresos } = await supabase.from('ingresos').select('*');
    if (errorIngresos) console.error("Error Ingresos:", errorIngresos.message);
    
    if (rawIngresos && rawIngresos.length > 0) {
      ingresosMensuales = procesarIngresosSupabase(rawIngresos);
      if (ingresosMensuales.length) estado.mesIngresos = ingresosMensuales[0].clave;
    }

    console.log(`✅ Datos cargados. Ingresos: ${ingresosMensuales.length}, Cuentas: ${dataCompleta.length}`);

    // C. Configuración UI
    configurarReferencias(); 
    configurarInteracciones();

    fechasDisponibles = obtenerFechasOrdenadas(dataCompleta);
    estado.fecha = fechasDisponibles[0] || null;
    dataFiltrada = filtrarPorFecha(dataCompleta, estado.fecha);

    prepararSelectorIngresos();
    
    // D. Renderizado Inicial
    refrescarTodo();

    if (elementos.year) elementos.year.textContent = new Date().getFullYear();

  } catch (error) {
    console.error('❌ Error crítico:', error);
    if (errorBanner) {
        errorBanner.classList.remove('is-hidden');
        errorBanner.querySelector('p').textContent = "Error: " + error.message;
    }
  } finally {
    if (loader) loader.classList.add('hidden');
  }
}

// ==========================================
// 4. PROCESAMIENTO
// ==========================================
function getVal(obj, key) {
    if (!obj) return undefined;
    return obj[key] !== undefined ? obj[key] : (obj[key.toLowerCase()] !== undefined ? obj[key.toLowerCase()] : undefined);
}

function normalizarFilaCuenta(d) {
  return {
    fecha_estado: getVal(d, 'FECHA_ESTADO') || getVal(d, 'fecha_estado'), 
    mes_deuda: (getVal(d, 'MES_DEUDA') || getVal(d, 'mes_deuda') || '').toString().trim().toUpperCase(),
    locacion: getVal(d, 'LOCACION') || getVal(d, 'locacion') || 'Sin Locación',
    cliente: getVal(d, 'CLIENTE') || getVal(d, 'cliente') || 'Desconocido',
    monto_bs: Number(getVal(d, 'MONTO_BS') || getVal(d, 'monto_bs') || 0),
    monto_usd: Number(getVal(d, 'MONTO_USD') || getVal(d, 'monto_usd') || 0)
  };
}

function procesarIngresosSupabase(datos) {
  return datos.map(d => {
    const mesNombre = (getVal(d, 'month') || '').toString().toLowerCase();
    const mesNumero = indiceMesNombre(mesNombre);
    const anio = Number(getVal(d, 'year'));
    if (mesNumero === null || !anio) return null;

    const vVehiculos = Number(getVal(d, 'fleet_vehiculos')||0);
    const vCamionetas = Number(getVal(d, 'fleet_camionetas')||0);
    const vSuv = Number(getVal(d, 'fleet_suv')||0);
    const vFull = Number(getVal(d, 'fleet_full_size')||0);
    const vCamioncito = Number(getVal(d, 'fleet_camioncito')||0);

    const partesFlota = [];
    if (vVehiculos > 0) partesFlota.push(`Vehículos: ${vVehiculos}`);
    if (vCamionetas > 0) partesFlota.push(`Camionetas: ${vCamionetas}`);
    if (vSuv > 0) partesFlota.push(`SUV: ${vSuv}`);
    if (vFull > 0) partesFlota.push(`Full Size: ${vFull}`);
    
    let totalUnidades = Number(getVal(d, 'fleet_total') || 0);
    if (totalUnidades === 0) totalUnidades = vVehiculos + vCamionetas + vSuv + vFull + vCamioncito;

    return {
      mesNumero, anio,
      ingresoBs: Number(getVal(d, 'income_bs') || 0),
      ingresoUsd: Number(getVal(d, 'income_usd') || 0),
      unidades: totalUnidades,
      composicion: partesFlota.join(' · ') || 'Sin detalle',
      clave: `${anio}-${String(mesNumero + 1).padStart(2, '0')}`
    };
  }).filter(Boolean).sort((a,b) => (b.anio - a.anio) || (b.mesNumero - a.mesNumero));
}

// ==========================================
// 5. REFERENCIAS DOM (CORREGIDO)
// ==========================================
function configurarReferencias() {
  // Asignamos variables con nombres amigables para usarlos en el código
  elementos.fechaBadge = document.getElementById('fecha-actual');
  elementos.calendarioToggle = document.getElementById('calendario-toggle');
  elementos.calendarioLabel = document.getElementById('calendario-label');
  elementos.calendarioDropdown = document.getElementById('calendario-dropdown');
  
  // FILTROS (Aquí estaba el error antes, ahora asignados correctamente)
  elementos.selectMes = document.getElementById('filtro-mes');
  elementos.selectLoc = document.getElementById('filtro-locacion');
  elementos.selectCliente = document.getElementById('filtro-cliente');
  
  elementos.selectMesIngresos = document.getElementById('filtro-mes-ingresos');
  elementos.tablaBody = document.getElementById('tabla-body');
  elementos.year = document.getElementById('year');
  elementos.btnDeudaMensual = document.getElementById('btn-deuda-mensual');

  // Ingresos IDs
  elementos.ingresosTotalAnio = document.getElementById('ingresos-total-anio');
  elementos.ingresosTotalAnioDetalle = document.getElementById('ingresos-total-anio-detalle');
  elementos.ingresosTotalAnioUsd = document.getElementById('ingresos-total-anio-usd');
  elementos.ingresosTotalAnioUsdDetalle = document.getElementById('ingresos-total-anio-usd-detalle');
  elementos.ingresosMensualBs = document.getElementById('ingresos-mensual-bs');
  elementos.ingresosMensualBsDetalle = document.getElementById('ingresos-mensual-bs-detalle');
  elementos.ingresosMensualUsd = document.getElementById('ingresos-mensual-usd');
  elementos.ingresosMensualUsdDetalle = document.getElementById('ingresos-mensual-usd-detalle');
  elementos.ingresosVariacion = document.getElementById('ingresos-variacion');
  elementos.ingresosVariacionDetalle = document.getElementById('ingresos-variacion-detalle');
  elementos.ingresosFlota = document.getElementById('ingresos-flota');
  elementos.ingresosFlotaDetalle = document.getElementById('ingresos-flota-detalle');
  elementos.ingresoPorUnidad = document.getElementById('ingreso-por-unidad');
  elementos.ingresoPorUnidadDetalle = document.getElementById('ingreso-por-unidad-detalle');
  elementos.ingresosMesActual = document.getElementById('ingresos-mes-actual');
  elementos.progressBarFill = document.getElementById('progress-bar-fill');
  elementos.progressText = document.getElementById('progress-text');
  elementos.daysLeftText = document.getElementById('days-left-text');

  // Cuentas por Cobrar IDs
  elementos.totalBs = document.getElementById('total-bs');
  elementos.totalUsd = document.getElementById('total-usd');
  elementos.clientesActivos = document.getElementById('clientes-activos');
  elementos.mesTop = document.getElementById('mes-top');
  elementos.tipoCambio = document.getElementById('tipo-cambio');
  elementos.porcentajeCobrado = document.getElementById('porcentaje-cobrado');
  elementos.montoCobrado = document.getElementById('monto-cobrado');
  
  elementos.listaSalidas = document.getElementById('empresas-salieron'); 
  elementos.paretoList = document.getElementById('pareto-list');
  elementos.paretoBotones = document.querySelectorAll('.pareto-toggle button');

  elementos.clienteNombre = document.getElementById('cliente-nombre');
  elementos.clienteTotalBs = document.getElementById('cliente-total-bs');
  elementos.clienteTotalUsd = document.getElementById('cliente-total-usd');

  elementos.chartIngresos = document.getElementById('chart-ingresos');
  elementos.chartMensual = document.getElementById('chart-mensual');
  elementos.chartLocacion = document.getElementById('chart-locacion');
  elementos.chartCliente = document.getElementById('chart-cliente');
}

// ==========================================
// 6. LÓGICA PRINCIPAL
// ==========================================

function refrescarTodo() {
  if (elementos.fechaBadge) elementos.fechaBadge.textContent = estado.fecha || '—';
  
  // Sincronizar fecha
  if (estado.fecha && ingresosMensuales.length > 0) {
      const p = estado.fecha.split('-');
      if (p.length===3) {
          const clave = `${parseInt(p[0])}-${String(parseInt(p[1])).padStart(2,'0')}`;
          if (ingresosMensuales.some(i => i.clave === clave)) estado.mesIngresos = clave;
      }
  }
  
  actualizarIngresosKpi();
  
  dataFiltrada = filtrarPorFecha(dataCompleta, estado.fecha);
  actualizarIndicadoresCuentas(dataFiltrada); 
  actualizarRetirosMes(); 
  
  renderCharts(dataFiltrada);
  
  // IMPORTANTE: Primero actualizamos opciones, luego filtramos la tabla
  // Pero ojo: si actualizamos opciones, perdemos la selección si no la restauramos.
  // En este flujo simplificado, actualizamos opciones SOLO si cambiamos de fecha global.
  // Pero aquí lo llamamos siempre. Para que el filtro funcione, debemos asegurarnos de que aplicarFiltrosTabla use los valores actuales.
  
  // Si el filtro está vacío, llenamos las opciones
  if (elementos.selectMes && elementos.selectMes.options.length <= 1) {
      actualizarOpcionesFiltros();
  }
  
  const datosTabla = aplicarFiltrosTabla();
  renderTable(datosTabla);
  
  actualizarOpcionesCliente();
  actualizarPanelCliente(dataFiltrada, estado.cliente, estado.mostrarGraficoCliente);
  actualizarPareto(dataFiltrada, estado.pareto);
  actualizarSelectorFecha();
}

// ==========================================
// 7. FUNCIONES ESPECÍFICAS
// ==========================================

function aplicarFiltrosTabla() {
  return dataFiltrada.filter(i => {
    const mesOk = !estado.filtroMes || i.mes_deuda === estado.filtroMes;
    const locOk = !estado.filtroLoc || i.locacion === estado.filtroLoc;
    return mesOk && locOk;
  });
}

function renderTable(registros) {
  if (!elementos.tablaBody) return;
  if (!registros.length) { 
      elementos.tablaBody.innerHTML = '<tr><td colspan="6" class="empty-row">Sin datos para los filtros seleccionados</td></tr>'; 
      return; 
  }
  
  // Limitamos a 200 filas para rendimiento
  elementos.tablaBody.innerHTML = registros.slice(0, 200).map(r => `
    <tr>
      <td>${r.fecha_estado}</td>
      <td>${r.mes_deuda}</td>
      <td>${r.locacion}</td>
      <td>${r.cliente}</td>
      <td>$${fmtUsd(r.monto_usd)}</td>
      <td>Bs ${fmt(r.monto_bs)}</td>
    </tr>
  `).join('');
}

function actualizarOpcionesFiltros() {
  if (!elementos.selectMes) return;
  
  // Guardamos selección actual
  const prevMes = estado.filtroMes;
  const prevLoc = estado.filtroLoc;

  const meses = [...new Set(dataFiltrada.map(d => d.mes_deuda))].sort((a,b)=>ordenMes(a)-ordenMes(b));
  elementos.selectMes.innerHTML = '<option value="">Todos</option>' + meses.map(m => `<option value="${m}">${m}</option>`).join('');
  
  const locs = [...new Set(dataFiltrada.map(d => d.locacion))].sort();
  elementos.selectLoc.innerHTML = '<option value="">Todas</option>' + locs.map(l => `<option value="${l}">${l}</option>`).join('');
  
  // Restauramos selección si aún existe
  if (meses.includes(prevMes)) elementos.selectMes.value = prevMes;
  else estado.filtroMes = ''; // Reset si no existe
  
  if (locs.includes(prevLoc)) elementos.selectLoc.value = prevLoc;
  else estado.filtroLoc = '';
}

function actualizarIndicadoresCuentas(data) {
  const totalBs = data.reduce((s, i) => s + i.monto_bs, 0);
  const totalUsd = data.reduce((s, i) => s + i.monto_usd, 0);
  const clientes = new Set(data.map(i => i.cliente)).size;
  
  const porMes = {};
  data.forEach(i => porMes[i.mes_deuda] = (porMes[i.mes_deuda]||0) + i.monto_bs);
  const mesTop = Object.entries(porMes).sort((a,b)=>b[1]-a[1])[0]?.[0] || '—';

  setText('total-bs', `Bs ${fmt(totalBs)}`);
  setText('total-usd', `$${fmtUsd(totalUsd)}`);
  setText('clientes-activos', clientes);
  setText('mes-top', mesTop);
  setText('tipo-cambio', '6,96 Bs'); 
}

function actualizarRetirosMes() {
  if (!elementos.listaSalidas) return;
  
  const idxActual = fechasDisponibles.indexOf(estado.fecha);
  if (idxActual === -1 || idxActual === fechasDisponibles.length - 1) {
    elementos.listaSalidas.innerHTML = '<li class="empty">Sin datos previos para comparar</li>';
    setText('monto-cobrado', 'Bs 0');
    setText('porcentaje-cobrado', '0%');
    return;
  }

  const fechaPrev = fechasDisponibles[idxActual + 1];
  const saldosHoy = agruparSaldoPorCliente(dataFiltrada);
  const dataPrev = filtrarPorFecha(dataCompleta, fechaPrev);
  const saldosPrev = agruparSaldoPorCliente(dataPrev);
  
  const retiros = [];
  let totalCobrado = 0;
  let totalDeudaPrev = 0;

  for (const [cli, saldoAnt] of Object.entries(saldosPrev)) {
    totalDeudaPrev += saldoAnt;
    const saldoAct = saldosHoy[cli] || 0;
    if (saldoAct < saldoAnt) {
      const pagado = saldoAnt - saldoAct;
      totalCobrado += pagado;
      retiros.push({ cliente: cli, pagado, tipo: saldoAct === 0 ? 'Total' : 'Parcial' });
    }
  }

  retiros.sort((a,b) => b.pagado - a.pagado);
  const topRetiros = retiros.slice(0, 7);

  if (topRetiros.length === 0) {
    elementos.listaSalidas.innerHTML = '<li class="empty">No hubo retiros</li>';
  } else {
    elementos.listaSalidas.innerHTML = topRetiros.map(r => `
      <li><strong>${r.cliente}</strong><span>Bs ${fmt(r.pagado)} <small>(${r.tipo})</small></span></li>
    `).join('');
  }

  setText('monto-cobrado', `Bs ${fmt(totalCobrado)}`);
  const pct = totalDeudaPrev > 0 ? (totalCobrado / totalDeudaPrev) * 100 : 0;
  setText('porcentaje-cobrado', `${pct.toFixed(1)}%`);
  
  const elPct = elementos.porcentajeCobrado;
  if(elPct) {
      elPct.className = 'value';
      elPct.style.color = pct > 10 ? '#4ade80' : (pct > 0 ? '#facc15' : '#f87171');
  }
}

function actualizarIngresosKpi() {
  if(!ingresosMensuales.length) return;
  
  const obj = ingresosMensuales.find(i => i.clave === estado.mesIngresos) || ingresosMensuales[0];
  estado.mesIngresos = obj.clave;
  
  if(elementos.selectMesIngresos) elementos.selectMesIngresos.value = obj.clave;
  
  const totalAnio = ingresosMensuales.filter(i=>i.anio===obj.anio).reduce((s,x)=>s+x.ingresoBs,0);
  const totalAnioUsd = ingresosMensuales.filter(i=>i.anio===obj.anio).reduce((s,x)=>s+x.ingresoUsd,0);

  const idx = ingresosMensuales.findIndex(i => i.clave === obj.clave);
  const previo = ingresosMensuales[idx + 1];
  
  let varMensual = 0;
  if (previo && previo.ingresoBs > 0) varMensual = ((obj.ingresoBs - previo.ingresoBs) / previo.ingresoBs) * 100;
  
  const ingUnidad = obj.unidades ? obj.ingresoBs/obj.unidades : 0;

  setText('ingresos-total-anio', `Bs ${fmt(totalAnio)}`);
  setText('ingresos-total-anio-detalle', `Acumulado ${obj.anio}`);
  setText('ingresos-total-anio-usd', `$${fmtUsd(totalAnioUsd)}`);
  
  setText('ingresos-mensual-bs', `Bs ${fmt(obj.ingresoBs)}`);
  setText('ingresos-mes-actual', `${obtenerNombreMes(obj.mesNumero)} ${obj.anio}`);
  setText('ingresos-mensual-usd', `$${fmtUsd(obj.ingresoUsd)}`);
  
  const elVar = elementos.ingresosVariacion;
  setText('ingresos-variacion', `${varMensual>=0?'+':''}${varMensual.toFixed(1)}%`);
  if(elVar) {
      elVar.className = 'value';
      elVar.classList.add(varMensual >= 0 ? 'trend-positive' : 'trend-negative'); 
  }

  setText('ingresos-flota', `${obj.unidades} uds`);
  setText('ingresos-flota-detalle', obj.composicion);
  setText('ingreso-por-unidad', `Bs ${fmt(ingUnidad)}`);
  
  // BARRA DE PROGRESO
  const elBar = elementos.progressBarFill;
  const elText = elementos.progressText;
  const elLeft = elementos.daysLeftText;
  
  if (elBar && elText && elLeft) {
      const now = new Date();
      if (now.getFullYear() === obj.anio && now.getMonth() === obj.mesNumero) {
          const totalDays = new Date(obj.anio, obj.mesNumero + 1, 0).getDate();
          const currentDay = now.getDate();
          const pct = Math.min(100, (currentDay / totalDays) * 100);
          elBar.style.width = `${pct}%`;
          elText.textContent = `Día ${currentDay} de ${totalDays}`;
          elLeft.textContent = `Faltan ${totalDays - currentDay} días`;
      } else if (new Date(obj.anio, obj.mesNumero, 1) < now) {
          elBar.style.width = '100%';
          elText.textContent = 'Mes Cerrado';
          elLeft.textContent = 'Completado';
      } else {
          elBar.style.width = '0%';
          elText.textContent = 'No iniciado';
          elLeft.textContent = 'Pendiente';
      }
  }

  renderGraficoIngresos();
}

function renderGraficoIngresos() {
  const elChart = elementos.chartIngresos;
  if (!elChart) return;
  if (charts.ingresos) charts.ingresos.destroy();

  const dataG = [...ingresosMensuales].sort((a,b) => (a.anio - b.anio) || (a.mesNumero - b.mesNumero));
  const ctx = elChart.getContext('2d');
  
  charts.ingresos = new Chart(ctx, {
      type: 'line',
      data: {
          labels: dataG.map(d => `${obtenerNombreMes(d.mesNumero).substring(0,3)} ${d.anio}`),
          datasets: [
              { 
                  label: 'Ingresos (Bs)', 
                  data: dataG.map(d => d.ingresoBs),
                  borderColor: '#ffffff',
                  backgroundColor: 'rgba(255,255,255,0.0)',
                  borderWidth: 2,
                  tension: 0.4,
                  pointRadius: 0,
                  pointHoverRadius: 6,
                  pointBackgroundColor: '#ffffff',
                  fill: true,
                  yAxisID: 'y'
              },
              { 
                  label: 'Flota (Uds)', 
                  data: dataG.map(d => d.unidades),
                  borderColor: 'rgba(255,255,255,0.5)', 
                  borderWidth: 2,
                  borderDash: [5, 5],
                  tension: 0.4,
                  pointRadius: 0,
                  pointHoverRadius: 6,
                  fill: false,
                  yAxisID: 'y1'
              }
          ]
      },
      options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: 'index', intersect: false },
          plugins: {
              legend: { labels: { color: '#ffffff' } },
              tooltip: { backgroundColor: 'rgba(0,0,0,0.9)', titleColor: '#fff', bodyColor: '#fff', borderColor: 'rgba(255,255,255,0.2)', borderWidth: 1 }
          },
          scales: {
              x: { ticks: { color: 'rgba(255,255,255,0.7)' }, grid: { display: false } },
              y: { position: 'left', ticks: { color: 'rgba(255,255,255,0.7)', callback: v => `Bs ${v/1000}k` }, grid: { color: 'rgba(255,255,255,0.1)', borderDash: [5, 5] } },
              y1: { position: 'right', ticks: { color: 'rgba(255,255,255,0.5)' }, grid: { display: false } }
          }
      }
  });
}

function renderCharts(data) {
  if (elementos.chartMensual) {
    if (charts.mensual) charts.mensual.destroy();
    if (data && data.length) {
        const porMes = {}; 
        data.forEach(d => porMes[d.mes_deuda] = (porMes[d.mes_deuda]||0) + d.monto_bs);
        const labelsMes = Object.keys(porMes).sort((a,b) => ordenMes(a)-ordenMes(b));
        
        charts.mensual = new Chart(elementos.chartMensual, {
          type: 'line',
          data: {
            labels: labelsMes,
            datasets: [{
              label: 'Monto Bs',
              data: labelsMes.map(m => porMes[m]),
              borderColor: '#0f172a',
              backgroundColor: 'rgba(15, 23, 42, 0.1)',
              fill: true,
              borderWidth: 2,
              tension: 0.35,
              pointRadius: 3,
              pointBackgroundColor: '#111827'
            }]
          },
          options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } } }
        });
    }
  }

  if (elementos.chartLocacion) {
    if (charts.locacion) charts.locacion.destroy();
    if (data && data.length) {
        const porLoc = {}; 
        data.forEach(d => porLoc[d.locacion] = (porLoc[d.locacion]||0) + d.monto_bs);
        charts.locacion = new Chart(elementos.chartLocacion, {
          type: 'doughnut',
          data: {
            labels: Object.keys(porLoc),
            datasets: [{
              data: Object.values(porLoc),
              backgroundColor: ['#0f172a', '#334155', '#64748b', '#94a3b8'],
              borderWidth: 0
            }]
          },
          options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'right', labels: { usePointStyle: true } } } }
        });
    }
  }
}

// --- UTILS ---
function configurarInteracciones() {
  elementos.calendarioToggle?.addEventListener('click', () => {
    calendarioAbierto = !calendarioAbierto;
    elementos.calendarioDropdown.classList.toggle('open', calendarioAbierto);
  });
  
  // CORRECCIÓN: Event listeners conectados correctamente
  elementos.selectMes?.addEventListener('change', (e) => { 
      estado.filtroMes = e.target.value; 
      // Solo refrescamos la tabla y charts de cuentas, no todo el dashboard
      const datosTabla = aplicarFiltrosTabla();
      renderTable(datosTabla);
  });
  
  elementos.selectLoc?.addEventListener('change', (e) => { 
      estado.filtroLoc = e.target.value; 
      const datosTabla = aplicarFiltrosTabla();
      renderTable(datosTabla);
  });
  
  elementos.selectCliente?.addEventListener('change', (e) => { 
    estado.cliente = e.target.value; 
    actualizarPanelCliente(dataFiltrada, estado.cliente, estado.mostrarGraficoCliente); 
  });
  
  elementos.selectMesIngresos?.addEventListener('change', (e) => {
    estado.mesIngresos = e.target.value;
    actualizarIngresosKpi();
  });
  
  elementos.paretoBotones?.forEach(btn => btn.addEventListener('click', (e) => {
    elementos.paretoBotones.forEach(b => b.classList.remove('active'));
    e.target.classList.add('active');
    estado.pareto = e.target.dataset.pareto;
    actualizarPareto(dataFiltrada, estado.pareto);
  }));
  
  if (elementos.btnDeudaMensual) {
      elementos.btnDeudaMensual.addEventListener('click', () => {
          estado.mostrarGraficoCliente = !estado.mostrarGraficoCliente;
          if(estado.mostrarGraficoCliente) elementos.btnDeudaMensual.classList.add('active');
          else elementos.btnDeudaMensual.classList.remove('active');
          actualizarPanelCliente(dataFiltrada, estado.cliente, estado.mostrarGraficoCliente);
      });
  }
}

function actualizarSelectorFecha() {
  const elDrop = elementos.calendarioDropdown;
  const elLabel = elementos.calendarioLabel;
  if (!elDrop) return;
  elLabel.textContent = estado.fecha || 'Sin Datos';
  
  elDrop.innerHTML = '<div class="calendar-list">' + fechasDisponibles.map(f => 
    `<div class="calendar-item ${f===estado.fecha?'selected':''}" onclick="document.dispatchEvent(new CustomEvent('cambioFecha', {detail:'${f}'}))">${f}</div>`
  ).join('') + '</div>';
  
  if (!window.eventoFechaConfigurado) {
      document.addEventListener('cambioFecha', (e) => {
          estado.fecha = e.detail;
          calendarioAbierto = false; 
          elDrop.classList.remove('open');
          refrescarTodo();
      });
      window.eventoFechaConfigurado = true;
  }
}

function actualizarOpcionesCliente() {
  if (!elementos.selectCliente) return;
  const clientes = [...new Set(dataFiltrada.map(d => d.cliente))].sort();
  elementos.selectCliente.innerHTML = '<option value="">Seleccionar...</option>' + clientes.map(c => `<option value="${c}">${c}</option>`).join('');
  
  if (!estado.cliente) {
      const parkano = clientes.find(c => c.toUpperCase().includes('PARKANO'));
      if (parkano) estado.cliente = parkano;
  }
  
  elementos.selectCliente.value = estado.cliente;
}

function actualizarPareto(data, tipo) {
    if(!elementos.paretoList) return;
    const sums = {}; data.forEach(d=>sums[d.cliente]=(sums[d.cliente]||0)+d.monto_bs);
    const sorted = Object.entries(sums).sort((a,b)=>b[1]-a[1]);
    const total = Object.values(sums).reduce((a,b)=>a+b,0);
    let acc = 0; const list = [];
    for(const [c,v] of sorted) {
        acc += v; const pct = acc/total;
        if(tipo==='80' && pct<=0.85) list.push({c,v});
        else if(tipo==='20' && pct>0.80) list.push({c,v});
    }
    if(tipo==='80' && !list.length && sorted.length) list.push({c:sorted[0][0], v:sorted[0][1]});
    elementos.paretoList.innerHTML = list.slice(0,10).map(i => `<li><strong>${i.c}</strong> <span>Bs ${fmt(i.v)}</span></li>`).join('');
}

function actualizarPanelCliente(data, cli, showGraph) {
    if(!cli || !data.length) {
        setText('cliente-nombre', '—');
        setText('cliente-total-bs', 'Bs 0');
        if(elementos.chartCliente) elementos.chartCliente.classList.add('is-hidden');
        return;
    }
    const recs = data.filter(d => d.cliente === cli);
    const tot = recs.reduce((s,i)=>s+i.monto_bs,0);
    const totUsd = recs.reduce((s,i)=>s+i.monto_usd,0);
    setText('cliente-nombre', cli);
    setText('cliente-total-bs', `Bs ${fmt(tot)}`);
    setText('cliente-total-usd', `$${fmtUsd(totUsd)}`);
    
    if(showGraph && elementos.chartCliente) {
        elementos.chartCliente.classList.remove('is-hidden');
        if(charts.cliente) charts.cliente.destroy();
        
        const historial = dataCompleta.filter(d => d.cliente === cli);
        const porMes = {}; 
        historial.forEach(d => porMes[d.mes_deuda] = (porMes[d.mes_deuda]||0) + d.monto_bs);
        
        const lbls = Object.keys(porMes).sort((a,b)=>ordenMes(a)-ordenMes(b));
        const ctx = elementos.chartCliente.getContext('2d');
        charts.cliente = new Chart(ctx, {
            type:'line', 
            data:{
                labels:lbls, 
                datasets:[{
                    label:'Deuda (Bs)', 
                    data:lbls.map(l=>porMes[l]), 
                    borderColor:'#ef233c', 
                    backgroundColor:'rgba(239,35,60,0.2)', 
                    fill:true, 
                    tension: 0.3
                }]
            },
            options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } } }
        });
    } else if(elementos.chartCliente) {
        elementos.chartCliente.classList.add('is-hidden');
    }
}

function obtenerFechasOrdenadas(data) {
  return [...new Set(data.map(d => d.fecha_estado))].sort().reverse();
}
function filtrarPorFecha(data, fecha) {
  return fecha ? data.filter(d => d.fecha_estado === fecha) : data;
}
function prepararSelectorIngresos() {
    if(elementos.selectMesIngresos) {
        elementos.selectMesIngresos.innerHTML = ingresosMensuales.map(i => {
            const nm = obtenerNombreMes(i.mesNumero);
            return `<option value="${i.clave}">${nm} ${i.anio}</option>`;
        }).join('');
    }
}
function agruparSaldoPorCliente(datos) {
  return datos.reduce((acc, i) => { acc[i.cliente] = (acc[i.cliente] || 0) + i.monto_bs; return acc; }, {});
}
function indiceMesNombre(n) {
  const m = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  let i = m.indexOf(n);
  if(i===-1) i = m.findIndex(x => x.startsWith(n.substring(0,3)));
  return i!==-1?i:null;
}
function obtenerNombreMes(idx) {
    const m = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return m[idx] || '';
}
function ordenMes(mes) {
  const [abr, y] = mes.toLowerCase().split('-');
  return (Number(y || 0) * 12) + indiceMesNombre(abr);
}
function fmt(n) { return Number(n).toLocaleString('es-BO', {minimumFractionDigits: 2, maximumFractionDigits: 2}); }
function fmtUsd(n) { return Number(n).toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}); }
function setText(id, txt) { 
    if(elementos[id]) elementos[id].textContent = txt; 
    else { const el = document.getElementById(id); if(el) el.textContent = txt; }
}