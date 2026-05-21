# TODO
- [ ] فهم شكل الطلب من frontend لاستدعاء Edge Function (تم جزئيًا عبر src/api/edgeFunctions.js)
- [ ] تحديث `supabase/functions/insert_waste_protected/index.ts`:
  - [ ] استخدام JWT من `Authorization` بدل `body.user_id`
  - [ ] التحقق من role عبر `public.profiles` باستخدام auth (بدون service_role في role check)
  - [ ] بدل insert في `waste_logs` مباشرة: insert في `public.invoice_items` مع `movement_type='waste'` ليشتغل trigger
  - [ ] إضافة validation لـ `product_id` و `qty` و `type`
- [ ] التأكد من أن insert في `invoice_items` لن يفشل بسبب أعمدة NOT NULL إضافية (نحتاج تأكيد schema/الحقول المطلوبة)
- [ ] تشغيل/اختبار function محليًا أو عبر Supabase dashboard

