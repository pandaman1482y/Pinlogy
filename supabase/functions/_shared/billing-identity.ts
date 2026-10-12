// Stable provider identity and a legacy marker are both accepted during migration.
export function identityValues(user: any): string[] {
  const values: string[] = [];
  for (const identity of user.identities ?? []) {
    const provider = String(identity.provider ?? '').toLowerCase();
    if (!['apple', 'google'].includes(provider)) continue;
    const stable = String(identity.provider_id ?? identity.identity_data?.sub ?? identity.id ?? '').trim();
    const legacy = String(identity.identity_id ?? identity.id ?? '').trim();
    if (stable) values.push(`${provider}:${stable}`);
    if (legacy) values.push(`${provider}:${legacy}`);
  }
  if (user.email_confirmed_at && user.email) {
    values.push(`email:${String(user.email).trim().toLowerCase()}`);
  }
  return [...new Set(values)];
}

export function appleSubject(identity: any): string {
  return String(identity.provider_id ?? identity.identity_data?.sub ?? identity.id ?? '').trim();
}
