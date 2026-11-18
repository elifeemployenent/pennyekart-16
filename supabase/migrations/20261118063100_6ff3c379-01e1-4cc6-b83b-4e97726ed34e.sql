ALTER TABLE public.utility_service_requests ALTER COLUMN service_id DROP NOT NULL;
ALTER TABLE public.utility_service_requests
  ADD COLUMN IF NOT EXISTS broadcast_category_id uuid REFERENCES public.utility_service_categories(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS accepted_by uuid;
CREATE INDEX IF NOT EXISTS idx_utility_requests_broadcast ON public.utility_service_requests(broadcast_category_id) WHERE service_id IS NULL;

-- Available partners in the same category can see open broadcast requests.
CREATE POLICY "Category partners can view open broadcast requests"
ON public.utility_service_requests FOR SELECT TO authenticated
USING (
  service_id IS NULL AND status = 'pending' AND broadcast_category_id IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.user_id = auth.uid() AND p.seller_type = 'utility'
      AND p.utility_category_id = broadcast_category_id
      AND COALESCE(p.is_available, true)
  )
);

-- First partner to accept wins; the row is then locked to their service.
CREATE OR REPLACE FUNCTION public.accept_broadcast_utility_request(_request_id uuid, _unit text, _value integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _cat uuid; _svc uuid;
BEGIN
  SELECT utility_category_id INTO _cat FROM profiles
   WHERE user_id = auth.uid() AND seller_type = 'utility';
  IF _cat IS NULL THEN RAISE EXCEPTION 'Not a utility partner'; END IF;
  SELECT id INTO _svc FROM utility_services
   WHERE provider_user_id = auth.uid() AND category_id = _cat
   ORDER BY is_active DESC, created_at LIMIT 1;
  IF _svc IS NULL THEN RAISE EXCEPTION 'Add a service in this category before accepting'; END IF;
  UPDATE utility_service_requests
     SET service_id = _svc, accepted_by = auth.uid(), status = 'assigned',
         availability_unit = _unit, availability_value = _value
   WHERE id = _request_id AND service_id IS NULL AND status = 'pending'
     AND broadcast_category_id = _cat;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.accept_broadcast_utility_request(uuid, text, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.accept_broadcast_utility_request(uuid, text, integer) TO authenticated;