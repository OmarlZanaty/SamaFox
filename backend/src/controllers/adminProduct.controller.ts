import path from "path";
import { Request, Response } from "express";
import prisma from "../utils/prisma";
import { extractPosterFrame } from "../gifts/videoValidate";

/**
 * A25/B5 — a still for a VIDEO product, so the store grid has something to draw
 * without spinning up a decoder per tile.
 *
 * Returns the poster's public URL, or null when there is no poster to make (a
 * still product) or ffmpeg could not produce one. Never throws: a missing
 * poster costs a placeholder tile, and must not cost the upload.
 */
async function buildPosterUrl(
  file: any,
  isVideo: boolean,
  baseUrl: string,
): Promise<string | null> {
  if (!isVideo || !file?.path) return null;
  const posterPath = await extractPosterFrame(file.path).catch(() => null);
  if (!posterPath) return null;
  return `${baseUrl}/uploads/${path.basename(posterPath)}`;
}

/**
 * Layout guides the dashboard sends with a decorated product: where its EMPTY
 * inner box is, and where the 9-slice centre sits. Both are FRACTIONS of the
 * artwork (0..1 from each edge) so they survive any upload resolution.
 *
 * The client's rule, repeated for bubbles, entry bars and mic frames alike:
 * "انا محدود داخل مربع الفقاعه الفارغ ... مليش علاقه بأي زخرفة" — the app draws
 * only inside `insets`, and stretches only the `slice` middle.
 *
 * Returns `undefined` when the field was not sent (so an unrelated edit keeps
 * whatever was configured) and `null` to clear it back to the app defaults.
 */
function parseLayoutMeta(body: any): any | null | undefined {
  const raw = body?.meta ?? body?.layout;
  if (raw === undefined) return undefined;
  if (raw === null || String(raw).trim() === "") return null;

  let obj: any = raw;
  if (typeof raw === "string") {
    try {
      obj = JSON.parse(raw);
    } catch {
      return undefined; // malformed input must never wipe a good config
    }
  }
  if (!obj || typeof obj !== "object") return null;

  const box = (v: any): any => {
    if (!v || typeof v !== "object") return undefined;
    const side = (n: any) => {
      const f = Number(n);
      // Anything outside 0..0.49 per side would leave no inner box at all.
      return Number.isFinite(f) ? Math.min(0.49, Math.max(0, f)) : 0;
    };
    return { l: side(v.l), t: side(v.t), r: side(v.r), b: side(v.b) };
  };

  const out: any = {};
  const insets = box(obj.insets);
  const slice = box(obj.slice);
  if (insets) out.insets = insets;
  if (slice) out.slice = slice;
  return Object.keys(out).length ? out : null;
}

export const createProduct = async (req: Request, res: Response) => {
  try {
    const { name, type, price_coins } = req.body;

    if (!name || !type || price_coins == null) {
      return res.status(400).json({ message: "بيانات ناقصة" });
    }

    const file = (req as any).file;
    if (!file) return res.status(400).json({ message: "يجب رفع ملف" });

    const isVideo = file.mimetype.startsWith("video/");
    const isImage = file.mimetype.startsWith("image/");

    // 2026-08-23 client request: "اولا جميع المنتجات اضيف (صوره- فيديو)".
    // Every product type now takes EITHER an image or a video — the old
    // per-type restrictions (video-only مركبات, image-only everything else)
    // are gone. Anything that is neither is still refused.
    if (!isVideo && !isImage) {
      return res.status(400).json({ message: "يجب رفع صورة أو فيديو" });
    }

    const configuredBaseUrl = String(process.env.BASE_URL || "").trim().replace(/\/+$/, "");
    const forwardedProto = (String(req.headers["x-forwarded-proto"] || "").split(",")[0] || "").trim();
    const protocol = forwardedProto || req.protocol || "http";
    const host = req.get("host") || "";
    const requestBaseUrl = host ? `${protocol}://${host}` : "";
    const baseUrl = configuredBaseUrl || requestBaseUrl || `http://localhost:${process.env.PORT || 3000}`;
    const assetUrl = `${baseUrl}/uploads/${file.filename}`;

    const mappedType =
      type === "seat_effect"
        ? "ENTRANCE_EFFECT"
        : type === "avatar_frame" || type === "frame"
          ? "FRAME"
          : type === "entrance"
            ? "ENTRANCE_BANNER"
            : type === "badge"
              ? "BADGE"
              : type === "chat_bubble"
                ? "CHAT_BUBBLE"
                : type === "chat_top_banner"
                  ? "CHAT_TOP_BANNER"
                  // خلفية الصفحة الشخصية / إطار تزيين الصفحة الشخصية — both
                  // added 2026-08-23, both accept صورة or فيديو like the rest.
                  : type === "profile_background"
                    ? "PROFILE_BACKGROUND"
                    : type === "profile_decor"
                      ? "PROFILE_DECOR"
                      : type;

    // Group 9: is_private=true puts the item in the Private Store — hidden
    // from the in-app store, only grantable by ID from the dashboard.
    const isPrivate = req.body?.is_private === "true" || req.body?.is_private === true;

    // Owner request: every product gets a term. `duration_days` empty, 0 or
    // "permanent"/"أبدي" means it never expires — the dashboard sends either a
    // day count or the permanent flag.
    const rawDuration = req.body?.duration_days;
    const isPermanent =
      rawDuration === undefined ||
      rawDuration === null ||
      String(rawDuration).trim() === "" ||
      String(rawDuration).trim() === "0" ||
      req.body?.is_permanent === "true" ||
      req.body?.is_permanent === true;
    const durationDays = isPermanent ? null : Math.max(1, Math.floor(Number(rawDuration) || 0)) || null;

    const layoutMeta = parseLayoutMeta(req.body);
    const previewUrl = await buildPosterUrl(file, isVideo, baseUrl);

    const product = await prisma.item.create({
      data: {
        name,
        description: "",
        type: mappedType,
        assetUrl,
        previewUrl,
        priceCoins: Number(price_coins),
        isPurchasable: !isPrivate,
        durationDays,
        ...(layoutMeta !== undefined ? { meta: layoutMeta } : {}),
      } as any,
    });

    return res.json({
      id: product.id,
      name: product.name,
      type: product.type,
      price_coins: product.priceCoins,
      file_url: product.assetUrl,
      preview_url: (product as any).previewUrl ?? null,
      is_private: !product.isPurchasable,
      duration_days: (product as any).durationDays ?? null,
      meta: (product as any).meta ?? null,
    });
  } catch (error) {
    console.error("createProduct error:", error);
    return res.status(500).json({ message: "فشل إنشاء المنتج" });
  }
};

// GET /admin-products/products — dashboard list of ALL items (app + private)
export const listProductsAdmin = async (_req: Request, res: Response) => {
  try {
    const items = await prisma.item.findMany({ orderBy: { createdAt: "desc" } });
    return res.json({
      data: items.map((i) => ({
        id: i.id,
        name: i.name,
        type: i.type,
        price_coins: i.priceCoins,
        file_url: i.assetUrl,
        preview_url: (i as any).previewUrl ?? null,
        is_private: !i.isPurchasable,
        // The dashboard edits/display the term, so it has to come back here —
        // without it every row rendered as "أبدي".
        duration_days: (i as any).durationDays ?? null,
        grant_to_all: (i as any).grantToAll ?? false,
        // Layout guides so the dashboard can re-open the inner-box editor with
        // whatever was already configured for this product.
        meta: (i as any).meta ?? null,
        created_at: i.createdAt,
      })),
    });
  } catch (error) {
    console.error("listProductsAdmin error:", error);
    return res.status(500).json({ message: "فشل تحميل المنتجات" });
  }
};

/**
 * Parses the dashboard's duration input. Returns `undefined` when the field
 * wasn't sent at all (so an edit that only renames a product keeps its term),
 * `null` for أبدي, otherwise a day count.
 */
function parseDurationDays(body: any): number | null | undefined {
  const raw = body?.duration_days;
  const permanentFlag = body?.is_permanent === true || body?.is_permanent === "true";
  if (permanentFlag) return null;
  if (raw === undefined) return undefined;
  if (raw === null || String(raw).trim() === "" || String(raw).trim() === "0") return null;
  const days = Math.floor(Number(raw));
  if (!Number.isFinite(days) || days <= 0) return null;
  return days;
}

// PATCH /admin-products/products/:id — edit a product: store visibility, name,
// price, and (owner request) the term in days for items uploaded without one.
export const setProductVisibility = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const data: any = {};

    if (req.body?.is_private !== undefined) {
      data.isPurchasable = !(req.body.is_private === true || req.body.is_private === "true");
    }
    if (typeof req.body?.name === "string" && req.body.name.trim()) {
      data.name = req.body.name.trim();
    }
    if (req.body?.price_coins !== undefined && String(req.body.price_coins).trim() !== "") {
      const price = Math.floor(Number(req.body.price_coins));
      if (Number.isFinite(price) && price >= 0) data.priceCoins = price;
    }
    const durationDays = parseDurationDays(req.body);
    if (durationDays !== undefined) data.durationDays = durationDays;
    const layoutMeta = parseLayoutMeta(req.body);
    if (layoutMeta !== undefined) data.meta = layoutMeta;

    if (!Object.keys(data).length) {
      return res.status(400).json({ message: "لا يوجد ما يتم تحديثه" });
    }

    const item = await prisma.item.update({ where: { id }, data });
    return res.json({
      id: item.id,
      name: item.name,
      price_coins: item.priceCoins,
      is_private: !item.isPurchasable,
      duration_days: (item as any).durationDays ?? null,
      meta: (item as any).meta ?? null,
    });
  } catch (error: any) {
    if (error?.code === "P2025") return res.status(404).json({ message: "Product not found" });
    console.error("setProductVisibility error:", error);
    return res.status(500).json({ message: "فشل تحديث المنتج" });
  }
};

/** Expiry stamped on a grant from the product's configured term. */
export function expiryFromItem(item: { durationDays?: number | null } | any): Date | null {
  const days = Number((item as any)?.durationDays ?? 0);
  if (!Number.isFinite(days) || days <= 0) return null;
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}

// POST /admin-products/grant — manually grant an item, either to one user by
// display ID or (scope: "all") to every user of the app. A grant to everyone
// also flags the product so new sign-ups receive it automatically.
export const grantProduct = async (req: Request, res: Response) => {
  try {
    const itemId = String(req.body?.itemId || "");
    const scope = String(req.body?.scope || "user").toLowerCase();
    const displayId = Number(req.body?.displayId);
    if (!itemId) return res.status(400).json({ message: "itemId مطلوب" });
    if (scope !== "all" && !displayId) {
      return res.status(400).json({ message: "itemId و displayId مطلوبان" });
    }

    const item = await prisma.item.findUnique({ where: { id: itemId } });
    if (!item) return res.status(404).json({ message: "المنتج غير موجود" });

    // ===== جميع المستخدمين =====
    if (scope === "all") {
      const expiresAt = expiryFromItem(item);
      const users = await prisma.user.findMany({ select: { id: true } });
      let granted = 0;
      // Chunked so a large user base doesn't build one huge statement.
      const CHUNK = 500;
      for (let i = 0; i < users.length; i += CHUNK) {
        const slice = users.slice(i, i + CHUNK);
        const result = await prisma.userItem.createMany({
          data: slice.map((u) => ({ userId: u.id, itemId, expiresAt })),
          skipDuplicates: true,
        });
        granted += result.count;
      }

      // Keep granting it to whoever registers later.
      await prisma.item.update({ where: { id: itemId }, data: { grantToAll: true } as any });

      try {
        const { createNotification } = await import("../services/notification.service");
        await Promise.all(
          users.map((u) =>
            createNotification({
              userId: u.id,
              type: "ITEM_GRANTED",
              title: "🎁 تم منحك منتجاً",
              body: `منحتك إدارة التطبيق: ${item.name}`,
              data: { itemId },
            }),
          ),
        );
      } catch (e) {
        console.warn("grantProduct(all) notification failed:", e);
      }

      return res.json({
        message: `تم منح المنتج لجميع المستخدمين (${granted} حساب جديد)`,
        granted,
        totalUsers: users.length,
        item: { id: item.id, name: item.name, duration_days: (item as any).durationDays ?? null },
      });
    }

    const user = await prisma.user.findUnique({
      where: { displayId },
      select: { id: true, name: true, displayId: true },
    });
    if (!user) return res.status(404).json({ message: "لا يوجد مستخدم بهذا الرقم" });

    try {
      await prisma.userItem.create({
        data: { userId: user.id, itemId, expiresAt: expiryFromItem(item) },
      });
    } catch (err: any) {
      if (err?.code === "P2002") {
        return res.status(409).json({ message: "المستخدم يملك هذا المنتج بالفعل" });
      }
      throw err;
    }

    try {
      const { createNotification } = await import("../services/notification.service");
      await createNotification({
        userId: user.id,
        type: "ITEM_GRANTED",
        title: "🎁 تم منحك منتجاً",
        body: `منحتك إدارة التطبيق: ${item.name}`,
        data: { itemId },
      });
    } catch (e) {
      console.warn("grantProduct notification failed:", e);
    }

    return res.json({
      message: "تم منح المنتج بنجاح",
      user: { id: user.id, displayId: user.displayId, name: user.name },
      item: { id: item.id, name: item.name },
    });
  } catch (error) {
    console.error("grantProduct error:", error);
    return res.status(500).json({ message: "فشل منح المنتج" });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const item = await prisma.item.findUnique({ where: { id } });
    if (!item) return res.status(404).json({ message: "Product not found" });

    await prisma.$transaction(async (tx) => {
      await tx.user.updateMany({
        where: { activeFrameId: id },
        data: { activeFrameId: null, avatarFrameUrl: null },
      });

      await tx.room.updateMany({
        where: { activeThemeId: id },
        data: { activeThemeId: null },
      });

      // B2/B3 put an equipped خلفية/إطار تزيين الصفحة الشخصية on the USER row
      // as a bare URL (the profile is rendered from the user payload alone), so
      // deleting the product left every owner's page still painting it —
      // "عاوز عند حذف اي منتج من لوحة التحكم يحذف من البرنامج".
      //
      // Matched on the exact assetUrl, which clears only the people who equipped
      // THIS product: `profileBgUrl` doubles as a self-uploaded background from
      // تعديل الملف الشخصي, and that must survive.
      if (item.assetUrl) {
        if (item.type === "PROFILE_BACKGROUND") {
          await tx.user.updateMany({
            where: { profileBgUrl: item.assetUrl },
            data: { profileBgUrl: null, profileBgType: "image" },
          });
        } else if (item.type === "PROFILE_DECOR") {
          await tx.user.updateMany({
            where: { profileDecorUrl: item.assetUrl },
            data: { profileDecorUrl: null, profileDecorType: "image" },
          });
        }
      }

      await tx.userItem.deleteMany({
        where: { itemId: id },
      });

      await tx.item.delete({ where: { id } });
    });

    return res.json({ message: "Product deleted successfully" });
  } catch (error) {
    console.error("deleteProduct error:", error);
    return res.status(500).json({ message: "Failed to delete product" });
  }
};
