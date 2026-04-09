export declare const calculateLevel: (xp: number) => number;
export declare const xpForNextLevel: (currentLevel: number) => number;
export declare const awardRoomXP: (roomId: number, xpAmount: number) => Promise<{
    success: boolean;
    error: string;
    xp?: undefined;
    level?: undefined;
    leveledUp?: undefined;
    xpGained?: undefined;
} | {
    success: boolean;
    xp: number;
    level: number;
    leveledUp: boolean;
    xpGained: number;
    error?: undefined;
}>;
export declare const awardUserXP: (userId: number, xpAmount: number) => Promise<{
    success: boolean;
    error: string;
    xp?: undefined;
    level?: undefined;
    leveledUp?: undefined;
    xpGained?: undefined;
} | {
    success: boolean;
    xp: number;
    level: number;
    leveledUp: boolean;
    xpGained: number;
    error?: undefined;
}>;
export declare const getRoomLevelInfo: (roomId: number) => Promise<{
    success: boolean;
    error: string;
    level?: undefined;
    xp?: undefined;
    currentLevelXP?: undefined;
    nextLevelXP?: undefined;
    xpInCurrentLevel?: undefined;
    xpNeededForNextLevel?: undefined;
    progress?: undefined;
} | {
    success: boolean;
    level: number;
    xp: number;
    currentLevelXP: number;
    nextLevelXP: number;
    xpInCurrentLevel: number;
    xpNeededForNextLevel: number;
    progress: number;
    error?: undefined;
}>;
export declare const getUserLevelInfo: (userId: number) => Promise<{
    success: boolean;
    error: string;
    level?: undefined;
    xp?: undefined;
    currentLevelXP?: undefined;
    nextLevelXP?: undefined;
    xpInCurrentLevel?: undefined;
    xpNeededForNextLevel?: undefined;
    progress?: undefined;
} | {
    success: boolean;
    level: number;
    xp: number;
    currentLevelXP: number;
    nextLevelXP: number;
    xpInCurrentLevel: number;
    xpNeededForNextLevel: number;
    progress: number;
    error?: undefined;
}>;
//# sourceMappingURL=xp.service.d.ts.map