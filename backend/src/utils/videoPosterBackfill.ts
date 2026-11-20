import path from 'path';
/** Only locally hosted /uploads files; never fetch arbitrary remote URLs. */
export function localVideoPath(assetUrl: string, uploadsDir: string): string | null {
  try {
    const pathname = decodeURIComponent(new URL(assetUrl, 'http://local').pathname);
    if (!pathname.startsWith('/uploads/') || !/\.(mp4|webm|mov|m4v)$/i.test(pathname)) return null;
    const root = path.resolve(uploadsDir);
    const file = path.resolve(root, pathname.slice('/uploads/'.length));
    const relative = path.relative(root, file);
    return relative.startsWith('..') || path.isAbsolute(relative) ? null : file;
  } catch { return null; }
}
