-- صور في شات الروم — picture messages in room chat, gated by app_settings.room_image_min_vip.
ALTER TABLE "room_messages" ADD COLUMN "type" TEXT NOT NULL DEFAULT 'text';
ALTER TABLE "room_messages" ADD COLUMN "imageUrl" TEXT;
