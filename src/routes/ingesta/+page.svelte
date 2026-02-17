<script lang="ts">
	import { onMount } from 'svelte';
	import { compressActaPhoto } from '$lib/utils/compress';
	import { validateActa } from '$lib/utils/validators';
	import { savePendingActa, getPendingActas, removePendingActa, isOnline } from '$lib/utils/offline';

	let { data } = $props();

	// Estado
	let mesas: any[] = $state([]);
	let partidos: any[] = $state([]);
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
	let historial: any[] = $state([]);
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
		const [mesasRes, partidosRes] = await Promise.all([
			data.supabase
				.from('mesas')
				.select('id, numero, recinto_id, total_habilitados, recintos!inner(nombre, id)')
				.eq('recintos.id', data.perfil?.recinto_id)
				.order('numero'),
			data.supabase.from('partidos').select('*').order('orden')
		]);

		mesas = mesasRes.data ?? [];
		partidos = partidosRes.data ?? [];

		// Inicializar votos para cada partido
		const v: Record<string, number> = {};
		for (const p of partidos) {
			v[p.id] = 0;
		}
		votos = v;
	}

	async function loadHistorial() {
		const { data: actas } = await data.supabase
			.from('actas')
			.select('id, mesa_id, estado, created_at, mesas(numero)')
			.eq('delegado_id', data.perfil?.id ?? '')
			.order('created_at', { ascending: false });
		historial = actas ?? [];

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
		for (const acta of pending) {
			try {
				await submitToSupabase(acta);
				await removePendingActa(acta.id);
			} catch {
				break;
			}
		}
		pendingCount = (await getPendingActas()).length;
	}

	async function submitToSupabase(actaData: any) {
		// Subir foto si existe
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

		// Insertar acta
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

		// Insertar votos
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
			error = err.message || 'Error al enviar el acta.';
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
	<!-- Status bar -->
	<div class="flex items-center justify-between mb-6">
		<h1 class="text-xl font-bold text-gray-900">Ingesta de Actas</h1>
		<div class="flex items-center gap-2">
			{#if pendingCount > 0}
				<span class="bg-warning-500/10 text-warning-600 text-xs font-medium px-2.5 py-1 rounded-full">
					{pendingCount} pendiente{pendingCount > 1 ? 's' : ''}
				</span>
			{/if}
			<span
				class="flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full {online
					? 'bg-success-500/10 text-success-600'
					: 'bg-danger-500/10 text-danger-600'}"
			>
				<span class="w-2 h-2 rounded-full {online ? 'bg-success-500' : 'bg-danger-500'}"></span>
				{online ? 'En línea' : 'Sin conexión'}
			</span>
		</div>
	</div>

	{#if success}
		<div class="bg-success-500/10 border border-success-500/20 text-success-600 text-sm rounded-lg px-4 py-3 mb-4">
			{success}
		</div>
	{/if}

	{#if error}
		<div class="bg-danger-500/10 border border-danger-500/20 text-danger-600 text-sm rounded-lg px-4 py-3 mb-4">
			{error}
		</div>
	{/if}

	<!-- Formulario -->
	<form onsubmit={handleSubmit} class="space-y-6">
		<!-- Selección de mesa -->
		<div class="bg-white rounded-xl border border-gray-200 p-5">
			<h2 class="text-sm font-semibold text-gray-900 mb-3">Mesa Electoral</h2>
			<select
				bind:value={selectedMesa}
				required
				class="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
			>
				<option value="">Seleccionar mesa...</option>
				{#each mesas as mesa}
					<option value={mesa.id}>Mesa {mesa.numero} ({mesa.total_habilitados} habilitados)</option>
				{/each}
			</select>
		</div>

		<!-- Foto del acta -->
		<div class="bg-white rounded-xl border border-gray-200 p-5">
			<h2 class="text-sm font-semibold text-gray-900 mb-3">Foto del Acta</h2>
			{#if fotoPreview}
				<div class="relative mb-3">
					<img src={fotoPreview} alt="Preview del acta" class="w-full rounded-lg border border-gray-200" />
					<button
						type="button"
						onclick={() => {
							fotoFile = null;
							fotoPreview = '';
						}}
						class="absolute top-2 right-2 bg-white/90 text-gray-600 w-8 h-8 rounded-full flex items-center justify-center hover:bg-white shadow"
					>
						x
					</button>
				</div>
			{:else}
				<label
					class="flex flex-col items-center justify-center w-full h-40 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:border-primary-400 hover:bg-primary-50/50 transition-colors"
				>
					<div class="text-center">
						<p class="text-sm text-gray-500 mb-1">
							{compressing ? 'Comprimiendo foto...' : 'Toca para tomar foto del acta'}
						</p>
						<p class="text-xs text-gray-400">Se comprimirá automáticamente</p>
					</div>
					<input
						type="file"
						accept="image/*"
						capture="environment"
						onchange={handleFoto}
						class="hidden"
					/>
				</label>
			{/if}
		</div>

		<!-- Votos por partido -->
		<div class="bg-white rounded-xl border border-gray-200 p-5">
			<h2 class="text-sm font-semibold text-gray-900 mb-3">Votos por Partido</h2>
			<div class="space-y-3">
				{#each partidos as partido}
					<div class="flex items-center justify-between gap-3">
						<div class="flex items-center gap-2 flex-1 min-w-0">
							<span
								class="w-3 h-3 rounded-full shrink-0"
								style="background-color: {partido.color}"
							></span>
							<span class="text-sm text-gray-700 truncate">{partido.sigla}</span>
						</div>
						<input
							type="number"
							min="0"
							max="300"
							bind:value={votos[partido.id]}
							class="w-20 px-3 py-2 border border-gray-300 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
						/>
					</div>
				{/each}

				<hr class="border-gray-100" />

				<div class="flex items-center justify-between gap-3">
					<span class="text-sm text-gray-700">Votos Nulos</span>
					<input
						type="number"
						min="0"
						max="300"
						bind:value={votosNulos}
						class="w-20 px-3 py-2 border border-gray-300 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
					/>
				</div>

				<div class="flex items-center justify-between gap-3">
					<span class="text-sm text-gray-700">Votos en Blanco</span>
					<input
						type="number"
						min="0"
						max="300"
						bind:value={votosBlancos}
						class="w-20 px-3 py-2 border border-gray-300 rounded-lg text-sm text-center focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
					/>
				</div>

				<hr class="border-gray-100" />

				<div class="flex items-center justify-between gap-3">
					<span class="text-sm font-semibold text-gray-900">Total Votantes</span>
					<input
						type="number"
						min="1"
						max="300"
						bind:value={totalVotantes}
						required
						class="w-20 px-3 py-2 border border-gray-300 rounded-lg text-sm text-center font-semibold focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
					/>
				</div>

				<!-- Validación visual -->
				<div
					class="flex items-center justify-between text-xs px-3 py-2 rounded-lg {totalVotantes > 0 && sumaVotos === totalVotantes
						? 'bg-success-500/10 text-success-600'
						: totalVotantes > 0
							? 'bg-danger-500/10 text-danger-600'
							: 'bg-gray-50 text-gray-400'}"
				>
					<span>Suma de votos: {sumaVotos}</span>
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

		<!-- Botón enviar -->
		<button
			type="submit"
			disabled={loading || !selectedMesa || !validation.valid}
			class="w-full bg-primary-600 hover:bg-primary-700 text-white font-medium py-3 px-4 rounded-xl transition-colors disabled:opacity-50 disabled:cursor-not-allowed text-sm"
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
			<h2 class="text-sm font-semibold text-gray-900 mb-3">Actas Enviadas</h2>
			<div class="space-y-2">
				{#each historial as acta}
					<div class="bg-white rounded-lg border border-gray-200 px-4 py-3 flex items-center justify-between">
						<div>
							<span class="text-sm font-medium text-gray-900">Mesa {acta.mesas?.numero}</span>
							<span class="text-xs text-gray-400 ml-2">
								{new Date(acta.created_at).toLocaleString('es-BO', { hour: '2-digit', minute: '2-digit' })}
							</span>
						</div>
						<span
							class="text-xs font-medium px-2.5 py-1 rounded-full {acta.estado === 'verificada'
								? 'bg-success-500/10 text-success-600'
								: acta.estado === 'observada'
									? 'bg-warning-500/10 text-warning-600'
									: acta.estado === 'rechazada'
										? 'bg-danger-500/10 text-danger-600'
										: 'bg-gray-100 text-gray-500'}"
						>
							{acta.estado}
						</span>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</div>
