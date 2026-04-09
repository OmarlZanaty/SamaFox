import { Request, Response } from 'express';
export declare const getDailyQuests: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
export declare const updateQuestProgress: (userId: number, metric: string, incrementBy?: number) => Promise<{
    questCompleted: boolean;
    quest: {
        id: string;
        name: string;
        createdAt: Date;
        description: string;
        target: number;
        metric: string;
        rewardCoins: number;
    };
    reward: number;
} | {
    questCompleted: boolean;
    quest?: undefined;
    reward?: undefined;
}>;
export declare const completeQuest: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const createDailyQuest: (req: Request, res: Response) => Promise<Response<any, Record<string, any>> | undefined>;
//# sourceMappingURL=quest.controller.d.ts.map