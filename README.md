# Rocket Caro

Caro 15×15 bắn rocket, góc nhìn thứ nhất (Godot 4.7). Hai đội đứng hai bên một bàn cờ khổng lồ;
mỗi lượt 15 giây, một phát bắn, gió + trọng lực làm lệch đường đạn. Đủ 5 dấu liên tiếp là thắng.

## Chạy
Mở thư mục này bằng Godot 4.7 rồi bấm Play (F5).

## Kích thước bàn
Đổi `N` (số ô mỗi cạnh) và `CELL` (độ lớn mỗi ô) ở đầu `scripts/core/rules.gd`; sân, shader, minimap tự co theo. Luật thắng vẫn là `WIN_LEN` = 5 ô liên tiếp. Sau khi đổi, export lại web và khởi động lại server (client và server phải cùng phiên bản).

## Ngôn ngữ và cảnh báo sức khỏe
- **Ngôn ngữ**: Tiếng Việt (mặc định) và English, chọn trong *Cài đặt* hoặc ngay trên màn cảnh báo lúc mở game; đổi là giao diện dựng lại ngay, lựa chọn được nhớ. Chuỗi tiếng Việt trong mã là "khóa"; bản tiếng Anh nằm ở bảng `EN` trong `scripts/core/loc.gd` (thiếu mục nào thì tự rơi về tiếng Việt). Thêm chữ mới: viết `Loc.t("câu tiếng Việt")` rồi thêm một dòng vào bảng. Thông điệp do máy chủ gửi (lỗi phòng, "đang chờ đối thủ") là khóa tiếng Việt + tham số, máy khách tự dịch.
- **Cảnh báo sức khỏe** (chống chóng mặt/tiền đình): hiện mỗi lần mở game, có thể tick *Không hiện lại màn hình này*; xem lại bất cứ lúc nào ở *Cài đặt*. Mô tả độ khó Siêu khó cũng ghi rõ "dễ gây chóng mặt".

## Menu
Màn hình chính chia hai cột: bên trái là tên bạn (tự lưu), *Cách chơi* và *Cài đặt* (độ nhạy chuột, âm lượng, lưu trên máy);
bên phải là ba chế độ: *Chơi mạng LAN*, *Chơi với Bot*, *2 người · cùng máy*. Mọi màn hình con đều có nút quay lại ở góc trên trái.
Luồng LAN: Kết nối (địa chỉ máy chủ, tự điền khi mở từ trang web của máy chủ) → Sảnh phòng → phòng chờ/trận.
Cài đặt lưu ở `user://settings.cfg` (script `scripts/core/prefs.gd`).

## Chế độ chơi
- **Đấu với bot** và **2 người · cùng máy** (offline, chạy được cả trên web).
- **Chơi mạng LAN** (web hoặc desktop):
  1. Trên một máy trong mạng chạy `./play_lan.sh` (thêm `--rebuild` nếu vừa sửa code). Script bật
     web server HTTPS (cổng 8443) + HTTP cho chính máy này (cổng 8060) và server trọng tài
     (WebSocket nội bộ cổng 24571, được tunnel qua chính cổng web), rồi in ra URL.
  2. Máy khác mở `https://192.168.x.x:8443`. Trình duyệt cảnh báo chứng chỉ tự ký (bấm
     *Nâng cao → Tiếp tục truy cập*, chỉ một lần): Godot web bắt buộc "secure context" (HTTPS hoặc
     localhost) nên không thể dùng http://IP-LAN. Rồi bấm *Chơi mạng LAN → Vào phòng*
     (địa chỉ tự điền).
  3. Sảnh phòng: danh sách phòng cập nhật trực tiếp (tên, số người, tên người trong phòng,
     đang đấu hay chưa). *Tạo phòng* (tên tùy chọn), bấm vào phòng còn chỗ để vào, hoặc *Vào nhanh*
     (ghép với phòng đang chờ, không có thì tự mở phòng mới). Mỗi phòng 2 người: người vào trước là
     X, người vào sau là O. Tối đa 64 phòng chạy song song; phòng tự đóng khi hết người.
  4. Server là trọng tài của từng phòng: tung gió, mô phỏng đường đạn, phán kết quả; máy chơi chỉ
     gửi hướng bắn và phát lại kết quả. Ai thoát giữa trận thì người còn lại chờ người mới.
     *Rời trận* đưa bạn về sảnh mà không mất kết nối; hết ván bấm *Chơi lại* để đấu tiếp cùng phòng.
  - Bản desktop (F5 trong Godot) cũng vào được: nhập IP máy chạy server.
  - Cho phép kết nối đến qua tường lửa macOS khi được hỏi (python3 và Godot).
  - Chưa hỗ trợ cảm ứng/điện thoại (cần chuột + bàn phím).

## Độ khó
**Khoảng cách:** ở Bình thường, Khó, Rất khó, người chơi đứng cách bàn **160** (xa), nên rocket bay lâu hơn (~1.6 giây), gió làm lệch nhiều hơn và bàn trông nhỏ hơn (chuột phải/Z để zoom). Siêu khó giữ khoảng cách **100**. Chỉnh ở `START_Z_FAR` / `START_Z_NEAR` trong `scripts/core/rules.gd`.
Chọn ở menu chính (chơi bot / 2 người) hoặc khi tạo phòng LAN; lựa chọn được nhớ. Mỗi mức gồm mức trước cộng thêm:
- **Bình thường**: không gió, không trọng lực (rocket bay thẳng).
- **Khó**: gió + trọng lực, đổi gió mỗi lượt.
- **Rất khó**: bàn cờ nghiêng mạnh và xoay quanh trục đứng (9°–34°), đổi mỗi lượt. Độ dốc tính theo người bắn: ngả ra xa 17°–46°, hoặc ngả vào gần nhẹ hơn (17°–23°, vì ngả vào gần mạnh sẽ che kín màn hình); bàn mất 0.8 giây để chuyển góc và trong lúc đó chưa bắn được. **Đồng thời người bắn bị đưa đi vòng quanh bàn cờ liên tục** (bán kính 160, 0.30–0.50 rad/s, một vòng khoảng 12–21 giây, chiều và điểm xuất phát ngẫu nhiên mỗi lượt). Thân người luôn quay mặt về tâm bàn, chuột vẫn ngắm như thường; có lúc thấy bàn chính diện, có lúc chỉ thấy cạnh bàn hoặc mặt sau (bị lật gương). Vòng quay dừng khi rocket rời nòng. Gió, độ dốc và minimap hiển thị theo chỗ đang đứng; có dòng gợi ý "Bàn ở bên trái/phải" khi bạn nhìn lạc hướng. Vị trí là hàm của thời gian trong lượt (`Rules.shooter_pos`): máy khách gửi kèm thời điểm bắn, trọng tài chấp nhận nếu trễ không quá 0.5 giây rồi tự tính chỗ đứng.
- **Siêu khó**: gió + trọng lực, và bàn cờ **lật, quay liên tục rất nhanh** (lật 0.7–1.2 rad/s quanh trục ngang, quay 1.2–2.0 rad/s quanh trục đứng; tốc độ và chiều đổi mỗi lượt, bàn không bị giật mà quay tiếp từ góc cũ). Người chơi đứng yên ở mức này. Có thêm **đạn băng** (xem phần Đạn). Rocket bay mất khoảng 1 giây nên phải bắn *đón đầu*: hình bàn quay trên bảng điều kiện cho biết bàn đang ở đâu.
Cách làm bàn quay khớp giữa các máy: tư thế của bàn là một hàm của **đồng hồ bàn** (`board_time`) do trọng tài giữ. Khi bắn, trọng tài tính cả đường bay theo đồng hồ đó và gửi kèm thời điểm bắn; máy khách gắn đồng hồ bàn của mình vào tiến độ bay của rocket, nên lúc rocket chạm bàn thì bàn ở đúng tư thế trọng tài đã tính (đạn đuổi được trọng tài gửi kèm đồng hồ liên tục). Bot kiểm tra từng cách ngắm bằng mô phỏng và chờ đúng thời điểm.

Mọi điều kiện của một lượt nằm trong một dictionary `env` (`Rules.roll_env`), do trọng tài tung rồi gửi cho mọi máy, nên vật lý, bot và hiển thị luôn khớp nhau. Bảng ở giữa trên hiển thị gió, trọng lực, độ dốc theo góc nhìn của từng người chơi.

## Đạn
Phím `1` thường · `2` tẩy · `3` đuổi · `4` băng (chọn trong lượt của bạn). Mỗi loại đặc biệt chỉ dùng **1 lần/người/ván**.
- **Đạn tẩy**: trúng dấu của đối thủ thì xóa dấu đó; trúng ô trống/dấu của mình thì mất lượt.
- **Đạn đuổi**: sau khi bắn, rocket bị kéo về phía điểm tâm ngắm trên bàn cờ, di chuột để lái
  (lực kéo có giới hạn). Server mô phỏng thời gian thực theo hướng ngắm bạn gửi lên.
- **Đạn băng** (chỉ Siêu khó): trúng bất kỳ ô nào trên bàn thì bàn **đứng yên ngay tại tư thế lúc trúng** trong `FREEZE_TURNS` = 4 lượt (2 lượt mỗi người, vì lượt kế tiếp là của đối thủ), không đặt dấu; hết băng bàn quay tiếp từ đúng tư thế đó. Bàn không được "nắn" về góc dễ bắn, nên phải chọn thời điểm bắn cho chính xác. Không bắn được khi bàn đang bị đóng băng. Bảng điều kiện hiện "ĐÓNG BĂNG · còn N lượt", bàn phủ lớp băng. Trọng tài phát `net_freeze` với góc của bàn tại thời điểm chạm (`tau` trong kết quả `step_flight`), rồi `roll_env(..., frozen)` giữ `omega = 0`.
- HUD trên cùng hiển thị gió (mũi tên theo hướng *màn hình của bạn*) và trọng lực.

## Đăng lên itch.io
1. `./export_itch.sh` tạo `build/itch/rocket-caro-web.zip` (khoảng 10 MB, `index.html` nằm ở gốc zip).
2. itch.io → *Upload new project*: Kind of project = **HTML**, tải zip lên, tick *This file will be played in the browser*, viewport 1280×720, bật *Fullscreen button*.
3. Ảnh bìa và ảnh chụp có sẵn trong `itch/`, nội dung trang trong `itch/PAGE.md`.
Lưu ý: itch chỉ lưu file tĩnh nên **chơi mạng không chạy sẵn trên itch** (không có máy chủ trận đấu). Bản itch chơi được với Bot và 2 người cùng máy. Muốn chơi mạng qua itch cần một máy chủ công khai có HTTPS (chạy `godot --headless -- --server` sau một reverse proxy hỗ trợ WebSocket, chuyển tiếp `/` có `Upgrade: websocket` vào cổng 24571) rồi nhập `wss://ten-mien.com` trong màn hình kết nối.

## Chơi online: super-caro.kembabies.io.vn
`./deploy/deploy.sh` chạy test luật, export bản web ở máy này, rsync lên VPS `<VPS_IP>` (`/home/deploy/kembabies/super-caro`) rồi `docker compose up -d --build`. Hai container: `super-caro-web` (nginx phục vụ file tĩnh đã nén gzip, `127.0.0.1:8792`; request có `Upgrade: websocket` được chuyển sang trọng tài) và `super-caro-game` (Godot 4.7.2 headless chạy `--server` từ chính `index.pck` vừa export, nên client và server luôn cùng phiên bản). Host Nginx giữ TLS. Vhost: `deploy/super-caro.kembabies.io.vn.conf` (cài một lần bằng sudo, xem đầu file). `./deploy/deploy.sh ps | logs | restart` để vận hành. Trên itch.io, nhập `wss://super-caro.kembabies.io.vn` ở màn kết nối là chơi mạng được.

## Điều khiển
Chuột ngắm · click/Space bắn · chuột phải/Z zoom · 1–4 chọn đạn · mũi tên cũng ngắm · Esc tạm dừng.
**Người chơi không tự di chuyển** (cách bàn 160, riêng Siêu khó là 100; ở Rất khó bị đưa đi vòng quanh bàn). Máy chủ luôn bắn từ chỗ đứng do luật tính ra, bỏ qua vị trí mà máy khách gửi lên.

## Skin
Mỗi lần vào trận (Bot, 2 người, hoặc trước khi vào LAN) có màn **Chọn skin**, lựa chọn được nhớ (`Prefs.skins`). Danh mục nằm ở `scripts/core/skins.gd` (id dạng chuỗi để sau này gắn với tài khoản/cửa hàng):
- **Bàn cờ**: Giấy cổ, Bảng phấn, Gỗ, Neon. Chỉ mình bạn thấy (mỗi máy vẽ bàn theo lựa chọn của mình).
- **Dấu trên bàn**: Cổ điển X/O, Ngôi sao, Trái tim, Kim cương. Cùng kiểu cho cả hai đội, khác màu; vẽ trong `board.gdshader`.
- **Hiệu ứng nổ**: Lửa, Pháo hoa, Kim tuyến, Điện. Đạn đặc biệt vẫn giữ màu riêng để nhận ra loại đạn.
- **Vệt đường bay**: Khói, Lửa, Cầu vồng, Lấp lánh.
Dấu, hiệu ứng nổ và vệt đường bay đi theo trận: máy khách gửi kèm `srv_hello`, trọng tài lọc qua `Skins.sanitize` rồi phát trong `net_new_match`. Bot chọn ngẫu nhiên. Thêm skin: thêm một dòng vào bảng tương ứng (và vào `loc.gd` cho tên tiếng Anh). Test nhanh: `-- --skin=neon,star,fireworks,rainbow` (không lưu).

## Màn hình tải (web)
`web/shell.html` thay trang tải mặc định của Godot (logo + thanh tiến trình trơn) bằng màn hình Rocket Caro: bàn caro nhỏ tự xếp 5 ô, rocket bay, thanh tiến trình có số MB, tự chọn tiếng Việt/Anh theo trình duyệt, tắt chuyển động khi hệ thống bật "giảm chuyển động". Boot splash của engine đã tắt (`application/boot_splash/show_image=false`) nên không còn logo Godot sau khi tải xong.

## Cấu trúc
- `scripts/core/rules.gd` — luật, độ khó/`env`, vật lý đường đạn (kể cả bàn nghiêng), kiểm tra thắng, bot (thuần logic).
- `scripts/core/net.gd` — autoload `Net`: WebSocket server/client.
- `scripts/game/game.gd` — điều khiển trận + RPC (phải nằm ở `/root/Main/Game` trên mọi máy; server trọng tài = cờ `--server`).
- `scripts/game/world.gd`, `fps_rig.gd`, `rocket.gd`, `sfx.gd` — sân, người chơi, rocket, âm thanh.
- `shaders/board.gdshader` — vẽ cả bàn cờ 15×15 (lưới, X, O, ô thắng) từ một texture 15×15.
- `scripts/ui/` — HUD và các màn hình menu.

## Assets
Hiện tại mọi thứ là placeholder tạo bằng code. Âm thanh có thể thay bằng cách bỏ file vào
`assets/audio/` với tên: `launch` (đạn thường), `launch_erase` (đạn tẩy), `launch_steer` (đạn đuổi), `boom`, `mark`, `block`, `win`, `lose`, `tick` (`.ogg/.wav/.mp3`). Hiện đã có file thật cho 3 tiếng bắn; các tiếng còn lại vẫn là âm tổng hợp bằng code.

### Nguồn âm thanh
- `launch.mp3`: *cartoon-rocket-whoosh* (UNIVERSFIELD)
- `launch_erase.mp3`: *hi-speed-electronic-whoosh-1* (freesound_community)
- `launch_steer.mp3`: *cartoon-swirl* (UNIVERSFIELD)
(các file tải về từ Pixabay/Freesound; kiểm tra giấy phép nếu bạn phát hành game).
Model/texture thì sửa trong `world.gd`, `rocket.gd`, `fps_rig.gd`.

## Test tự động (không cần người chơi)
Sau `--` là cờ riêng của game:
```
godot --headless --path . --script tools/test_rules.gd                # test luật/đạn
godot --headless --path . -- --autobot --autoquit=25                 # bot tự đấu
godot --headless --path . -- --server --autoquit=40                  # server trọng tài
godot --headless --path . -- --autojoin=127.0.0.1 --autoquit=30      # client tự "vào nhanh" và chơi (chạy nhiều cái: cứ 2 cái một phòng)
```
