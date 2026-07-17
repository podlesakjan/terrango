### 1. ONBOARDING SCREEN: First Launch (Onboarding / Welcome)
This screen is displayed only once when the application is opened for the first time. It is designed to make the game start as fast and barrier-free as possible.
Key Elements:
*   **Field for entering Nick (Nickname):** A simple text input.
*   **Button for quick registration:** One large button (e.g., via Google / Apple Sign-In) that immediately pairs the entered Nick with a new account.
*   **Instant start:** The player is redirected to the Main Map immediately after registration.

### 2. MAIN SCREEN: Tactical Map (Home / Map)
Visual Appearance: A dark futuristic map with colored hexagons (blue = yours, red = enemy, no color = free). Colors must not override the map background. This means the colors will have sufficient transparency. A static advertisement banner is placed at the bottom of the screen with a sufficient safety distance from game elements.
Key Elements on the Screen:
*   **GPS Presence Indicator:** The dot of your current location. The hexagon in which you are currently physically standing has a highlighted border.
*   **Status Bar (Top part):** Display of your Nick, the total number of occupied hexagons, and the current size of your reserve (e.g., ⚔️ 120 / 📡 35).
*   **Quick Switches (Bottom part above the ad):**
    *   "RECRUITMENT" button (access to the radar scanner).
    *   "BARRACKS" button (overview of your army).
    *   "BASES" button (list of your territories).
*   **Hexagon Context Panel (Bottom Sheet):** Slides up after tapping on any hexagon:
    *   **Free:** "Occupy territory" button (inputting how many soldiers the player will leave there, minimum 1; option to enter the name of a new territorial unit).
    *   **Own:** Name of the territory, switch to designate the hexagon as a Center 👑, composition of the current garrison, option to reinforce the garrison, option to withdraw soldiers back to reserves, and calculation of the Background Bonus (+100% per each neighbor).
    *   **Enemy:** Name of the owner, fog of war ("??? BS"), "Scout" button, and "ATTACK!" button (active only if you are physically standing in the hexagon).

### 3. SCREEN: Army Recruitment (Automatic BLE Radar)
This screen serves as a visual tracker for automatic recruitment. No wasting time by clicking on each device – the game does all the hard work for you.
Visual Appearance: A large circular sci-fi radar with a smoothly rotating scanning beam.
Key Elements:
*   **Automatic collection (No-Click):** As soon as Bluetooth captures a unique ID in the surroundings, the radar immediately locks the cursor onto it.
*   **Visualization feed (Recruitment history):** A dynamic, constantly scrolling text and graphical feed runs below the radar showing the latest recruited units:
    *   "[2s ago] Strong signal detected -> Recruited Warrior (Prototype, 250 BS) ⚔️"
    *   "[12s ago] Weak signal detected -> Recruited Support (Jammer, Standard, 50 BS) 📡"
    *   "[30s ago] ID already scanned previously -> Recruitment skipped 🚫"
*   **Total overview of recruited soldiers:** since the time the user entered the recruitment screen.

### 4. SCREEN: Barracks (Total Army Overview)
Visual Appearance: A clean, tabular overview divided into two main sections: Reserve (soldiers ready in the phone for attack) and Patrols (soldiers deployed on hexagons).
Key Elements:
*   **Summary statistics at the top:** Total combat strength (BS) of your reserve.
*   **List of units in Reserve:** Compact cards of soldiers sorted by BS. Each card displays only:
    *   Class icon (sword for Warrior, eye/lightning/target for individual Support skills).
    *   Rarity (Standard / Advanced / Prototype).
    *   Numerical value of Combat Strength (e.g., 150 BS).
*   **List of units in Patrol:** A list showing how many soldiers are in which specific hexagon/territory.

### 5. SCREEN: Territory Management (Bases)
A clear list of your empire for quick orientation and remote defense.
Visual Appearance: A list of your territory clusters divided into two categories.
Key Elements:
*   **Home Territory:** Name of your main base, number of connected hexagons, button for quickly centering the map on your Center.
*   **Outpost Territories:** A list of all your standalone territories (e.g., "Cabin by the woods - 3 hexagons").
*   **Renaming and management:** Option to click on a pencil icon and immediately rename any territory.

### 6. SCREEN: Combat Reports (Battle Logs)
A clear archive, thanks to which you can find out what was happening on the map when you did not have the application turned on.
Visual Appearance: A timeline with clear cards of battles and espionage.
Key Elements:
*   **Clash History:** A list of battles with color coding (Green = Victory, Red = Defeat). The number of the player's dead and surviving soldiers. The opponent's numbers must not be shown.
*   **Spy Reports:** Results of your scouting carried out by a Support unit.

### 7. SCREEN: General Settings and Profile (Settings & Profile)
Technical background of the game and your statistics.
Key Elements:
*   **Player Profile:** Option to change nickname, link to a Google/Apple account, overall statistics (number of conquered hexagons, biggest won battle, total number of scanned Bluetooth devices).
*   **Technical Toggles:**
    *   **Prevent screen sleep (Wake Lock):** Prevents the display from turning off during active walking outside and scanning.
    *   **Run in background (Foreground Service):** Allows the game to collect GPS and BLE data in the background with the phone screen turned off in your pocket.