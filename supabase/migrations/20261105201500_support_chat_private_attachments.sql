-- Private support attachments: images/PDF only, 10 MB each.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'support-attachments',
  'support-attachments',
  false,
  10485760,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
    'application/pdf'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

ALTER TABLE public.support_messages
  ADD COLUMN IF NOT EXISTS attachment_path text,
  ADD COLUMN IF NOT EXISTS attachment_name text,
  ADD COLUMN IF NOT EXISTS attachment_mime text,
  ADD COLUMN IF NOT EXISTS attachment_size bigint;

ALTER TABLE public.support_messages
  ADD CONSTRAINT support_messages_attachment_metadata_check
  CHECK (
    (
      attachment_path IS NULL
      AND attachment_name IS NULL
      AND attachment_mime IS NULL
      AND attachment_size IS NULL
    )
    OR
    (
      attachment_path IS NOT NULL
      AND attachment_name IS NOT NULL
      AND attachment_mime IN (
        'image/jpeg','image/png','image/webp','image/gif',
        'image/heic','image/heif','application/pdf'
      )
      AND attachment_size BETWEEN 1 AND 10485760
      AND attachment_path LIKE conversation_id::text || '/%'
    )
  );

DROP POLICY IF EXISTS "support_attachments_read_conversation" ON storage.objects;
CREATE POLICY "support_attachments_read_conversation"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'support-attachments'
  AND EXISTS (
    SELECT 1
    FROM public.support_conversations c
    WHERE c.id::text = (storage.foldername(name))[1]
      AND (c.user_id = (SELECT auth.uid()) OR public.is_admin())
  )
);

DROP POLICY IF EXISTS "support_attachments_upload_conversation" ON storage.objects;
CREATE POLICY "support_attachments_upload_conversation"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'support-attachments'
  AND EXISTS (
    SELECT 1
    FROM public.support_conversations c
    WHERE c.id::text = (storage.foldername(name))[1]
      AND (c.user_id = (SELECT auth.uid()) OR public.is_admin())
  )
);
