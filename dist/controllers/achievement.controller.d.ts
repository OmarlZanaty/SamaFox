import { Request, Response } from 'express';
export declare const getAllAchievements: (req: Request, res: Response) => Promise<void>;
export declare const getUserAchievements: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
export declare const checkAchievements: (userId: number, metric: string, currentValue: number) => Promise<{
    id: string;
    name: string;
    createdAt: Date;
    updatedAt: Date;
    description: string;
    iconUrl: string;
    target: number;
    metric: string;
}[]>;
export declare const createAchievement: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
//# sourceMappingURL=achievement.controller.d.ts.map