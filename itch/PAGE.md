# Nội dung gợi ý cho trang itch.io

**Title:** Rocket Caro
**Project URL (slug):** rocket-caro
**Short description / tagline (tối đa ~100 ký tự):**
Caro khổng lồ 15×15, đặt dấu bằng rocket. Gió, trọng lực và cả bàn cờ đang lật quay sẽ làm bạn lệch tay.

**Kind of project:** HTML
**Genre:** Strategy (hoặc Shooter)
**Tags:** caro, gomoku, tic-tac-toe, fps, artillery, physics, godot, singleplayer, local-multiplayer
**Classification:** Games
**Release status:** Prototype (hoặc In development)

## Mô tả (dán vào ô Description)

**Rocket Caro**: caro 15×15 giữa hai bờ sông. Thay vì đánh dấu bằng chuột, bạn đứng ở một bên, ngắm và **bắn rocket** vào ô muốn đặt dấu. Xếp 5 dấu liên tiếp để thắng.

**Vì sao khó?**
- Mỗi lượt chỉ có 15 giây và một phát bắn.
- Gió và trọng lực làm rocket lệch khỏi tâm ngắm.
- Rocket trúng cây, đá, hoặc ô đã có dấu thì mất lượt.
- 4 độ khó: *Bình thường* (không gió, không trọng lực), *Khó* (có gió và trọng lực), *Rất khó* (bàn cờ nghiêng và xoay đổi mỗi lượt, còn bạn bị đưa đi vòng quanh bàn cờ), *Siêu khó* (bàn cờ lật và quay liên tục rất nhanh, có đạn băng để đóng băng bàn).
- Hai đạn đặc biệt, mỗi loại dùng 1 lần mỗi ván: **đạn tẩy** xóa một dấu của đối thủ, **đạn đuổi** cho bạn lái rocket bằng chuột sau khi bắn.

**Chế độ chơi (bản trên trang này):** chơi với Bot, hoặc 2 người thay phiên trên cùng một máy.
**Chơi mạng LAN** cần chạy máy chủ riêng (xem hướng dẫn trong bản tải về / README); trang itch.io chỉ lưu file game nên không tự có máy chủ.

## Điều khiển
| | |
|---|---|
| Chuột | Ngắm (click vào game lần đầu để khóa chuột). Bạn đứng yên một chỗ, không đi lại được |
| Click trái / Space | Bắn |
| Chuột phải / Z | Zoom |
| 1 / 2 / 3 | Chọn đạn thường / tẩy / đuổi |
| Esc | Tạm dừng, thả chuột |

## Embed settings (đã thử)
- Viewport size: **1280 × 720** (hoặc 1100 × 650)
- ☑ Fullscreen button
- ☑ Automatically start on page load: **tắt** (để người chơi click, vì trình duyệt cần click mới phát âm thanh và khóa chuột)
- ☐ Mobile friendly: **tắt** (cần chuột và bàn phím)
- ☐ SharedArrayBuffer support: **không cần** (bản export không dùng đa luồng)
