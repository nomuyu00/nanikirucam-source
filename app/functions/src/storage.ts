import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions/v2';

/** 既定の Storage バケット名。取得できなければ空文字。 */
export function bucketName(): string {
  try {
    return getStorage().bucket().name;
  } catch {
    return '';
  }
}

export async function cardExists(cardPath: string): Promise<boolean> {
  try {
    const [exists] = await getStorage().bucket().file(cardPath).exists();
    return exists;
  } catch (err) {
    logger.warn('cardExists failed', err);
    return false;
  }
}

export async function loadCard(cardPath: string): Promise<Uint8Array | null> {
  try {
    const file = getStorage().bucket().file(cardPath);
    const [exists] = await file.exists();
    if (!exists) return null;
    const [buf] = await file.download();
    return new Uint8Array(buf);
  } catch (err) {
    logger.warn('loadCard failed', err);
    return null;
  }
}

/** `cards/{problemId}/` 以下をすべて削除する。 */
export async function deleteCards(problemId: string): Promise<void> {
  await getStorage().bucket().deleteFiles({ prefix: `cards/${problemId}/`, force: true });
}
