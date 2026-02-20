<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import { Chart, registerables } from 'chart.js';
	import type { Partido, Distrito, ResultadoPartido, EvolucionEntry } from '$lib/types/database';


	Chart.register(...registerables);

	let { data } = $props();

	// Estado
	let partidos: Partido[] = $state([]);
	let distritos: Distrito[] = $state([]);
	let filtroDistrito = $state('');
	let totalMesas = $state(0);
	let actasProcesadas = $state(0);
	let actasVerificadas = $state(0);
	let resultados: Record<string, { sigla: string; color: string; votos: number }> = $state({});
	let totalVotosValidos = $state(0);
	let totalNulos = $state(0);
	let totalBlancos = $state(0);
	let evolucion: { hora: string; actas: number }[] = $state([]);
	let resultadosPorDistrito: Record<string, Record<string, number>> = $state({});
	let loading = $state(true);

	// Chart instances
	let barChart: Chart | null = null;
	let donutChart: Chart | null = null;
	let lineChart: Chart | null = null;
	let channel: any = null;
	let map: import('leaflet').Map | null = null;

	// Sanitize text for safe HTML insertion (prevent XSS)
	function escapeHtml(text: string): string {
		const div = document.createElement('div');
		div.textContent = text;
		return div.innerHTML;
	}

	// Debounce timer for realtime updates
	let recalculateTimer: ReturnType<typeof setTimeout> | null = null;

	// District coordinates for Santa Cruz de la Sierra
	const districtCoords: Record<string, [number, number]> = {
		'Distrito 1 - Casco Viejo': [-17.7833, -63.1822],
		'Distrito 2 - Norte': [-17.7650, -63.1820],
		'Distrito 3 - Estacion Argentina': [-17.7920, -63.1680],
		'Distrito 4 - El Bajio': [-17.8050, -63.1830],
		'Distrito 5 - Pampa de la Isla': [-17.7780, -63.1530],
		'Distrito 6 - Villa 1ro de Mayo': [-17.7980, -63.1480],
		'Distrito 7 - UV Guaracachi': [-17.8150, -63.1600],
		'Distrito 8 - Plan 3000': [-17.8100, -63.1300],
		'Distrito 9 - Palmasola': [-17.7600, -63.2100],
		'Distrito 10 - El Urubo': [-17.7400, -63.2350],
		'Distrito 11 - Montero Hoyos': [-17.7250, -63.1850],
		'Distrito 12 - La Guardia': [-17.8500, -63.1900],
		'Distrito 13 - Nuevo Palmar': [-17.8300, -63.2200],
		'Distrito 14 - Paurito': [-17.8550, -63.1100],
		'Distrito 15 - Satelite Norte': [-17.7450, -63.1650]
	};

	onMount(async () => {
		await loadInitialData();
		setupRealtime();
	});

	// Reactively render charts when data changes and DOM is ready
	$effect(() => {
		// Read reactive dependencies to track them
		const _loading = loading;
		const _resultados = resultados;
		const _evolucion = evolucion;
		const _rpd = resultadosPorDistrito;

		if (_loading) return;

		// Wait for DOM to reflect state changes before rendering
		tick().then(() => {
			renderCharts();
			renderMap();
		});
	});

	onDestroy(() => {
		if (recalculateTimer) clearTimeout(recalculateTimer);
		if (channel) data.supabase.removeChannel(channel);
		barChart?.destroy();
		donutChart?.destroy();
		lineChart?.destroy();
		if (map) map.remove();
	});

	let loadError = $state('');

	async function loadInitialData() {
		loading = true;
		loadError = '';

		try {
			const [partidosRes, distritosRes] = await Promise.all([
				data.supabase.from('partidos').select('*').order('orden'),
				data.supabase.from('distritos').select('*').order('numero')
			]);

			if (partidosRes.error) throw partidosRes.error;
			if (distritosRes.error) throw distritosRes.error;

			partidos = partidosRes.data ?? [];
			distritos = distritosRes.data ?? [];

			await recalculate();
		} catch {
			loadError = 'Error al cargar datos. Intenta recargar la pagina.';
		} finally {
			loading = false;
		}
	}

	async function recalculate() {
		// Try optimized RPC first, fall back to legacy queries
		const { data: rpcData, error: rpcError } = await data.supabase
			.rpc('get_dashboard_data', { p_distrito_id: filtroDistrito || null });

		if (!rpcError && rpcData) {
			applyRpcData(rpcData);
		} else {
			await recalculateLegacy();
		}

	}

	function applyRpcData(stats: Record<string, any>) {
		totalMesas = stats.total_mesas ?? 0;
		actasProcesadas = stats.actas?.procesadas ?? 0;
		actasVerificadas = stats.actas?.verificadas ?? 0;
		totalNulos = stats.actas?.total_nulos ?? 0;
		totalBlancos = stats.actas?.total_blancos ?? 0;

		const res: Record<string, { sigla: string; color: string; votos: number }> = {};
		for (const vp of stats.votos_partido ?? []) {
			res[vp.id] = { sigla: vp.sigla, color: vp.color, votos: vp.votos };
		}
		resultados = res;
		totalVotosValidos = Object.values(res).reduce((s, r) => s + r.votos, 0);

		evolucion = (stats.evolucion ?? []).map((e: { hora: string; actas: number }) => ({ hora: e.hora, actas: e.actas }));

		if (!filtroDistrito && stats.por_distrito) {
			const distRes: Record<string, Record<string, number>> = {};
			for (const pd of stats.por_distrito) {
				distRes[pd.distrito_nombre] = pd.votos ?? {};
			}
			resultadosPorDistrito = distRes;
		}
	}

	async function recalculateLegacy() {
		const mesasCount = await data.supabase.from('mesas').select('*', { count: 'exact', head: true });
		if (mesasCount.error) throw new Error('Error al contar mesas');
		totalMesas = mesasCount.count ?? 0;

		let actasQuery = data.supabase
			.from('actas')
			.select(
				`id, estado, votos_nulos, votos_blancos, created_at,
				 mesas!inner(recinto_id, recintos!inner(distrito_id))`,
				{ count: 'exact' }
			);
		if (filtroDistrito) {
			actasQuery = actasQuery.eq('mesas.recintos.distrito_id', filtroDistrito);
		}

		const { data: actasData, count: actasCount, error: actasError } = await actasQuery;
		if (actasError) throw new Error('Error al cargar actas');
		actasProcesadas = actasCount ?? 0;
		actasVerificadas = actasData?.filter((a) => a.estado === 'verificada').length ?? 0;
		totalNulos = actasData?.reduce((s: number, a) => s + a.votos_nulos, 0) ?? 0;
		totalBlancos = actasData?.reduce((s: number, a) => s + a.votos_blancos, 0) ?? 0;

		const actaIds = actasData?.map((a) => a.id) ?? [];
		const res: Record<string, { sigla: string; color: string; votos: number }> = {};
		for (const p of partidos) res[p.id] = { sigla: p.sigla, color: p.color, votos: 0 };

		if (actaIds.length > 0) {
			const { data: votosData, error: votosError } = await data.supabase
				.from('votos').select('partido_id, cantidad').in('acta_id', actaIds);
			if (votosError) throw new Error('Error al cargar votos');
			for (const v of votosData ?? []) {
				if (res[v.partido_id]) res[v.partido_id].votos += v.cantidad;
			}
		}
		resultados = res;
		totalVotosValidos = Object.values(res).reduce((s, r) => s + r.votos, 0);

		const evoMap = new Map<string, number>();
		let runningCount = 0;
		const sorted = [...(actasData ?? [])].sort(
			(a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
		);
		for (const acta of sorted) {
			runningCount++;
			const hora = new Date(acta.created_at).toLocaleTimeString('es-BO', { hour: '2-digit', minute: '2-digit' });
			evoMap.set(hora, runningCount);
		}
		evolucion = [...evoMap.entries()].map(([hora, actas]) => ({ hora, actas }));

		if (!filtroDistrito) {
			const distRes: Record<string, Record<string, number>> = {};
			for (const d of distritos) {
				distRes[d.nombre] = {};
				for (const p of partidos) distRes[d.nombre][p.sigla] = 0;
			}
			if (actaIds.length > 0) {
				const { data: votosConActa, error: votosDistError } = await data.supabase
					.from('votos')
					.select('partido_id, cantidad, actas!inner(mesas!inner(recintos!inner(distritos!inner(nombre))))')
					.in('acta_id', actaIds);
				if (votosDistError) throw new Error('Error al cargar votos por distrito');
				for (const v of votosConActa ?? []) {
					const distNombre = (v as any).actas?.mesas?.recintos?.distritos?.nombre;
					const partido = partidos.find((p) => p.id === v.partido_id);
					if (distNombre && partido && distRes[distNombre]) distRes[distNombre][partido.sigla] += v.cantidad;
				}
			}
			resultadosPorDistrito = distRes;
		}
	}

	function renderCharts() {
		const sortedResults = Object.values(resultados).sort((a, b) => b.votos - a.votos);

		// Bar chart
		const barCanvas = document.getElementById('barChart') as HTMLCanvasElement;
		if (barCanvas) {
			barChart?.destroy();
			barChart = new Chart(barCanvas, {
				type: 'bar',
				data: {
					labels: sortedResults.map((r) => r.sigla),
					datasets: [{
						data: sortedResults.map((r) => r.votos),
						backgroundColor: sortedResults.map((r) => r.color + '20'),
						borderColor: sortedResults.map((r) => r.color),
						borderWidth: 1.5,
						borderRadius: 6,
						barThickness: 28
					}]
				},
				options: {
					indexAxis: 'y',
					responsive: true,
					maintainAspectRatio: false,
					plugins: { legend: { display: false } },
					scales: {
						x: { grid: { color: '#f3f4f6' }, ticks: { font: { size: 11, family: 'Inter' } } },
						y: { grid: { display: false }, ticks: { font: { size: 12, weight: 'bold' as const, family: 'Inter' } } }
					}
				}
			});
		}

		// Donut chart
		const donutCanvas = document.getElementById('donutChart') as HTMLCanvasElement;
		if (donutCanvas) {
			donutChart?.destroy();
			const top5 = sortedResults.slice(0, 5);
			donutChart = new Chart(donutCanvas, {
				type: 'doughnut',
				data: {
					labels: top5.map((r) => r.sigla),
					datasets: [{
						data: top5.map((r) => r.votos),
						backgroundColor: top5.map((r) => r.color),
						borderWidth: 3,
						borderColor: '#fff'
					}]
				},
				options: {
					responsive: true,
					maintainAspectRatio: false,
					cutout: '70%',
					plugins: {
						legend: { position: 'bottom', labels: { font: { size: 11, family: 'Inter' }, padding: 16, usePointStyle: true, pointStyle: 'circle' } }
					}
				}
			});
		}

		// Line chart
		const lineCanvas = document.getElementById('lineChart') as HTMLCanvasElement;
		if (lineCanvas && evolucion.length > 0) {
			lineChart?.destroy();
			lineChart = new Chart(lineCanvas, {
				type: 'line',
				data: {
					labels: evolucion.map((e) => e.hora),
					datasets: [{
						label: 'Actas procesadas',
						data: evolucion.map((e) => e.actas),
						borderColor: '#2563eb',
						backgroundColor: 'rgba(37, 99, 235, 0.05)',
						fill: true,
						tension: 0.4,
						pointRadius: 0,
						pointHoverRadius: 4,
						borderWidth: 2
					}]
				},
				options: {
					responsive: true,
					maintainAspectRatio: false,
					plugins: { legend: { display: false } },
					scales: {
						x: { grid: { display: false }, ticks: { font: { size: 10, family: 'Inter' }, maxTicksLimit: 8 } },
						y: { grid: { color: '#f3f4f6' }, beginAtZero: true, ticks: { font: { size: 10, family: 'Inter' } } }
					}
				}
			});
		}
	}

	async function renderMap() {
		const mapContainer = document.getElementById('mapContainer');
		if (!mapContainer || Object.keys(resultadosPorDistrito).length === 0) return;

		const L = await import('leaflet');

		if (map) map.remove();

		map = L.map('mapContainer', {
			zoomControl: false,
			attributionControl: false
		}).setView([-17.7833, -63.1822], 12);

		L.control.zoom({ position: 'topright' }).addTo(map);

		L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
			maxZoom: 19
		}).addTo(map);

		// Ensure map tiles render correctly after container is fully laid out
		setTimeout(() => map?.invalidateSize(), 200);

		// Add district markers
		for (const [distName, votes] of Object.entries(resultadosPorDistrito)) {
			const coords = districtCoords[distName];
			if (!coords) continue;

			const totalDistVotes = Object.values(votes).reduce((s, v) => s + v, 0);
			if (totalDistVotes === 0) continue;

			// Find leading party
			let leadParty = '';
			let leadVotes = 0;
			for (const [sigla, v] of Object.entries(votes)) {
				if (v > leadVotes) {
					leadVotes = v;
					leadParty = sigla;
				}
			}

			const partido = partidos.find((p) => p.sigla === leadParty);
			const color = partido?.color ?? '#6b7280';
			const safeColor = color.replace(/[^#a-fA-F0-9]/g, '');
			const radius = Math.max(300, Math.min(1200, totalDistVotes / 3));
			const safeDistName = escapeHtml(distName.replace('Distrito ', 'D'));
			const safeLeadParty = escapeHtml(leadParty);
			const pctStr = totalDistVotes > 0 ? ((leadVotes / totalDistVotes) * 100).toFixed(1) : '0';

			L.circle(coords, {
				radius,
				color: safeColor,
				fillColor: safeColor,
				fillOpacity: 0.25,
				weight: 2
			}).addTo(map).bindPopup(`
				<div style="font-family:Inter,sans-serif;min-width:140px">
					<div style="font-weight:700;font-size:13px;margin-bottom:4px">${safeDistName}</div>
					<div style="font-size:12px;color:#6b7280;margin-bottom:6px">${totalDistVotes.toLocaleString('es-BO')} votos</div>
					<div style="font-size:12px">
						<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${safeColor};margin-right:4px"></span>
						<strong>${safeLeadParty}</strong> — ${leadVotes.toLocaleString('es-BO')} (${pctStr}%)
					</div>
				</div>
			`);
		}
	}

	function debouncedRecalculate() {
		if (recalculateTimer) clearTimeout(recalculateTimer);
		recalculateTimer = setTimeout(() => {
			recalculate();
		}, 500);
	}

	function setupRealtime() {
		channel = data.supabase
			.channel('dashboard-live')
			.on('postgres_changes', { event: '*', schema: 'public', table: 'actas' }, () => {
				debouncedRecalculate();
			})
			.on('postgres_changes', { event: '*', schema: 'public', table: 'votos' }, () => {
				debouncedRecalculate();
			})
			.subscribe();
	}

	function pct(votos: number): string {
		if (totalVotosValidos === 0) return '0.0';
		return ((votos / totalVotosValidos) * 100).toFixed(1);
	}

	function cobertura(): string {
		if (totalMesas === 0) return '0.0';
		return ((actasProcesadas / totalMesas) * 100).toFixed(1);
	}

	async function handleFiltroChange() {
		await recalculate();
	}
</script>

<svelte:head>
	<title>Quantis - Dashboard Electoral</title>
</svelte:head>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
	<!-- Header -->
	<div class="flex items-center justify-between mb-6">
		<div>
			<h1 class="text-lg font-bold text-gray-900">Panel de Resultados</h1>
			<p class="text-xs text-gray-400 mt-0.5">Conteo rapido — Santa Cruz de la Sierra</p>
		</div>
		<div class="flex items-center gap-3">
			<select
				bind:value={filtroDistrito}
				onchange={handleFiltroChange}
				aria-label="Filtrar por distrito"
				class="px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 outline-none"
			>
				<option value="">Todos los distritos</option>
				{#each distritos as d}
					<option value={d.id}>{d.nombre}</option>
				{/each}
			</select>
			<span class="flex items-center gap-1.5 text-xs font-medium text-primary-600 bg-primary-50 px-2.5 py-1.5 rounded-full">
				<span class="w-1.5 h-1.5 rounded-full bg-primary-500 animate-pulse"></span>
				En vivo
			</span>
		</div>
	</div>

	{#if loadError}
		<div class="bg-red-50 text-red-600 text-sm rounded-lg px-4 py-3 mb-4">{loadError}</div>
	{/if}

	{#if loading}
		<div class="flex items-center justify-center py-20">
			<div class="flex items-center gap-2 text-gray-400">
				<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
					<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
					<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
				</svg>
				<span class="text-sm">Cargando datos...</span>
			</div>
		</div>
	{:else}
		<!-- KPIs -->
		<div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<div class="flex items-center gap-2 mb-2">
					<svg class="w-4 h-4 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
					</svg>
					<p class="text-xs text-gray-400">Actas Procesadas</p>
				</div>
				<p class="text-2xl font-bold text-gray-900 tabular-nums">{actasProcesadas}</p>
				<p class="text-xs text-gray-400 mt-1">de {totalMesas} mesas</p>
			</div>

			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<div class="flex items-center gap-2 mb-2">
					<svg class="w-4 h-4 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M10.5 6a7.5 7.5 0 107.5 7.5h-7.5V6z" />
						<path stroke-linecap="round" stroke-linejoin="round" d="M13.5 10.5H21A7.5 7.5 0 0013.5 3v7.5z" />
					</svg>
					<p class="text-xs text-gray-400">Cobertura</p>
				</div>
				<p class="text-2xl font-bold text-primary-600 tabular-nums">{cobertura()}%</p>
				<div class="mt-2 h-1 bg-gray-100 rounded-full overflow-hidden">
					<div class="h-full bg-primary-500 rounded-full transition-all" style="width: {cobertura()}%"></div>
				</div>
			</div>

			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<div class="flex items-center gap-2 mb-2">
					<svg class="w-4 h-4 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
					</svg>
					<p class="text-xs text-gray-400">Verificadas</p>
				</div>
				<p class="text-2xl font-bold text-gray-900 tabular-nums">{actasVerificadas}</p>
				<p class="text-xs text-gray-400 mt-1">
					{actasProcesadas > 0 ? ((actasVerificadas / actasProcesadas) * 100).toFixed(0) : 0}% del total
				</p>
			</div>

			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<div class="flex items-center gap-2 mb-2">
					<svg class="w-4 h-4 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
					</svg>
					<p class="text-xs text-gray-400">Total Votos</p>
				</div>
				<p class="text-2xl font-bold text-gray-900 tabular-nums">
					{(totalVotosValidos + totalNulos + totalBlancos).toLocaleString('es-BO')}
				</p>
				<p class="text-xs text-gray-400 mt-1">
					{totalNulos.toLocaleString('es-BO')} nulos · {totalBlancos.toLocaleString('es-BO')} blancos
				</p>
			</div>
		</div>

		<!-- Charts Row -->
		<div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
			<!-- Resultados tabla -->
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-4">Resultados por Partido</h2>
				<div class="space-y-3">
					{#each Object.values(resultados).sort((a, b) => b.votos - a.votos) as res, i}
						<div>
							<div class="flex items-center justify-between mb-1">
								<div class="flex items-center gap-2">
									<span class="text-xs font-bold text-gray-300 w-4">{i + 1}</span>
									<span class="w-2.5 h-2.5 rounded-full" style="background-color: {res.color}"></span>
									<span class="text-sm font-medium text-gray-900">{res.sigla}</span>
								</div>
								<div class="text-right">
									<span class="text-sm font-bold text-gray-900 tabular-nums">{pct(res.votos)}%</span>
									<span class="text-xs text-gray-400 ml-1 tabular-nums">({res.votos.toLocaleString('es-BO')})</span>
								</div>
							</div>
							<div class="h-1.5 bg-gray-50 rounded-full overflow-hidden ml-6">
								<div
									class="h-full rounded-full transition-all duration-500"
									style="width: {pct(res.votos)}%; background-color: {res.color}"
								></div>
							</div>
						</div>
					{/each}
				</div>
			</div>

			<!-- Bar chart -->
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-4">Votos por Partido</h2>
				<div class="h-64">
					<canvas id="barChart"></canvas>
				</div>
			</div>

			<!-- Donut chart -->
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-4">Distribucion</h2>
				<div class="h-64">
					<canvas id="donutChart"></canvas>
				</div>
			</div>
		</div>

		<!-- Map + Evolution Row -->
		<div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
			<!-- Mapa -->
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<div class="flex items-center justify-between mb-4">
					<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Mapa Electoral</h2>
					<div class="flex items-center gap-1">
						<svg class="w-3.5 h-3.5 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z" />
							<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z" />
						</svg>
						<span class="text-xs text-gray-400">Santa Cruz</span>
					</div>
				</div>
				<div id="mapContainer" class="h-72 rounded-lg overflow-hidden bg-gray-50"></div>
			</div>

			<!-- Evolucion temporal -->
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-4">Evolucion del Conteo</h2>
				<div class="h-72">
					{#if evolucion.length > 0}
						<canvas id="lineChart"></canvas>
					{:else}
						<div class="flex items-center justify-center h-full">
							<div class="text-center">
								<svg class="w-8 h-8 text-gray-200 mx-auto mb-2" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
									<path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75z" />
								</svg>
								<p class="text-xs text-gray-400">Se mostrara al procesar actas</p>
							</div>
						</div>
					{/if}
				</div>
			</div>
		</div>

		<!-- Tabla por distrito -->
		{#if !filtroDistrito && Object.keys(resultadosPorDistrito).length > 0}
			<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
				<h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-4">Resultados por Distrito</h2>
				<div class="overflow-x-auto">
					<table class="w-full text-sm">
						<thead>
							<tr class="border-b border-gray-100">
								<th class="text-left py-2.5 pr-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Distrito</th>
								{#each partidos as p}
									<th class="text-right py-2.5 px-2 text-xs font-semibold" style="color: {p.color}">
										{p.sigla}
									</th>
								{/each}
								<th class="text-right py-2.5 pl-3 text-xs font-semibold text-gray-400 uppercase tracking-wider">Total</th>
							</tr>
						</thead>
						<tbody>
							{#each Object.entries(resultadosPorDistrito) as [distrito, votos]}
								{@const total = Object.values(votos).reduce((s, v) => s + v, 0)}
								{@const maxVotos = Math.max(...Object.values(votos))}
								<tr class="border-b border-gray-50 hover:bg-gray-50/50 transition-colors">
									<td class="py-2.5 pr-4 text-xs text-gray-700 whitespace-nowrap font-medium">{distrito.replace('Distrito ', 'D')}</td>
									{#each partidos as p}
										{@const v = votos[p.sigla] ?? 0}
										<td class="py-2.5 px-2 text-right text-xs tabular-nums {v === maxVotos && v > 0 ? 'font-bold text-gray-900' : 'text-gray-500'}">
											{v > 0 ? v.toLocaleString('es-BO') : '-'}
										</td>
									{/each}
									<td class="py-2.5 pl-3 text-right text-xs font-semibold text-gray-900 tabular-nums">
										{total > 0 ? total.toLocaleString('es-BO') : '-'}
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		{/if}
	{/if}
</div>
