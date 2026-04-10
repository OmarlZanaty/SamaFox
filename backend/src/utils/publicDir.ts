import fs from 'fs';
import path from 'path';

export const resolvePublicDir = (): string => {
  const staticPublicCandidates: string[] = [
    path.join(process.cwd(), 'public'),
    path.resolve(process.cwd(), '../public'),
    path.resolve(__dirname, '../../public'),
    path.resolve(__dirname, '../public')
  ];

  return (
    staticPublicCandidates.find((candidate) => fs.existsSync(candidate)) ??
    path.join(process.cwd(), 'public')
  );
};
