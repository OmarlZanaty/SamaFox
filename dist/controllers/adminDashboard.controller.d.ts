import { Request, Response } from 'express';
type AdminReq = Request;
export declare const adminDashboardOverview: (req: AdminReq, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminDashboardListUsers: (req: AdminReq, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminDashboardListRooms: (req: AdminReq, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminDashboardListChargingAgencies: (req: AdminReq, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const adminDashboardUpdateAgencyStatus: (req: AdminReq, res: Response) => Promise<Response<any, Record<string, any>>>;
export {};
//# sourceMappingURL=adminDashboard.controller.d.ts.map