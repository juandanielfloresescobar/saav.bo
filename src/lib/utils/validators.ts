export interface VoteValidation {
	valid: boolean;
	message: string;
}

export function validateActa(
	votos: Record<string, number>,
	votosNulos: number,
	votosBlancos: number,
	totalVotantes: number
): VoteValidation {
	const sumaVotosPartidos = Object.values(votos).reduce((sum, v) => sum + v, 0);
	const sumaTotal = sumaVotosPartidos + votosNulos + votosBlancos;

	if (totalVotantes <= 0) {
		return { valid: false, message: 'El total de votantes debe ser mayor a 0' };
	}

	if (totalVotantes > 300) {
		return { valid: false, message: 'El total de votantes no puede exceder 300 por mesa' };
	}

	for (const [partido, cantidad] of Object.entries(votos)) {
		if (cantidad < 0) {
			return { valid: false, message: `Los votos de ${partido} no pueden ser negativos` };
		}
	}

	if (votosNulos < 0 || votosBlancos < 0) {
		return { valid: false, message: 'Los votos nulos y blancos no pueden ser negativos' };
	}

	if (sumaTotal !== totalVotantes) {
		return {
			valid: false,
			message: `La suma de votos (${sumaTotal}) no coincide con el total de votantes (${totalVotantes})`
		};
	}

	return { valid: true, message: 'Acta válida' };
}
