import imageCompression from 'browser-image-compression';

const ACTA_DEFAULTS = {
	maxSizeMB: 1,
	maxWidthOrHeight: 1200,
	useWebWorker: true
};

export async function compressActaPhoto(
	file: File,
	options: Partial<typeof ACTA_DEFAULTS> = {}
): Promise<File> {
	try {
		const compressed = await imageCompression(file, { ...ACTA_DEFAULTS, ...options });
		return new File([compressed], file.name, {
			type: compressed.type,
			lastModified: Date.now()
		});
	} catch {
		return file;
	}
}
