# Technical Architecture Design: Geo-MMO Strategy

This document defines the technology stack, workload distribution between client and server, and the complete API interface specification for a mobile game built on the Uber H3 hexagonal grid (resolution 9). The design strictly respects the 7 proposed UI screens and game mechanics.

---

## 1. Proposed Technology Overview (Tech Stack)

### Client Side (Flutter Application)
*   **Framework:** Flutter (Dart) – ensures cross-platform development for iOS and Android with native performance for 2D graphics.
*   **Map Display:** `flutter_map` + `latlong2` + **Mapbox Tiles** vector tiles (dark, futuristic style). It utilizes the free tier of up to 50,000 MAU.
*   **Local Geomathematics:** `h3_flutter` – C-port of the Uber H3 library integrated into Dart via FFI. It enables instant conversion of GPS coordinates to hexagon indices directly on the device.
*   **Geolocation & Sensors:** `geolocator` – acquiring precise GPS coordinates with spoofed location detection (`isMocked`) enabled.
*   **Environment Scanning:** `flutter_blue_plus` – low-level Bluetooth Low Energy (BLE) management for passive capturing of surrounding broadcasts in both foreground and background.
*   **Network Communication:** `web_socket_channel` (encrypted WebSockets) for the real-time game loop and `http` for standard REST requests.
*   **Monetization:** `google_mobile_ads` (Google AdMob) – implementation of a static advertisement banner at the bottom of the map, handled safely via `SafeArea`.
*   **Keep-Alive Services:** `wakelock_plus` (preventing screen dimming while walking) and `flutter_background_service` (ensuring stable BLE scanning in a pocket).

### Server Side (Authoritative Game Server)
*   **Runtime & Framework:** Node.js / TypeScript + **NestJS** – robust modular architecture with excellent built-in support for WebSockets (`@nestjs/websockets`).
*   **Real-time Network Layer:** Socket.io integrated into NestJS – ensures a persistent, bidirectional connection, multiplexing, and room management (rooms for specific map regions).
*   **Spatial Mathematics:** `h3-js` (Node.js bindings) – validation of hexagon neighborhoods and background bonus calculations on the server side.
*   **Persistent Storage:** **PostgreSQL + PostGIS** – relational database for secure storage of user accounts, soldiers, grid ownership, and the history of unique Bluetooth IDs.
*   **In-Memory Cache & Distribution:** **Redis** – lightning-fast management of online player positions and distribution of map state changes across server instances using Redis Pub/Sub.

### External Infrastructure
*   **Firebase Cloud Messaging (FCM) & APNs:** Delivery of background push notifications (alerts for an approaching or completed attack).

---

## 2. Computational Distribution Architecture (Client vs. Server)

To achieve maximum game smoothness, save mobile phone battery, and minimize data transfer, the architecture is designed so that the client performs the maximum possible visual and deterministic calculations locally. The server acts exclusively as an **authoritative data storage and rules validator (Anticheat)**.

### What the Client (Flutter) Calculates and Processes:
1.  **Geometry Rendering:** The server sends only clean text H3 indices (e.g., `"891f1a1c62fffff"`) to the application. Using `h3_flutter`, Flutter locally calculates the exact latitudes and longitudes of all 6 vertices of the hexagon and renders them as a vector polygon over the Mapbox tiles.
2.  **Local Recruitment Calculation:** When the BLE radar captures the MAC address / UUID of a device and the signal strength (RSSI), the client itself locally performs a SHA-256 hash to determine the class, eventual specific skill (Scout, Jammer, Decoy), and base Combat Strength (BS) according to the signal strength. The resulting generated soldier is sent to the server for approval.
3.  **Bonus Calculation for UI:** When expanding an owned hexagon in the Context Panel (Screen 2), the client locally queries the H3 library for the indices of the 6 neighboring hexagons and compares them with the list of its owned fields. It immediately prints the background bonus (**+100%** per neighbor) onto the UI without burdening the server with a query.

### What the Server (NestJS) Strictly Calculates and Verifies:
1.  **Validation of BLE ID Uniqueness (Anti-Cheat):** The server holds a historical index of all Bluetooth IDs that a given player has ever scanned. When the client sends a recruitment result, the server verifies whether the player is abusing this ID for a second time. If the ID is unique, the server writes the soldier into the PostgreSQL database. This ensures that when logging in on a different phone, the player has their army completely available.
2.  **Authoritative Combat Simulation:** The combat calculation takes place exclusively on the server. The server takes the attacker's data, requests the defender's actual garrison from the database, applies the spatial neighborhood bonus (which it verifies itself in PostGIS/H3), and evaluates the result. This protects the game against phone memory modification.
3.  **Verification of Physical GPS Presence:** During any offensive or scouting action, the server compares the player's declared GPS coordinates (which passed the `isMocked` check on the client) with the actual boundaries of the target H3 hexagon. If the player is not physically standing in the hexagon, the server rejects the action.
4.  **Logistics & Territory Cluster Management:** The server monitors the integrity of the Home Base. If a hexagon designated as the **Center 👑** is captured, the server uses a graph algorithm (Breadth-First Search over H3 indices) to recalculate the connectivity of the territory and transforms the cut-off polygons into Outposts. It also processes the deduction of the **40%** penalty or the deletion of a Support unit during remote reinforcement transfers.

---

## 3. Complete Endpoint Specifications (API Contract)

### 3.1 REST API Endpoints (HTTP)
Used for asynchronous operations, account management, viewing history, and static overviews. All endpoints except registration require an `Authorization: Bearer <JWT_TOKEN>` header.

#### Onboarding / Welcome Screen (Screen 1)
*   **`POST /api/v1/auth/register`**
    *   **Description:** Registration of a new player or login via Apple/Google Sign-In.
    *   **Request Body:**
        ```json
        {
          "nickname": "Válečník99",
          "idToken": "eyJhbGciOiJSUzI1NiIs..."
        }
        ```
    *   **Response (201):**
        ```json
        {
          "userId": "d3b07384-d113-4956-a5e2-aa5988d8b28a",
          "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
        ```

*   **`POST /api/v1/territory/establish`**
    *   **Description:** Establishing the very first hexagon (main base) upon launching the game for the first time.
    *   **Request Body:**
        ```json
        {
          "h3Index": "891f1a1c62fffff",
          "name": "Nová Citadela"
        }
        ```
    *   **Response (201):**
        ```json
        {
          "status": "success",
          "territoryId": "a1a2a3a4-b5b6-c7c8-d9e0-f1a2a3a4b5b6"
        }
        ```

#### Barracks (Screen 4)
*   **`GET /api/v1/barracks`**
    *   **Description:** Loading the complete state of the army for synchronization on any device.
    *   **Response (200):**
        ```json
        {
          "reserves": [
            { "id": "u1", "type": "WARRIOR", "rarity": "PROTOTYPE", "bs": 250, "skill": null },
            { "id": "u2", "type": "SUPPORT", "rarity": "STANDARD", "bs": 50, "skill": "SCOUT" }
          ],
          "patrols": [
            {
              "h3Index": "891f1a1c62fffff",
              "territoryName": "Domovská základna",
              "soldierCount": 5,
              "totalBs": 650
            }
          ]
        }
        ```

#### Territory Management (Screen 5)
*   **`GET /api/v1/territory/list`**
    *   **Description:** A list of all controlled territory clusters, divided by type.
    *   **Response (200):**
        ```json
        {
          "home": {
            "id": "home-id",
            "name": "Hlavní základna",
            "hexCount": 14,
            "centerH3Index": "891f1a1c62fffff"
          },
          "outposts": [
            {
              "id": "outpost-1",
              "name": "Chata u lesa",
              "hexCount": 3,
              "representativeH3Index": "891f1a1c62ffffe"
            }
          ]
        }
        ```

*   **`PATCH /api/v1/territory/:id/rename`**
    *   **Description:** Renaming a territory cluster (both Home Base and Outpost).
    *   **Request Body:**
        ```json
        {
          "name": "Válečná zóna Alfa"
        }
        ```
    *   **Response (200):**
        ```json
        { "status": "success" }
        ```

#### Battle Logs (Screen 6)
*   **`GET /api/v1/battle-logs`**
    *   **Description:** Loading battle history and scouting reports onto a timeline.
    *   **Response (200):**
        ```json
        [
          {
            "id": "log-1",
            "timestamp": "2026-07-17T14:30:00Z",
            "type": "ATTACK",
            "h3Index": "891f1a1c62fffff",
            "result": "VICTORY",
            "myDead": 3,
            "mySurvivors": 8
          },
          {
            "id": "log-2",
            "timestamp": "2026-07-17T12:15:00Z",
            "type": "SCOUT",
            "h3Index": "891f1a1c62ffffb",
            "result": "SUCCESS",
            "revealedBs": 450
          }
        ]
        ```

#### Settings & Profile (Screen 7)
*   **`GET /api/v1/profile`**
    *   **Description:** Loading the player's profile statistics.
    *   **Response (200):**
        ```json
        {
          "nickname": "Válečník99",
          "email": "user@email.com",
          "stats": {
            "hexesClaimed": 42,
            "biggestBattleBs": 1850,
            "scannedDevices": 341
          }
        }
        ```

*   **`PATCH /api/v1/profile/nickname`**
    *   **Description:** Changing the player's nickname with a uniqueness check on the server.
    *   **Request Body:**
        ```json
        {
          "nickname": "NovýNick123"
        }
        ```
    *   **Response (200):**
        ```json
        { "status": "success" }
        ```

---

### 3.2 WebSocket Gateway (Real-time Protocol)
The WebSocket connection is initiated on the Tactical Map (Screen 2) and remains active throughout the gameplay. The client and server communicate by sending JSON events through the established channel.

#### Direction: Client -> Server (Player Actions)

*   **Event: `map_subscribe`**
    *   **Usage:** Subscribing to map changes based on the visible bounding box in the Flutter application.
    *   **Payload:**
        ```json
        {
          "visibleH3Indexes": ["891f1a1c62fffff", "891f1a1c62ffffe", "891f1a1c62ffffd"]
        }
        ```

*   **Event: `location_update`**
    *   **Usage:** Periodic update of the player's location to highlight the current hexagon and validate the movement speed (Anti-Cheat).
    *   **Payload:**
        ```json
        {
          "latitude": 50.0755,
          "longitude": 14.4378,
          "h3Index": "891f1a1c62fffff",
          "isMocked": false
        }
        ```

*   **Event: `recruit_device`**
    *   **Usage:** Sending a locally calculated soldier from the BLE Radar (Screen 3) to the server for uniqueness validation and storage.
    *   **Payload:**
        ```json
        {
          "bluetoothId": "4A:5F:6E:7D:8C:9B",
          "calculatedSoldier": {
            "type": "WARRIOR",
            "rarity": "PROTOTYPE",
            "bs": 250,
            "skill": null
          }
        }
        ```

*   **Event: `garrison_modify`**
    *   **Usage:** Withdrawing soldiers from a hexagon back into reserves or deploying them to a garrison (within the context panel on an owned field).
    *   **Payload:**
        ```json
        {
          "h3Index": "891f1a1c62fffff",
          "action": "DEPLOY", 
          "soldierIds": ["u1", "u2"]
        }
        ```

*   **Event: `send_reinforcements`**
    *   **Usage:** Logistics and remote defense. Sending immediate reinforcements from reserves to a sector under attack.
    *   **Payload:**
        ```json
        {
          "targetH3Index": "891f1a1c62ffffb",
          "soldierIds": ["u3", "u4", "u5"],
          "burnSupportUnitId": "u6"
        }
        ```
        *(If it is an Outpost and `burnSupportUnitId` is `null`, the server automatically applies **40%** casualties to the sent soldier IDs).*

*   **Event: `scout_hex`**
    *   **Usage:** Activating espionage on an enemy hexagon (requires physical presence).
    *   **Payload:**
        ```json
        {
          "targetH3Index": "891f1a1c62ffffa",
          "scoutSoldierId": "u7"
        }
        ```

*   **Event: `attack_hex`**
    *   **Usage:** Initiating an attack on an occupied enemy hexagon (requires physical presence).
    *   **Payload:**
        ```json
        {
          "targetH3Index": "891f1a1c62ffffa",
          "attackerSoldierIds": ["u1", "u2", "u3", "u4"]
        }
        ```

---

#### Direction: Server -> Client (State Updates & Notifications)

*   **Event: `map_grid_update`**
    *   **Usage:** The server sends grid changes to all connected clients in the given area (e.g., a change of field ownership after a battle).
    *   **Payload:**
        ```json
        {
          "hexagons": [
            {
              "h3Index": "891f1a1c62fffff",
              "ownerName": "Nepřítel01",
              "color": "#E53935",
              "hasGarrison": true,
              "isCenter": false
            }
          ]
        }
        ```

*   **Event: `recruit_result`**
    *   **Usage:** Response to a recruitment attempt. Updates the visualization feed on the BLE Radar.
    *   **Payload (Success):**
        ```json
        {
          "status": "SUCCESS",
          "bluetoothId": "4A:5F:6E:7D:8C:9B",
          "message": "Rekrutován Bojovník (Prototyp, 250 BS) ⚔️"
        }
        ```
    *   **Payload (Duplicate):**
        ```json
        {
          "status": "SKIPPED",
          "bluetoothId": "4A:5F:6E:7D:8C:9B",
          "message": "ID již dříve naskenováno -> Přeskočeno 🚫"
        }
        ```

*   **Event: `incoming_attack_alert`**
    *   **Usage:** Immediate warning for a remote defender. Triggers a 120-second window to send reinforcements.
    *   **Payload:**
        ```json
        {
          "defendingH3Index": "891f1a1c62fffff",
          "territoryName": "Domovská základna",
          "attackerName": "Ragnarok",
          "secondsRemaining": 120
        }
        ```

*   **Event: `scout_result`**
    *   **Usage:** Delivery of scouting results with respect to the defender's countermeasures.
    *   **Payload:**
        ```json
        {
          "targetH3Index": "891f1a1c62ffffa",
          "status": "SUCCESS", 
          "revealedBs": 1250 
        }
        ```
        *(Note: If the defender had a `Decoy` skill in their garrison, the `revealedBs` value is automatically increased to five times the actual strength by the server. If they had a `Jammer`, the status returns as `"JAMMED"` and `revealedBs` will be `0`).*

*   **Event: `battle_result`**
    *   **Usage:** Immediate display of the battle result and cleanup of the local army inside the phone.
    *   **Payload:**
        ```json
        {
          "battleId": "b-999",
          "h3Index": "891f1a1c62ffffa",
          "result": "VICTORY",
          "myDeadCount": 2,
          "mySurvivors": [
            { "id": "u1", "bs": 210 },
            { "id": "u2", "bs": 145 }
          ]
        }
        ```