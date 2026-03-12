<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { Chart, registerables } from 'chart.js';
	import type { Partido, Distrito, Municipio } from '$lib/types/database';

	Chart.register(...registerables);

	let { data } = $props();

	// Estado
	let partidos: Partido[] = $state([]);
	let distritos: Distrito[] = $state([]);
	let municipios: Municipio[] = $state([]);
	let filtroMunicipio = $state('');
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
	let loadError = $state('');

	// DOM references via bind:this (reactive — triggers $effect when element mounts/unmounts)
	let barCanvas = $state<HTMLCanvasElement | undefined>(undefined);
	let donutCanvas = $state<HTMLCanvasElement | undefined>(undefined);
	let lineCanvas = $state<HTMLCanvasElement | undefined>(undefined);
	let mapEl = $state<HTMLDivElement | undefined>(undefined);

	// Non-reactive refs for cleanup
	let channel: any = null;
	let recalculateTimer: ReturnType<typeof setTimeout> | null = null;

	// Derived: current municipality object
	let municipioActual = $derived(municipios.find(m => m.id === filtroMunicipio));

	// Derived: districts filtered by selected municipality
	let distritosFiltered = $derived(
		filtroMunicipio ? distritos.filter(d => d.municipio_id === filtroMunicipio) : distritos
	);

	// Sanitize text for safe HTML insertion (prevent XSS)
	function escapeHtml(text: string): string {
		const div = document.createElement('div');
		div.textContent = text;
		return div.innerHTML;
	}

	// District coordinates by municipality
	const MUNICIPALITY_COORDS: Record<string, Record<number, [number, number]>> = {
		'WAR': {
			1: [-17.5103, -63.1647], // Central - Warnes centro
			2: [-17.4850, -63.1700], // Norte - Juan Latino
			3: [-17.5380, -63.1580], // Sur - Los Chacos
			4: [-17.5150, -63.1350], // Este - Asusaquí
			5: [-17.5050, -63.1950], // Oeste - Clara Chuchío
			6: [-17.5250, -63.1450]  // Industrial - Parque Industrial
		},
		'SCZ': {
			1: [-17.7833, -63.1822],  // Casco Viejo
			2: [-17.7650, -63.1820],  // Norte - Villa 1ro de Mayo
			3: [-17.7700, -63.1600],  // Noreste - Pampa de la Isla
			4: [-17.7950, -63.1500],  // Este - Plan 3000
			5: [-17.8050, -63.1550],  // Sureste - Los Lotes
			6: [-17.8100, -63.1800],  // Sur - El Bajío
			7: [-17.7900, -63.2050],  // Suroeste
			8: [-17.7700, -63.2100],  // Oeste - Equipetrol
			9: [-17.7600, -63.1950],  // Noroeste - Urbarí
			10: [-17.7400, -63.1750], // Norte Periurbano
			11: [-17.7850, -63.1350], // Este Periurbano
			12: [-17.8250, -63.1900], // Sur Periurbano
			13: [-17.7500, -63.1200], // Paurito
			14: [-17.7300, -63.2100], // Montero Hoyos
			15: [-17.8400, -63.1400]  // El Palmar del Oratorio
		}
	};

	function getDistrictCoords(distName: string): [number, number] | undefined {
		const codigo = municipioActual?.codigo ?? 'WAR';
		const coords = MUNICIPALITY_COORDS[codigo];
		if (!coords) return undefined;

		const distrito = distritos.find((d) => d.nombre === distName);
		if (distrito) return coords[distrito.numero];
		const numMatch = distName.match(/(\d+)/);
		if (numMatch) return coords[parseInt(numMatch[1])];
		return undefined;
	}

	// ─── Lifecycle ───

	onMount(async () => {
		await loadInitialData();
		setupRealtime();
	});

	onDestroy(() => {
		if (recalculateTimer) clearTimeout(recalculateTimer);
		if (channel) data.supabase.removeChannel(channel);
	});

	// ─── Chart effects (each manages its own lifecycle) ───

	// Bar chart
	$effect(() => {
		const canvas = barCanvas;
		if (!canvas) return;

		const sorted = Object.values(resultados).sort((a, b) => b.votos - a.votos);
		if (sorted.length === 0) return;

		const chart = new Chart(canvas, {
			type: 'bar',
			data: {
				labels: sorted.map((r) => r.sigla),
				datasets: [
					{
						data: sorted.map((r) => r.votos),
						backgroundColor: sorted.map((r) => r.color + '20'),
						borderColor: sorted.map((r) => r.color),
						borderWidth: 1.5,
						borderRadius: 6,
						barThickness: 28
					}
				]
			},
			options: {
				indexAxis: 'y',
				responsive: true,
				maintainAspectRatio: false,
				plugins: { legend: { display: false } },
				scales: {
					x: {
						grid: { color: '#f1f5f9' },
						ticks: { font: { size: 11, family: 'Inter' } }
					},
					y: {
						grid: { display: false },
						ticks: { font: { size: 12, weight: 'bold' as const, family: 'Inter' } }
					}
				}
			}
		});

		return () => {
			chart.destroy();
		};
	});

	// Donut chart
	$effect(() => {
		const canvas = donutCanvas;
		if (!canvas) return;

		const sorted = Object.values(resultados).sort((a, b) => b.votos - a.votos);
		if (sorted.length === 0) return;

		const top5 = sorted.slice(0, 5);
		const chart = new Chart(canvas, {
			type: 'doughnut',
			data: {
				labels: top5.map((r) => r.sigla),
				datasets: [
					{
						data: top5.map((r) => r.votos),
						backgroundColor: top5.map((r) => r.color),
						borderWidth: 3,
						borderColor: '#fff'
					}
				]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				cutout: '70%',
				plugins: {
					legend: {
						position: 'bottom',
						labels: {
							font: { size: 11, family: 'Inter' },
							padding: 16,
							usePointStyle: true,
							pointStyle: 'circle'
						}
					}
				}
			}
		});

		return () => {
			chart.destroy();
		};
	});

	// Line chart
	$effect(() => {
		const canvas = lineCanvas;
		if (!canvas) return;

		const evo = evolucion;
		if (evo.length === 0) return;

		const chart = new Chart(canvas, {
			type: 'line',
			data: {
				labels: evo.map((e) => e.hora),
				datasets: [
					{
						label: 'Actas procesadas',
						data: evo.map((e) => e.actas),
						borderColor: '#2563eb',
						backgroundColor: 'rgba(37, 99, 235, 0.05)',
						fill: true,
						tension: 0.4,
						pointRadius: 0,
						pointHoverRadius: 4,
						borderWidth: 2
					}
				]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				plugins: { legend: { display: false } },
				scales: {
					x: {
						grid: { display: false },
						ticks: { font: { size: 10, family: 'Inter' }, maxTicksLimit: 8 }
					},
					y: {
						grid: { color: '#f1f5f9' },
						beginAtZero: true,
						ticks: { font: { size: 10, family: 'Inter' } }
					}
				}
			}
		});

		return () => {
			chart.destroy();
		};
	});

	// Leaflet map
	$effect(() => {
		const el = mapEl;
		if (!el) return;

		// Read reactive deps so this re-runs when data changes
		const distData = resultadosPorDistrito;
		const _partidos = partidos;
		const _distritos = distritos;
		const muni = municipioActual;

		const mapCenter: [number, number] = muni
			? [muni.latitud, muni.longitud]
			: [-17.5103, -63.1647];
		const mapZoom = muni?.zoom_level ?? 13;

		let mapInstance: import('leaflet').Map | null = null;
		let active = true;

		import('leaflet').then((L) => {
			if (!active) return;

			mapInstance = L.map(el, {
				zoomControl: false,
				attributionControl: false
			}).setView(mapCenter, mapZoom);

			L.control.zoom({ position: 'topright' }).addTo(mapInstance);

			L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
				maxZoom: 19
			}).addTo(mapInstance);

			// Ensure tiles render after container is laid out
			setTimeout(() => mapInstance?.invalidateSize(), 200);

			// Add district markers
			if (Object.keys(distData).length === 0) return;

			for (const [distName, votes] of Object.entries(distData)) {
				const coords = getDistrictCoords(distName);
				if (!coords) continue;

				const totalDistVotes = Object.values(votes).reduce((s, v) => s + v, 0);
				if (totalDistVotes === 0) continue;

				let leadParty = '';
				let leadVotes = 0;
				for (const [sigla, v] of Object.entries(votes)) {
					if (v > leadVotes) {
						leadVotes = v;
						leadParty = sigla;
					}
				}

				const partido = _partidos.find((p) => p.sigla === leadParty);
				const color = partido?.color ?? '#6b7280';
				const safeColor = color.replace(/[^#a-fA-F0-9]/g, '');
				const radius = Math.max(300, Math.min(1200, totalDistVotes / 3));
				const safeDistName = escapeHtml(distName.replace('Distrito ', 'D'));
				const safeLeadParty = escapeHtml(leadParty);
				const pctStr =
					totalDistVotes > 0 ? ((leadVotes / totalDistVotes) * 100).toFixed(1) : '0';

				L.circle(coords, {
					radius,
					color: safeColor,
					fillColor: safeColor,
					fillOpacity: 0.25,
					weight: 2
				})
					.addTo(mapInstance!)
					.bindPopup(
						`<div style="font-family:Inter,sans-serif;min-width:140px">
						<div style="font-weight:700;font-size:13px;margin-bottom:4px">${safeDistName}</div>
						<div style="font-size:12px;color:#6b7280;margin-bottom:6px">${totalDistVotes.toLocaleString('es-BO')} votos</div>
						<div style="font-size:12px">
							<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${safeColor};margin-right:4px"></span>
							<strong>${safeLeadParty}</strong> — ${leadVotes.toLocaleString('es-BO')} (${pctStr}%)
						</div>
					</div>`
					);
			}
		});

		return () => {
			active = false;
			if (mapInstance) {
				mapInstance.remove();
				mapInstance = null;
			}
		};
	});

	// ─── Data loading ───

	async function loadInitialData() {
		loading = true;
		loadError = '';

		try {
			const [partidosRes, distritosRes, municipiosRes] = await Promise.all([
				data.supabase.from('partidos').select('*').order('orden'),
				data.supabase.from('distritos').select('*').order('numero'),
				data.supabase.from('municipios').select('*').order('nombre')
			]);

			if (partidosRes.error) throw partidosRes.error;
			if (distritosRes.error) throw distritosRes.error;

			partidos = partidosRes.data ?? [];
			distritos = distritosRes.data ?? [];
			municipios = municipiosRes.data ?? [];

			// Default to first municipality
			if (municipios.length > 0) {
				filtroMunicipio = municipios[0].id;
			}

			await recalculate();
		} catch {
			loadError = 'Error al cargar datos. Intenta recargar la página.';
		} finally {
			loading = false;
		}
	}

	async function recalculate() {
		const { data: rpcData, error: rpcError } = await data.supabase.rpc('get_dashboard_data', {
			p_municipio_id: filtroMunicipio || null,
			p_distrito_id: filtroDistrito || null
		});

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

		evolucion = (stats.evolucion ?? []).map((e: { hora: string; actas: number }) => ({
			hora: e.hora,
			actas: e.actas
		}));

		if (stats.por_distrito) {
			const distRes: Record<string, Record<string, number>> = {};
			for (const pd of stats.por_distrito) {
				distRes[pd.distrito_nombre] = pd.votos ?? {};
			}
			resultadosPorDistrito = distRes;
		}
	}

	async function recalculateLegacy() {
		// Build district filter based on municipality
		const municipioDistritos = filtroMunicipio
			? distritos.filter(d => d.municipio_id === filtroMunicipio)
			: distritos;
		const distritoIds = filtroDistrito
			? [filtroDistrito]
			: municipioDistritos.map(d => d.id);

		const mesasCount = await data.supabase
			.from('mesas')
			.select('*, recintos!inner(distrito_id)', { count: 'exact', head: true })
			.in('recintos.distrito_id', distritoIds);
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
		} else if (distritoIds.length > 0) {
			actasQuery = actasQuery.in('mesas.recintos.distrito_id', distritoIds);
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
				.from('votos')
				.select('partido_id, cantidad')
				.in('acta_id', actaIds);
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
			const hora = new Date(acta.created_at).toLocaleTimeString('es-BO', {
				hour: '2-digit',
				minute: '2-digit'
			});
			evoMap.set(hora, runningCount);
		}
		evolucion = [...evoMap.entries()].map(([hora, actas]) => ({ hora, actas }));

		const distRes: Record<string, Record<string, number>> = {};
		for (const d of municipioDistritos) {
			distRes[d.nombre] = {};
			for (const p of partidos) distRes[d.nombre][p.sigla] = 0;
		}
		if (actaIds.length > 0) {
			const { data: votosConActa, error: votosDistError } = await data.supabase
				.from('votos')
				.select(
					'partido_id, cantidad, actas!inner(mesas!inner(recintos!inner(distritos!inner(nombre))))'
				)
				.in('acta_id', actaIds);
			if (!votosDistError) {
				for (const v of votosConActa ?? []) {
					const distNombre = (v as any).actas?.mesas?.recintos?.distritos?.nombre;
					const partido = partidos.find((p) => p.id === v.partido_id);
					if (distNombre && partido && distRes[distNombre])
						distRes[distNombre][partido.sigla] += v.cantidad;
				}
			}
		}
		resultadosPorDistrito = distRes;
	}

	// ─── Realtime ───

	function debouncedRecalculate() {
		if (recalculateTimer) clearTimeout(recalculateTimer);
		recalculateTimer = setTimeout(async () => {
			try {
				await recalculate();
			} catch {
				// Silently ignore realtime refresh errors
			}
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

	// ─── Helpers ───

	function pct(votos: number): string {
		if (totalVotosValidos === 0) return '0.0';
		return ((votos / totalVotosValidos) * 100).toFixed(1);
	}

	function cobertura(): string {
		if (totalMesas === 0) return '0.0';
		return ((actasProcesadas / totalMesas) * 100).toFixed(1);
	}

	async function handleMunicipioChange() {
		filtroDistrito = ''; // Reset district filter when municipality changes
		try {
			await recalculate();
		} catch {
			loadError = 'Error al cambiar municipio.';
		}
	}

	async function handleFiltroChange() {
		try {
			await recalculate();
		} catch {
			loadError = 'Error al filtrar datos.';
		}
	}
</script>

<svelte:head>
	<title>Quantis - Dashboard Electoral</title>
</svelte:head>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 animate-in">
	<!-- Header -->
	<div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-8">
		<div class="flex items-center justify-between">
			<div>
				<h1 class="text-lg sm:text-xl font-extrabold text-slate-900 tracking-tight">Panel de Resultados</h1>
				<p class="text-[12px] sm:text-[13px] text-slate-400 mt-0.5 font-medium">Conteo rápido — {municipioActual?.nombre ?? 'Cargando'}</p>
			</div>
			<div class="sm:hidden flex items-center gap-2 text-[11px] font-semibold text-primary-600 bg-primary-50 border border-primary-100 px-2.5 py-1 rounded-full">
				<span class="w-1.5 h-1.5 rounded-full bg-primary-500 live-dot"></span>
				En vivo
			</div>
		</div>
		<div class="flex items-center gap-3">
			{#if municipios.length > 1}
				<select
					bind:value={filtroMunicipio}
					onchange={handleMunicipioChange}
					aria-label="Seleccionar municipio"
					class="input !w-full sm:!w-auto !py-2 !px-3 !text-[13px] !font-semibold"
				>
					{#each municipios as m}
						<option value={m.id}>{m.nombre}</option>
					{/each}
				</select>
			{/if}
			<select
				bind:value={filtroDistrito}
				onchange={handleFiltroChange}
				aria-label="Filtrar por distrito"
				class="input !w-full sm:!w-auto !py-2 !px-3 !text-[13px]"
			>
				<option value="">Todos los distritos</option>
				{#each distritosFiltered as d}
					<option value={d.id}>{d.nombre}</option>
				{/each}
			</select>
			<div class="hidden sm:flex items-center gap-2 text-[12px] font-semibold text-primary-600 bg-primary-50 border border-primary-100 px-3 py-1.5 rounded-full">
				<span class="w-2 h-2 rounded-full bg-primary-500 live-dot"></span>
				En vivo
			</div>
		</div>
	</div>

	{#if loadError}
		<div class="flex items-center gap-2.5 bg-danger-50 border border-danger-100 text-danger-600 text-sm rounded-xl px-4 py-3 mb-6">
			<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
				<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
			</svg>
			{loadError}
		</div>
	{/if}

	{#if loading}
		<div class="flex flex-col items-center justify-center py-24">
			<div class="w-10 h-10 rounded-xl bg-gradient-to-br from-primary-600 to-primary-800 flex items-center justify-center mb-4 shadow-lg shadow-primary-600/20">
				<span class="text-white font-extrabold text-sm">Q</span>
			</div>
			<div class="flex items-center gap-2.5 text-slate-400">
				<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
					<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
					<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
				</svg>
				<span class="text-sm font-medium">Cargando datos...</span>
			</div>
		</div>
	{:else}
		<!-- KPIs -->
		<div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
			<div class="card-flat p-5 kpi-card" style="--kpi-color: #3b82f6">
				<div class="flex items-center gap-2 mb-3">
					<div class="w-8 h-8 rounded-lg bg-primary-50 flex items-center justify-center">
						<svg class="w-4 h-4 text-primary-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
						</svg>
					</div>
					<p class="text-[12px] font-semibold text-slate-500">Actas Procesadas</p>
				</div>
				<p class="text-[22px] sm:text-[28px] font-extrabold text-slate-900 tabular-nums leading-none">{actasProcesadas}</p>
				<p class="text-[12px] text-slate-400 mt-2 font-medium">de {totalMesas} mesas</p>
			</div>

			<div class="card-flat p-5 kpi-card" style="--kpi-color: #2563eb">
				<div class="flex items-center gap-2 mb-3">
					<div class="w-8 h-8 rounded-lg bg-primary-50 flex items-center justify-center">
						<svg class="w-4 h-4 text-primary-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M10.5 6a7.5 7.5 0 107.5 7.5h-7.5V6z" />
							<path stroke-linecap="round" stroke-linejoin="round" d="M13.5 10.5H21A7.5 7.5 0 0013.5 3v7.5z" />
						</svg>
					</div>
					<p class="text-[12px] font-semibold text-slate-500">Cobertura</p>
				</div>
				<p class="text-[22px] sm:text-[28px] font-extrabold text-primary-600 tabular-nums leading-none">{cobertura()}%</p>
				<div class="mt-3 h-1.5 bg-slate-100 rounded-full overflow-hidden">
					<div class="h-full bg-gradient-to-r from-primary-500 to-primary-400 rounded-full transition-all duration-700" style="width: {cobertura()}%"></div>
				</div>
			</div>

			<div class="card-flat p-5 kpi-card" style="--kpi-color: #10b981">
				<div class="flex items-center gap-2 mb-3">
					<div class="w-8 h-8 rounded-lg bg-success-50 flex items-center justify-center">
						<svg class="w-4 h-4 text-success-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
						</svg>
					</div>
					<p class="text-[12px] font-semibold text-slate-500">Verificadas</p>
				</div>
				<p class="text-[22px] sm:text-[28px] font-extrabold text-slate-900 tabular-nums leading-none">{actasVerificadas}</p>
				<p class="text-[12px] text-slate-400 mt-2 font-medium">
					{actasProcesadas > 0 ? ((actasVerificadas / actasProcesadas) * 100).toFixed(0) : 0}% del total
				</p>
			</div>

			<div class="card-flat p-5 kpi-card" style="--kpi-color: #8b5cf6">
				<div class="flex items-center gap-2 mb-3">
					<div class="w-8 h-8 rounded-lg bg-violet-50 flex items-center justify-center">
						<svg class="w-4 h-4 text-violet-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
						</svg>
					</div>
					<p class="text-[12px] font-semibold text-slate-500">Total Votos</p>
				</div>
				<p class="text-[22px] sm:text-[28px] font-extrabold text-slate-900 tabular-nums leading-none">
					{(totalVotosValidos + totalNulos + totalBlancos).toLocaleString('es-BO')}
				</p>
				<p class="text-[12px] text-slate-400 mt-2 font-medium">
					{totalNulos.toLocaleString('es-BO')} nulos &middot; {totalBlancos.toLocaleString('es-BO')} blancos
				</p>
			</div>
		</div>

		<!-- Charts Row -->
		<div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
			<!-- Resultados tabla -->
			<div class="card p-6">
				<h2 class="section-title mb-5">Resultados por Partido</h2>
				<div class="space-y-3.5">
					{#each Object.values(resultados).sort((a, b) => b.votos - a.votos) as res, i}
						<div>
							<div class="flex items-center justify-between mb-1.5">
								<div class="flex items-center gap-2.5">
									<span class="text-[11px] font-bold text-slate-300 w-4 tabular-nums">{i + 1}</span>
									<span class="w-3 h-3 rounded-full shadow-sm" style="background-color: {res.color}"></span>
									<span class="text-[13px] font-semibold text-slate-800">{res.sigla}</span>
								</div>
								<div class="text-right flex items-baseline gap-1.5">
									<span class="text-[14px] font-extrabold text-slate-900 tabular-nums">{pct(res.votos)}%</span>
									<span class="text-[11px] text-slate-400 tabular-nums font-medium">({res.votos.toLocaleString('es-BO')})</span>
								</div>
							</div>
							<div class="h-2 bg-slate-50 rounded-full overflow-hidden ml-[26px]">
								<div
									class="h-full rounded-full transition-all duration-700 ease-out"
									style="width: {pct(res.votos)}%; background-color: {res.color}"
								></div>
							</div>
						</div>
					{/each}
				</div>
			</div>

			<!-- Bar chart -->
			<div class="card p-6">
				<h2 class="section-title mb-5">Votos por Partido</h2>
				<div class="h-64">
					<canvas bind:this={barCanvas}></canvas>
				</div>
			</div>

			<!-- Donut chart -->
			<div class="card p-6">
				<h2 class="section-title mb-5">Distribución</h2>
				<div class="h-64">
					<canvas bind:this={donutCanvas}></canvas>
				</div>
			</div>
		</div>

		<!-- Map + Evolution Row -->
		<div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
			<!-- Mapa -->
			<div class="card p-6">
				<div class="flex items-center justify-between mb-5">
					<h2 class="section-title">Mapa Electoral</h2>
					<div class="flex items-center gap-1.5 text-slate-400">
						<svg class="w-3.5 h-3.5 text-primary-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z" />
							<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z" />
						</svg>
						<span class="text-[12px] font-medium">{municipioActual?.nombre ?? ''}</span>
					</div>
				</div>
				<div bind:this={mapEl} class="h-72 rounded-xl overflow-hidden bg-slate-50 border border-slate-100"></div>
			</div>

			<!-- Evolucion temporal -->
			<div class="card p-6">
				<h2 class="section-title mb-5">Evolución del Conteo</h2>
				<div class="h-72">
					{#if evolucion.length > 0}
						<canvas bind:this={lineCanvas}></canvas>
					{:else}
						<div class="flex items-center justify-center h-full">
							<div class="text-center">
								<div class="w-12 h-12 rounded-xl bg-slate-50 flex items-center justify-center mx-auto mb-3">
									<svg class="w-6 h-6 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
										<path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75z" />
									</svg>
								</div>
								<p class="text-[13px] text-slate-400 font-medium">Se mostrará al procesar actas</p>
							</div>
						</div>
					{/if}
				</div>
			</div>
		</div>

		<!-- Tabla por distrito -->
		{#if !filtroDistrito && Object.keys(resultadosPorDistrito).length > 0}
			<div class="card p-6">
				<h2 class="section-title mb-5">Resultados por Distrito</h2>
				<div class="overflow-x-auto -mx-2">
					<table class="w-full text-sm">
						<thead>
							<tr class="border-b border-slate-100">
								<th class="text-left py-3 pr-4 pl-2 text-[11px] font-bold text-slate-400 uppercase tracking-wider">Distrito</th>
								{#each partidos as p}
									<th class="text-right py-3 px-2 text-[11px] font-bold uppercase tracking-wider" style="color: {p.color}">
										{p.sigla}
									</th>
								{/each}
								<th class="text-right py-3 pl-3 pr-2 text-[11px] font-bold text-slate-400 uppercase tracking-wider">Total</th>
							</tr>
						</thead>
						<tbody>
							{#each Object.entries(resultadosPorDistrito) as [distrito, votos]}
								{@const total = Object.values(votos).reduce((s, v) => s + v, 0)}
								{@const maxVotos = Math.max(...Object.values(votos))}
								<tr class="border-b border-slate-50 hover:bg-slate-50/80 transition-colors">
									<td class="py-3 pr-4 pl-2 text-[12px] text-slate-700 whitespace-nowrap font-semibold">{distrito.replace('Distrito ', 'D')}</td>
									{#each partidos as p}
										{@const v = votos[p.sigla] ?? 0}
										<td class="py-3 px-2 text-right text-[12px] tabular-nums {v === maxVotos && v > 0 ? 'font-bold text-slate-900' : 'text-slate-400'}">
											{v > 0 ? v.toLocaleString('es-BO') : '-'}
										</td>
									{/each}
									<td class="py-3 pl-3 pr-2 text-right text-[12px] font-bold text-slate-900 tabular-nums">
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
