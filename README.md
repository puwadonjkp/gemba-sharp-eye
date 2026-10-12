# Operation Sharp-Eye Gemba — digital board

กระดานเดินตรวจ (Gemba walk) แบบดิจิทัล แชร์ลิงก์เดียว หลายคนแก้ไขพร้อมกันแบบ real-time

- แตะช่องเพื่อเลือก ผ่าน / ไม่ผ่าน / ขีด (ไม่ได้ตรวจ)
- ไม่ผ่าน → ใส่สิ่งที่เจอ + แนบรูป แล้วขึ้นใน Action ใต้ Cell อัตโนมัติ (จัดกลุ่มตามเครื่อง)
- ปรับตารางได้ (ปุ่มเฟือง): Cell, เครื่อง, หัวข้อที่ตรวจ, น้ำหนักคะแนน
- "บันทึกวันนี้" เก็บภาพบอร์ดไว้ดูย้อนหลังแบบแก้ไม่ได้ (ปุ่ม "ประวัติ")

## โครงสร้าง

| ไฟล์ | หน้าที่ |
|---|---|
| `index.html` | แอปทั้งหมด (HTML+CSS+JS ไฟล์เดียว) |
| `supabase-shim.js` | ต่อแอปเข้ากับ Supabase (document store + realtime) |
| `config.js` | URL และ anon key ของ Supabase (เป็น public key) |
| `vendor-supabase.js` | supabase-js (bundle แล้ว ไม่พึ่ง CDN) |
| `supabase/migrations/` | SQL สร้างตารางและสิทธิ์ |

## ข้อมูลใน Supabase

สองตาราง `docs` (ข้อมูลเล็ก ส่ง realtime) และ `blobs` (รูปเต็ม ดึงเมื่อเปิดดู) path รูปแบบ `collection/id`

## โหมดสิทธิ์ตอนนี้ (ทดสอบ)

ใครมีลิงก์ก็อ่านและแก้ไขได้ (RLS policy `docs_all`, `blobs_all`) เหมาะกับช่วงทดลองเท่านั้น
ข้อควรรู้: anon key อยู่ในไฟล์หน้าเว็บ ใครเปิดดูโค้ดก็เรียกฐานข้อมูลตรง ๆ ได้ ห้ามใส่ข้อมูลลับ

### ขั้นต่อไป (ภายหลัง)
1. เปิด Supabase Auth (email / magic link หรือ password)
2. เปลี่ยน policy เป็น `to authenticated` (หรืออ่านได้ทุกคน เขียนได้เฉพาะผู้ล็อกอิน)
3. แก้ `user.can()` ใน `supabase-shim.js` และเพิ่มหน้า login

## ตัวนับผู้เข้าชม

มุมใต้ชื่อบอร์ด: **ออนไลน์ตอนนี้** (Realtime Presence, ไม่เก็บลงฐานข้อมูล) · **วันนี้ X ครั้ง · Y คน** · **รวมทั้งหมด**
- นับ 1 ครั้งต่อเบราว์เซอร์เซสชัน (รีเฟรชไม่นับซ้ำ) "คน" = เบราว์เซอร์ที่เปิดครั้งแรกของวันนั้น (เวลาไทย)
- เก็บในตาราง `visit_stats` เขียนได้ผ่านฟังก์ชัน `visit_hit` เท่านั้น (migration 0002)
- เป็นตัวเลขคร่าว ๆ: คนที่รู้ anon key เรียกฟังก์ชันซ้ำเพื่อเพิ่มตัวเลขได้

## รันในเครื่อง

```
python3 -m http.server 8000   # แล้วเปิด http://localhost:8000
```

## Deploy

GitHub Pages: Settings → Pages → Source: **Deploy from a branch** → Branch `main` / folder `/ (root)` → Save
เว็บจะอยู่ที่ https://puwadonjkp.github.io/gemba-sharp-eye/
