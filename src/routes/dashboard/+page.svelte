<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { Chart, registerables } from 'chart.js';

	Chart.register(...registerables);

	let { data } = $props();

	// Estado
	let partidos: any[] = $state([]);
	let distritos: any[] = $state([]);
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
	let distritoChart: Chart | null = null;
	let channel: any = null;

	onMount(async () => {
		await loadInitialData();
		setupRealtime();
	});

	onDestroy(() => {
		if (channel) data.supabase.removeChannel(channel);
		barChart?.destroy();
		donutChart?.destroy();
		lineChart?.destroy();
		distritoChart?.destroy();
	});

	async function loadInitialData() {
		loading = true;

		// Cargar catálogos
		const [partidosRes, distritosRes, mesasCount] = await Promise.all([
			data.supabase.from('partidos').select('*').order('orden'),
			data.supabase.from('distritos').select('*').order('numero'),
			data.supabase.from('mesas').select('*', { count: 'exact', head: true })
		]);

		partidos = partidosRes.data ?? [];
		distritos = distritosRes.data ?? [];
		totalMesas = mesasCount.count ?? 0;

		await recalculate();
		loading = false;
	}

	async function recalculate() {
		// Contar actas
		let actasQuery = data.supabase
			.from('actas')
			.select(
				`id, estado, total_votantes, votos_nulos, votos_blancos, created_at,
				 mesas!inner(recinto_id, recintos!inner(distrito_id))`,
				{ count: 'exact' }
			);

		if (filtroDistrito) {
			actasQuery = actasQuery.eq('mesas.recintos.distrito_id', filtroDistrito);
		}

		const { data: actasData, count: actasCount } = await actasQuery;
		actasProcesadas = actasCount ?? 0;
		actasVerificadas = actasData?.filter((a: any) => a.estado === 'verificada').length ?? 0;

		// Total nulos/blancos
		totalNulos = actasData?.reduce((s: number, a: any) => s + a.votos_nulos, 0) ?? 0;
		totalBlancos = actasData?.reduce((s: number, a: any) => s + a.votos_blancos, 0) ?? 0;

		// Votos por partido
		const actaIds = actasData?.map((a: any) => a.id) ?? [];
		const res: Record<string, { sigla: string; color: string; votos: number }> = {};
		for (const p of partidos) {
			res[p.id] = { sigla: p.sigla, color: p.color, votos: 0 };
		}

		if (actaIds.length > 0) {
			const { data: votosData } = await data.supabase
				.from('votos')
				.select('partido_id, cantidad')
				.in('acta_id', actaIds);

			for (const v of votosData ?? []) {
				if (res[v.partido_id]) {
					res[v.partido_id].votos += v.cantidad;
				}
			}
		}

		resultados = res;
		totalVotosValidos = Object.values(res).reduce((s, r) => s + r.votos, 0);

		// Evolución temporal
		const evoMap = new Map<string, number>();
		let runningCount = 0;
		const sorted = [...(actasData ?? [])].sort(
			(a: any, b: any) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
		);
		for (const acta of sorted) {
			runningCount++;
			const hora = new Date(acta.created_at).toLocaleTimeString('es-BO', {
				hour: '2-digit',
				minute: '2-digit'
			});
			evoMap.set(hora, runningCount);
		}
		evolucion = [...evoMap.entries()].map(([hora, actas]) => ({ hora, actas }));

		// Resultados por distrito
		if (!filtroDistrito) {
			const distRes: Record<string, Record<string, number>> = {};
			for (const d of distritos) {
				distRes[d.nombre] = {};
				for (const p of partidos) {
					distRes[d.nombre][p.sigla] = 0;
				}
			}

			if (actaIds.length > 0) {
				const { data: votosConActa } = await data.supabase
					.from('votos')
					.select('partido_id, cantidad, actas!inner(mesas!inner(recintos!inner(distritos!inner(nombre))))')
					.in('acta_id', actaIds);

				for (const v of votosConActa ?? []) {
					const distNombre = (v as any).actas?.mesas?.recintos?.distritos?.nombre;
					const partido = partidos.find((p: any) => p.id === v.partido_id);
					if (distNombre && partido && distRes[distNombre]) {
						distRes[distNombre][partido.sigla] += v.cantidad;
					}
				}
			}
			resultadosPorDistrito = distRes;
		}

		renderCharts();
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
					datasets: [
						{
							data: sortedResults.map((r) => r.votos),
							backgroundColor: sortedResults.map((r) => r.color),
							borderRadius: 6,
							barThickness: 32
						}
					]
				},
				options: {
					indexAxis: 'y',
					responsive: true,
					maintainAspectRatio: false,
					plugins: { legend: { display: false } },
					scales: {
						x: { grid: { display: false }, ticks: { font: { size: 11 } } },
						y: { grid: { display: false }, ticks: { font: { size: 12, weight: 'bold' as const } } }
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
					datasets: [
						{
							data: top5.map((r) => r.votos),
							backgroundColor: top5.map((r) => r.color),
							borderWidth: 2,
							borderColor: '#fff'
						}
					]
				},
				options: {
					responsive: true,
					maintainAspectRatio: false,
					cutout: '65%',
					plugins: {
						legend: { position: 'bottom', labels: { font: { size: 11 }, padding: 12 } }
					}
				}
			});
		}

		// Line chart (evolución)
		const lineCanvas = document.getElementById('lineChart') as HTMLCanvasElement;
		if (lineCanvas && evolucion.length > 0) {
			lineChart?.destroy();
			lineChart = new Chart(lineCanvas, {
				type: 'line',
				data: {
					labels: evolucion.map((e) => e.hora),
					datasets: [
						{
							label: 'Actas procesadas',
							data: evolucion.map((e) => e.actas),
							borderColor: '#1a56db',
							backgroundColor: 'rgba(26, 86, 219, 0.1)',
							fill: true,
							tension: 0.3,
							pointRadius: 2
						}
					]
				},
				options: {
					responsive: true,
					maintainAspectRatio: false,
					plugins: { legend: { display: false } },
					scales: {
						x: { grid: { display: false }, ticks: { font: { size: 10 }, maxTicksLimit: 10 } },
						y: { grid: { color: '#f1f5f9' }, beginAtZero: true }
					}
				}
			});
		}
	}

	function setupRealtime() {
		channel = data.supabase
			.channel('dashboard-live')
			.on('postgres_changes', { event: '*', schema: 'public', table: 'actas' }, () => {
				recalculate();
			})
			.on('postgres_changes', { event: '*', schema: 'public', table: 'votos' }, () => {
				recalculate();
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
	<div class="flex items-center justify-between mb-6">
		<div>
			<h1 class="text-xl font-bold text-gray-900">Panel de Resultados</h1>
			<p class="text-sm text-gray-500">Conteo rápido — Santa Cruz de la Sierra</p>
		</div>
		<div class="flex items-center gap-3">
			<select
				bind:value={filtroDistrito}
				onchange={handleFiltroChange}
				class="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 outline-none"
			>
				<option value="">Todos los distritos</option>
				{#each distritos as d}
					<option value={d.id}>{d.nombre}</option>
				{/each}
			</select>
			<span class="flex items-center gap-1.5 text-xs font-medium text-success-600 bg-success-500/10 px-2.5 py-1.5 rounded-full">
				<span class="w-2 h-2 rounded-full bg-success-500 animate-pulse"></span>
				En vivo
			</span>
		</div>
	</div>

	{#if loading}
		<div class="text-center py-20 text-gray-400">Cargando datos...</div>
	{:else}
		<!-- KPIs -->
		<div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<p class="text-xs text-gray-500 mb-1">Actas Procesadas</p>
				<p class="text-2xl font-bold text-gray-900">{actasProcesadas}</p>
				<p class="text-xs text-gray-400">de {totalMesas} mesas</p>
			</div>
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<p class="text-xs text-gray-500 mb-1">Cobertura</p>
				<p class="text-2xl font-bold text-primary-600">{cobertura()}%</p>
				<div class="mt-2 h-1.5 bg-gray-100 rounded-full overflow-hidden">
					<div class="h-full bg-primary-500 rounded-full transition-all" style="width: {cobertura()}%"></div>
				</div>
			</div>
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<p class="text-xs text-gray-500 mb-1">Verificadas</p>
				<p class="text-2xl font-bold text-success-600">{actasVerificadas}</p>
				<p class="text-xs text-gray-400">
					{actasProcesadas > 0 ? ((actasVerificadas / actasProcesadas) * 100).toFixed(0) : 0}% del total
				</p>
			</div>
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<p class="text-xs text-gray-500 mb-1">Total Votos</p>
				<p class="text-2xl font-bold text-gray-900">
					{(totalVotosValidos + totalNulos + totalBlancos).toLocaleString('es-BO')}
				</p>
				<p class="text-xs text-gray-400">
					{totalNulos} nulos · {totalBlancos} blancos
				</p>
			</div>
		</div>

		<!-- Resultados principales -->
		<div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
			<!-- Tabla de resultados -->
			<div class="bg-white rounded-xl border border-gray-200 p-5 lg:col-span-1">
				<h2 class="text-sm font-semibold text-gray-900 mb-4">Resultados por Partido</h2>
				<div class="space-y-3">
					{#each Object.values(resultados).sort((a, b) => b.votos - a.votos) as res}
						<div>
							<div class="flex items-center justify-between mb-1">
								<div class="flex items-center gap-2">
									<span class="w-3 h-3 rounded-full" style="background-color: {res.color}"></span>
									<span class="text-sm font-medium text-gray-900">{res.sigla}</span>
								</div>
								<div class="text-right">
									<span class="text-sm font-bold text-gray-900">{pct(res.votos)}%</span>
									<span class="text-xs text-gray-400 ml-1">({res.votos.toLocaleString('es-BO')})</span>
								</div>
							</div>
							<div class="h-2 bg-gray-100 rounded-full overflow-hidden">
								<div
									class="h-full rounded-full transition-all duration-500"
									style="width: {pct(res.votos)}%; background-color: {res.color}"
								></div>
							</div>
						</div>
					{/each}
				</div>
			</div>

			<!-- Gráfico de barras -->
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<h2 class="text-sm font-semibold text-gray-900 mb-4">Votos por Partido</h2>
				<div class="h-64">
					<canvas id="barChart"></canvas>
				</div>
			</div>

			<!-- Gráfico de dona -->
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<h2 class="text-sm font-semibold text-gray-900 mb-4">Distribución</h2>
				<div class="h-64">
					<canvas id="donutChart"></canvas>
				</div>
			</div>
		</div>

		<!-- Evolución temporal -->
		<div class="bg-white rounded-xl border border-gray-200 p-5 mb-6">
			<h2 class="text-sm font-semibold text-gray-900 mb-4">Evolución del Conteo</h2>
			<div class="h-48">
				{#if evolucion.length > 0}
					<canvas id="lineChart"></canvas>
				{:else}
					<div class="flex items-center justify-center h-full text-sm text-gray-400">
						Se mostrará la evolución cuando se procesen actas
					</div>
				{/if}
			</div>
		</div>

		<!-- Tabla detallada por partido y distrito (si no hay filtro de distrito) -->
		{#if !filtroDistrito && Object.keys(resultadosPorDistrito).length > 0}
			<div class="bg-white rounded-xl border border-gray-200 p-5">
				<h2 class="text-sm font-semibold text-gray-900 mb-4">Resultados por Distrito</h2>
				<div class="overflow-x-auto">
					<table class="w-full text-sm">
						<thead>
							<tr class="border-b border-gray-200">
								<th class="text-left py-2 pr-4 text-xs font-semibold text-gray-500">Distrito</th>
								{#each partidos as p}
									<th class="text-right py-2 px-2 text-xs font-semibold" style="color: {p.color}">
										{p.sigla}
									</th>
								{/each}
							</tr>
						</thead>
						<tbody>
							{#each Object.entries(resultadosPorDistrito) as [distrito, votos]}
								<tr class="border-b border-gray-50 hover:bg-gray-50">
									<td class="py-2 pr-4 text-xs text-gray-700 whitespace-nowrap">{distrito}</td>
									{#each partidos as p}
										<td class="py-2 px-2 text-right text-xs text-gray-600">
											{votos[p.sigla] ?? 0}
										</td>
									{/each}
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		{/if}
	{/if}
</div>
