import { Request, Response } from 'express';
export declare const getAllUsers: (req: Request, res: Response) => Promise<void>;
export declare const addCoins: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const deleteProduct: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const removeCoins: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare function getDashboardStats(req: Request, res: Response): Promise<void>;
export declare const getAllTransactions: (req: Request, res: Response) => Promise<void>;
export declare const deleteRoom: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const toggleUserBan: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const toggleAdminStatus: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=admin.controller.d.ts.map