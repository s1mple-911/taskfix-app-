-- TASKFIX_V8.sql — "kim bajardi" kuzatuvi uchun additive ustunlar
-- Asilbek RUN qiladi. Idempotent, mavjud ma'lumotga tegmaydi.
--
-- Maqsad: vazifa "Bajarildi" deb belgilanganda KIM va QACHON belgilaganini saqlash,
-- toki qabul qiluvchi (acceptor) vazifani ochganda "Bajardi: {ism} · sana" ko'rsin.
-- Mavjud `submitter_id` faqat acceptor-oqimida to'ladi va vaqtни saqlamaydi — shuning
-- uchun aniq maydonlar qo'shamiz. Kod ikkala maydonni ham to'ldiradi (best-effort);
-- bu ustunlar bo'lmasa ham ilova ishlashda davom etadi (jimgina o'tadi).

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS bajardi_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS bajardi_at timestamptz;

COMMENT ON COLUMN public.tasks.bajardi_user_id IS 'Vazifani "Bajarildi" deb belgilagan foydalanuvchi (bajaruvchi)';
COMMENT ON COLUMN public.tasks.bajardi_at IS 'Vazifa "Bajarildi" deb belgilangan vaqt';

-- Filtr/ko'rinish uchun indeks (ixtiyoriy, lekin foydali)
CREATE INDEX IF NOT EXISTS idx_tasks_bajardi_user ON public.tasks (bajardi_user_id);

-- Tekshiruv: ustunlar mavjudligini tasdiqlaymiz (jimgina o'tmasin)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'bajardi_user_id'
  ) THEN
    RAISE EXCEPTION 'bajardi_user_id ustuni qo''shilmadi';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'bajardi_at'
  ) THEN
    RAISE EXCEPTION 'bajardi_at ustuni qo''shilmadi';
  END IF;
END $$;
