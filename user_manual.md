# DTN Satellite Simulator - User Manual

## Overview
This application simulates a Delay Tolerant Network (DTN) over a constellation of Low Earth Orbit (LEO) satellites and Ground Stations. It allows you to model how data bundles traverse a disrupted network where continuous end-to-end connectivity is not guaranteed.

## GUI Concepts & Definitions

The Graphical User Interface (GUI) is divided into three main tabs: **Nodes & Ping**, **Settings**, and **Scenario**.

### 1. Nodes & Ping Tab
This tab lets you manage the network topology (satellites and ground stations).

#### Parameters Explained:
-   **Sat Alt (Satellite Altitude)**: The height of the satellite above the Earth's surface (in Kilometers). Normal LEO altitude is between 400 km and 2000 km.
-   **Incl (Inclination)**: The angle of the orbit relative to Earth's equator.
    -   `0 deg`: Equatorial orbit.
    -   `90 deg`: Polar orbit (goes over the poles).
    -   `53 deg`: Common inclination (like Starlink or GPS).
-   **RAAN (Right Ascension of Ascending Node)**: A way to space out satellites in different orbital "planes" or rings around the Earth. If you want satellites to follow each other in a line, keep RAAN the same. To spread them out like a net, change the RAAN (e.g., 0, 30, 60...).
-   **GS Lat/Lon (Ground Station Latitude/Longitude)**: The GPS coordinates of a ground station on Earth.
-   **GS Alt (Ground Station Altitude)**: Height above sea level (usually 0 meters).

#### Features:
-   **Open Satellite Viewer**: Opens a 3D visualization of the satellites orbiting Earth.
-   **Ping**: A diagnostic tool to check if two directly connected nodes can "see" each other *right now*. It checks:
    1.  **Line of Sight (LOS)**: Is Earth blocking the view?
    2.  **Range**: Are they close enough (based on PHY settings)?

### 2. Settings Tab
Configure the physical layer (PHY) and DTN routing behavior.

-   **PHY Mode (RF Bands)**:
    -   **SBand** (~1 Mbps, 4000 km range): Standard radio band for satellite control and lower-rate data. Reliable, easier to establish links.
    -   **KaBand** (~100 Mbps, 3500 km range): High-frequency band for high-speed data. Requires precise antenna pointing, so the effective range is modeled as slightly shorter or harder to maintain.
    -   **SatelliteRF** (Generic): A custom profile representing a general mid-range RF link (10 Mbps).

-   **Routing Protocols**:
    -   **Epidemic**: The "flood" strategy. When a satellite meets another node, it copies *all* separate bundles it carries to that node. Guarantees delivery if a path exists but uses significant storage and bandwidth.
    -   **PRoPHET** (Probabilistic Routing Protocol using History of Encounters and Transitivity): *[Experimental]* Nodes track how often they see others and only forward data to nodes that have a higher probability of meeting the destination.
    -   **Spray and Wait**: *[Experimental]* Limits the number of copies. The source sprays `L` copies to the first `L` nodes it meets, then those nodes "wait" until they meet the destination.

### 3. Scenario Tab
Run full network simulations.

-   **Source / Destination**: Select which node generates the data and which node should receive it.
-   **# Bundles**: How many data packets to send.
-   **Playback Speed**: Controls how fast the simulation runs compared to real-time. `0` runs as fast as the computer allows.

---

## Technical Concepts

### Satellite RF Bands (S-Band vs Ka-Band)
Radio Frequency (RF) communications are classified by "bands" of the electromagnetic spectrum.
-   **S-Band (2-4 GHz)**: "Wider" beam, easier to aim, penetrates rain/clouds better. Used for telemetry and tracking.
-   **Ka-Band (26-40 GHz)**: "Narrow" beam, allows extremely high data rates (like satellite internet), but is sensitive to rain fade and requires very accurate pointing.

### DTN (Delay Tolerant Networking)
Unlike the regular Internet (TCP/IP), which fails if a wire is cut, DTN is designed for space. It uses a **Store-Carry-Forward** mechanism:
1.  **Store**: Keep the data message ("bundle") in memory.
2.  **Carry**: Hold onto it while the satellite moves in orbit (waiting for a link).
3.  **Forward**: When a connection opens (e.g., passing over a Ground Station or another Satellite), send the bundle.
