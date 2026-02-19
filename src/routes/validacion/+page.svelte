<script lang="ts">
	import { onMount } from 'svelte';

	let { data } = $props();

	let actas: any[] = $state([]);
	let selectedActa: any = $state(null);
	let votosActa: any[] = $state([]);
	let filtroEstado = $state('pendiente');
	let filtroDistrito = $state('');
	let distritos: any[] = $state([]);
	let loading = $state(false);
	let observaciones = $state('');
	let counts = $state({ pendiente: 0, verificada: 0, observada: 0, rechazada: 0 });

	onMount(async () => {
		await Promise.all([loadActas(), loadDistritos(), loadCounts()]);
	});

	async function loadDistritos() {
		const { data: d } = await data.supabase.from('distritos').select('*').order('numero');
		distritos = d ?? [];
	}

	async function loadCounts() {
		const estados = ['pendiente', 'verificada', 'observada', 'rechazada'] as const;
		for (const estado of estados) {
			const { count } = await data.supabase
				.from('actas')
				.select('*', { count: 'exact', head: true })
				.eq('estado', estado);
			counts[estado] = count ?? 0;
		}
	}

	async function loadActas() {
		loading = true;
		let query = data.supabase
			.from('actas')
			.select(
				`id, mesa_id, delegado_id, foto_url, total_votantes, votos_nulos, votos_blancos,
				 estado, observaciones, created_at,
				 mesas!inner(numero, recinto_id, recintos!inner(nombre, distrito_id, distritos!inner(numero, nombre))),
				 usuarios!actas_delegado_id_fkey(nombre)`
			)
			.eq('estado', filtroEstado)
			.order('created_at', { ascending: true });

		if (filtroDistrito) {
			query = query.eq('mesas.recintos.distrito_id', filtroDistrito);
		}

		const { data: result } = await query;
		actas = result ?? [];
		loading = false;
	}

	async function selectActa(acta: any) {
		selectedActa = acta;
		observaciones = acta.observaciones ?? '';
		const { data: v } = await data.supabase
			.from('votos')
			.select('cantidad, partidos(sigla, color)')
			.eq('acta_id', acta.id);
		votosActa = v ?? [];
	}

	async function updateEstado(nuevoEstado: string) {
		if (!selectedActa) return;
		loading = true;

		await data.supabase
			.from('actas')
			.update({
				estado: nuevoEstado,
				verificado_por: data.perfil?.id,
				observaciones: observaciones || null,
				updated_at: new Date().toISOString()
			})
			.eq('id', selectedActa.id);

		selectedActa = null;
		votosActa = [];
		await Promise.all([loadActas(), loadCounts()]);
		loading = false;
	}

	const estadoConfig: Record<string, { label: string; color: string }> = {
		pendiente: { label: 'Pendientes', color: 'primary' },
		verificada: { label: 'Verificadas', color: 'success' },
		observada: { label: 'Observadas', color: 'warning' },
		rechazada: { label: 'Rechazadas', color: 'danger' }
	};
</script>

<svelte:head>
	<title>Quantis - Validacion de Actas</title>
</svelte:head>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
	<div class="flex items-center justify-between mb-6">
		<div>
			<h1 class="text-lg font-bold text-gray-900">Validacion de Actas</h1>
			<p class="text-xs text-gray-400 mt-0.5">Verifica las actas cargadas por delegados</p>
		</div>
		<select
			bind:value={filtroDistrito}
			onchange={() => loadActas()}
			class="px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 outline-none"
		>
			<option value="">Todos los distritos</option>
			{#each distritos as d}
				<option value={d.id}>{d.nombre}</option>
			{/each}
		</select>
	</div>

	<!-- Contadores -->
	<div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
		{#each ['pendiente', 'verificada', 'observada', 'rechazada'] as estado}
			{@const active = filtroEstado === estado}
			<button
				onclick={() => { filtroEstado = estado; loadActas(); }}
				class="bg-white rounded-xl border p-4 text-left transition-all shadow-sm
					{active ? 'border-primary-500 ring-1 ring-primary-200' : 'border-gray-100 hover:border-gray-200'}"
			>
				<p class="text-2xl font-bold {estado === 'verificada' ? 'text-success-600' : estado === 'observada' ? 'text-warning-600' : estado === 'rechazada' ? 'text-danger-600' : 'text-gray-900'}">
					{counts[estado]}
				</p>
				<p class="text-xs text-gray-400 mt-0.5">{estadoConfig[estado].label}</p>
			</button>
		{/each}
	</div>

	<div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
		<!-- Lista de actas -->
		<div class="space-y-2">
			{#if loading && !selectedActa}
				<div class="text-center py-12 text-gray-400 text-sm">Cargando actas...</div>
			{:else if actas.length === 0}
				<div class="text-center py-12">
					<svg class="w-10 h-10 text-gray-200 mx-auto mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
					</svg>
					<p class="text-sm text-gray-400">No hay actas {filtroEstado === 'pendiente' ? 'pendientes' : 'con estado "' + filtroEstado + '"'}</p>
				</div>
			{:else}
				{#each actas as acta}
					<button
						onclick={() => selectActa(acta)}
						class="w-full text-left bg-white rounded-lg border p-4 transition-all shadow-sm
							{selectedActa?.id === acta.id ? 'border-primary-500 ring-1 ring-primary-200' : 'border-gray-100 hover:border-gray-200'}"
					>
						<div class="flex items-center justify-between mb-1">
							<span class="text-sm font-semibold text-gray-900">Mesa {acta.mesas?.numero}</span>
							<span class="text-xs text-gray-400">
								{new Date(acta.created_at).toLocaleString('es-BO', { hour: '2-digit', minute: '2-digit' })}
							</span>
						</div>
						<p class="text-xs text-gray-500">{acta.mesas?.recintos?.nombre} — D{acta.mesas?.recintos?.distritos?.numero}</p>
						<p class="text-xs text-gray-400 mt-0.5">Delegado: {acta.usuarios?.nombre}</p>
					</button>
				{/each}
			{/if}
		</div>

		<!-- Panel de verificacion -->
		{#if selectedActa}
			<div class="bg-white rounded-xl border border-gray-100 p-5 sticky top-20 shadow-sm">
				<h3 class="text-sm font-semibold text-gray-900 mb-4">
					Verificar — Mesa {selectedActa.mesas?.numero}
				</h3>

				{#if selectedActa.foto_url}
					<div class="mb-4">
						<img
							src={selectedActa.foto_url}
							alt="Acta electoral"
							class="w-full rounded-lg cursor-zoom-in"
						/>
					</div>
				{:else}
					<div class="mb-4 bg-gray-50 rounded-lg p-8 text-center text-sm text-gray-400">
						Sin foto adjunta
					</div>
				{/if}

				<div class="space-y-2 mb-4">
					<h4 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Datos</h4>
					{#each votosActa as voto}
						<div class="flex items-center justify-between text-sm">
							<div class="flex items-center gap-2">
								<span class="w-2 h-2 rounded-full" style="background-color: {voto.partidos?.color}"></span>
								<span class="text-gray-600">{voto.partidos?.sigla}</span>
							</div>
							<span class="font-semibold text-gray-900 tabular-nums">{voto.cantidad}</span>
						</div>
					{/each}
					<div class="border-t border-gray-100 pt-2 space-y-1.5">
						<div class="flex justify-between text-sm">
							<span class="text-gray-400">Nulos</span>
							<span class="text-gray-600 tabular-nums">{selectedActa.votos_nulos}</span>
						</div>
						<div class="flex justify-between text-sm">
							<span class="text-gray-400">Blancos</span>
							<span class="text-gray-600 tabular-nums">{selectedActa.votos_blancos}</span>
						</div>
						<div class="flex justify-between text-sm font-semibold">
							<span class="text-gray-900">Total</span>
							<span class="text-gray-900 tabular-nums">{selectedActa.total_votantes}</span>
						</div>
					</div>
				</div>

				<div class="mb-4">
					<label for="obs" class="block text-xs font-medium text-gray-400 mb-1">Observaciones</label>
					<textarea
						id="obs"
						bind:value={observaciones}
						rows="2"
						placeholder="Notas sobre esta acta..."
						class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 focus:bg-white outline-none resize-none transition-all"
					></textarea>
				</div>

				<div class="grid grid-cols-3 gap-2">
					<button
						onclick={() => updateEstado('verificada')}
						disabled={loading}
						class="bg-primary-600 hover:bg-primary-700 text-white text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Verificar
					</button>
					<button
						onclick={() => updateEstado('observada')}
						disabled={loading}
						class="bg-white border border-gray-200 hover:bg-gray-50 text-gray-700 text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Observar
					</button>
					<button
						onclick={() => updateEstado('rechazada')}
						disabled={loading}
						class="bg-white border border-danger-200 hover:bg-danger-50 text-danger-600 text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Rechazar
					</button>
				</div>
			</div>
		{:else}
			<div class="bg-gray-50 rounded-xl flex items-center justify-center p-16">
				<div class="text-center">
					<svg class="w-10 h-10 text-gray-200 mx-auto mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
					</svg>
					<p class="text-sm text-gray-400">Selecciona un acta para verificar</p>
				</div>
			</div>
		{/if}
	</div>
</div>
