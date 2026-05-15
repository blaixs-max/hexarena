# HexArena — Wager-Based Multiplayer Mimari Planı

**Versiyon**: 1.0 · 2026-05-12
**Durum**: Tasarım onaylandı, implementasyon sırada

---

## 📋 Karar Özeti

| # | Konu | Karar |
|---|---|---|
| 1 | Blockchain | Solana (Lumexia ekosistemi ile uyumlu) |
| 2 | Token | LMX (SPL Token) — başlangıçta, yeni token Faz 4 |
| 3 | Hesap modeli | Her maç on-chain (Solana fee çok düşük) |
| 4 | Escrow | Solana Anchor smart contract zorunlu |
| 5 | Wallet | Phantom + Solflare + Backpack desteği |
| 6 | Beraberlik | Sudden death, 10 dakika timeout, refund |
| 7 | Platform fee | %3 (50% treasury, 30% burn, 20% LP) |
| 8 | Disconnect | AI devralır, kazançlar adil |
| 9 | Anti-cheat | 6 katman, MVP'de Layer 1-4 |

---

## 🏗️ Sistem Mimarisi (4 Katman)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. CLIENT (Godot Web Export — Vercel'de)                        │
│    - HexArena oyun                                              │
│    - JavaScriptBridge → Wallet Adapter                          │
│    - WebSocket → Master Server                                  │
└──────────────────┬──────────────────────────────────────────────┘
                   │ WSS (gameplay) + HTTPS (auth)
┌──────────────────▼──────────────────────────────────────────────┐
│ 2. MASTER SERVER (Godot Dedicated — Oracle Cloud)               │
│    - Lobby management (oda kur/listele/katıl)                   │
│    - Match orchestration (server-authoritative simulation)      │
│    - Wallet balance check via RPC                               │
│    - Match result signing (Ed25519)                             │
└──────────────────┬──────────────────────────────────────────────┘
                   │ Solana RPC + signed txs
┌──────────────────▼──────────────────────────────────────────────┐
│ 3. BLOCKCHAIN LAYER (Solana Mainnet/Devnet)                     │
│    - LMX SPL Token                                              │
│    - hexarena_match Anchor Program                              │
│       └── create_match, join_match, lock_match,                 │
│           complete_match, cancel_match, withdraw                │
└──────────────────┬──────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────────┐
│ 4. USER WALLETS                                                 │
│    Phantom / Solflare / Backpack                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎮 Tam Maç Akışı

### Faz A — Oda Oluşturma
```
1. Host: "ODA KUR" → tıklar
2. Modal: entry fee belirler (örn 5000 LMX)
3. Host wallet imzalar → master server'a kayıt
4. Smart contract: create_match(host_wallet, entry_fee) called
   - Match PDA oluşturulur (deterministik adres)
   - State: "WAITING_FOR_PLAYERS"
5. Master server WSS broadcast → lobby listesinde göründü:
   "HexArenaRoom · 1/6 · 5000 LMX"
```

### Faz B — Oyuncular Katılır
```
6. Misafir lobbyden seçer → "KATIL"
7. Master server RPC ile wallet balance check
   - getBalance(misafir_wallet, LMX mint)
   - if balance < 5000: reject "Yetersiz bakiye"
   - if balance >= 5000: proceed
8. Misafir wallet imzalar → join_match(match_id) tx
9. Smart contract: 5000 LMX → match PDA escrow
10. Master server'a notify: "Player joined"
11. Lobby update: "2/6 · 5000 LMX"
```

### Faz C — Slot Reservation & Ready
```
12. Oyuncu odaya girer (master server WSS push)
13. UI: 6 slot göster (3 ev + 3 deplasman)
14. Slot seç → "OTUR" → WSS event
15. Tüm 6 slot dolduğunda "READY" butonu aktif
16. Her oyuncu "READY" → host görür
17. Host "MAÇI BAŞLAT" → tüm 6 ready ise enable
```

### Faz D — Payment Lock
```
18. Host BAŞLAT → smart contract lock_match(match_id)
    - State: "LOCKED" (her oyuncu zaten escrowda payment yaptı)
    - Eğer 1+ oyuncu payment'sız ise → otomatik cancel_match
19. UI: "Ödemeler kilitlendi ✓"
20. Master server match.tscn instance'ı yükler
21. Tüm 6 client'a "MATCH_START" mesajı
```

### Faz E — Gameplay (3 dakika maç)
```
22. Server-authoritative simulation
23. Client sadece input gönderir (move, sprint, kick)
24. Server top/oyuncu state'i tutar, her 50ms WSS sync push
25. Goals, fouls, time → server tarafında track
26. Match end:
    - 3 dk doldu + skor eşit → SUDDEN DEATH
    - Sudden death max 10 dk → ilk gol veya timeout → refund
    - Normal end → skor belli
```

### Faz F — Result & Payout
```
27. Server match_result imzalar (Ed25519):
    {
      match_id: "abc123",
      winners: [wallet1, wallet2, wallet3],
      losers: [wallet4, wallet5, wallet6],
      score_a: 3, score_b: 2,
      duration: 174.5,
      timestamp: ...,
      signature: "Ed25519(...)"
    }
28. Client smart contract'a complete_match(...) çağrısı:
    - Contract imzayı doğrular (server pubkey ile)
    - 30000 LMX havuzdan dağıt:
      * Platform fee: 900 LMX (%3)
        - 450 LMX → treasury
        - 270 LMX → burn
        - 180 LMX → LP rewards
      * Kazanan takım: 29100 LMX → her birine 9700 LMX
29. Smart contract tx confirmed → client görür
30. UI: "+9700 LMX kazandın!" celebration
```

### Faz G — Edge Cases
```
- Payment timeout (60s): otomatik cancel_match → refund herkese
- 1 oyuncu DC olur: AI devralır (server matching)
- Sudden death timeout: refund herkese
- Server crash mid-match: 10 dakika sonra otomatik refund job
- Suspicious activity: replay log audit, ban eligibility
```

---

## 📜 Solana Smart Contract Spec

### Program: `hexarena_match`

**Anchor IDL (TypeScript pseudo-spec):**

```rust
#[program]
pub mod hexarena_match {
    use super::*;

    // Yeni maç oluştur
    pub fn create_match(
        ctx: Context<CreateMatch>,
        match_id: [u8; 32],         // unique ID
        entry_fee: u64,             // LMX amount (örn 5_000_000_000 for 5000 LMX with 6 decimals)
        max_players: u8,            // 6
    ) -> Result<()> {
        // Match PDA initialize
        // State = WaitingForPlayers
    }

    // Oyuncu maça katılır (LMX yatırır)
    pub fn join_match(
        ctx: Context<JoinMatch>,
        match_id: [u8; 32],
    ) -> Result<()> {
        // Transfer entry_fee → match escrow PDA
        // Add player to participants list
    }

    // Host maçı kilitler (tüm ödemeler tamam)
    pub fn lock_match(
        ctx: Context<LockMatch>,
        match_id: [u8; 32],
    ) -> Result<()> {
        // Verify 6 players paid
        // State = Locked
        // emit MatchLocked event
    }

    // Maç sonucu — server imzalı
    pub fn complete_match(
        ctx: Context<CompleteMatch>,
        match_id: [u8; 32],
        winners: Vec<Pubkey>,       // 3 wallets
        scores: [u8; 2],            // [team_a_goals, team_b_goals]
        server_signature: [u8; 64], // Ed25519
    ) -> Result<()> {
        // Verify server_signature with HEXARENA_PUBKEY
        // Hash payload, verify match
        // Distribute pot:
        //   - 30,000 LMX total
        //   - 900 LMX platform fee:
        //     - 450 → treasury
        //     - 270 → burn (LMX token authority)
        //     - 180 → LP rewards (LP pool)
        //   - 29,100 LMX → 3 winners (9,700 each)
        // State = Completed
    }

    // Maç iptali (timeout, DC, refund)
    pub fn cancel_match(
        ctx: Context<CancelMatch>,
        match_id: [u8; 32],
        reason: u8,                 // 0=timeout, 1=server_signed_cancel, ...
    ) -> Result<()> {
        // Verify can cancel (timeout reached OR server signed)
        // Refund each participant their entry_fee
        // State = Cancelled
    }
}
```

### Account Structures
```rust
#[account]
pub struct Match {
    pub match_id: [u8; 32],
    pub host: Pubkey,
    pub entry_fee: u64,
    pub max_players: u8,
    pub participants: Vec<Pubkey>,    // up to 6
    pub state: MatchState,            // enum
    pub created_at: i64,
    pub locked_at: Option<i64>,
    pub completed_at: Option<i64>,
    pub winners: Vec<Pubkey>,
    pub scores: [u8; 2],
}

pub enum MatchState {
    WaitingForPlayers,
    Locked,
    InProgress,
    Completed,
    Cancelled,
}
```

### Security Constraints
- Server pubkey hardcoded (HEXARENA_AUTHORITY)
- Match PDA seed: `["match", match_id.as_ref()]`
- Cancel match: kimseden imza gerekmez 60s timeout sonrası
- Complete match: sadece server imzasıyla
- Refund logic: deterministik (entry_fee × participants_count)

---

## 🖥️ Backend (Master Server) Spec

### Mevcut Altyapı
- `scripts/server/master_main.gd` — Godot dedicated WebSocket server
- Oracle Cloud Free Tier ARM (24GB RAM)
- Cloudflare Tunnel ile wss:// TLS

### Yeni Modüller
```
scripts/server/
  master_main.gd              ← mevcut (entry point)
  lobby_manager.gd            ← YENİ: oda listesi, slot mgmt
  match_orchestrator.gd       ← YENİ: matches state machine
  solana_client.gd            ← YENİ: RPC bağlantı (balance check)
  match_signer.gd             ← YENİ: Ed25519 sign result
  anti_cheat.gd               ← YENİ: input validation, rate limit
```

### Public RPC Endpoints (HTTPS REST API)
```
GET  /api/lobbies               → public match list
GET  /api/wallet/:pubkey/balance → balance check
POST /api/wallet/:pubkey/verify  → signature challenge (auth)
```

### WebSocket Protocol
```
S2C  lobby_state      → mevcut tüm odalar
C2S  create_room      → yeni oda (host)
C2S  join_room        → oda katılma talep
C2S  reserve_slot     → koltuk seçme
C2S  toggle_ready     → ready/unready
S2C  match_starting   → tüm clientlara
C2S  player_input     → 60Hz gameplay input
S2C  state_sync       → 20Hz gameplay state
S2C  match_ended      → sonuç + signed result
```

---

## 🌐 Frontend (Godot Web) Spec

### Wallet Adapter — JavaScript Bridge
```gdscript
# scripts/web/wallet_bridge.gd
extends Node

var window = JavaScriptBridge.get_interface("window")
var _on_connect_cb = JavaScriptBridge.create_callback(_on_wallet_connected)

func connect_phantom():
    window.solana.connect()
    # callback: _on_wallet_connected

func sign_transaction(serialized_tx_b64: String):
    window.solana.signTransaction(serialized_tx_b64)
    # callback: _on_tx_signed
```

### `index.html` Additional Scripts
```html
<script src="https://unpkg.com/@solana/web3.js@latest/lib/index.iife.js"></script>
<script src="https://unpkg.com/@solana/spl-token@latest/lib/index.iife.js"></script>
<script src="wallet-adapter.js"></script>
```

### New UI Screens
- **Wallet Bağla** modal (lobby ana menüde, ÇOKLU OYUNCU öncesi)
- **Bakiye + Yatır/Çek** ekranı
- **Oda Listesi** (canlı, entry fee badge'lı)
- **Slot Reservation** ekranı
- **Payment Pending** statü göstergesi
- **Match End** celebration + kazanç ekranı

---

## 🛡️ Anti-Cheat Spec

### Layer 1 — Server-Authoritative (ZORUNLU)
- Tüm physics, AI, top, oyuncu pozisyonları server tarafında
- Client: input gönderir + render
- Faz 2.3 zaten bu mimariyi kuruyor

### Layer 2 — Input Validation
- Max 60 input/sec per client
- Imkansız input reddedilir (örn velocity > 2x sprint_speed)
- Aim assist server tarafında hesaplanır

### Layer 3 — Match Result Signing
- Server private key (Ed25519) ile sonuç imzalanır
- Smart contract sadece bu imzalı sonuçları kabul eder
- Server key compromise olursa devnet'te audit edilmeli

### Layer 4 — Basic Sybil Protection
- IP başına max 2 wallet/saat
- Yeni wallet (<7 gün): 10000 LMX/gün cap
- Kasten DC pattern: rep score

### Layer 5 — Replay & Audit (Faz 4)
- Server input log + state snapshot (1 hafta retention)
- Anomali alert: anormal winrate, ultra hızlı maç
- Manual review + ban tool

### Layer 6 — ML Behavioral (Faz 5)
- Reaction time pattern
- Movement organicness
- Decision pattern entropy

---

## 💰 Tokenomics

### LMX Token (başlangıç)
- Solana SPL Token
- Decimals: 6 (1 LMX = 1,000,000 base units)
- Mint authority: HexArena treasury (sonra DAO transfer)
- Initial supply: TBD (Lumexia ile uyumlu)

### Fee Flow (Her maç için)
```
30,000 LMX havuz
├── %97 (29,100 LMX) → Kazananlar (3 × 9,700)
└── %3 (900 LMX) Platform Fee:
    ├── %50 (450 LMX) → HexArena Treasury
    ├── %30 (270 LMX) → LMX Burn (deflasyon)
    └── %20 (180 LMX) → LP Rewards Pool
```

### Deflasyon Modeli
- Her maç 270 LMX burn
- 1000 maç/gün = 270,000 LMX/gün burn
- Token sahibi long-term value gain

### Token Sink Mekanizmaları
- Entry fee (her oyuncu wager)
- LMX burn (3% komisyondan)
- NFT skin/amblem alımı (Faz 4)
- Premium pass / cosmetic (Faz 5)

---

## 🗺️ Yol Haritası

### Faz 2.3 — Master Server Online (Şimdi)
**Süre**: 2-3 gün
- Oracle Cloud Free Tier kurulum
- Master server deploy (no money yet, sadece match-making test)
- Cloudflare Tunnel wss:// TLS
- network.gd master_server_url update

### Faz 2.4 — Lobby UI Multiplayer
**Süre**: 3-4 gün
- ODA KUR ekranı (entry fee belirleme — şimdilik placeholder)
- Lobby listesi (real-time WebSocket)
- Slot reservation + READY system
- "Mock LMX" mode (gerçek wallet bağlanmadan test)

### Faz 3.1 — Wallet Adapter
**Süre**: 2-3 gün
- Solana web3.js + wallet-adapter Godot'a entegrasyon
- Phantom/Solflare/Backpack bağlantı UI
- "Bakiye göster" + signed challenge auth

### Faz 3.2 — Smart Contract
**Süre**: 5-7 gün
- Anchor program implementation
- Match account structs
- create/join/lock/complete/cancel fonksiyonlar
- Unit tests + integration tests (devnet)

### Faz 3.3 — Backend Solana Integration
**Süre**: 3-4 gün
- master_server'a Solana RPC client
- Balance check API
- Server private key + match signing
- Backend → smart contract integration tests

### Faz 3.4 — Frontend Integration
**Süre**: 3-4 gün
- Wallet bağla → balance göster
- Oda kur → smart contract create_match
- Katıl → join_match tx
- Match end → complete_match tx + kazanç UI

### Faz 3.5 — Anti-Cheat Hardening
**Süre**: 1 hafta
- Layer 2 (input validation)
- Layer 4 (Sybil protection)
- Server input rate limit

### Faz 3.6 — Devnet Test
**Süre**: 3-4 gün
- Devnet'te full end-to-end test
- 10+ test wallet ile gerçek senaryolar
- Bug fixes

### Faz 3.7 — Security Audit
**Süre**: 1-2 hafta (3rd party)
- Smart contract audit (önerilen: OtterSec, Halborn, veya benzer)
- Backend penetration test
- Frontend XSS/CSRF check

### Faz 3.8 — Mainnet Launch
**Süre**: 1 gün
- LMX token deploy mainnet
- Smart contract mainnet deploy
- Master server production config
- Soft launch (sınırlı kullanıcı)

**TOPLAM**: ~6-8 hafta MVP earn-to-play

---

## ⚠️ Riskler & Mitigasyon

| Risk | Etki | Mitigasyon |
|---|---|---|
| Smart contract bug → fund loss | KATASTROFİK | 3rd party audit, devnet test, formal verification |
| Server private key compromise | Yüksek | HSM/KMS storage, key rotation policy, multi-sig backup |
| Sybil/bot saldırı | Orta-Yüksek | Layer 4 + IP/wallet limits + KYC (yüksek havuzlar) |
| RPC node hatası (Solana down) | Düşük (nadir) | Çoklu RPC endpoint (Helius, QuickNode), retry logic |
| Regülasyon (gambling laws) | Orta | Hukuki danışmanlık, KYC opsiyonu, ülke kısıtı (geofence) |
| Token volatility | Orta | Stablecoin alt seçeneği (USDC), fiat on-ramp |
| Server DDoS | Orta | Cloudflare DDoS protection, rate limit, IP ban |
| Hile/exploit | Yüksek | Anti-cheat layers, replay audit, hotfix capability |

---

## 📚 Önerilen Tools & Servis

| Kategori | Öneri |
|---|---|
| Smart contract framework | Anchor (Solana) |
| Smart contract audit | OtterSec, Halborn, Neodyme |
| RPC providers | Helius, QuickNode, Triton |
| Indexing | Helius webhooks, Solana Explorer API |
| Backend hosting | Oracle Cloud Free → Hetzner Cloud (production) |
| Frontend hosting | Vercel + Cloudflare |
| Monitoring | Sentry, Grafana |
| Wallet adapters | @solana/wallet-adapter-base + ui |

---

## ✅ Aktif Faz: 2.3 — Master Server Online Multiplayer

**Sonraki adım**: Oracle Cloud Free Tier hesap aç + master server deploy.

**Şimdilik onaylar gerekiyor:**
1. ✅ Token: LMX (Solana SPL)
2. ✅ Fee modeli: %3 (50/30/20)
3. ✅ Anti-cheat: 6-layer (MVP'de L1-L4)
4. ⏳ Smart contract audit firma seçimi (Faz 3.7)
5. ⏳ Hukuki danışmanlık (gambling regulation)

Detaylar bekleniyor.
