# Quick Start Guide

## 1. Start PostgreSQL & Redis

```bash
cd /home/jan/AndroidStudioProjects/Terrango/apps/server

# Start Docker containers
docker-compose up -d

# Verify they're running
docker ps | grep terrango
```

Expected output:
```
terrango-cache   redis:7-alpine   Up X seconds   0.0.0.0:6379->6379/tcp
terrango-db      postgres:16      Up X seconds   0.0.0.0:5432->5432/tcp
```

## 2. Configure Environment

```bash
# Copy example env
cp .env.example .env

# (Optional) Edit .env if you changed Docker ports or want different settings
# cat .env
```

## 3. Install Dependencies

```bash
npm install --legacy-peer-deps
```

Wait for it to complete (~30 seconds).

## 4. Build TypeScript

```bash
npm run build
```

Should output: `BUILD SUCCESS` or just finish without errors.

## 5. Run Development Server

```bash
npm run start:dev
```

Expected startup messages:
```
[Nest] 12345   - 07/18/2026, 10:30:45 AM     LOG [InstanceLoader] DatabaseModule dependencies initialized
[Nest] 12345   - 07/18/2026, 10:30:45 AM     LOG [TypeOrmModule] Database connection initialized
[Nest] 12345   - 07/18/2026, 10:30:45 AM     LOG [InstanceLoader] RedisModule dependencies initialized
```

Server listens on `http://localhost:3000`

## 6. Test It Works

### Register a player (HTTP):
```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "nickname": "TestPlayer99",
    "idToken": "test-token-12345"
  }'
```

Expected response:
```json
{
  "userId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Connect WebSocket (optional test):
```bash
# Install wscat if you don't have it:
npm install -g wscat

# Connect:
wscat -c "ws://localhost:3000/socket.io/?token=YOUR_JWT_TOKEN_HERE"

# Send message:
{"event":"request_map_snapshot","data":{"visibleH3Indexes":[]}}
```

## 7. Stop Containers

```bash
# Stop but keep data:
docker-compose stop

# Stop and delete (WARNING: data lost):
docker-compose down -v
```

## Troubleshooting

### "Cannot connect to database"
- Check if PostgreSQL is running: `docker ps | grep postgres`
- Check connection: `psql -h localhost -U terrango -d terrango`
- If not running: `docker-compose up -d postgres`

### "Redis connection refused"
- Check if Redis is running: `docker ps | grep redis`
- If not running: `docker-compose up -d redis`

### "Port already in use"
- Kill process on port 3000: `lsof -ti:3000 | xargs kill -9`
- Or use `PORT=3001 npm run start:dev`

### "TypeScript compilation errors"
- Delete node_modules: `rm -rf node_modules`
- Reinstall: `npm install --legacy-peer-deps`
- Rebuild: `npm run build`

## API Testing Tools

### Postman
- Import the REST endpoints from README.md
- Create environment with token from /register response
- Test all endpoints

### WebSocket Testing
- Use `wscat` (shown above)
- Or build a simple HTML client with `socket.io-client`

## Next Steps

1. Read `/docs/architecture.md` to understand system design
2. Explore `/src/game/domain.ts` for data models
3. Check `/src/game/game.service.ts` for core logic
4. Implement missing features (push notifications, battle persistence, etc.)

## Production Deployment

For production:
1. Use strong JWT_SECRET (generate with: `openssl rand -base64 32`)
2. Use external PostgreSQL & Redis (managed services)
3. Update `.env` with production URLs
4. Set `NODE_ENV=production`
5. Enable HTTPS on reverse proxy (nginx)
6. Configure database backups & monitoring
7. Set up scaling with socket.io-redis adapter (already integrated)

---

**Status**: ✅ Core server (REST + WebSocket) complete
**Next**: Add push notifications, refine battle concurrency, optimize queries

