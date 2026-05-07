# Multiplayer Plan (Faz 2 — sonraya bırakıldı)

## Mimari

Master Server + Çoklu Game Server'lar (Oracle Cloud Free Tier):

```
Oracle Cloud VM (Ampere A1, 4 core, 24GB RAM, ücretsiz ömür boyu)
├── Master Server (Node.js, port 8080)
│   ├── GET  /rooms              → aktif oda listesi
│   ├── POST /rooms/claim        → boş oda al
│   ├── POST /servers/:p/heartbeat → server health
│   └── POST /servers/:p/release → odayı serbest bırak
│
├── Game Server #1 (Godot --server, port 7777)
├── Game Server #2 (Godot --server, port 7778)
├── ...
└── Game Server #10 (Godot --server, port 7786)
```

## Akış

**Oda kuran:**
1. ODA KUR → master'a HTTP POST
2. Master boş port atar (örn 7779) + odayı işaretler
3. Client oracle.com:7779'a ENet ile bağlanır
4. Liste'de "Player X'in Odası" görünür

**Katılan:**
1. ONLINE OYUNLAR → master HTTP GET /rooms
2. Liste döner: oda adları + player count + state
3. Tıkla → oracle.com:port'a bağlan

## Yapılacaklar (sıraya göre)

### Kod tarafı
- [ ] `master_server/master.js` — Node.js master HTTP API
- [ ] `master_server/start.bat` / `.sh` — 10 Godot --server pre-launch
- [ ] `scripts/autoload/master_client.gd` — Godot HTTP client
- [ ] Lobby'de **ONLINE OYNA** paneli — oda listesi + ODA KUR

### Oracle Cloud
- [ ] Hesap aç (cloud.oracle.com → free tier)
- [ ] Ampere A1 VM yarat (4 core, 24GB RAM, Always Free)
- [ ] SSH key kur, public IP not al
- [ ] Firewall: 7777-7786 (UDP), 8080 (TCP) aç
- [ ] Node.js + Godot binary kurulumu
- [ ] systemd service tanımla (master + 10 server otomatik başlasın)

### Test
- [ ] Lokal Windows'ta master + 10 server + 2 client → tam akış
- [ ] Oracle deploy → 1 PC + 1 telefon ile internet test

## Kullanılan teknoloji
- **Master backend**: Node.js (basit HTTP, in-memory state)
- **Game server**: Godot 4.6.2 headless (`--server` flag)
- **Network protocol**: ENet UDP (Godot built-in)
- **NAT bypass**: server public IP'de, client outbound UDP yapıyor — NAT engeli yok
- **Hosting**: Oracle Cloud Free Tier (kalıcı bedava)

## Notlar
- Phase 1 LAN multiplayer çalışıyor (server browser ile)
- Singleplayer fix önceliklendirildi (kullanıcı isteği)
- Online'a dönüldüğünde bu doküman + mevcut Network/Lobby kodu temel olur
