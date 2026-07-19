# Terrango Server

Authoritative NestJS game server for Terrango geo-MMO strategy game.

## Architecture

- **Framework**: NestJS 11 + TypeScript
- **Database**: PostgreSQL 16 with TypeORM
- **Cache & Pub/Sub**: Redis 7
- **Real-time**: Socket.io WebSockets
- **Spatial Math**: H3-js (Uber hexagonal grid)

## Setup

### Prerequisites

- Node.js >= 20.0.0
- Docker + Docker Compose (for local PostgreSQL & Redis)
- npm or yarn

### Installation

1. Install dependencies:
```bash
npm install --legacy-peer-deps
```

2. Start PostgreSQL and Redis containers:
```bash
docker-compose up -d
```

3. Create `.env` file from template:
```bash
cp .env.example .env
```

4. Build TypeScript:
```bash
npm run build
```

## Running

### Development mode (with hot reload):
```bash
npm run start:dev
```

### Production mode:
```bash
npm run build
npm run start
```

The server will start on `http://localhost:3000` by default.

## Project Structure

```
src/
├── auth/              # Authentication & JWT
│   ├── auth.service.ts
│   ├── auth.controller.ts
│   ├── bearer-auth.guard.ts
│   └── current-player.decorator.ts
├── game/              # Game domain & WebSocket
│   ├── game.service.ts      # Core game logic
│   ├── game.gateway.ts      # WebSocket handlers
│   ├── game.controller.ts   # REST endpoints
│   ├── game.module.ts
│   └── domain.ts
├── database/          # Data persistence
│   ├── entities/      # TypeORM entities
│   ├── repositories/  # Data access layer
│   └── database.module.ts
├── redis/             # Pub/Sub for cross-instance
│   └── redis.module.ts
├── app.module.ts
└── main.ts
```

## API Endpoints

All endpoints require `Authorization: Bearer <JWT_TOKEN>` header (except `/api/v1/auth/register`).

### Authentication
- `POST /api/v1/auth/register` - Register/login player

### Territory Management
- `POST /api/v1/territory/establish` - Create home base
- `POST /api/v1/territory/occupy` - Occupy free hexagon
- `PATCH /api/v1/territory/:id/center` - Change center
- `PATCH /api/v1/territory/:id/rename` - Rename territory
- `GET /api/v1/territory/list` - List all territories

### Hexagon Info
- `GET /api/v1/hex/:h3Index` - Get hexagon details (owned/enemy/free state)

### Army Management
- `GET /api/v1/barracks` - List all soldiers by location

### Battle History
- `GET /api/v1/battle-logs` - Get battle history

### Profile
- `GET /api/v1/profile` - Get player profile & stats
- `PATCH /api/v1/profile/nickname` - Change nickname

## WebSocket Events

### Client → Server

- `request_map_snapshot` - Request initial map state
- `resume_session` - Sync after reconnect
- `map_subscribe` - Subscribe to hexagon changes in viewport
- `location_update` - Update player GPS location
- `recruit_device` - Recruit soldier from BLE device
- `garrison_modify` - Deploy/withdraw soldiers
- `send_reinforcements` - Send soldiers to defend
- `scout_hex` - Spy on enemy hexagon
- `attack_hex` - Initiate battle

### Server → Client

- `map_snapshot` - Complete hex state for viewport
- `map_grid_update` - Changes to visible hexagons
- `hex_detail_update` - Updated single hexagon (garrison, bonuses, etc)
- `army_update` - Total reserves/garrison counts
- `territory_update` - Territory connectivity changes
- `recruit_result` - Success/skipped soldier recruitment
- `incoming_attack_alert` - Enemy attacking your hex
- `scout_result` - Scouting success/jammed/decoy info
- `battle_result` - Battle resolution & survivors
- `locality_user_event` - Generic user-specific events

## Database Migrations

TypeORM synchronization is enabled in development (`synchronize: true` in database.module.ts).

In production, use TypeORM CLI to generate and manage migrations:
```bash
npx typeorm migration:generate src/database/migrations/MigrationName
npx typeorm migration:run
```

## Environment Variables

See `.env.example` for all available options:

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | - | Full PostgreSQL connection string for managed deployments |
| `DB_HOST` | localhost | PostgreSQL host |
| `DB_PORT` | 5432 | PostgreSQL port |
| `DB_USER` | terrango | PostgreSQL user |
| `DB_PASSWORD` | terrango | PostgreSQL password |
| `DB_NAME` | terrango | PostgreSQL database |
| `DB_SSL` | false | Enable SSL for PostgreSQL connections |
| `REDIS_URL` | redis://localhost:6379 | Redis connection URL |
| `JWT_SECRET` | terrango-dev-secret | Secret for JWT signing (⚠️ change in production!) |
| `NODE_ENV` | development | Environment mode |

> In production, set `DATABASE_URL` or the full `DB_*` set explicitly.
> The `localhost` defaults are intended only for local development.

## Architecture Highlights

### In-Memory + Persistent Hybrid

- **Entities stored in PostgreSQL**: users, soldiers, hexagons, territories, battle logs, bluetooth scans
- **In-memory cache**: User sessions, game state snapshots for performance
- **Redis Pub/Sub**: Cross-instance event distribution for horizontal scaling
- **Socket.io rooms**: Efficient broadcasting of map updates to subscribed clients

### Anti-Cheat Measures

- GPS coordinate validation: Client must be physically in target hexagon
- Movement speed anti-cheat: Reject if player moves too fast (see `MAX_SPEED_KMH`)
- Mocked location detection: Server rejects `isMocked: true` from client
- Token verification: JWT signature validation on all requests
- Bluetooth ID uniqueness: Prevent recruiting same device multiple times

### Pending Battles

- Battles resolve after `ATTACK_PREPARATION_MS` (default 3 seconds)
- Combat strength calculation includes neighborhood bonuses for defender
- Survivors projected based on damage ratio
- Territory reconciliation on ownership change

## Roadmap / Future Enhancements

- [ ] Proper OAuth2 idToken verification (Google/Apple Sign-In)
- [ ] Push notification integration (FCM/APNs)
- [ ] Persistent battle scheduling with Redis sorted sets
- [ ] Rate limiting & DDoS protection
- [ ] Database backup & replication
- [ ] Kubernetes deployment (Helm charts)
- [ ] Monitoring & observability (Prometheus/Grafana)
- [ ] Performance testing & load balancing

## License

Proprietary - Terrango Project

