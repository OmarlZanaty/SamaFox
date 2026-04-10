export type TokenPayload = {
    userId: number;
};
export declare function signToken(payload: TokenPayload): string;
export declare function signRefreshToken(payload: TokenPayload): string;
export declare function verifyToken(token: string): TokenPayload;
export declare function verifyRefreshToken(token: string): TokenPayload;
export declare const signAccessToken: typeof signToken;
export declare const verifyAccessToken: typeof verifyToken;
export declare const signRefresh: typeof signRefreshToken;
export declare const verifyRefresh: typeof verifyRefreshToken;
//# sourceMappingURL=jwt.d.ts.map