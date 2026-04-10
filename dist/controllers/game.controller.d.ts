import { Request, Response } from 'express';
export declare const playDice: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
export declare const getLeaderboard: (req: Request, res: Response) => Promise<void>;
export declare const getUserGameStats: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
//# sourceMappingURL=game.controller.d.ts.map