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
</script>

<svelte:head>
	<title>Quantis - Validación de Actas</title>
</svelte:head>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
	<h1 class="text-xl font-bold text-gray-900 mb-6">Validación de Actas</h1>

	<!-- Contadores -->
	<div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
		<button
			onclick={() => { filtroEstado = 'pendiente'; loadActas(); }}
			class="bg-white rounded-xl border p-4 text-left transition-colors {filtroEstado === 'pendiente' ? 'border-primary-500 ring-1 ring-primary-500' : 'border-gray-200'}"
		>
			<p class="text-2xl font-bold text-gray-900">{counts.pendiente}</p>
			<p class="text-xs text-gray-500">Pendientes</p>
		</button>
		<button
			onclick={() => { filtroEstado = 'verificada'; loadActas(); }}
			class="bg-white rounded-xl border p-4 text-left transition-colors {filtroEstado === 'verificada' ? 'border-success-500 ring-1 ring-success-500' : 'border-gray-200'}"
		>
			<p class="text-2xl font-bold text-success-600">{counts.verificada}</p>
			<p class="text-xs text-gray-500">Verificadas</p>
		</button>
		<button
			onclick={() => { filtroEstado = 'observada'; loadActas(); }}
			class="bg-white rounded-xl border p-4 text-left transition-colors {filtroEstado === 'observada' ? 'border-warning-500 ring-1 ring-warning-500' : 'border-gray-200'}"
		>
			<p class="text-2xl font-bold text-warning-600">{counts.observada}</p>
			<p class="text-xs text-gray-500">Observadas</p>
		</button>
		<button
			onclick={() => { filtroEstado = 'rechazada'; loadActas(); }}
			class="bg-white rounded-xl border p-4 text-left transition-colors {filtroEstado === 'rechazada' ? 'border-danger-500 ring-1 ring-danger-500' : 'border-gray-200'}"
		>
			<p class="text-2xl font-bold text-danger-600">{counts.rechazada}</p>
			<p class="text-xs text-gray-500">Rechazadas</p>
		</button>
	</div>

	<!-- Filtro distrito -->
	<div class="mb-4">
		<select
			bind:value={filtroDistrito}
			onchange={() => loadActas()}
			class="px-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 outline-none"
		>
			<option value="">Todos los distritos</option>
			{#each distritos as d}
				<option value={d.id}>{d.nombre}</option>
			{/each}
		</select>
	</div>

	<div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
		<!-- Lista de actas -->
		<div class="space-y-2">
			{#if loading && !selectedActa}
				<div class="text-center py-12 text-gray-400 text-sm">Cargando actas...</div>
			{:else if actas.length === 0}
				<div class="text-center py-12 text-gray-400 text-sm">
					No hay actas con estado "{filtroEstado}"
				</div>
			{:else}
				{#each actas as acta}
					<button
						onclick={() => selectActa(acta)}
						class="w-full text-left bg-white rounded-lg border p-4 hover:border-primary-300 transition-colors {selectedActa?.id === acta.id ? 'border-primary-500 ring-1 ring-primary-500' : 'border-gray-200'}"
					>
						<div class="flex items-center justify-between mb-1">
							<span class="text-sm font-medium text-gray-900">
								Mesa {acta.mesas?.numero}
							</span>
							<span class="text-xs text-gray-400">
								{new Date(acta.created_at).toLocaleString('es-BO', {
									hour: '2-digit',
									minute: '2-digit'
								})}
							</span>
						</div>
						<p class="text-xs text-gray-500">
							{acta.mesas?.recintos?.nombre} — D{acta.mesas?.recintos?.distritos?.numero}
						</p>
						<p class="text-xs text-gray-400 mt-0.5">
							Delegado: {acta.usuarios?.nombre}
						</p>
					</button>
				{/each}
			{/if}
		</div>

		<!-- Panel de verificación -->
		{#if selectedActa}
			<div class="bg-white rounded-xl border border-gray-200 p-5 sticky top-20">
				<h3 class="text-sm font-semibold text-gray-900 mb-4">
					Verificar Acta — Mesa {selectedActa.mesas?.numero}
				</h3>

				<!-- Foto del acta -->
				{#if selectedActa.foto_url}
					<div class="mb-4">
						<img
							src={selectedActa.foto_url}
							alt="Acta electoral"
							class="w-full rounded-lg border border-gray-200 cursor-zoom-in"
						/>
					</div>
				{:else}
					<div class="mb-4 bg-gray-50 rounded-lg p-8 text-center text-sm text-gray-400">
						Sin foto adjunta
					</div>
				{/if}

				<!-- Datos ingresados -->
				<div class="space-y-2 mb-4">
					<h4 class="text-xs font-semibold text-gray-500 uppercase tracking-wider">
						Datos Ingresados
					</h4>
					{#each votosActa as voto}
						<div class="flex items-center justify-between text-sm">
							<div class="flex items-center gap-2">
								<span
									class="w-2.5 h-2.5 rounded-full"
									style="background-color: {voto.partidos?.color}"
								></span>
								<span class="text-gray-700">{voto.partidos?.sigla}</span>
							</div>
							<span class="font-medium text-gray-900">{voto.cantidad}</span>
						</div>
					{/each}
					<hr class="border-gray-100" />
					<div class="flex justify-between text-sm">
						<span class="text-gray-500">Nulos</span>
						<span class="text-gray-700">{selectedActa.votos_nulos}</span>
					</div>
					<div class="flex justify-between text-sm">
						<span class="text-gray-500">Blancos</span>
						<span class="text-gray-700">{selectedActa.votos_blancos}</span>
					</div>
					<div class="flex justify-between text-sm font-semibold">
						<span class="text-gray-900">Total</span>
						<span class="text-gray-900">{selectedActa.total_votantes}</span>
					</div>
				</div>

				<!-- Observaciones -->
				<div class="mb-4">
					<label for="obs" class="block text-xs font-medium text-gray-500 mb-1">
						Observaciones
					</label>
					<textarea
						id="obs"
						bind:value={observaciones}
						rows="2"
						placeholder="Opcional: notas sobre esta acta..."
						class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 outline-none resize-none"
					></textarea>
				</div>

				<!-- Acciones -->
				<div class="grid grid-cols-3 gap-2">
					<button
						onclick={() => updateEstado('verificada')}
						disabled={loading}
						class="bg-success-500 hover:bg-success-600 text-white text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Verificar
					</button>
					<button
						onclick={() => updateEstado('observada')}
						disabled={loading}
						class="bg-warning-500 hover:bg-warning-600 text-white text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Observar
					</button>
					<button
						onclick={() => updateEstado('rechazada')}
						disabled={loading}
						class="bg-danger-500 hover:bg-danger-600 text-white text-sm font-medium py-2.5 rounded-lg transition-colors disabled:opacity-50"
					>
						Rechazar
					</button>
				</div>
			</div>
		{:else}
			<div class="bg-gray-50 rounded-xl border border-dashed border-gray-300 flex items-center justify-center p-12">
				<p class="text-sm text-gray-400">Selecciona un acta para verificar</p>
			</div>
		{/if}
	</div>
</div>
