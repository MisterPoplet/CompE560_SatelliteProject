# DTN Simulation Integration Guide

## Overview
This simulation is built using MATLAB's Object-Oriented Programming capabilities. The code is organized into a package `+dtn` to keep the namespace clean and modular.

## Directory Structure
- `src/+dtn/+core/`: Contains the main simulation loop (`Simulation.m`), node logic (`Node.m`), and data structures (`Bundle.m`).
- `src/+dtn/+phy/`: Physical layer models (e.g., `PhyLayer.m`).
- `src/+dtn/+link/`: Link layer models (e.g., `LinkLayer.m`).
- `src/+dtn/+net/`: Network layer base classes.
- `src/+dtn/+routing/`: Specific routing protocol implementations.
- `src/+dtn/+gui/`: Visualization components.

## How to Add a New Routing Protocol
To implement a new routing protocol (e.g., `MaxProp`), follow these steps:

1.  **Create a new class** in `src/+dtn/+routing/` named `MaxProp.m`.
2.  **Inherit from the base Router class**:
    ```matlab
    classdef MaxProp < dtn.net.Router
        properties
            % Add protocol-specific state here
        end
        
        methods
            function obj = MaxProp(node)
                obj = obj@dtn.net.Router(node);
            end
            
            function handleContact(obj, otherNode)
                % Logic for when two nodes meet
                % 1. Exchange summary vectors
                % 2. Decide which bundles to forward
            end
        end
    end
    ```
3.  **Register the protocol**: In your simulation configuration (or `run_simulation.m`), specify `'MaxProp'` as the routing strategy for the nodes.

## How to Add a New Mobility Model
1.  Create a new class in `src/+dtn/+core/` (or a new `+mobility` package if it grows).
2.  Implement a `getPosition(time)` method that returns the [x, y, z] coordinates.

## GUI Integration
The GUI uses a listener pattern. The `Simulation` class broadcasts events (e.g., `ContactStart`, `BundleDelivered`). The `Gui` class listens to these events and updates the display.
- To add a new metric, add a listener in `+dtn/+gui/MetricsPanel.m`.

## Running Experiments
Use the scripts in the `experiments/` folder. They are designed to:
1.  Setup a `Simulation` object.
2.  Configure nodes and parameters.
3.  Run the simulation loop.
4.  Extract logs and plot results.
