# Satellite DTN Simulator

A MATLAB-based simulator for Delay Tolerant Networking (DTN) over LEO satellite constellations.

## Getting Started

1.  Open MATLAB.
2.  Navigate to this folder.
3.  Run `main.m` in the command window.

## Documentation

-   **[User Manual](user_manual.md)**: Explains how to use the GUI, what the satellite parameters mean (Altitude, RAAN, etc.), and details on RF bands (S-Band vs Ka-Band).
-   **[Developer Documentation](documentation.md)**: Explains the code structure, classes, and how to extend the simulator.

## Features

-   **Orbit Simulation**: Models 12+ LEO satellites and Ground Stations.
-   **RF Link Modeling**: Includes Line-of-Sight (Earth occlusion) checks and max range limits based on S-Band or Ka-Band profiles.
-   **DTN Routing**: Simulates Store-Carry-Forward behavior (Epidemic routing) to deliver messages across disconnected path segments.
-   **Visualization**: Includes a 3D Earth viewer to see satellite positions in real-time.

## Quick Key Concepts

-   **DTN**: Protocols for networks with intermittent connectivity (like space).
-   **Epidemic Routing**: Messages are flooded to every node encountered to maximize delivery probability.
-   **S-Band**: Reliable, long-range, lower speed radio.
-   **Ka-Band**: High speed, slightly shorter effective range, sensitive radio.
