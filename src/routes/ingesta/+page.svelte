<script lang="ts">
	import { onMount } from 'svelte';
	import { compressActaPhoto } from '$lib/utils/compress';
	import { validateActa } from '$lib/utils/validators';
	import { savePendingActa, getPendingActas, removePendingActa, isOnline } from '$lib/utils/offline';
	import type { Partido, Mesa, Acta } from '$lib/types/database';

	let { data } = $props();

	let mesas: Mesa[] = $state([]);
	let partidos: Partido[] = $state([]);
	let selectedMesa = $state('');
	let fotoFile: File | null = $state(null);
	let fotoPreview = $state('');
	let compressing = $state(false);
	let votos: Record<string, number> = $state({});
	let votosNulos = $state(0);
	let votosBlancos = $state(0);
	let totalVotantes = $state(0);
	let loading = $state(false);
	let success = $state('');
	let error = $state('');
	let historial: Acta[] = $state([]);
	let pendingCount = $state(0);
	let online = $state(true);
	let validation = $derived(validateActa(votos, votosNulos, votosBlancos, totalVotantes));
	let sumaVotos = $derived(
		Object.values(votos).reduce((s, v) => s + v, 0) + votosNulos + votosBlancos
	);

	onMount(async () => {
		online = isOnline();
		window.addEventListener('online', () => (online = true));
		window.addEventListener('offline', () => (online = false));

		await loadData();
		await loadHistorial();
		await syncPending();
	});

	async function loadData() {
		const recintoId = data.perfil?.recinto_id;

		try {
			const [mesasRes, partidosRes] = await Promise.all([
				recintoId
					? data.supabase
							.from('mesas')
							.select('id, numero, recinto_id, total_habilitados, recintos!inner(nombre)')
							.eq('recinto_id', recintoId)
							.order('numero')
					: Promise.resolve({ data: [], error: null }),
				data.supabase.from('partidos').select('*').order('orden')
			]);

			if (mesasRes.error) throw mesasRes.error;
			if (partidosRes.error) throw partidosRes.error;

			mesas = (mesasRes.data ?? []) as Mesa[];
			partidos = partidosRes.data ?? [];

			const v: Record<string, number> = {};
			for (const p of partidos) {
				v[p.id] = 0;
			}
			votos = v;
		} catch {
			error = 'Error al cargar datos iniciales. Verifica tu conexion.';
		}
	}

	async function loadHistorial() {
		const perfilId = data.perfil?.id;
		if (!perfilId) {
			historial = [];
			return;
		}

		const { data: actas, error: historialError } = await data.supabase
			.from('actas')
			.select('id, mesa_id, estado, created_at, mesas(numero)')
			.eq('delegado_id', perfilId)
			.order('created_at', { ascending: false });
		if (!historialError) historial = (actas ?? []) as unknown as Acta[];

		const pending = await getPendingActas();
		pendingCount = pending.length;
	}

	async function handleFoto(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		compressing = true;
		try {
			fotoFile = await compressActaPhoto(file);
			fotoPreview = URL.createObjectURL(fotoFile);
		} catch {
			fotoFile = file;
			fotoPreview = URL.createObjectURL(file);
		}
		compressing = false;
	}

	async function syncPending() {
		if (!online) return;
		const pending = await getPendingActas();
		let syncErrors = 0;
		for (const acta of pending) {
			try {
				await submitToSupabase(acta);
				await removePendingActa(acta.id);
			} catch (err: unknown) {
				syncErrors++;
				// Skip duplicate errors (already synced) and remove them
				if (err && typeof err === 'object' && 'code' in err && err.code === '23505') {
					await removePendingActa(acta.id);
					syncErrors--;
				}
				// Continue trying other actas instead of stopping
			}
		}
		pendingCount = (await getPendingActas()).length;
		if (syncErrors > 0 && pendingCount > 0) {
			error = `${syncErrors} acta(s) no se pudieron sincronizar. Se reintentara automaticamente.`;
		}
	}

	async function submitToSupabase(actaData: Record<string, any>) {
		let fotoUrl = null;
		if (actaData.foto) {
			const fileName = `${data.session?.user.id}/${Date.now()}.jpg`;
			const { error: uploadError } = await data.supabase.storage
				.from('actas-fotos')
				.upload(fileName, actaData.foto);
			if (!uploadError) {
				const { data: urlData } = data.supabase.storage
					.from('actas-fotos')
					.getPublicUrl(fileName);
				fotoUrl = urlData.publicUrl;
			}
		}

		const { data: actaResult, error: actaError } = await data.supabase
			.from('actas')
			.insert({
				mesa_id: actaData.mesa_id,
				delegado_id: data.perfil?.id,
				foto_url: fotoUrl,
				total_votantes: actaData.total_votantes,
				votos_nulos: actaData.votos_nulos,
				votos_blancos: actaData.votos_blancos
			})
			.select()
			.single();

		if (actaError) throw actaError;

		const votosInsert = Object.entries(actaData.votos)
			.filter(([, cantidad]) => (cantidad as number) >= 0)
			.map(([partido_id, cantidad]) => ({
				acta_id: actaResult.id,
				partido_id,
				cantidad
			}));

		const { error: votosError } = await data.supabase.from('votos').insert(votosInsert);
		if (votosError) throw votosError;
	}

	async function handleSubmit(e: Event) {
		e.preventDefault();
		if (!validation.valid) {
			error = validation.message;
			return;
		}

		loading = true;
		error = '';
		success = '';

		const actaData = {
			id: crypto.randomUUID(),
			mesa_id: selectedMesa,
			foto: fotoFile,
			votos: { ...votos },
			votos_nulos: votosNulos,
			votos_blancos: votosBlancos,
			total_votantes: totalVotantes,
			timestamp: Date.now()
		};

		if (!online) {
			await savePendingActa(actaData);
			success = 'Acta guardada localmente. Se enviara cuando haya conexion.';
			pendingCount++;
			resetForm();
			loading = false;
			return;
		}

		try {
			await submitToSupabase(actaData);
			success = 'Acta enviada correctamente.';
			await loadHistorial();
			resetForm();
		} catch (err: any) {
			const code = err?.code;
			const msg = err?.message ?? '';

			if (code === '23505') {
				error = 'Ya existe un acta registrada para esta mesa. No se puede duplicar.';
			} else if (code === '42501' || msg.includes('policy')) {
				error = 'No tienes permisos para registrar actas en esta mesa.';
			} else if (msg.includes('Failed to fetch') || msg.includes('NetworkError') || !navigator.onLine) {
				error = 'Error de conexion. Guardando acta localmente...';
				await savePendingActa(actaData);
				pendingCount++;
				resetForm();
			} else {
				error = 'Error al enviar el acta. Intenta de nuevo.';
				console.error('Submit error:', err);
			}
		}
		loading = false;
	}

	function resetForm() {
		selectedMesa = '';
		fotoFile = null;
		fotoPreview = '';
		votosNulos = 0;
		votosBlancos = 0;
		totalVotantes = 0;
		const v: Record<string, number> = {};
		for (const p of partidos) v[p.id] = 0;
		votos = v;
	}
</script>

<svelte:head>
	<title>Quantis - Ingesta de Actas</title>
</svelte:head>

<div class="max-w-2xl mx-auto px-4 py-6">
	<!-- Header -->
	<div class="flex items-center justify-between mb-6">
		<div>
			<h1 class="text-lg font-bold text-gray-900">Ingesta de Actas</h1>
			<p class="text-xs text-gray-400 mt-0.5">Registra los datos del acta electoral</p>
		</div>
		<div class="flex items-center gap-2">
			{#if pendingCount > 0}
				<span class="bg-warning-50 text-warning-600 text-xs font-medium px-2.5 py-1 rounded-full">
					{pendingCount} pendiente{pendingCount > 1 ? 's' : ''}
				</span>
			{/if}
			<span
				class="flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full
					{online ? 'bg-primary-50 text-primary-600' : 'bg-gray-100 text-gray-500'}"
			>
				<span class="w-1.5 h-1.5 rounded-full {online ? 'bg-primary-500' : 'bg-gray-400'}"></span>
				{online ? 'En linea' : 'Sin conexion'}
			</span>
		</div>
	</div>

	{#if success}
		<div class="bg-success-50 text-success-600 text-sm rounded-lg px-4 py-3 mb-4">
			{success}
		</div>
	{/if}

	{#if error}
		<div class="bg-danger-50 text-danger-600 text-sm rounded-lg px-4 py-3 mb-4">
			{error}
		</div>
	{/if}

	<form onsubmit={handleSubmit} class="space-y-4">
		<!-- Mesa -->
		<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
			<h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Mesa Electoral</h2>
			<select
				bind:value={selectedMesa}
				required
				class="w-full px-3.5 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all"
			>
				<option value="">Seleccionar mesa...</option>
				{#each mesas as mesa}
					<option value={mesa.id}>Mesa {mesa.numero} ({mesa.total_habilitados} habilitados)</option>
				{/each}
			</select>
		</div>

		<!-- Foto -->
		<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
			<h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Foto del Acta</h2>
			{#if fotoPreview}
				<div class="relative mb-3">
					<img src={fotoPreview} alt="Preview del acta" class="w-full rounded-lg" />
					<button
						type="button"
						onclick={() => { fotoFile = null; fotoPreview = ''; }}
						class="absolute top-2 right-2 bg-white text-gray-500 w-7 h-7 rounded-full flex items-center justify-center shadow-sm hover:text-gray-700"
						aria-label="Eliminar foto"
					>
						<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</div>
			{:else}
				<label class="flex flex-col items-center justify-center w-full h-32 border border-dashed border-gray-200 rounded-lg cursor-pointer hover:border-primary-300 hover:bg-primary-50/30 transition-all">
					<svg class="w-8 h-8 text-gray-300 mb-2" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" />
						<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0z" />
					</svg>
					<p class="text-xs text-gray-400">
						{compressing ? 'Comprimiendo...' : 'Toca para capturar foto'}
					</p>
					<input type="file" accept="image/*" capture="environment" onchange={handleFoto} class="hidden" />
				</label>
			{/if}
		</div>

		<!-- Votos -->
		<div class="bg-white rounded-xl border border-gray-100 p-5 shadow-sm">
			<h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Votos por Partido</h2>
			<div class="space-y-2.5">
				{#each partidos as partido}
					<div class="flex items-center justify-between gap-3">
						<div class="flex items-center gap-2 flex-1 min-w-0">
							<span class="w-2.5 h-2.5 rounded-full shrink-0" style="background-color: {partido.color}"></span>
							<span class="text-sm text-gray-700 truncate">{partido.sigla}</span>
						</div>
						<input
							type="number"
							min="0"
							max="300"
							bind:value={votos[partido.id]}
							class="w-20 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all"
						/>
					</div>
				{/each}

				<div class="border-t border-gray-100 pt-2.5 mt-2.5 space-y-2.5">
					<div class="flex items-center justify-between gap-3">
						<span class="text-sm text-gray-500">Votos Nulos</span>
						<input
							type="number" min="0" max="300"
							bind:value={votosNulos}
							class="w-20 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all"
						/>
					</div>
					<div class="flex items-center justify-between gap-3">
						<span class="text-sm text-gray-500">Votos en Blanco</span>
						<input
							type="number" min="0" max="300"
							bind:value={votosBlancos}
							class="w-20 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all"
						/>
					</div>
				</div>

				<div class="border-t border-gray-100 pt-2.5 mt-2.5">
					<div class="flex items-center justify-between gap-3">
						<span class="text-sm font-semibold text-gray-900">Total Votantes</span>
						<input
							type="number" min="1" max="300"
							bind:value={totalVotantes}
							required
							class="w-20 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-center font-semibold focus:ring-2 focus:ring-primary-500 focus:border-primary-500 focus:bg-white outline-none transition-all"
						/>
					</div>

					<div class="flex items-center justify-between text-xs px-3 py-2 rounded-lg mt-2.5
						{totalVotantes > 0 && sumaVotos === totalVotantes
							? 'bg-success-50 text-success-600'
							: totalVotantes > 0
								? 'bg-danger-50 text-danger-600'
								: 'bg-gray-50 text-gray-400'}">
						<span>Suma: {sumaVotos}</span>
						<span>
							{#if totalVotantes > 0 && sumaVotos === totalVotantes}
								Cuadra correctamente
							{:else if totalVotantes > 0}
								Diferencia: {Math.abs(sumaVotos - totalVotantes)}
							{:else}
								Ingresa los votos
							{/if}
						</span>
					</div>
				</div>
			</div>
		</div>

		<button
			type="submit"
			disabled={loading || !selectedMesa || !validation.valid}
			class="w-full bg-primary-600 hover:bg-primary-700 text-white font-semibold py-3 px-4 rounded-xl transition-colors disabled:opacity-40 disabled:cursor-not-allowed text-sm"
		>
			{#if loading}
				Enviando acta...
			{:else if !online}
				Guardar localmente
			{:else}
				Enviar Acta
			{/if}
		</button>
	</form>

	<!-- Historial -->
	{#if historial.length > 0}
		<div class="mt-8">
			<h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Actas Enviadas</h2>
			<div class="space-y-2">
				{#each historial as acta}
					<div class="bg-white rounded-lg border border-gray-100 px-4 py-3 flex items-center justify-between shadow-sm">
						<div>
							<span class="text-sm font-medium text-gray-900">Mesa {acta.mesas?.numero}</span>
							<span class="text-xs text-gray-400 ml-2">
								{new Date(acta.created_at).toLocaleString('es-BO', { hour: '2-digit', minute: '2-digit' })}
							</span>
						</div>
						<span class="text-xs font-medium px-2 py-0.5 rounded-full
							{acta.estado === 'verificada'
								? 'bg-success-50 text-success-600'
								: acta.estado === 'observada'
									? 'bg-warning-50 text-warning-600'
									: acta.estado === 'rechazada'
										? 'bg-danger-50 text-danger-600'
										: 'bg-gray-50 text-gray-500'}">
							{acta.estado}
						</span>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</div>
