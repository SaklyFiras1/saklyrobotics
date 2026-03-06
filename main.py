import os
import sys
import time
import csv
sys.path.append(os.getcwd())

from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot

# ----------------------------
# Initialize simulation client
# ----------------------------
def init_simulation(host="localhost", port=23000, timeout=60):
    client = RemoteAPIClient(host=host, port=port)
    sim_obj = None
    elapsed = 0
    interval = 1
    while elapsed < timeout:
        try:
            sim_obj = client.require('sim')
            print(f"→ Connected to sim object after {elapsed}s")
            break
        except Exception:
            time.sleep(interval)
            elapsed += interval
            print(f"→ Waiting for sim object... {elapsed}s elapsed")
    if sim_obj is None:
        raise RuntimeError("Impossible de se connecter à l'objet 'sim' via ZMQ API")
    return sim_obj

sim = init_simulation()

# Initialize robot
armRobot = UniversalRobot('UR10')
armRobot.AttachGripper('vacuum_gripper')

# ----------------------------
# Helper functions
# ----------------------------
def SavePalletPosition():
    """Automatically save pallet positions to CSV"""
    with open('pallet_positions.csv', mode='w', newline='') as file:
        writer = csv.writer(file)
        height = 0
        for i in range(21):
            if i != 0 and i % 7 == 0:
                height += 200
            pos = armRobot.GetObjectPosition(f'Cartoons{i + 1}')
            print(f"Saving position {i+1}: {pos}")
            writer.writerow(pos)
            time.sleep(0.1)


def LoadPalletPosition():
    """Load pallet positions from CSV"""
    positions = []
    if not os.path.exists('pallet_positions.csv'):
        raise FileNotFoundError("CSV file 'pallet_positions.csv' not found!")
    with open('pallet_positions.csv', 'r') as file:
        reader = csv.reader(file)
        for row in reader:
            positions.append([float(i) for i in row])
    return positions


def putObjectToPallet(count, palletPos):
    """Move object to pallet"""
    pos_up = [palletPos[0], palletPos[1], palletPos[2] + 200, 180, 0, palletPos[5]-90]
    pos_down = [palletPos[0], palletPos[1], palletPos[2] + 110, 180, 0, palletPos[5]-90]

    if count > 13:  # third layer
        pos_up = [palletPos[0], palletPos[1], palletPos[2] - 50, 180, 0, palletPos[5]-90]
        pos_down = [palletPos[0], palletPos[1], palletPos[2] - 90, 180, 0, palletPos[5]-90]

    # Move robot above pallet
    armRobot.MoveL(pos_up, 500)
    print(f"[DEBUG] Joint positions: {armRobot.ReadJointPosition()}")
    armRobot.MoveL(pos_down, 50)

    # Release gripper and return
    armRobot.gripper.Release()
    armRobot.MoveL(pos_up, 500)

    # Move back to standby
    standby_joints = [-14.21, 23.61, 122.55, -56.18, -90.09, 75.74]
    armRobot.MoveJ(standby_joints, 180)


def record_positions():
    """Save and reload pallet positions"""
    sim.startSimulation()
    time.sleep(1)
    SavePalletPosition()
    positions = LoadPalletPosition()
    print("Loaded positions:", positions)
    sim.stopSimulation()


def main():
    """Main pallet picking function"""
    sim.startSimulation()
    time.sleep(1)  # wait for the simulation to fully start

    # Get sensor handle
    prox_sensor = sim.getObject('/ConveyorSensor')
    targetPositions = LoadPalletPosition()

    # Move to standby
    armRobot.MoveL([570, 0, 400, 180, 0, 90], 100)

    count = 0
    timeout = time.time() + 120  # 2 min safety timeout

    while count < len(targetPositions):
        if time.time() > timeout:
            print("[ERROR] Timeout reached, stopping simulation")
            break

        try:
            ret, dist, pos, handle, norm = sim.readProximitySensor(prox_sensor)
            if ret == 1:
                print(f"[INFO] Object {count+1} detected")
                box_position = armRobot.GetObjectPosition2(handle)
                pick_pos = [box_position[0], box_position[1], box_position[2] + 105, 180, 0, 90]
                armRobot.MoveL(pick_pos, 300)
                armRobot.gripper.Catch()
                putObjectToPallet(count, targetPositions[count])
                count += 1
        except Exception as e:
            print(f"[WARNING] Sensor read error: {e}")
        
        time.sleep(0.1)

    sim.stopSimulation()
    print("[INFO] Simulation finished")


if __name__ == "__main__":
    # Example usage
    try:
        record_positions()  # Save positions first
        main()              # Start main pick-and-place loop
    except KeyboardInterrupt:
        print("[INFO] Interrupted by user")
        sim.stopSimulation()
    except Exception as e:
        print(f"[ERROR] {e}")
        sim.stopSimulation()
