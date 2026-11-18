UPDATE public.profiles p SET utility_category_id = s.category_id
FROM (SELECT provider_user_id, min(category_id::text)::uuid AS category_id FROM public.utility_services
      WHERE category_id IS NOT NULL GROUP BY provider_user_id HAVING count(DISTINCT category_id) = 1) s
WHERE p.user_id = s.provider_user_id AND p.seller_type = 'utility' AND p.utility_category_id IS NULL;

DROP POLICY IF EXISTS "Category partners can view open broadcast requests" ON public.utility_service_requests;
CREATE POLICY "Category partners can view open broadcast requests" ON public.utility_service_requests
FOR SELECT TO authenticated USING (
  service_id IS NULL AND status = 'pending' AND broadcast_category_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = auth.uid() AND p.seller_type = 'utility' AND COALESCE(p.is_available, true)
    AND (p.utility_category_id = utility_service_requests.broadcast_category_id
         OR EXISTS (SELECT 1 FROM public.utility_services s WHERE s.provider_user_id = auth.uid() AND s.category_id = utility_service_requests.broadcast_category_id)))
);

CREATE OR REPLACE FUNCTION public.accept_broadcast_utility_request(_request_id uuid, _unit text, _value integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _cat uuid; _svc uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND seller_type = 'utility') THEN
    RAISE EXCEPTION 'Not a utility partner'; END IF;
  SELECT broadcast_category_id INTO _cat FROM utility_service_requests WHERE id = _request_id;
  IF _cat IS NULL THEN RETURN false; END IF;
  SELECT id INTO _svc FROM utility_services WHERE provider_user_id = auth.uid() AND category_id = _cat
   ORDER BY is_active DESC, created_at LIMIT 1;
  IF _svc IS NULL THEN RAISE EXCEPTION 'Add a service in this category before accepting'; END IF;
  UPDATE utility_service_requests SET service_id = _svc, accepted_by = auth.uid(), status = 'assigned',
         availability_unit = _unit, availability_value = _value
   WHERE id = _request_id AND service_id IS NULL AND status = 'pending' AND broadcast_category_id = _cat;
  RETURN FOUND;
END $$;