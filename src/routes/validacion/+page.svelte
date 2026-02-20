<script lang="ts">
	import { onMount } from 'svelte';
	import type { Acta, VotoDisplay, Distrito, EstadoActa, EstadoCounts } from '$lib/types/database';
	import { ESTADOS } from '$lib/types/database';

	let { data } = $props();

	let actas: Acta[] = $state([]);
	let selectedActa: Acta | null = $state(null);
	let votosActa: VotoDisplay[] = $state([]);
	let filtroEstado: EstadoActa = $state('pendiente');
	let filtroDistrito = $state('');
	let distritos: Distrito[] = $state([]);
	let loading = $state(false);
	let pageError = $state('');
	let observaciones = $state('');
	let counts: EstadoCounts = $state({ pendiente: 0, verificada: 0, observada: 0, rechazada: 0 });
	let hasMore = $state(false);
	const PAGE_SIZE = 50;

	onMount(async () => {
		await Promise.all([loadActas(), loadDistritos(), loadCounts()]);
	});

	async function loadDistritos() {
		const { data: d, error: distError } = await data.supabase.from('distritos').select('*').order('numero');
		if (!distError) distritos = d ?? [];
	}

	async function loadCounts() {
		// Try RPC first (single query), fall back to sequential counts
		const { data: rpcData, error: rpcError } = await data.supabase
			.rpc('get_acta_counts_by_estado');

		if (!rpcError && rpcData) {
			const fresh = { pendiente: 0, verificada: 0, observada: 0, rechazada: 0 };
			for (const row of rpcData) {
				if (row.estado in fresh) {
					fresh[row.estado as EstadoActa] = Number(row.count);
				}
			}
			counts = fresh;
		} else {
			const estados = ['pendiente', 'verificada', 'observada', 'rechazada'] as const;
			for (const estado of estados) {
				const { count } = await data.supabase
					.from('actas')
					.select('*', { count: 'exact', head: true })
					.eq('estado', estado);
				counts[estado] = count ?? 0;
			}
		}
	}

	async function loadActas(append = false) {
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
			.order('created_at', { ascending: true })
			.range(append ? actas.length : 0, (append ? actas.length : 0) + PAGE_SIZE - 1);

		if (filtroDistrito) {
			query = query.eq('mesas.recintos.distrito_id', filtroDistrito);
		}

		const { data: result, error: queryError } = await query;
		if (queryError) {
			pageError = 'Error al cargar actas. Intenta de nuevo.';
			loading = false;
			return;
		}
		const fetched = result ?? [];
		hasMore = fetched.length === PAGE_SIZE;

		if (append) {
			actas = [...actas, ...(fetched as unknown as Acta[])];
		} else {
			actas = fetched as unknown as Acta[];
		}
		loading = false;
	}

	async function selectActa(acta: Acta) {
		selectedActa = acta;
		observaciones = acta.observaciones ?? '';
		pageError = '';
		const { data: v, error: votosError } = await data.supabase
			.from('votos')
			.select('cantidad, partidos(sigla, color)')
			.eq('acta_id', acta.id);
		if (votosError) {
			pageError = 'Error al cargar los votos del acta.';
			return;
		}
		votosActa = (v ?? []) as unknown as VotoDisplay[];
	}

	async function updateEstado(nuevoEstado: EstadoActa) {
		if (!selectedActa) return;
		loading = true;
		pageError = '';

		const { data: updated, error: updateError } = await data.supabase
			.from('actas')
			.update({
				estado: nuevoEstado,
				verificado_por: data.perfil?.id,
				observaciones: observaciones || null,
				updated_at: new Date().toISOString()
			})
			.eq('id', selectedActa.id)
			.eq('estado', selectedActa.estado)
			.select();

		if (updateError) {
			pageError = 'Error al actualizar el acta. Intenta de nuevo.';
			loading = false;
			return;
		}

		if (!updated || updated.length === 0) {
			pageError = 'El acta fue modificada por otro usuario. Recargando...';
			selectedActa = null;
			votosActa = [];
			await Promise.all([loadActas(), loadCounts()]);
			loading = false;
			return;
		}

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
	<title>Quantis - Validación de Actas</title>
</svelte:head>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 animate-in">
	<div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-8">
		<div>
			<h1 class="text-lg sm:text-xl font-extrabold text-slate-900 tracking-tight">Validación de Actas</h1>
			<p class="text-[12px] sm:text-[13px] text-slate-400 mt-0.5 font-medium">Verifica las actas cargadas por delegados</p>
		</div>
		<select
			bind:value={filtroDistrito}
			onchange={() => loadActas()}
			aria-label="Filtrar por distrito"
			class="input !w-full sm:!w-auto !py-2 !px-3 !text-[13px]"
		>
			<option value="">Todos los distritos</option>
			{#each distritos as d}
				<option value={d.id}>{d.nombre}</option>
			{/each}
		</select>
	</div>

	{#if pageError}
		<div class="flex items-center gap-2.5 bg-danger-50 border border-danger-100 text-danger-600 text-sm rounded-xl px-4 py-3 mb-6">
			<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
				<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
			</svg>
			{pageError}
		</div>
	{/if}

	<!-- Contadores -->
	<div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-8">
		{#each ESTADOS as estado}
			{@const active = filtroEstado === estado}
			{@const cfg = estadoConfig[estado]}
			<button
				onclick={() => { filtroEstado = estado as EstadoActa; loadActas(); }}
				class="card-flat p-4 text-left transition-all
					{active ? 'ring-2 ring-primary-500/30 border-primary-400' : 'hover:border-slate-300'}"
			>
				<p class="text-[22px] sm:text-[26px] font-extrabold tabular-nums leading-none
					{estado === 'verificada' ? 'text-success-600' : estado === 'observada' ? 'text-warning-600' : estado === 'rechazada' ? 'text-danger-600' : 'text-slate-900'}">
					{counts[estado]}
				</p>
				<p class="text-[12px] text-slate-400 mt-2 font-semibold">{cfg.label}</p>
			</button>
		{/each}
	</div>

	<div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
		<!-- Lista de actas -->
		<div class="space-y-2.5">
			{#if loading && !selectedActa}
				<div class="flex items-center justify-center py-16">
					<div class="flex items-center gap-2.5 text-slate-400">
						<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
							<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
							<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
						</svg>
						<span class="text-sm font-medium">Cargando actas...</span>
					</div>
				</div>
			{:else if actas.length === 0}
				<div class="text-center py-16">
					<div class="w-14 h-14 rounded-xl bg-slate-50 flex items-center justify-center mx-auto mb-4">
						<svg class="w-7 h-7 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
						</svg>
					</div>
					<p class="text-[13px] text-slate-400 font-medium">No hay actas {filtroEstado === 'pendiente' ? 'pendientes' : 'con estado "' + filtroEstado + '"'}</p>
				</div>
			{:else}
				{#each actas as acta}
					<button
						onclick={() => selectActa(acta)}
						class="w-full text-left card-flat p-4 transition-all
							{selectedActa?.id === acta.id ? 'ring-2 ring-primary-500/30 border-primary-400' : 'hover:border-slate-300'}"
					>
						<div class="flex items-center justify-between mb-1.5">
							<span class="text-[13px] font-bold text-slate-800">Mesa {acta.mesas?.numero}</span>
							<span class="text-[12px] text-slate-400 font-medium">
								{new Date(acta.created_at).toLocaleString('es-BO', { hour: '2-digit', minute: '2-digit' })}
							</span>
						</div>
						<p class="text-[12px] text-slate-500 font-medium">{acta.mesas?.recintos?.nombre} — D{acta.mesas?.recintos?.distritos?.numero}</p>
						<p class="text-[11px] text-slate-400 mt-0.5">Delegado: {acta.usuarios?.nombre}</p>
					</button>
				{/each}

				{#if hasMore}
					<button
						onclick={() => loadActas(true)}
						disabled={loading}
						class="w-full py-3 text-[13px] font-semibold text-primary-600 hover:bg-primary-50 rounded-xl transition-colors disabled:opacity-50"
					>
						{loading ? 'Cargando...' : 'Cargar más actas'}
					</button>
				{/if}
			{/if}
		</div>

		<!-- Panel de verificación -->
		{#if selectedActa}
			<div class="card p-6 sticky top-24">
				<h3 class="text-[14px] font-bold text-slate-900 mb-5">
					Verificar — Mesa {selectedActa.mesas?.numero}
				</h3>

				{#if selectedActa.foto_url && selectedActa.foto_url.startsWith('https://')}
					<div class="mb-5">
						<img
							src={selectedActa.foto_url}
							alt="Acta electoral"
							class="w-full rounded-xl cursor-zoom-in shadow-sm"
						/>
					</div>
				{:else}
					<div class="mb-5 bg-slate-50 rounded-xl p-10 text-center border border-slate-100">
						<div class="w-10 h-10 rounded-lg bg-slate-100 flex items-center justify-center mx-auto mb-2">
							<svg class="w-5 h-5 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
								<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5a2.25 2.25 0 002.25-2.25V6.75a2.25 2.25 0 00-2.25-2.25H3.75A2.25 2.25 0 001.5 6.75v12a2.25 2.25 0 002.25 2.25z" />
							</svg>
						</div>
						<p class="text-[13px] text-slate-400 font-medium">Sin foto adjunta</p>
					</div>
				{/if}

				<div class="space-y-2 mb-5">
					<h4 class="section-title mb-3">Datos del Acta</h4>
					{#each votosActa as voto}
						<div class="flex items-center justify-between text-[13px] py-1">
							<div class="flex items-center gap-2.5">
								<span class="w-2.5 h-2.5 rounded-full shadow-sm" style="background-color: {voto.partidos?.color}"></span>
								<span class="text-slate-600 font-medium">{voto.partidos?.sigla}</span>
							</div>
							<span class="font-bold text-slate-900 tabular-nums">{voto.cantidad}</span>
						</div>
					{/each}
					<div class="border-t border-slate-100 pt-2.5 mt-2 space-y-1.5">
						<div class="flex justify-between text-[13px]">
							<span class="text-slate-400 font-medium">Nulos</span>
							<span class="text-slate-600 tabular-nums font-semibold">{selectedActa.votos_nulos}</span>
						</div>
						<div class="flex justify-between text-[13px]">
							<span class="text-slate-400 font-medium">Blancos</span>
							<span class="text-slate-600 tabular-nums font-semibold">{selectedActa.votos_blancos}</span>
						</div>
						<div class="flex justify-between text-[13px] font-bold pt-1">
							<span class="text-slate-900">Total</span>
							<span class="text-slate-900 tabular-nums">{selectedActa.total_votantes}</span>
						</div>
					</div>
				</div>

				<div class="mb-5">
					<label for="obs" class="block section-title mb-2">Observaciones</label>
					<textarea
						id="obs"
						bind:value={observaciones}
						rows="2"
						placeholder="Notas sobre esta acta..."
						class="input resize-none"
					></textarea>
				</div>

				<div class="grid grid-cols-3 gap-2.5">
					<button
						onclick={() => updateEstado('verificada' as EstadoActa)}
						disabled={loading}
						class="btn-primary py-2.5 text-[13px] text-center"
					>
						Verificar
					</button>
					<button
						onclick={() => updateEstado('observada' as EstadoActa)}
						disabled={loading}
						class="bg-white border-1.5 border-slate-200 hover:bg-slate-50 text-slate-700 text-[13px] font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-50"
					>
						Observar
					</button>
					<button
						onclick={() => updateEstado('rechazada' as EstadoActa)}
						disabled={loading}
						class="bg-white border-1.5 border-danger-200 hover:bg-danger-50 text-danger-600 text-[13px] font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-50"
					>
						Rechazar
					</button>
				</div>
			</div>
		{:else}
			<div class="hidden lg:flex bg-slate-50/50 border border-dashed border-slate-200 rounded-2xl items-center justify-center p-20">
				<div class="text-center">
					<div class="w-14 h-14 rounded-xl bg-white border border-slate-100 flex items-center justify-center mx-auto mb-4 shadow-sm">
						<svg class="w-7 h-7 text-slate-300" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
						</svg>
					</div>
					<p class="text-[13px] text-slate-400 font-medium">Selecciona un acta para verificar</p>
				</div>
			</div>
		{/if}
	</div>
</div>
