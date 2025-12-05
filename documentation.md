# Developer Documentation

## Architecture Overview

The project is built in MATLAB using object-oriented programming. The architecture follows a Model-View-Controller (MVC) pattern, although simplified into a "App + Managers" structure.

### Key Files & Classes

#### 1. `main.m` - Entry Point
-   Clears the workspace.
-   Instantiates the `DTNApp` class to launch the GUI.

#### 2. `DTNApp.m` - The GUI Application
-   **Role**: Handles all user interaction, button clicks, and visualization.
-   **Key Properties**:
    -   `scenarioManager`: Instance of `dtn.ScenarioManager`. Handles the "truth" of the simulation (where nodes are).
    -   `viewer`: A `satelliteScenarioViewer` object for the 3D globe visualization.
-   **Logic**:
    -   Callbacks (e.g., `onPingButton`, `onRunScenarioButton`) gather data from UI fields and call the underlying logic classes.
    -   Creates a timer-based or loop-based simulation when "Run Scenario" is clicked.

#### 3. `+dtn/ScenarioManager.m`
-   **Role**: Manages the collection of satellites and ground stations.
-   **Data**: Stores an array of nodes (structs with name, type, orbital elements).
-   **Functions**:
    -   `addSatellite()` / `addGroundStation()`: Creates the entities.
    -   `getLatLonAlt(time)`: Calculates precise position of any node at a given time.

#### 4. `+dtn/DTNSimulator.m`
-   **Role**: The simulation engine. This runs "headless" (without UI) logic for the DTN scenario.
-   **Process (`run` method)**:
    1.  Initialize bundles (messages) at the source node.
    2.  Loop through time steps (e.g., every 1 second).
    3.  **Update Positions**: Calculate X,Y,Z for all nodes.
    4.  **Check Connectivity**:
        -   Is distance < Max Range? (from `PHYProfiles`)
        -   Is there Line-of-Sight? (Check for Earth occlusion).
    5.  **Forward Bundles**: If connected, copy bundles to the neighbor (Epidemic routing).
    6.  **Check Delivery**: If a node holding the bundle is the Destination, mark as Delivered.

#### 5. `+dtn/PHYProfiles.m`
-   **Role**: Static helper to define RF capabilities.
-   **Parameters**:
    -   `SBand`: 4000 km range, 1 Mbps.
    -   `KaBand`: 3500 km range, 100 Mbps.

## Extending the Code

### Adding a New Routing Protocol
Currently, `DTNSimulator.m` defaults to Epidemic routing. To add **Spray and Wait**:
1.  Open `DTNSimulator.m`.
2.  Modify the bundling struct to track "copies left".
3.  In the forwarding loop (`run` method), check if `copies_left > 1` before forwarding.
4.  If forwarding, decrement the `copies_left` count.

### Adding a New PHY Mode
1.  Open `PHYProfiles.m`.
2.  Add a new case to the switch statement (e.g., `case 'Optical'`).
3.  Define properties (Resulting range, data rate, etc.).
4.  Update `DTNApp.m` to include this new option in the Dropdown menu.

## References & Further Reading

### Routing Protocols
1.  Lindgren, Anders, Avri Doria, and Elwyn Davies. *Probabilistic Routing Protocol for Intermittently Connected Networks*. RFC 6693, Internet Engineering Task Force, Aug. 2012, https://datatracker.ietf.org/doc/html/rfc6693.
2.  Spyropoulos, Thrasyvoulos, Konstantinos Psounis, and Cauligi S. Raghavendra. "Spray and Wait: An Efficient Routing Scheme for Intermittently Connected Mobile Networks." *Proceedings of the 2005 ACM SIGCOMM Workshop on Delay-Tolerant Networking*, ACM, 2005, pp. 252-259.
3.  Vahdat, Amin, and David Becker. *Epidemic Routing for Partially Connected Ad Hoc Networks*. Technical Report CS-200006, Duke University, Apr. 2000.

### Satellite Communications
4.  Ippolito, Louis J. *Satellite Communications Systems Engineering: Atmospheric Effects, Satellite Link Design and System Performance*. Wiley, 2008.
5.  "Chapter 10: Telecommunications." *Basics of Space Flight*, NASA Science Solar System Exploration, https://solarsystem.nasa.gov/basics/chapter10-1/. Accessed 5 Dec. 2025.

