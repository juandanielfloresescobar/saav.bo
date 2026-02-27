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
			error = 'Error al cargar datos iniciales. Verifica tu conexión.';
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
			success = 'Acta guardada localmente. Se enviará cuando haya conexión.';
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
				error = 'Error de conexión. Guardando acta localmente...';
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

<div class="max-w-2xl mx-auto px-4 py-8 animate-in">
	<!-- Header -->
	<div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-8">
		<div>
			<h1 class="text-lg sm:text-xl font-extrabold text-slate-900 tracking-tight">Ingesta de Actas</h1>
			<p class="text-[12px] sm:text-[13px] text-slate-400 mt-0.5 font-medium">Registra los datos del acta electoral</p>
		</div>
		<div class="flex items-center gap-2">
			{#if pendingCount > 0}
				<span class="badge bg-warning-50 border border-warning-100 text-warning-600">
					<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
						<path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
					</svg>
					{pendingCount} pendiente{pendingCount > 1 ? 's' : ''}
				</span>
			{/if}
			<div class="badge {online ? 'bg-primary-50 border border-primary-100 text-primary-600' : 'bg-slate-100 border border-slate-200 text-slate-500'}">
				<span class="w-2 h-2 rounded-full {online ? 'bg-primary-500 live-dot' : 'bg-slate-400'}"></span>
				{online ? 'En línea' : 'Sin conexión'}
			</div>
		</div>
	</div>

	{#if success}
		<div class="flex items-center gap-2.5 bg-success-50 border border-success-100 text-success-600 text-sm rounded-xl px-4 py-3 mb-6">
			<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
				<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
			</svg>
			{success}
		</div>
	{/if}

	{#if error}
		<div class="flex items-center gap-2.5 bg-danger-50 border border-danger-100 text-danger-600 text-sm rounded-xl px-4 py-3 mb-6">
			<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
				<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
			</svg>
			{error}
		</div>
	{/if}

	<form onsubmit={handleSubmit} class="space-y-5">
		<!-- Mesa -->
		<div class="card p-6">
			<h2 class="section-title mb-3">Mesa Electoral</h2>
			<select
				bind:value={selectedMesa}
				required
				class="input"
			>
				<option value="">Seleccionar mesa...</option>
				{#each mesas as mesa}
					<option value={mesa.id}>Mesa {mesa.numero} ({mesa.total_habilitados} habilitados)</option>
				{/each}
			</select>
		</div>

		<!-- Foto -->
		<div class="card p-6">
			<h2 class="section-title mb-3">Foto del Acta</h2>
			{#if fotoPreview}
				<div class="relative">
					<img src={fotoPreview} alt="Preview del acta" class="w-full rounded-xl" />
					<button
						type="button"
						onclick={() => { fotoFile = null; fotoPreview = ''; }}
						class="absolute top-3 right-3 bg-white/90 glass text-slate-500 w-8 h-8 rounded-full flex items-center justify-center shadow-lg hover:text-slate-700 transition-colors"
						aria-label="Eliminar foto"
					>
						<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</div>
			{:else}
				<label class="flex flex-col items-center justify-center w-full h-36 border-2 border-dashed border-slate-200 rounded-xl cursor-pointer hover:border-primary-300 hover:bg-primary-50/30 transition-all group">
					<div class="w-12 h-12 rounded-xl bg-slate-50 flex items-center justify-center mb-3 group-hover:bg-primary-50 transition-colors">
						<svg class="w-6 h-6 text-slate-300 group-hover:text-primary-400 transition-colors" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" />
							<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0z" />
						</svg>
					</div>
					<p class="text-[13px] text-slate-400 font-medium">
						{compressing ? 'Comprimiendo...' : 'Toca para capturar foto'}
					</p>
					<input type="file" accept="image/*" capture="environment" onchange={handleFoto} class="hidden" />
				</label>
			{/if}
		</div>

		<!-- Votos -->
		<div class="card p-6">
			<h2 class="section-title mb-4">Votos por Partido</h2>
			<div class="space-y-3">
				{#each partidos as partido}
					<div class="flex items-center justify-between gap-3">
						<div class="flex items-center gap-2.5 flex-1 min-w-0">
							<span class="w-3 h-3 rounded-full shrink-0 shadow-sm" style="background-color: {partido.color}"></span>
							<span class="text-[13px] text-slate-700 truncate font-medium">{partido.sigla}</span>
						</div>
						<input
							type="number"
							min="0"
							max="300"
							bind:value={votos[partido.id]}
							class="input !w-20 text-center !px-2 tabular-nums font-semibold"
						/>
					</div>
				{/each}

				<div class="border-t border-slate-100 pt-3 mt-3 space-y-3">
					<div class="flex items-center justify-between gap-3">
						<span class="text-[13px] text-slate-500 font-medium">Votos Nulos</span>
						<input
							type="number" min="0" max="300"
							bind:value={votosNulos}
							class="input !w-20 text-center !px-2 tabular-nums font-semibold"
						/>
					</div>
					<div class="flex items-center justify-between gap-3">
						<span class="text-[13px] text-slate-500 font-medium">Votos en Blanco</span>
						<input
							type="number" min="0" max="300"
							bind:value={votosBlancos}
							class="input !w-20 text-center !px-2 tabular-nums font-semibold"
						/>
					</div>
				</div>

				<div class="border-t border-slate-100 pt-3 mt-3">
					<div class="flex items-center justify-between gap-3">
						<span class="text-[13px] font-bold text-slate-900">Total Votantes</span>
						<input
							type="number" min="1" max="300"
							bind:value={totalVotantes}
							required
							class="input !w-20 text-center !px-2 tabular-nums font-bold"
						/>
					</div>

					<div class="flex items-center justify-between text-[12px] px-3.5 py-2.5 rounded-xl mt-3 font-semibold
						{totalVotantes > 0 && sumaVotos === totalVotantes
							? 'bg-success-50 border border-success-100 text-success-600'
							: totalVotantes > 0
								? 'bg-danger-50 border border-danger-100 text-danger-600'
								: 'bg-slate-50 border border-slate-100 text-slate-400'}">
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
			class="w-full btn-primary py-3.5 text-[15px]"
		>
			{#if loading}
				<span class="flex items-center justify-center gap-2">
					<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
						<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
						<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
					</svg>
					Enviando acta...
				</span>
			{:else if !online}
				Guardar localmente
			{:else}
				Enviar Acta
			{/if}
		</button>
	</form>

	<!-- Historial -->
	{#if historial.length > 0}
		<div class="mt-10">
			<h2 class="section-title mb-4">Actas Enviadas</h2>
			<div class="space-y-2.5">
				{#each historial as acta}
					<div class="card-flat px-5 py-3.5 flex items-center justify-between">
						<div>
							<span class="text-[13px] font-semibold text-slate-800">Mesa {acta.mesas?.numero}</span>
							<span class="text-[12px] text-slate-400 ml-2 font-medium">
								{new Date(acta.created_at).toLocaleString('es-BO', { hour: '2-digit', minute: '2-digit' })}
							</span>
						</div>
						<span class="badge
							{acta.estado === 'verificada'
								? 'bg-success-50 text-success-600'
								: acta.estado === 'observada'
									? 'bg-warning-50 text-warning-600'
									: acta.estado === 'rechazada'
										? 'bg-danger-50 text-danger-600'
										: 'bg-slate-50 text-slate-500'}">
							{acta.estado}
						</span>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</div>
