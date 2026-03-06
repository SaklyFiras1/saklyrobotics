import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot

@pytest.fixture(scope="module")
def sim():
    """Connect to CoppeliaSim and wait until ready"""
    client = RemoteAPIClient(host='127.0.0.1', port=23000)
    sim_obj = None

    max_wait = 60  # increase timeout to 60 seconds
    interval = 1
    elapsed = 0

    print("→ Waiting for CoppeliaSim ZMQ server...")
    while elapsed < max_wait:
        try:
            sim_obj = client.require('sim')
            # test simple call to ensure server responds
            sim_obj.getObjectCount()
            break
        except Exception:
            time.sleep(interval)
            elapsed += interval
            print(f"  still waiting... ({elapsed}s/{max_wait}s)")

    if sim_obj is None:
        pytest.fail("Impossible de se connecter à l'objet 'sim' via ZMQ API")
    
    print("→ Connected to CoppeliaSim ZMQ server")
    sim_obj.startSimulation()
    time.sleep(2.0)  # allow simulation to settle
    yield sim_obj
    print("→ Stopping CoppeliaSim simulation")
    sim_obj.stopSimulation()
    time.sleep(0.5)


def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"


def test_load_positions_format(sim):
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0
    assert len(positions[0]) == 6


def test_robot_and_scene(sim):
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6


def test_gripper_init(sim):
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None
