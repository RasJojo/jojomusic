import { pbkdf2Sync, randomBytes, timingSafeEqual } from 'node:crypto';

const ALGORITHM = 'sha256';
const ITERATIONS = 390_000;

function toPythonBase64Url(buffer: Buffer): string {
  return buffer
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function fromPythonBase64Url(value: string): Buffer {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(normalized + padding, 'base64');
}

export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const digest = pbkdf2Sync(password, salt, ITERATIONS, 32, ALGORITHM);
  return `pbkdf2_${ALGORITHM}$${ITERATIONS}$${toPythonBase64Url(salt)}$${toPythonBase64Url(digest)}`;
}

export function verifyPassword(password: string, passwordHash: string): boolean {
  const parts = passwordHash.split('$');
  if (parts.length !== 4 || parts[0] !== `pbkdf2_${ALGORITHM}`) {
    return false;
  }

  const iterations = Number(parts[1]);
  if (!Number.isFinite(iterations) || iterations <= 0) {
    return false;
  }

  const salt = fromPythonBase64Url(parts[2]);
  const expected = fromPythonBase64Url(parts[3]);
  const candidate = pbkdf2Sync(password, salt, iterations, expected.length, ALGORITHM);
  return timingSafeEqual(candidate, expected);
}
