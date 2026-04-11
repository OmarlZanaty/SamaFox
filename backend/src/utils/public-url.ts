import { Request } from 'express';

const trimTrailingSlash = (value: string) => value.replace(/\/+$/, '');

const pickForwarded = (value?: string | string[]) => {
  if (!value) return null;
  const first = Array.isArray(value) ? value[0] : value.split(',')[0];
  return first?.trim() || null;
};

export const getPublicBaseUrl = (req: Request): string => {
  const configuredBaseUrl = process.env.PUBLIC_BASE_URL?.trim();
  if (configuredBaseUrl) {
    return trimTrailingSlash(configuredBaseUrl);
  }

  const forwardedProto = pickForwarded(req.headers['x-forwarded-proto']);
  const forwardedHost = pickForwarded(req.headers['x-forwarded-host']);

  const protocol = forwardedProto || req.protocol;
  const host = forwardedHost || req.get('host');

  return trimTrailingSlash(`${protocol}://${host}`);
};
