import { Request, Response } from 'express';
export declare const getGifts: (req: Request, res: Response) => Promise<void>;
export declare const getGiftHistory: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const sendGift: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=gift.controller.d.ts.map