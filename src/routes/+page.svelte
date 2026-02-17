<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	let { data } = $props();

	onMount(() => {
		if (!data.session) {
			goto('/auth');
			return;
		}
		if (!data.perfil) {
			goto('/auth');
			return;
		}
		switch (data.perfil.rol) {
			case 'delegado':
				goto('/ingesta');
				break;
			case 'verificador':
				goto('/validacion');
				break;
			case 'candidato':
			case 'admin':
				goto('/dashboard');
				break;
			default:
				goto('/auth');
		}
	});
</script>

<div class="flex items-center justify-center min-h-screen">
	<div class="text-center">
		<div class="w-12 h-12 bg-primary-600 rounded-xl flex items-center justify-center mx-auto mb-4">
			<span class="text-white font-bold text-xl">Q</span>
		</div>
		<p class="text-gray-500">Cargando Quantis...</p>
	</div>
</div>
