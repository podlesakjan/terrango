import { MigrationInterface, QueryRunner } from 'typeorm';

export class InitialSchema1723000000000 implements MigrationInterface {
  name = 'InitialSchema1723000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "users" (
        "id" uuid NOT NULL,
        "providerId" text NOT NULL,
        "nickname" text NOT NULL,
        "email" text,
        "homeCenterH3Index" text,
        "stats" jsonb NOT NULL DEFAULT '{"hexesClaimed":0,"biggestBattleBs":0,"scannedDevices":0}',
        "createdAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "UQ_users_providerId" UNIQUE ("providerId"),
        CONSTRAINT "UQ_users_nickname" UNIQUE ("nickname"),
        CONSTRAINT "PK_users" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "hexes" (
        "h3Index" text NOT NULL,
        "ownerId" uuid,
        "territoryId" uuid,
        "garrisonComposition" jsonb NOT NULL DEFAULT '[]'::jsonb,
        "changedAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "createdAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_hexes" PRIMARY KEY ("h3Index")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "territories" (
        "id" uuid NOT NULL,
        "ownerId" uuid NOT NULL,
        "name" text NOT NULL,
        "type" text NOT NULL,
        "centerH3Index" text,
        "hexIndexes" text NOT NULL,
        "representativeH3Index" text NOT NULL,
        "createdAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_territories" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "player_armies" (
        "id" uuid NOT NULL,
        "ownerId" uuid NOT NULL,
        "reservesComposition" jsonb NOT NULL DEFAULT '[]'::jsonb,
        "createdAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "UQ_player_armies_ownerId" UNIQUE ("ownerId"),
        CONSTRAINT "PK_player_armies" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "battle_logs" (
        "id" uuid NOT NULL,
        "userId" uuid NOT NULL,
        "type" text NOT NULL,
        "h3Index" text NOT NULL,
        "result" text NOT NULL,
        "myDead" integer,
        "mySurvivors" integer,
        "revealedBs" integer,
        "timestamp" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_battle_logs" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "bluetooth_scans" (
        "id" uuid NOT NULL,
        "userId" uuid NOT NULL,
        "deviceId" text NOT NULL,
        "scannedAt" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_bluetooth_scans" PRIMARY KEY ("id")
      )
    `);

    // Indexes
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_users_provider_id" ON "users" ("providerId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_users_nickname" ON "users" ("nickname")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_hexes_owner_id" ON "hexes" ("ownerId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_hexes_territory_id" ON "hexes" ("territoryId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_territories_owner_id" ON "territories" ("ownerId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_player_armies_owner_id" ON "player_armies" ("ownerId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_battle_logs_user_id" ON "battle_logs" ("userId")`);
    await queryRunner.query(`CREATE UNIQUE INDEX IF NOT EXISTS "idx_bluetooth_scans_user_device" ON "bluetooth_scans" ("userId", "deviceId")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_bluetooth_scans_user_device"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_battle_logs_user_id"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_player_armies_owner_id"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_territories_owner_id"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_hexes_territory_id"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_hexes_owner_id"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_users_nickname"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_users_provider_id"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "bluetooth_scans"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "battle_logs"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "player_armies"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "territories"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "hexes"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "users"`);
  }
}

