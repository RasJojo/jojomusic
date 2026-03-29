"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchJson = fetchJson;
exports.fetchText = fetchText;
async function fetchJson(input, init, timeoutMs = 8000) {
    const response = await fetch(input, {
        ...init,
        signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
        const body = await safeReadText(response);
        throw new Error(`${response.status} ${response.statusText}: ${body}`);
    }
    return (await response.json());
}
async function fetchText(input, init, timeoutMs = 8000) {
    const response = await fetch(input, {
        ...init,
        signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
        const body = await safeReadText(response);
        throw new Error(`${response.status} ${response.statusText}: ${body}`);
    }
    return response.text();
}
async function safeReadText(response) {
    try {
        return await response.text();
    }
    catch {
        return '';
    }
}
//# sourceMappingURL=http.util.js.map