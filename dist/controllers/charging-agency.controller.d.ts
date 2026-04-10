import { Request, Response } from 'express';
export declare const listChargingAgencies: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare function myChargingAgencies(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare const createChargingAgency: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const myAgencyBalance: (req: any, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const myAgencyTransfers: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const agencyTransferCoins: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const createTopupRequest: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const myTopupRequests: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminListTopups: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const reviewTopupRequest: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminAdjustAgencyBalance: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const updateChargingAgencyStatus: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=charging-agency.controller.d.ts.map