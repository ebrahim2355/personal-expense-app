export function checkedTestDatabaseUrl(
  rawUrl: string | undefined,
): string | undefined {
  if (rawUrl === undefined) {
    return undefined;
  }
  const url = new URL(rawUrl);
  const databaseName = decodeURIComponent(url.pathname.replace(/^\//, ''));
  if (!/(?:^|[-_])test$/i.test(databaseName)) {
    throw new Error(
      'TEST_DATABASE_URL must name a dedicated database ending in -test or _test.',
    );
  }
  return rawUrl;
}
