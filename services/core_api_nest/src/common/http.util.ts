export async function fetchJson<T>(
  input: string | URL,
  init?: RequestInit,
  timeoutMs = 8000,
): Promise<T> {
  const response = await fetch(input, {
    ...init,
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) {
    const body = await safeReadText(response);
    throw new Error(`${response.status} ${response.statusText}: ${body}`);
  }
  return (await response.json()) as T;
}

export async function fetchText(
  input: string | URL,
  init?: RequestInit,
  timeoutMs = 8000,
): Promise<string> {
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

async function safeReadText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return '';
  }
}
