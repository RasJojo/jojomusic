"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hashPassword = hashPassword;
exports.verifyPassword = verifyPassword;
const node_crypto_1 = require("node:crypto");
const ALGORITHM = 'sha256';
const ITERATIONS = 390_000;
function toPythonBase64Url(buffer) {
    return buffer
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}
function fromPythonBase64Url(value) {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    const padding = '='.repeat((4 - (normalized.length % 4)) % 4);
    return Buffer.from(normalized + padding, 'base64');
}
function hashPassword(password) {
    const salt = (0, node_crypto_1.randomBytes)(16);
    const digest = (0, node_crypto_1.pbkdf2Sync)(password, salt, ITERATIONS, 32, ALGORITHM);
    return `pbkdf2_${ALGORITHM}$${ITERATIONS}$${toPythonBase64Url(salt)}$${toPythonBase64Url(digest)}`;
}
function verifyPassword(password, passwordHash) {
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
    const candidate = (0, node_crypto_1.pbkdf2Sync)(password, salt, iterations, expected.length, ALGORITHM);
    return (0, node_crypto_1.timingSafeEqual)(candidate, expected);
}
//# sourceMappingURL=password.util.js.map